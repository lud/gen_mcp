defmodule GenMCP.SessionController do
  @moduledoc """
  Behaviour for session controllers.
  """

  alias GenMCP.Mux.Channel

  @callback fetch_session(session_id :: String.t(), channel :: Channel.t(), opts :: any()) ::
              {:ok, session_data :: any()} | {:error, :not_found}
end
