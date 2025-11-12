# credo:disable-for-this-file Credo.Check.Readability.LargeNumbers

defmodule GenMCP.RpcError.Compiler do
  # RPC codes https://docs.trafficserver.apache.org/en/latest/developer-guide/jsonrpc/jsonrpc-node-errors.en.html
  # MCP specific http://mcpevals.io/blog/mcp-error-codes

  defmacro defcasterror(matcher, rpc_code, http_status, [{:do, payload}]) do
    {matcher, guard} =
      case matcher do
        {:when, _whenmeta, [matcher, guard]} -> {matcher, guard}
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

defmodule GenMCP.RpcError do
  @rpc_invalid_request -32600
  @rpc_invalid_params -32602
  @rpc_internal_error -32603
  @rpc_resource_not_found -32002
  @rpc_prompt_not_found @rpc_invalid_params

  import GenMCP.RpcError.Compiler
  require Logger

  defcasterror :missing_session_id, :missing_session_id, 400 do
    %{
      message: "Header mcp-session-id was not provided"
    }
  end

  defcasterror :bad_rpc, @rpc_invalid_request, 400 do
    %{
      message: "Invalid RPC request"
    }
  end

  defcasterror :bad_rpc_version, 1, 400 do
    %{
      message: "Invalid RPC version, only 2.0 is accepted"
    }
  end

  defcasterror %JSV.ValidationError{} = e, @rpc_invalid_params, 400 do
    %{
      data: JSV.normalize_error(e),
      message: "Invalid Parameters"
    }
  end

  defcasterror :already_initialized, @rpc_invalid_params, 400 do
    %{
      message: "Session is already initialized"
    }
  end

  defcasterror {:unsupported_protocol, version}, @rpc_invalid_request, 400 do
    %{
      data: %{version: version, supported: GenMCP.supported_protocol_versions()},
      message: "Unsupported protocol version"
    }
  end

  defcasterror {:unknown_tool, name} when is_binary(name), @rpc_invalid_params, 400 do
    %{
      data: %{tool: name},
      message: "Unknown tool #{name}"
    }
  end

  defcasterror {:resource_not_found, uri} when is_binary(uri), @rpc_resource_not_found, 400 do
    %{
      data: %{uri: uri},
      message: "Resource not found: #{uri}"
    }
  end

  defcasterror {:prompt_not_found, name} when is_binary(name), @rpc_prompt_not_found, 400 do
    %{
      data: %{name: name},
      message: "Prompt not found: #{name}"
    }
  end

  defcasterror :invalid_cursor, @rpc_invalid_params, 400 do
    %{
      message: "Invalid pagination cursor"
    }
  end

  defcasterror :expired_cursor, @rpc_invalid_params, 400 do
    %{
      message: "Expired pagination cursor"
    }
  end

  defcasterror message when is_binary(message), @rpc_internal_error, 500 do
    %{
      message: message
    }
  end

  defcasterror :not_initialized, @rpc_internal_error, 400 do
    %{
      message: "Server not initialized"
    }
  end

  @raise_on_unknown Mix.env() == :test

  defcasterror {:session_start_failed, _reason}, @rpc_internal_error, 500 do
    %{
      message: "Session Start Error"
    }
  end

  defcasterror reason, @rpc_internal_error, 500 do
    msg = "unknown MCP RPC error: #{inspect(reason)}"
    Logger.warning(msg)

    if Process.get(:_type_checker_hack_unknown_rpc_error_reason, @raise_on_unknown) do
      raise ArgumentError, msg
    end

    %{
      message: "Internal Error"
    }
  end
end
