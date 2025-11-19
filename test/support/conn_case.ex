defmodule GenMCP.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Phoenix.ConnTest

  require Phoenix.ConnTest

  using do
    quote do
      use GenMCP.TestWeb, :verified_routes

      import Phoenix.ConnTest
      import Phoenix.Controller, only: [json: 2, text: 2, html: 2]
      import Plug.Conn
      import unquote(__MODULE__)

      @endpoint GenMCP.TestWeb.Endpoint
    end
  end

  setup _tags do
    conn = ConnTest.build_conn()
    {:ok, conn: conn}
  end
end
