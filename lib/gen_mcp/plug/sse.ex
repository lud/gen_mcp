defmodule GenMcp.Plug.Sse do
  alias JSV.Codec
  import Plug.Conn

  @behaviour Plug

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    send_json(conn, %{})
  end

  defp send_json(conn, data) do
    send_resp(conn, 200, Codec.encode!(data))
  end
end
