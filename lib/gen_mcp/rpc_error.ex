# credo:disable-for-this-file Credo.Check.Readability.LargeNumbers

defmodule GenMCP.RpcError.Compiler do
  # RPC codes https://docs.trafficserver.apache.org/en/latest/developer-guide/jsonrpc/jsonrpc-node-errors.en.html
  # MCP specific http://mcpevals.io/blog/mcp-error-codes

  @moduledoc false

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
  @moduledoc """
  Helper module used to transform application errors into MCP/RPC error
  payloads and HTTP status codes.
  """

  import GenMCP.RpcError.Compiler

  require Logger

  @rpc_invalid_request -32_600
  @rpc_invalid_params -32_602
  @rpc_method_not_found -32_601
  @rpc_internal_error -32_603
  @mcp_resource_not_found -32_002
  @mcp_prompt_not_found @rpc_invalid_params

  # https://github.com/modelcontextprotocol/modelcontextprotocol/issues/1442
  @mcp_unsupported_protocol_version -32_000

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

  defcasterror {:invalid_params, %JSV.ValidationError{} = e}, @rpc_invalid_params, 400 do
    %{
      data: JSV.normalize_error(e),
      message: "Invalid Parameters"
    }
  end

  defcasterror {:invalid_params, errmsg} when is_binary(errmsg), @rpc_invalid_params, 400 do
    %{
      message: errmsg
    }
  end

  defcasterror {:invalid_params, _}, @rpc_invalid_params, 400 do
    %{
      message: "Invalid Parameters"
    }
  end

  defcasterror :already_initialized, @rpc_invalid_params, 400 do
    %{
      message: "Session is already initialized"
    }
  end

  defcasterror {:unsupported_protocol, version}, @mcp_unsupported_protocol_version, 400 do
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

  defcasterror {:resource_not_found, uri} when is_binary(uri), @mcp_resource_not_found, 400 do
    %{
      data: %{uri: uri},
      message: "Resource not found: #{uri}"
    }
  end

  defcasterror {:prompt_not_found, name} when is_binary(name), @mcp_prompt_not_found, 400 do
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

  defcasterror {:mcp_server_init_failure, _reason}, @rpc_internal_error, 500 do
    %{
      message: "Session Start Error"
    }
  end

  defcasterror {:unknown_method, method} when is_binary(method), @rpc_method_not_found, 400 do
    %{
      data: %{method: method},
      message: "Unknown method #{method}"
    }
  end

  defcasterror {:session_not_found, sid} when is_binary(sid), @rpc_internal_error, 404 do
    %{
      data: %{session_id: sid},
      message: "Session not found"
    }
  end

  defcasterror %NimbleOptions.ValidationError{}, @rpc_internal_error, 500 do
    %{
      message: "Internal Error"
    }
  end

  # -- catchall ---------------------------------------------------------------

  defcasterror reason, @rpc_internal_error, 500 do
    unknown_error(reason)

    %{
      message: "Internal Error"
    }
  end

  if Mix.env() == :test do
    @spec unknown_error(term) :: no_return
    def unknown_error(reason) do
      raise ArgumentError, "unknown MCP error: #{inspect(reason)}"
    end
  else
    def unknown_error(_reason) do
      :ok
    end
  end
end
