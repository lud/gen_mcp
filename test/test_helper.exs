# `mix test` is aliased to mix `test --no-start` so we can start the local
# cluster
System.cmd("epmd", ~w(-daemon))
:ok = LocalCluster.start()

# Need to stop the logger to reload its config
Application.stop(:logger)

{:ok, started} = Application.ensure_all_started(:gen_mcp, mode: :concurrent)
{:ok, _} = GenMCP.TestWeb.Endpoint.start_link()

ExUnit.start(assert_receive_timeout: 100)
