defmodule GenMcp.Mux.SessionSupervisor do
  alias GenMcp.NodeSync
  use DynamicSupervisor

  def name do
    {:global, {__MODULE__, NodeSync.node_id()}}
  end

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: name())
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
