defmodule GenMCP.SessionController do
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

  IO.warn(
    """
    define a doc section for the callbacks explaining that GenMCP.Suite will call
    them, but it is not automatically done when using custom GenMCP
    implementations.

    Specifiy that the channel is the initialization channel until a GET request is
    received.

    Also when the get request is :DOWN, the channel must have a special tag that
    says nothing is listening right now.
    """,
    []
  )

  @doc """
  Called by `GenMCP.Suite` or custom implementations when a new session is
  created during initialization.

  Returns the updated channel with any default assigns, and the session state.
  """
  @callback create(session_id, PersistedClientInfo.normalized(), channel, arg) ::
              {:ok, channel, session_state}
              | {:stop, reason :: term()}

  IO.warn("todo update session when initialized notification is received", [])
  # @doc """
  # Called by `GenMCP.Suite` or custom implementations when a session is
  # initialized and before the session timeout time is reached.

  # Returns the updated channel with any default assigns, and the session state.
  # """
  # @callback update(session_id, PersistedClientInfo.normalized(), channel, arg) ::
  #             {:ok, channel, session_state}
  #             | {:stop, reason :: term()}

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
  """

  # TODO maybe we should find another name, because handle_info is typically a
  # 2-arity function

  @callback handle_info(info :: term(), channel, session_state) ::
              {:noreply, channel, session_state}
              | {:noreply, session_state}
              | {:stop, reason :: term()}

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
