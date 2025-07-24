defmodule GenMcp.TestWeb.Router do
  use Phoenix.Router

  @moduledoc false

  pipeline :mcp do
  end

  scope "/dummy", GenMcp.TestWeb do
    pipe_through :mcp

    get "/sse-test", LoopController, :sse
  end

  forward "/mcp", GenMcp.Plug.Sse

  match :*, "/*path", GenMcp.TestWeb.Router.Catchall, :not_found, warn_on_verify: true
end

defmodule GenMcp.TestWeb.Router.Catchall do
  use Phoenix.Controller,
    formats: [:html, :json],
    layouts: []

  @moduledoc false
  @spec not_found(term, term) :: no_return()
  def not_found(conn, _) do
    send_resp(conn, 404, "Not Found (catchall)")
  end
end
