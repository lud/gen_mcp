alias GenMCP.Support.ServerMock
alias GenMCP.TestWeb.Router.McpMock
alias GenMCP.TestWeb.Router.McpReal

require GenMCP.Transport.StreamableHTTP, as: StreamableHTTP

StreamableHTTP.defplug(McpMock)
StreamableHTTP.defplug(McpReal)
StreamableHTTP.defplug(McpPizza)

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

  pipeline :auth do
    plug GenMCP.TestWeb.Router.AuthWrapper
  end

  scope "/dummy", GenMCP.TestWeb do
    get "/sse-test", LoopController, :sse
  end

  scope "/mcp" do
    if Mix.env() == :test do
      forward "/mock", McpMock, server: ServerMock, foo: :bar

      scope "/" do
        pipe_through :auth

        forward "/mock-auth", McpMock,
          server: ServerMock,
          assigns: %{assign_from_forward: "hello", shared_assign: "from forward"},
          copy_assigns: [:assign_from_auth, :shared_assign, :unexisting_assign]
      end
    end

    forward "/real", McpReal,
      server_name: "Real Server",
      server_version: "0.0.1",
      server_title: "GenMCP own development server",
      tools: [GenMCP.Test.Tools.ErlangHasher, GenMCP.Test.Tools.Addition],
      extensions: [],
      foo: :bar

    forward "/pizza", McpPizza,
      server_name: "Pizza Server",
      server_version: "0.1.0",
      extensions: [GenMCP.Test.Extensions.Pizzaz]
  end

  # serve static assets for pizza example
  "test/support/extensions/pizzaz/assets/*"
  |> Path.wildcard()
  |> Enum.filter(&Regex.match?(~r{\.(js|css|map)$}, &1))
  |> Enum.map(fn p -> {Path.absname(p), Path.basename(p)} end)
  |> Enum.each(fn {absname, filename} ->
    get "/" <> filename, GenMCP.TestWeb.AssetController, :asset, assigns: %{asset_path: absname}
  end)
end
