# credo:disable-for-this-file Credo.Check.Readability.LargeNumbers

defmodule GenMCP.Error.Compiler do
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

defmodule GenMCP.Error do
  @moduledoc """
  Helper module used to transform application errors into MCP/RPC error
  payloads and HTTP status codes.
  """

  import GenMCP.Error.Compiler

  @rpc_invalid_request -32_600
  @rpc_invalid_params -32_602
  @rpc_method_not_found -32_601
  @rpc_internal_error -32_603
  @mcp_resource_not_found -32_602
  @mcp_header_mismatch -32_001
  @mcp_prompt_not_found @rpc_invalid_params

  # https://github.com/modelcontextprotocol/modelcontextprotocol/issues/1442
  @mcp_unsupported_protocol_version -32_004

  # The body of the 403 MAY be an id-less JSON-RPC error (draft transport spec,
  # Security & Endpoint); no specific code is mandated.
  defcasterror {:origin_forbidden, origin}, @rpc_invalid_request, 403 do
    %{
      message: "Origin not allowed",
      data: %{origin: origin}
    }
  end

  # The per-request worker exited without delivering a result (crash or silent
  # stop). The relay converts it to a proper JSON-RPC error instead of leaking
  # a generic Bandit 500. Crash details stay in the logs, not in the response.
  defcasterror :server_crashed, @rpc_internal_error, 500 do
    %{
      message: "Internal server error"
    }
  end

  defcasterror {:header_missing, header}, @mcp_header_mismatch, 400 do
    %{
      message: "Missing required header #{header}"
    }
  end

  defcasterror {:header_mismatch, header, hv, bv}, @mcp_header_mismatch, 400 do
    %{
      message:
        "Header mismatch: header #{header} with value #{inspect(hv)} does not match body value #{inspect(bv)}"
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

  defcasterror {:invalid_body, %JSV.ValidationError{} = e}, @rpc_invalid_params, 400 do
    %{
      data: JSV.normalize_error(e),
      message: "Invalid Parameters"
    }
  end

  defcasterror {:invalid_params, %JSV.ValidationError{} = e}, @rpc_invalid_params, 200 do
    %{
      data: JSV.normalize_error(e),
      message: "Invalid Parameters"
    }
  end

  defcasterror {:invalid_params, errmsg} when is_binary(errmsg), @rpc_invalid_params, 200 do
    %{
      message: "Invalid Parameters: " <> errmsg
    }
  end

  defcasterror {:invalid_params, _}, @rpc_invalid_params, 200 do
    %{
      message: "Invalid Parameters"
    }
  end

  # JSON-RPC level: client sent an unsupported protocolVersion in the initialize request.
  # This is an application-level error, returned as HTTP 200 with a JSON-RPC error body.
  defcasterror {:unsupported_protocol_version, unsupported},
               @mcp_unsupported_protocol_version,
               400 do
    %{
      data: %{requested: unsupported, supported: GenMCP.supported_protocol_versions()},
      message: "Unsupported protocol version"
    }
  end

  defcasterror {:unknown_tool, name} when is_binary(name), @rpc_invalid_params, 200 do
    %{
      data: %{tool: name},
      message: "Unknown tool #{name}"
    }
  end

  defcasterror {:resource_not_found, uri} when is_binary(uri), @mcp_resource_not_found, 200 do
    %{
      data: %{uri: uri},
      message: "Resource not found: #{uri}"
    }
  end

  defcasterror {:prompt_not_found, name} when is_binary(name), @mcp_prompt_not_found, 200 do
    %{
      data: %{name: name},
      message: "Prompt not found: #{name}"
    }
  end

  defcasterror :invalid_cursor, @rpc_invalid_params, 200 do
    %{
      message: "Invalid pagination cursor"
    }
  end

  defcasterror :expired_cursor, @rpc_invalid_params, 200 do
    %{
      message: "Expired pagination cursor"
    }
  end

  # A legal MCP method that this server does not implement (e.g. an optional
  # capability it never advertised). The request validated fine and was
  # dispatched, so this is an application-level JSON-RPC error in a 200 response
  # — distinct from {:unknown_method, _}, a method outside the protocol entirely
  # that the transport rejects with 404 before dispatch.
  defcasterror {:unsupported_method, method} when is_binary(method), @rpc_method_not_found, 200 do
    %{
      data: %{method: method},
      message: "Method not supported: #{method}"
    }
  end

  defcasterror message when is_binary(message), @rpc_internal_error, 500 do
    %{
      message: message
    }
  end

  defcasterror {:unknown_method, method} when is_binary(method), @rpc_method_not_found, 404 do
    %{
      data: %{method: method},
      message: "Unknown method #{method}"
    }
  end

  defcasterror %NimbleOptions.ValidationError{}, @rpc_internal_error, 500 do
    %{
      message: "Internal Error"
    }
  end

  defcasterror :invalid_request_state, @rpc_invalid_params, 200 do
    %{
      message: "Invalid request state"
    }
  end

  defcasterror :expired_request_state, @rpc_invalid_params, 200 do
    %{
      message: "Expired request state"
    }
  end

  defcasterror {:mcp_error, rpc_code, status_code, message}, rpc_code, status_code do
    %{
      message: message
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
    def unknown_error({%ExUnit.AssertionError{} = e, stack}) do
      :ok = IO.puts([IO.ANSI.red(), Exception.format(:error, e, stack), IO.ANSI.reset()])
    end

    def unknown_error(reason) do
      raise ArgumentError, "unknown MCP error: #{inspect(reason)}"
    end
  else
    def unknown_error(_reason) do
      :ok
    end
  end
end
