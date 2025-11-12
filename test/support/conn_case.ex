defmodule GenMCP.ConnCase do
  alias Phoenix.ConnTest
  require Phoenix.ConnTest
  use ExUnit.CaseTemplate

  @moduledoc false

  using do
    quote do
      @endpoint GenMCP.TestWeb.Endpoint

      import unquote(__MODULE__)
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.Controller, only: [json: 2, text: 2, html: 2]

      use GenMCP.TestWeb, :verified_routes
    end
  end

  setup _tags do
    conn = ConnTest.build_conn()
    {:ok, conn: conn}
  end
end
