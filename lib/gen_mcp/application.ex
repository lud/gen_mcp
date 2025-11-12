defmodule GenMCP.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  IO.warn("@todo remove autoconnect")

  def env do
    Process.get(:never_defined, unquote(Mix.env()))
  end

  IO.warn("""
  rename NodeSync to Cluster.

  It should be a supervisor that requires a name. It starts the pg itself, deriving a name from the parent name.
  It stats the node sync
  It must start a supervisor for stateful MCP servers
  """)

  @impl true
  def start(_type, _args) do
    children =
      [
        GenMCP.NodeSync.pg_child_spec(),
        GenMCP.NodeSync,
        GenMCP.Mux.SessionSupervisor,
        {Registry, name: GenMCP.Mux.registry(), keys: :unique},
        {Task, &connect/0}
      ] ++
        if env() == :dev do
          # [GenMCP.TestWeb.Endpoint]
          []
        else
          []
        end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GenMCP.Supervisor]
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
