defmodule GenMCP.TestWeb.Endpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :gen_mcp

  plug Plug.RequestId

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    body_reader: {__MODULE__, :read_body, []},
    json_decoder: Phoenix.json_library()

  plug GenMCP.TestWeb.Router

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, conn}
      # require(Logger).debug(
      #   """
      #   INPUT BODY
      #   #{body}
      #   """,
      #   ansi_color: :light_blue
      # )
      other -> raise "bad parse: #{inspect(other)}"
    end
  end
end
