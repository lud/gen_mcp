defmodule GenMcp.Error do
  defmacro errno do
    pk = {__MODULE__, :errno}
    prev = Process.get(pk, 0)
    code = prev + 1
    Process.put(pk, code)

    quote do
      unquote(code)
    end
  end

  def bad_rpc do
    %{
      code: errno(),
      data: nil,
      message: "invalid JSON-RPC payload"
    }
  end

  def json_schema_validation(jsv_err) do
    %{
      code: errno(),
      data: JSV.normalize_error(jsv_err),
      message: "request validation failed"
    }
  end

  def unknown_tool(tool_name) do
    %{
      code: errno(),
      message: "unknown tool #{tool_name}"
    }
  end
end
