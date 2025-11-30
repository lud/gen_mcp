defmodule GenMCP.TestWeb.AssetController do
  @moduledoc false

  use GenMCP.TestWeb, :controller

  def asset(conn, _) do
    asset_path = conn.assigns.asset_path

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_content_type(content_type(asset_path), nil)
    |> send_file(200, conn.assigns.asset_path)
  end

  defp content_type(asset_path) do
    cond do
      String.ends_with?(asset_path, ".js") -> "text/javascript"
      String.ends_with?(asset_path, ".css") -> "text/css"
      true -> "text/plain"
    end
  end
end
