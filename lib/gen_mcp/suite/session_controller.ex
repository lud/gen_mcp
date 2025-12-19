defmodule GenMCP.Suite.SessionController do
  @moduledoc """
  Behaviour for session controllers.
  """

  alias GenMCP.Mux.Channel
  alias GenMCP.Suite.PersistedClientInfo

  @type session_id :: String.t()
  @type arg :: term()
  @type restore_data :: term()
  @type session_state :: term()
  @type channel :: Channel.t()

  @doc """
  Retrieves an existing stored session.

  A channel is given to be able to compare authenticated channels with session
  ownership, but the channel cannot be altered at this step, so the callback
  does not return it.

  The `GenMCP` server implementation should call the `c:restore/3`
  callback, as does `GenMCP.Suite` to allow the session controller to define
  shared assigns.
  """
  @callback fetch(session_id :: String.t(), channel, arg) ::
              {:ok, restore_data}
              | {:error, :not_found}

  @doc """
  Called by `GenMCP.Suite` or custom implementations when a new session is
  created during initialization.

  Returns the updated channel with any default assigns, and the session state.
  """
  @callback create(session_id, PersistedClientInfo.normalized(), channel, arg) ::
              {:ok, channel, session_state}
              | {:stop, reason :: term()}

  @doc """
  Called by `GenMCP.Suite` or custom implementations when a session is
  initialized and before the session timeout time is reached.

  Returns the updated channel with any default assigns, and the session state.
  """
  @callback update(session_id, PersistedClientInfo.normalized(), channel, arg) ::
              {:ok, channel, session_state}
              | {:stop, reason :: term()}

  @doc """
  Called by `GenMCP.Suite` or custom implementations when a session is restored
  from stored data.

  Receives the return value of `c:fetch/3` as `session_state`.

  Returns the persisted client information, the updated channel with any
  restored assigns, and the session state.
  """
  @callback restore(restore_data, channel, arg) ::
              {:ok, PersistedClientInfo.normalized(), channel, session_state}
              | {:stop, reason :: term()}

  @doc """
  Called by `GenMCP.Suite` or custom implementations when the session process
  receives an info message.

  Once created or restored, the original arg from the `:session_controller`
  option given to server implementation is not carried anymore. Data that must
  be available at all time should be added into the `session_state`.

  Returns the updated session state and optionally the channel updated with
  assigns.

  To not be fighting about muscle memory, callback implementations must return
  `:noreply` tuples instead of `:ok` tuples!
  """

  # TODO maybe we should find another name, because handle_info is typically a
  # 2-arity function

  @callback handle_info(info :: term(), channel, session_state) ::
              {:noreply, channel, session_state}
              | {:noreply, session_state}
              | {:stop, reason :: term()}

  @doc """
  Called by `GenMCP.Suite` or custom implementations when the listener channel
  change.

  A listener channel is typically representing the HTTP request streaming from
  GET request to the MCP endpoint, used to send notifications and requests to
  the client that are not related to any client request.

  Channels can be open and closed at any time by the client. GenMCP will only
  allow one listener channel to be open at the same time. When the channel is
  closed by the client, this callback will be called with a channel whose
  `status` property is `:closed` and `:client` property is `nil` (instead of the
  HTTP request controller pid).

  To initialize the session controller with a closed channel after session
  initialization, this callback is also called immediately after the
  InitializeRequest is handled by the MCP server. In general this will happen
  before the InitializedNotification is received, so before the `c:update/4`
  callback is called, but it may depend on the client implementation.

  This callback is the right place to setup/teardown subscriptions to pubsub,
  GenStage, etc.

  Returns the updated session state and optionally the channel updated with
  assigns.

  ### Sequence diagram

  <div class="mermaid">
  sequenceDiagram
    Client ->> Suite: POST InitializeRequest
    Suite ->> SessionController: create/3
    par client initialization DOWN
        Client ->> Suite: DOWN (InitializeRequest)
        Suite ->> SessionController: listener_change/3 (closed)
    and notification
        Client ->> Suite: POST InitializedNotification
        Suite ->> SessionController: update/3
    end
    Client ->> Suite: GET ListenerRequest
    Suite ->> SessionController: listener_change/3 (stream)
    Client ->> Suite: DOWN (ListenerRequest)
    Suite ->> SessionController: listener_change/3 (closed)
  </div>
  """

  @callback listener_change(channel, session_state) ::
              {:ok, channel, session_state} | {:ok, session_state}

  @doc """
  Called by `GenMCP.Suite` or custom implementations when a session is being
  deleted.

  The return value is not checked. If the callback exits or raises, the session
  process will be terminated immediately. Failure to delete persisted data will
  not be retried and the session may be restore-able again, depending on your
  implementation.
  """
  @callback delete(session_id, session_state) :: term
end
