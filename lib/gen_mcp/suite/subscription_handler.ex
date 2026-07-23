defmodule GenMCP.Suite.SubscriptionHandler do
  @moduledoc """
  Behaviour for serving `subscriptions/listen`, the long-lived notification
  stream of a `GenMCP.Suite`.

  A client that wants server-driven change notifications
  (`notifications/tools/list_changed`, `notifications/resources/updated`, and the
  other list-changed notifications) sends a single `subscriptions/listen`
  request. Its response is an SSE stream that stays open and carries those
  notifications as they happen. A `GenMCP.Suite` routes that request to the one
  subscription handler configured on it, a module implementing this behaviour.

  The handler does three things across the life of the stream: it accepts or
  rejects the subscription and sets up the application event source in
  `c:subscribe/3`, it turns each event the worker later receives into
  notifications on the channel in `c:handle_message/4`, and it tears the source
  down in `c:handle_close/3` when the client disconnects. This streaming
  lifecycle mirrors the one in `GenMCP.Suite.Tool` (`c:GenMCP.Suite.Tool.call/3`,
  `c:GenMCP.Suite.Tool.handle_message/4`, `c:GenMCP.Suite.Tool.handle_close/3`).

  The events themselves come from the application. It broadcasts its own changes
  on whatever it already uses (`Phoenix.PubSub`, a `GenStage` pipeline, a plain
  `GenServer`), and `c:subscribe/3` is where the handler joins the
  connection-scoped worker process to that source.

  ## Minimal implementation

  A handler that lets a client subscribe to tool-list changes, which the
  application broadcasts on its `Phoenix.PubSub`. `c:subscribe/3` joins the
  worker to the topic, and `c:handle_message/4` forwards each broadcast as a
  `notifications/tools/list_changed` notification built from the
  `GenMCP.MCP.V2607` vocabulary:

      defmodule MyApp.ToolChanges do
        @behaviour GenMCP.Suite.SubscriptionHandler

        alias GenMCP.MCP.V2607, as: MCP
        alias GenMCP.Mux.Channel

        @impl true
        def subscribe(%MCP.SubscriptionFilter{toolsListChanged: true}, _channel, _arg) do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "tools")
          {:stream, %{}}
        end

        def subscribe(_filter, _channel, _arg) do
          {:stop, :nothing_to_watch}
        end

        @impl true
        def handle_message(:tools_changed, channel, state, _arg) do
          Channel.send_notification(channel, %MCP.ToolListChangedNotification{})
          {:stream, state}
        end

        @impl true
        def subscription_capabilities(_channel, _arg) do
          %{tools_list_changed: true}
        end
      end

  ### Wiring a handler into the server

  A subscription handler is given to the Suite through its `:subscription_handler`
  option, a single module or `{module, arg}` tuple (a Suite has one handler, not
  a list). Because the Suite is the default `:server`, that option is passed
  straight to the transport plug in your router:

      # In your router
      forward "/mcp", GenMCP.Transport.StreamableHTTP,
        server_name: "My App",
        server_version: "1.0.0",
        subscription_handler: MyApp.ToolChanges

  ## Advertising what can be subscribed

  A conformant client only sends `subscriptions/listen` for notification types
  the server advertises in `server/discover`. Implement
  `c:subscription_capabilities/2` to declare which types this handler emits, so
  the Suite advertises them. Without it nothing is advertised and clients will
  not subscribe.

  ## The acknowledgment is sent by the Suite

  The first message on the stream is always
  `notifications/subscriptions/acknowledged`, and the **Suite** sends it, never
  the handler. The handler's `c:subscribe/3` return only decides what the ack
  reports: `{:stream, state}` acknowledges the full requested filter, while
  `{:stream, honored, state}` acknowledges `honored`, a narrowed filter for cases
  where auth or capabilities allow only part of the request.

  ## Provider arguments

  Like the other Suite providers (see `GenMCP.Suite`), every callback receives:

  * `channel` is the request-scoped `t:GenMCP.Mux.Channel.t/0`. In `c:subscribe/3`
    and `c:subscription_capabilities/2` use its read-only `meta` (client info and
    auth assigns) to authorize. In `c:handle_message/4` and `c:handle_close/3` it
    is the channel that notifications are sent on.
  * `arg` is the value configured alongside the module as `{module, arg}` (a bare
    module is treated as `{module, []}`), letting one handler module be
    configured differently in different Suites.
  """

  import GenMCP.Utils.CallbackExt

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Mux.Channel

  @type arg :: term

  @type state :: term

  @type subscription_capabilities :: %{
          optional(:tools_list_changed) => boolean,
          optional(:prompts_list_changed) => boolean,
          optional(:resources_list_changed) => boolean,
          optional(:resources_updated) => boolean
        }

  @type subscription_handler :: module | {module, arg} | notification_handler_descriptor

  @type notification_handler_descriptor :: %{
          required(:mod) => module,
          required(:arg) => arg
        }

  @doc """
  Accepts or rejects a `subscriptions/listen` request and sets up the event source.

  Runs in the connection-scoped worker process that owns the stream. Subscribe
  the worker to the application's event source here (`Phoenix.PubSub`, a
  `GenStage` consumer, ...), and use the `channel`'s read-only `meta` to
  authorize. The `filter` is the `t:GenMCP.MCP.V2607.SubscriptionFilter.t/0` the
  client requested, naming the notification types it wants.

  The Suite sends the `acknowledged` message when this callback accepts, and the
  spec requires that message to be the first one carrying this subscription's
  id. Keep this callback to setup and authorization, and emit every notification
  from `c:handle_message/4`, once the stream is acknowledged and open. A handler
  that wants to push an initial notification right away can `send/2` itself a
  message here and emit from `c:handle_message/4` when it arrives.

  Return one of:

  * `{:stream, state}` - accept as requested. The Suite opens the stream and
    sends the `acknowledged` message reporting the full requested `filter`.
    `state` is the handler-private value carried to `c:handle_message/4`.
  * `{:stream, honored, state}` - accept but downgrade to `honored`, a filter
    that narrows (never widens) the request, for auth or capability reasons. The
    Suite reports `honored` in the `acknowledged` message.
  * `{:stop, reason}` - reject. No stream opens and no ack is sent; the Suite
    returns a normal error response instead.

  Enforcing the filter, that is not emitting a type the client did not request,
  is the handler's job: the Suite does not drop notifications at send time.

  ### Examples

  Accept only when the client asked for the type this handler serves, joining the
  app's pub/sub and starting from empty state:

      @impl true
      def subscribe(%MCP.SubscriptionFilter{toolsListChanged: true}, _channel, _arg) do
        Phoenix.PubSub.subscribe(MyApp.PubSub, "tools")
        {:stream, %{}}
      end

  Downgrade a broad request to only the part an unauthenticated caller may see:

      @impl true
      def subscribe(filter, channel, _arg) do
        honored =
          case channel.meta do
            %{current_user: %{role: :admin}} -> filter
            _ -> %MCP.SubscriptionFilter{toolsListChanged: filter.toolsListChanged}
          end

        {:stream, honored, %{}}
      end
  """
  @callback subscribe(filter :: MCP.SubscriptionFilter.t(), Channel.t(), arg) ::
              {:stream, state}
              | {:stream, honored :: MCP.SubscriptionFilter.t(), state}
              | {:stop, reason :: term}

  @doc """
  Turns one process message received while the stream is open into notifications.

  Invoked for each message the worker process receives during the subscription,
  typically a delivery from the event source joined in `c:subscribe/3`. Send the
  matching change notifications with `GenMCP.Mux.Channel.send_notification/2`
  (which stamps each one with the `io.modelcontextprotocol/subscriptionId` that
  ties it to this stream), then return to continue or stop.

  * `{:stream, state}` - keep the stream open with updated `state`.
  * `{:stop, reason}` - tear the subscription down gracefully. The Suite ends
    the stream by sending a `t:GenMCP.MCP.V2607.SubscriptionsListenResult.t/0`
    (`resultType: "complete"`, stamped with this stream's
    `io.modelcontextprotocol/subscriptionId`). The `reason` is split two ways:
    it is **not** surfaced to the client — the spec has no way to signal a failed
    teardown, so every stop yields the same graceful `complete` result — but it
    **is** forwarded to the OTP layer as the worker's exit reason. Use `:normal`,
    `:shutdown`, or `{:shutdown, term}` to keep that a clean exit.

  ### Examples

  Forward an application broadcast as a tool-list-changed notification, then keep
  the stream open:

      @impl true
      def handle_message(:tools_changed, channel, state, _arg) do
        Channel.send_notification(channel, %MCP.ToolListChangedNotification{})
        {:stream, state}
      end
  """
  @callback handle_message(msg :: term, Channel.t(), state, arg) ::
              {:stream, state} | {:stop, reason :: term}

  @doc """
  Cleans up when the stream is closed from the connection side. Optional.

  The Suite-level mirror of `c:GenMCP.handle_close/2`, invoked when the
  subscription stream is torn down from the outside while this handler owns it —
  the client disconnecting or the network failing — rather than by the handler's
  own `{:stop, reason}` (which ends the stream with a `SubscriptionsListenResult`
  and does not run this callback). The `channel` is already `:closed`, so nothing
  more can be sent and the return value is ignored. Use it only for side effects:
  unsubscribing the event source joined in `c:subscribe/3`, stopping helper
  processes, and so on.

  If the handler does not implement it, the worker stops immediately with no
  cleanup.

  ### Examples

      @impl true
      def handle_close(_channel, _state, _arg) do
        Phoenix.PubSub.unsubscribe(MyApp.PubSub, "tools")
        :ok
      end
  """
  @callback handle_close(Channel.t(), state, arg) :: term

  @doc """
  Declares which subscription notification types this handler can emit. Optional.

  The Suite calls this while building `server/discover` and folds the types
  declared `true` into the advertised capabilities, so a conformant client knows
  it may request them on `subscriptions/listen`. Return a
  `t:subscription_capabilities/0` map; the recognized keys are:

  * `:tools_list_changed` - `notifications/tools/list_changed`.
  * `:prompts_list_changed` - `notifications/prompts/list_changed`.
  * `:resources_list_changed` - `notifications/resources/list_changed`.
  * `:resources_updated` - `notifications/resources/updated`.

  Keys that are absent or `false` advertise nothing. If the handler does not
  implement this callback, the Suite advertises no subscription capability, so a
  conformant client will not subscribe.

  ### Examples

      @impl true
      def subscription_capabilities(_channel, _arg) do
        %{tools_list_changed: true, resources_updated: true}
      end
  """
  @callback subscription_capabilities(Channel.t(), arg) :: subscription_capabilities

  @optional_callbacks handle_close: 3, subscription_capabilities: 2

  @doc """
  Returns the descriptor map for a configured subscription handler.

  Normalizes the `:subscription_handler` option into the `%{mod: module, arg:
  arg}` form the Suite uses internally, accepting a bare module (with `arg`
  defaulting to `[]`), a `{module, arg}` tuple, or an already-expanded descriptor
  (returned unchanged). For the bare and tuple forms the module is loaded with
  `Code.ensure_loaded!/1`, so this raises if it does not exist.
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

  @doc """
  Invokes the handler's `c:subscribe/3` for a `subscriptions/listen` request.

  Given a descriptor from `expand/1`, the
  `t:GenMCP.MCP.V2607.SubscriptionsListenRequest.t/0`, and the request `channel`,
  calls the handler with the request's filter and the descriptor's `arg`, then
  normalizes the result so an accepted subscription always carries an explicit
  honored filter (`{:stream, filter, state}`). `GenMCP.Suite` uses this to drive
  a listen request.
  """
  def subscribe(handler, %MCP.SubscriptionsListenRequest{} = req, channel) do
    %MCP.SubscriptionFilter{} = filter = req.params.notifications
    %{mod: mod, arg: arg} = handler

    callback __MODULE__, mod.subscribe(filter, channel, arg) do
      {:stream, state} -> {:stream, filter, state}
      {:stream, %MCP.SubscriptionFilter{} = filter, state} -> {:stream, filter, state}
      {:stop, reason} -> {:stop, reason}
    end
  end

  @doc """
  Invokes the handler's `c:handle_message/4` for one stream message.

  Calls the handler with the application `message`, the `channel`, the handler
  `state`, and the descriptor's `arg`, returning its `{:stream, state}` or
  `{:stop, reason}` result. `GenMCP.Suite` calls this for every message the
  subscription worker receives.
  """
  def handle_message(handler, message, channel, state) do
    %{mod: mod, arg: arg} = handler

    callback __MODULE__, mod.handle_message(message, channel, state, arg) do
      {:stream, state} -> {:stream, state}
      {:stop, term} -> {:stop, term}
    end
  end

  @doc """
  Invokes the handler's `c:handle_close/3` on client disconnect, if implemented.

  Calls the optional callback with the closed `channel`, the handler `state`, and
  the descriptor's `arg`. When the handler does not export it, returns `:ok`
  without doing anything. `GenMCP.Suite` calls this when the client closes the
  stream.
  """
  def handle_close(handler, channel, state) do
    %{mod: mod, arg: arg} = handler

    if function_exported?(mod, :handle_close, 3) do
      mod.handle_close(channel, state, arg)
    else
      :ok
    end
  end

  @doc """
  Returns the handler's declared subscription capabilities for `server/discover`.

  Invokes the optional `c:subscription_capabilities/2` callback with the
  `channel` and the descriptor's `arg`, keeping only the recognized keys set to
  `true`, and returns `%{}` when the handler declares none. `GenMCP.Suite` folds
  the result into the capabilities it advertises.
  """
  def subscription_capabilities(handler, channel) do
    %{mod: mod, arg: arg} = handler

    if function_exported?(mod, :subscription_capabilities, 2) do
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
