defmodule GenMCP.TestWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :gen_mcp

  @moduledoc false

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    body_reader: {__MODULE__, :read_body, []},
    json_decoder: Phoenix.json_library()

  plug GenMCP.TestWeb.Router

  def read_body(conn, opts) do
    with {:ok, body, conn} <- Plug.Conn.read_body(conn, opts) do
      require(Logger).debug(
        """
        INPUT BODY
        #{body}
        """,
        ansi_color: :light_blue
      )

      {:ok, body, conn}
    end
  end
end
