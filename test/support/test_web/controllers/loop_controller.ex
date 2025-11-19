defmodule GenMCP.TestWeb.LoopController do
  @moduledoc false

  use GenMCP.TestWeb, :controller

  def sse(conn, _params) do
    conn = put_resp_header(conn, "content-type", "text/event-stream")
    conn = send_chunked(conn, 200)

    {:ok, conn} = chunk(conn, "pid: " <> (self() |> :erlang.term_to_binary() |> Base.encode64()))

    echo_loop(conn)
  end

  defp echo_loop(conn) do
    receive do
      {:echo, msg} ->
        {:ok, conn} = chunk(conn, "msg: #{msg}")
        echo_loop(conn)

      :stop_stream ->
        {:ok, conn} = chunk(conn, "msg: goodbye")
        conn
    end
  end
end
