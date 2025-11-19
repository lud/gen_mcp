defmodule GenMCP do
  @moduledoc """
  The main behaviour for MCP servers.
  """

  alias GenMCP.MCP
  alias GenMCP.Mux.Channel

  require(Elixir.GenMCP.MCP.ModMap).require_all()

  def supported_protocol_versions do
    ["2025-06-18"]
  end

  @type state :: term

  @callback init(session_id :: String.t(), term) :: {:ok, state} | {:stop, term}

  @type request :: MCP.InitializeRequest.t()
  @type result :: MCP.InitializeResult.t()
  @type notification :: MCP.InitializedNotification.t()
  @type server_reply :: {:result, result} | :stream | {:error, term}

  @callback handle_request(request, Channel.chan_info(), state) ::
              {:reply, server_reply, state} | {:stop, reason :: term, server_reply, state}
  @callback handle_notification(notification, state) :: {:noreply, state}
  @callback handle_info(term, state) :: {:noreply, state}
end
