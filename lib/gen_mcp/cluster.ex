defmodule GenMCP.Cluster do
  use Supervisor

  @doc false
  def scope do
    :gen_mcp_pg_scope
  end

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      pg_child_spec(),
      GenMCP.Cluster.NodeSync
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def pg_child_spec do
    %{
      id: :pg,
      module: :pg,
      start: {:pg, :start_link, [scope()]},
      type: :supervisor
    }
  end
end
