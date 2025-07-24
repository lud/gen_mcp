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
    # just to check transitive connectivity we will only connect to nodes with
    # lower and greated integer value
    str = Atom.to_string(node())

    case str do
      "genmcpdev-" <> rest ->
        {int, "@127.0.0.1"} = Integer.parse(rest)

        case int do
          0 ->
            Node.connect(:"genmcpdev-#{1}@127.0.0.1")

          n ->
            Node.connect(:"genmcpdev-#{n - 1}@127.0.0.1")
            Node.connect(:"genmcpdev-#{n + 1}@127.0.0.1")
        end

      _ ->
        # In tests or "mix run" without the demo node names we do not connect
        :ok
    end
  end
end
