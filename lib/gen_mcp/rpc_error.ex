# credo:disable-for-this-file Credo.Check.Readability.LargeNumbers

defmodule GenMcp.RpcError.Compiler do
  # RPC codes https://docs.trafficserver.apache.org/en/latest/developer-guide/jsonrpc/jsonrpc-node-errors.en.html

  defmacro defcasterror(matcher, rpc_code, http_status, [{:do, payload}]) do
    {matcher, guard} =
      case matcher do
        {:when, whenmeta, [matcher, guard]} -> {matcher, guard}
        matcher -> {matcher, true}
      end

    quote do
      def cast_error(unquote(matcher)) when unquote(guard) do
        http_status = unquote(http_status)
        payload = unquote(payload)
        payload = Map.put(payload, :code, unquote(rpc_code))
        {http_status, payload}
      end
    end
  end
end

defmodule GenMcp.RpcError do
  import GenMcp.RpcError.Compiler

  defcasterror :missing_session_id, :missing_session_id, 400 do
    %{
      message: "Header mcp-session-id was not provided"
    }
  end

  defcasterror :bad_rpc, -32600, 400 do
    %{
      message: "Invalid RPC request"
    }
  end

  defcasterror :bad_rpc_version, 1, 400 do
    %{
      message: "Invalid RPC version, only 2.0 is accepted"
    }
  end

  defcasterror {:jsv_err, e}, -32602, 400 do
    %{
      data: JSV.normalize_error(e),
      message: "Invalid Parameters"
    }
  end

  defcasterror {:unknown_tool, name} when is_binary(name), -32602, 400 do
    %{
      data: %{tool: name},
      message: "Unknown tool #{name}"
    }
  end

  # TODO telemetry report error
  defcasterror reason, -32603, 500 do
    %{
      message: "Internal Error"
    }
  end
end
