defmodule GenMcp.TestWeb do
  @moduledoc false

  def controller do
    quote do
      import Plug.Conn

      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: []

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: GenMcp.TestWeb.Endpoint,
        router: GenMcp.TestWeb.Router
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
