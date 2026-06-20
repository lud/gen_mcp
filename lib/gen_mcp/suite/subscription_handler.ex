defmodule GenMCP.Suite.SubscriptionHandler do
  @moduledoc """
  Behaviour for handling `subscriptions/listen` in `GenMCP.Suite`.

  The 2026-07-28 revision removed the standalone GET SSE stream. Long-lived
  server→client notifications (`notifications/tools/list_changed`,
  `notifications/resources/updated`, …) are now obtained by sending a
  `subscriptions/listen` request, whose response is itself an SSE stream that
  stays open and delivers the change notifications the client opted in to.

  When a `Suite` is configured with a subscription handler, it routes
  `subscriptions/listen` requests to this behaviour. The handler accepts (or
  rejects) the subscription, sets up the application-side source (pub/sub,
  `GenStage`, a `GenServer`, …), and translates the messages it later receives
  into notifications on the channel.

  ## Relationship to `GenMCP.Suite.Tool`

  This behaviour **structurally mirrors** `GenMCP.Suite.Tool`'s streaming triad
  — `subscribe`/`handle_message`/`handle_close` line up with Tool's
  `call`/`handle_message`/`handle_close`, and `channel` is threaded per callback
  exactly as it is for tools. Only the entry name and the return vocabulary
  differ: a subscription never produces a `{:result, …}`, so the return is
  narrowed to `{:stream, state} | {:stop, reason}`.

  It is a **dedicated** behaviour, not a reuse of `Suite.Tool`: notification
  handling will likely evolve separately from tools, and conflating the two
  invites mistakes.

  ## gen_mcp owns no pub/sub

  The producer of the change notifications is the **application**, not the
  framework. gen_mcp ships only the stream lifecycle; the app broadcasts changes
  on whatever pub/sub it already uses and `c:subscribe/3` is where the handler
  subscribes the (connection-scoped) worker process to that source.

  ## The acknowledgment is sent by `Suite`, not the handler

  The spec requires `notifications/subscriptions/acknowledged` to be the **first
  message** on the stream. Because that is a MUST, `Suite` always sends the ack
  itself, unconditionally — the handler never sends it. The return shape only
  decides what the ack reports:

    * `{:stream, state}` — the ack reports the **full requested filter**.
    * `{:stream, honored, state}` — the ack reports `honored` (a deliberate
      downgrade for auth/capability reasons).

  Filter **enforcement** (not pushing a type the client did not request) is the
  handler's responsibility for now; `Suite` does not drop non-honored
  notifications at send time.
  """

  import GenMCP.Utils.CallbackExt

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Mux.Channel

  @typedoc "The argument configured alongside the handler module (`{module, arg}`)."
  @type arg :: term

  @typedoc "Handler-private state threaded across the subscription's lifetime."
  @type state :: term

  @typedoc """
  Which subscription notification types a handler may emit, for `server/discover`
  advertisement. Snake-case keys, each mirroring its notification method; absent
  or `false` keys advertise nothing.

    * `:tools_list_changed`     → `tools.listChanged`
    * `:prompts_list_changed`   → `prompts.listChanged`
    * `:resources_list_changed` → `resources.listChanged`
    * `:resources_updated`      → `resources.subscribe`
  """
  @type subscription_capabilities :: %{
          optional(:tools_list_changed) => boolean,
          optional(:prompts_list_changed) => boolean,
          optional(:resources_list_changed) => boolean,
          optional(:resources_updated) => boolean
        }

  @typedoc """
  How a subscription handler is configured: a bare module, a `{module, arg}`
  tuple, or an already-expanded descriptor.
  """
  @type subscription_handler :: module | {module, arg} | notification_handler_descriptor

  @typedoc "The normalized form `Suite` works with internally."
  @type notification_handler_descriptor :: %{
          required(:mod) => module,
          required(:arg) => arg
        }

  @doc """
  Accept (or reject) a subscription.

  Runs in the stream-handling (per-request, connection-scoped) worker process;
  set up the application subscription here (pub/sub, `GenStage`, …) and use the
  `channel`'s read-only `meta` (client info / capabilities / auth context) to
  authorize.

    * `{:stream, state}` — accept as requested: opens the long-lived SSE stream
      and honors the **full requested filter**. `Suite` then emits the
      `notifications/subscriptions/acknowledged` message (reporting the full
      requested filter) before entering the stream loop.

    * `{:stream, honored, state}` — accept but **downgrade**: honor only
      `honored` (for auth/capability reasons). `Suite` reports `honored` in the
      `acknowledged` notification. A downgrade can only narrow the requested
      filter, never widen it.

    * `{:stop, reason}` — reject: no stream is opened and a normal error
      response is returned instead (so no ack is sent).
  """
  @callback subscribe(filter :: MCP.SubscriptionFilter.t(), Channel.t(), arg) ::
              {:stream, state}
              | {:stream, honored :: MCP.SubscriptionFilter.t(), state}
              | {:stop, reason :: term}

  @doc """
  Translate an application message into notifications on the channel.

  Invoked for each process message the worker receives while the subscription is
  open — typically a pub/sub delivery. Emit the corresponding change
  notifications with `GenMCP.Mux.Channel.send_notification/2` (which stamps the
  `io.modelcontextprotocol/subscriptionId`), then return to keep the stream open
  or stop it.

    * `{:stream, state}` — continue with updated state.
    * `{:stop, reason}` — tear the subscription down.
  """
  @callback handle_message(msg :: term, Channel.t(), state, arg) ::
              {:stream, state} | {:stop, reason :: term}

  @doc """
  Teardown when the client closes the stream (close = cancel).

  The Suite-level mirror of `c:GenMCP.handle_close/2`: invoked when the client
  disconnects while this handler owns the stream. The `channel` is already
  `:closed` (nothing more can be sent) and the return value is ignored — use it
  purely for side-effecting cleanup (unsubscribing the app source, etc.).

  **Optional.** If not implemented, the worker stops immediately with no cleanup.
  """
  @callback handle_close(Channel.t(), state, arg) :: term

  @doc """
  Declare which subscription notification types this handler may emit, so
  `Suite` advertises them in `server/discover`.

  Returns a `t:subscription_capabilities/0` map of boolean flags; `Suite` folds
  the declared-`true` flags onto the catalog's capability blocks (a block is
  advertised iff the catalog has items of that kind **or** a flag is declared
  `true` for it).

  **Optional.** If not implemented, `Suite` advertises no subscription
  capability (defaults to `%{}`), so a conformant client will not send
  `subscriptions/listen`; the runtime `-32601` backstop still covers a
  misbehaving client.
  """
  @callback subscription_capabilities(Channel.t(), arg) :: subscription_capabilities

  @optional_callbacks handle_close: 3, subscription_capabilities: 2

  @doc """
  Returns a descriptor for the given `module` or `{module, arg}` tuple.

  Normalizes the configured handler into the `%{mod: module, arg: arg}` form that
  `Suite` works with internally (mirrors `GenMCP.Suite.Extension.expand/1`). A
  bare module expands with `arg` defaulting to `[]`; an already-expanded
  descriptor is returned unchanged.
  """
  @spec expand(subscription_handler) :: notification_handler_descriptor
  def expand(%{mod: _, arg: _} = handler) do
    handler
  end

  def expand(mod) when is_atom(mod) do
    expand({mod, []})
  end

  def expand({mod, arg}) when is_atom(mod) do
    Code.ensure_loaded!(mod)
    %{mod: mod, arg: arg}
  end

  def subscribe(handler, %MCP.SubscriptionsListenRequest{} = req, channel) do
    %MCP.SubscriptionFilter{} = filter = req.params.notifications
    %{mod: mod, arg: arg} = handler

    callback __MODULE__, mod.subscribe(filter, channel, arg) do
      {:stream, state} -> {:stream, filter, state}
      {:stream, %MCP.SubscriptionFilter{} = filter, state} -> {:stream, filter, state}
      {:stop, reason} -> {:stop, reason}
    end
  end

  def handle_message(handler, message, channel, state) do
    %{mod: mod, arg: arg} = handler

    callback __MODULE__, mod.handle_message(message, channel, state, arg) do
      {:stream, state} -> {:stream, state}
      {:stop, term} -> {:stop, term}
    end
  end

  def handle_close(handler, channel, state) do
    %{mod: mod, arg: arg} = handler

    if function_exported?(mod, :handle_close, 3) do
      mod.handle_close(channel, state, arg)
    else
      :ok
    end
  end

  def subscription_capabilities(handler, channel) do
    %{mod: mod, arg: arg} = handler

    if function_exported?(mod, :handle_close, 3) do
      callback __MODULE__, mod.subscription_capabilities(channel, arg) do
        map when is_map(map) ->
          Map.filter(map, fn {k, v} ->
            v == true and
              k in [
                :tools_list_changed,
                :prompts_list_changed,
                :resources_list_changed,
                :resources_updated
              ]
          end)
      end
    else
      %{}
    end
  end
end
