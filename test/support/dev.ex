defmodule GenMCP.Support.Dev do
  @moduledoc false
  def child_spec(_) do
    Supervisor.child_spec({Task, &connect_nodes/0}, id: __MODULE__)
  end

  def connect_nodes do
    if System.get_env("GEN_MCP_DEV_AUTOCONNECT") == "true" do
      do_connect_nodes()
    else
      :ok
    end
  end

  defp do_connect_nodes do
    case Atom.to_string(node()) do
      "genmcpdev-" <> rest ->
        {n, "@127.0.0.1"} = Integer.parse(rest)

        Node.connect(:"genmcpdev-#{n - 1}@127.0.0.1")
        Node.connect(:"genmcpdev-#{n + 1}@127.0.0.1")

      _ ->
        nil
    end
  end
end
