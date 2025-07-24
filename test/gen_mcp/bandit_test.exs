defmodule GenMcp.BanditTest do
  use GenMcp.ConnCase, async: true

  test "can send message to a looping process over SSE" do
    parent = self()

    task =
      Task.async(fn ->
        Req.get!("http://localhost:5002/dummy/sse-test",
          retry: false,
          into: fn {:data, data}, {req, resp} ->
            case data do
              "pid: " <> base6_pid ->
                pid = base6_pid |> Base.decode64!() |> :erlang.binary_to_term()
                send(parent, {:controller_pid, pid})

              "msg: " <> msg ->
                send(parent, {:controller_msg, msg})
            end

            {:cont, {req, resp}}
          end
        )
      end)

    assert_receive {:controller_pid, ctpid}, 1000

    send(ctpid, {:echo, "hello"})
    assert_receive {:controller_msg, "hello"}

    send(ctpid, {:echo, "foo"})
    assert_receive {:controller_msg, "foo"}

    send(ctpid, {:echo, "with\nnew\nlines"})
    assert_receive {:controller_msg, "with\nnew\nlines"}

    send(ctpid, :stop_stream)
    assert_receive {:controller_msg, "goodbye"}

    resp = Task.await(task)
    assert %Req.Response{} = resp
    assert 200 = resp.status
    assert %{"content-type" => ["text/event-stream"]} = resp.headers
  end
end
