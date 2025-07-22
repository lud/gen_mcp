defmodule GenMcp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  IO.warn("@todo remove autoconnect")

  def start(_type, _args) do
    children = [
      GenMcp.NodeSync.pg_child_spec(),
      GenMcp.NodeSync,
      {Task, &connect/0}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GenMcp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def connect do
    require Logger

    for i <- 0..10 do
      node = :"genmcpdev-#{i}@127.0.0.1"
      Node.connect(node)
    end
  end
end
