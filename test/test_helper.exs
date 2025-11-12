System.cmd("epmd", ~w(-daemon))
:ok = LocalCluster.start()
Application.stop(:logger)
{:ok, _} = Application.ensure_all_started(:gen_mcp)

# Start the test endpoint
{:ok, _} = GenMCP.TestWeb.Endpoint.start_link()

ExUnit.start(assert_receive_timeout: 100)
