alias GenMCP.Support.ServerMock
alias GenMCP.Support.ToolMock
alias GenMCP.TestWeb.Router.Mcp2511
alias GenMCP.TestWeb.Router.Mcp2511Res
alias GenMCP.TestWeb.Router.Mcp2511Sub
alias GenMCP.TestWeb.Router.Mcp2511SubFull
alias GenMCP.TestWeb.Router.McpMock
alias GenMCP.TestWeb.Router.McpMockOrigins
alias GenMCP.TestWeb.Router.McpReal

require GenMCP.Transport.StreamableHTTP, as: StreamableHTTP
require GenMCP.Transport.StreamableHTTP.V2511, as: V2511

StreamableHTTP.defplug(McpMock)
StreamableHTTP.defplug(McpReal)
StreamableHTTP.defplug(McpMockOrigins)

# The 2025 compatibility transport is mounted on a real `GenMCP.Suite` with
# mock providers, not on a server mock: the point of these endpoints is the
# translation between the 2025 wire format and the 2026 core, so the core has
# to be the real one.
V2511.defplug(Mcp2511)
V2511.defplug(Mcp2511Res)
V2511.defplug(Mcp2511Sub)
V2511.defplug(Mcp2511SubFull)

defmodule GenMCP.TestWeb.Router.AuthWrapper do
  @moduledoc false

  # Wrapper is not actually needed since we use :runtime plug init mode but
  # otherwise stacktraces for mocks do not point to the right file.

  @auth_plug (if Mix.env() == :test do
                GenMCP.Support.AuthorizationMock
              else
                GenMCP.TestWeb.Router.NoAuth
              end)

  def init(opts) do
    @auth_plug.init(opts)
  end

  def call(conn, _opts) do
    @auth_plug.call(conn, [])
  end
end

defmodule GenMCP.TestWeb.Router.NoAuth do
  @moduledoc false
  @behaviour Plug

  def init(opts) do
    opts
  end

  def call(conn, _opts) do
    conn
  end
end

defmodule GenMCP.TestWeb.Router do
  @moduledoc false
  use Phoenix.Router

  scope "/dummy", GenMCP.TestWeb do
    get "/sse-test", LoopController, :sse
  end

  scope "/mcp" do
    if Mix.env() == :test do
      forward "/mock", McpMock, server: ServerMock, foo: :bar

      forward "/mock-origins", McpMockOrigins,
        server: ServerMock,
        allowed_origins: ["https://app.example.com"]

      forward "/v2511", Mcp2511,
        server_name: "Compat Server",
        server_version: "9.9.9",
        tools: [ToolMock]

      # A compat mount that declares resources, for the `resources/*` routes.
      forward "/v2511-res", Mcp2511Res,
        server_name: "Compat Server",
        server_version: "9.9.9",
        tools: [ToolMock],
        resources: [{GenMCP.Support.ResourceRepoMock, :compat_repo}]

      forward "/v2511-sub", Mcp2511Sub,
        server_name: "Compat Server",
        server_version: "9.9.9",
        tools: [ToolMock],
        subscription_handler: GenMCP.Support.SubscriptionHandlerMock

      # Same, on the handler mock that implements the optional `handle_close/3`,
      # for the client-disconnect test.
      forward "/v2511-sub-full", Mcp2511SubFull,
        server_name: "Compat Server",
        server_version: "9.9.9",
        tools: [ToolMock],
        subscription_handler: GenMCP.Support.SubscriptionHandlerFullMock

      scope "/" do
        pipe_through :auth

        forward "/mock-auth", McpMock,
          server: ServerMock,
          assigns: %{assign_from_forward: "hello", shared_assign: "from forward"},
          copy_assigns: [:assign_from_auth, :shared_assign, :unexisting_assign]
      end
    end
  end

  pipeline :auth do
    plug GenMCP.TestWeb.Router.AuthWrapper
  end
end
