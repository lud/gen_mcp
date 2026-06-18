# credo:disable-for-this-file Credo.Check.Readability.LargeNumbers

defmodule GenMCP.SuiteTest do
  use ExUnit.Case, async: true

  # Spec 004 — the stateless server contract.
  #
  # The Suite is driven exactly as the per-request worker (`GenMCP.Server`)
  # drives any `GenMCP` implementation:
  #
  #     {:ok, state} = Suite.init(server_opts)     # runs per request
  #     Suite.handle_request(req, channel, state)  # terminal or {:stream, state}
  #     Suite.handle_message(msg, channel, state)  # only after {:stream, _}
  #
  # There is no session: no initialize handshake, no session id, no
  # InitializedNotification bookkeeping. Client info and capabilities ride in
  # the request `_meta` and reach the Suite as the channel's read-only `meta`.
  # Requests are the `GenMCP.MCP.V2607` structs produced by the transport
  # validator.

  import GenMCP.Test.Helpers
  import Mox

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Mux.Channel
  alias GenMCP.Suite
  alias GenMCP.Suite.Tool
  alias GenMCP.Support.ExtensionMock
  alias GenMCP.Support.PromptRepoCacheMock
  alias GenMCP.Support.PromptRepoMock
  alias GenMCP.Support.ResourceRepoCacheMock
  alias GenMCP.Support.ResourceRepoMock
  alias GenMCP.Support.ResourceRepoMockTpl
  alias GenMCP.Support.ResourceRepoTplCacheMock
  alias GenMCP.Support.ToolFullMock
  alias GenMCP.Support.ToolMock

  setup :verify_on_exit!

  @protocol_version GenMCP.protocol_version()

  @server_info [
    server_name: "Test Server",
    server_version: "0"
  ]

  # Builds the per-request state, as the worker would on every request. Each
  # call simulates a brand new request: nothing carries over between two calls.
  defp init_suite(server_opts \\ []) do
    assert {:ok, state} = Suite.init(Keyword.merge(@server_info, server_opts))
    state
  end

  # The V2607 structs enforce the schema-required keys, `_meta` included (a
  # validated request always carries one). `nil` stands for "no client meta".

  defp discover_req do
    %MCP.DiscoverRequest{id: 1, params: %MCP.RequestParams{_meta: nil}}
  end

  defp call_tool_req(name, arguments \\ %{}, id \\ 1) do
    %MCP.CallToolRequest{
      id: id,
      params: %MCP.CallToolRequestParams{_meta: nil, name: name, arguments: arguments}
    }
  end

  # An MRTR retry (spec 007): the client re-sends the ORIGINAL call — a brand
  # new JSON-RPC id, the SAME name + arguments — echoing the opaque
  # `requestState` it received and the `inputResponses` it gathered.
  defp retry_tool_req(name, arguments, request_state, id \\ 2, input_responses \\ %{}) do
    %MCP.CallToolRequest{
      id: id,
      params: %MCP.CallToolRequestParams{
        _meta: nil,
        name: name,
        arguments: arguments,
        requestState: request_state,
        inputResponses: input_responses
      }
    }
  end

  defp list_tools_req do
    %MCP.ListToolsRequest{id: 1, params: %MCP.PaginatedRequestParams{_meta: nil}}
  end

  defp list_resources_req(cursor \\ nil) do
    %MCP.ListResourcesRequest{
      id: 1,
      params: %MCP.PaginatedRequestParams{_meta: nil, cursor: cursor}
    }
  end

  defp read_resource_req(uri) do
    %MCP.ReadResourceRequest{id: 1, params: %MCP.ReadResourceRequestParams{_meta: nil, uri: uri}}
  end

  defp list_resource_templates_req do
    %MCP.ListResourceTemplatesRequest{id: 1, params: %MCP.PaginatedRequestParams{_meta: nil}}
  end

  defp list_prompts_req(cursor \\ nil) do
    %MCP.ListPromptsRequest{
      id: 1,
      params: %MCP.PaginatedRequestParams{_meta: nil, cursor: cursor}
    }
  end

  defp get_prompt_req(name, arguments \\ nil) do
    %MCP.GetPromptRequest{
      id: 1,
      params: %MCP.GetPromptRequestParams{_meta: nil, name: name, arguments: arguments}
    }
  end

  # A full `_meta` as a conforming 2026-07-28 client sends it (the validator
  # casts the reverse-DNS keys to atoms and the values to structs).
  defp full_meta do
    %{
      "io.modelcontextprotocol/protocolVersion": @protocol_version,
      "io.modelcontextprotocol/clientInfo": %MCP.Implementation{
        name: "test-client",
        version: "1.0.0"
      },
      "io.modelcontextprotocol/clientCapabilities": %MCP.ClientCapabilities{}
    }
  end

  describe "per-request init" do
    test "builds state from the validated server opts" do
      assert {:ok, _state} = Suite.init(@server_info)
    end

    test "stops on invalid opts" do
      # Missing the required server_name/server_version.
      assert {:stop, _reason} = Suite.init([])
    end
  end

  describe "server/discover" do
    # `server/discover` replaces the `initialize` handshake for capability
    # discovery. It is the only request allowed to expand the full catalog
    # (running every extension provider), which keeps the capabilities
    # self-describing: the user never hand-declares them.

    test "returns self-describing server metadata with no components configured" do
      state = init_suite()

      assert {:result, result} = Suite.handle_request(discover_req(), build_channel(), state)

      # `logging` is always declared: the Suite can emit `notifications/message`
      # via Channel.send_log, and servers that emit logs MUST declare the
      # capability (spec 011).
      assert %MCP.DiscoverResult{
               resultType: "complete",
               supportedVersions: ["2026-07-28"],
               serverInfo: %MCP.Implementation{name: "Test Server", version: "0", title: nil},
               capabilities: %MCP.ServerCapabilities{
                 tools: nil,
                 resources: nil,
                 prompts: nil,
                 logging: %{}
               }
             } = result
    end

    test "serverInfo carries the configured title" do
      state = init_suite(server_title: "The Test Server")

      assert {:result, %MCP.DiscoverResult{serverInfo: server_info}} =
               Suite.handle_request(discover_req(), build_channel(), state)

      assert %MCP.Implementation{title: "The Test Server"} = server_info
    end

    test "declares tools capability when a tool is configured" do
      stub(ToolMock, :info, fn :name, :test_tool -> "TestTool" end)

      state = init_suite(tools: [{ToolMock, :test_tool}])

      assert {:result, %MCP.DiscoverResult{capabilities: caps}} =
               Suite.handle_request(discover_req(), build_channel(), state)

      assert %MCP.ServerCapabilities{tools: %{}, resources: nil, prompts: nil} = caps
    end

    test "runs every extension provider (the one eager path) and declares their capabilities" do
      ExtensionMock
      |> expect(:tools, fn _channel, :ext -> [{ToolMock, :ext_tool}] end)
      |> expect(:resources, fn _channel, :ext -> [{ResourceRepoMock, :ext_repo}] end)
      |> expect(:prompts, fn _channel, :ext -> [{PromptRepoMock, :ext_prompts}] end)

      stub(ToolMock, :info, fn :name, :ext_tool -> "ExtTool" end)
      stub(ResourceRepoMock, :prefix, fn :ext_repo -> "file:///" end)
      stub(PromptRepoMock, :prefix, fn :ext_prompts -> "greet" end)

      state = init_suite(extensions: [{ExtensionMock, :ext}])

      assert {:result, %MCP.DiscoverResult{capabilities: caps}} =
               Suite.handle_request(discover_req(), build_channel(), state)

      assert %MCP.ServerCapabilities{tools: %{}, resources: %{}, prompts: %{}, logging: %{}} =
               caps
    end
  end

  describe "state built from the request _meta" do
    test "providers receive the channel carrying the client meta" do
      # The transport extracts the `io.modelcontextprotocol/*` request `_meta`
      # fields into the channel's read-only `meta`; the Suite passes that
      # channel to providers so they can act on client identity/capabilities.
      expect(ExtensionMock, :tools, fn channel, :ext ->
        assert %{
                 client_info: %MCP.Implementation{name: "test-client", version: "1.0.0"},
                 client_capabilities: %MCP.ClientCapabilities{},
                 protocol_version: @protocol_version
               } = channel.meta

        []
      end)

      state = init_suite(extensions: [{ExtensionMock, :ext}])

      req = %MCP.ListToolsRequest{id: 1, params: %MCP.PaginatedRequestParams{_meta: full_meta()}}
      channel = Channel.from_request(nil, req, %{})

      assert {:result, %MCP.ListToolsResult{tools: []}} =
               Suite.handle_request(req, channel, state)
    end
  end

  describe "listing tools" do
    test "describes config tools" do
      ToolMock
      |> stub(:info, fn
        :name, :tool1 -> "Tool1"
        :title, :tool1 -> "Tool 1 title"
        :description, :tool1 -> "Tool 1 descr"
        :annotations, :tool1 -> %{title: "Tool 1 subtitle", destructiveHint: true}
        :name, :tool2 -> "Tool2"
        :title, :tool2 -> nil
        :description, :tool2 -> nil
        :annotations, :tool2 -> nil
        #
        :_meta, arg -> %{"arg" => Atom.to_string(arg)}
      end)
      |> stub(:input_schema, fn _ -> %{type: :object} end)
      |> stub(:output_schema, fn
        :tool1 -> %{type: :object}
        :tool2 -> nil
      end)

      state = init_suite(tools: [{ToolMock, :tool1}, {ToolMock, :tool2}])

      assert {:result, %MCP.ListToolsResult{tools: tools}} =
               Suite.handle_request(list_tools_req(), build_channel(), state)

      assert [
               %{
                 name: "Tool1",
                 title: "Tool 1 title",
                 _meta: %{"arg" => "tool1"},
                 description: "Tool 1 descr",
                 annotations: %{destructiveHint: true, title: "Tool 1 subtitle"},
                 inputSchema: %{"type" => "object"},
                 outputSchema: %{"type" => "object"}
               },
               %{
                 name: "Tool2",
                 inputSchema: %{"type" => "object"},
                 _meta: %{"arg" => "tool2"}
               }
             ] = tools
    end

    test "lists config tools first, then extension tools in declaration order" do
      ToolMock
      |> stub(:info, fn
        :name, :direct_tool -> "DirectTool"
        :name, :ext1_tool -> "Ext1Tool"
        :name, :ext2_tool -> "Ext2Tool"
        :title, _ -> nil
        :description, _ -> nil
        :annotations, _ -> nil
        :_meta, _ -> nil
      end)
      |> stub(:input_schema, fn _ -> %{type: :object} end)
      |> stub(:output_schema, fn _ -> nil end)

      ExtensionMock
      |> expect(:tools, fn _channel, :ext1 -> [{ToolMock, :ext1_tool}] end)
      |> expect(:tools, fn _channel, :ext2 -> [{ToolMock, :ext2_tool}] end)

      state =
        init_suite(
          tools: [{ToolMock, :direct_tool}],
          extensions: [{ExtensionMock, :ext1}, {ExtensionMock, :ext2}]
        )

      assert {:result, %MCP.ListToolsResult{tools: tools}} =
               Suite.handle_request(list_tools_req(), build_channel(), state)

      assert ["DirectTool", "Ext1Tool", "Ext2Tool"] = Enum.map(tools, & &1.name)
    end
  end

  describe "calling tools" do
    test "sync tool returning a terminal result" do
      ToolMock
      |> stub(:info, fn :name, :some_tool_arg -> "ExistingTool" end)
      |> expect(:call, fn req, channel, arg ->
        # The whole request is given
        assert %MCP.CallToolRequest{
                 id: 2,
                 params: %MCP.CallToolRequestParams{
                   arguments: %{"some" => "arg"},
                   name: "ExistingTool"
                 }
               } = req

        assert %Channel{} = channel
        assert :some_tool_arg = arg

        # Terminal return: no channel, no state — same vocabulary as the server.
        {:result, MCP.call_tool_result(text: "hello")}
      end)

      state = init_suite(tools: [{ToolMock, :some_tool_arg}])
      req = call_tool_req("ExistingTool", %{"some" => "arg"}, 2)

      assert {:result, result} = Suite.handle_request(req, build_channel(), state)

      assert %MCP.CallToolResult{
               resultType: "complete",
               content: [%MCP.TextContent{text: "hello"}],
               isError: nil,
               structuredContent: nil
             } = result
    end

    test "unknown tool" do
      state = init_suite()

      assert {:error, {:unknown_tool, "SomeTool"}} =
               Suite.handle_request(call_tool_req("SomeTool"), build_channel(), state)

      assert {200, %{code: -32_602, data: %{tool: "SomeTool"}, message: "Unknown tool SomeTool"}} =
               check_error({:unknown_tool, "SomeTool"})
    end

    test "a validate_request/2 failure rejects the call with invalid params" do
      # Request validation happens in the optional `validate_request/2`
      # callback, invoked by the dispatcher before the tool's `call/3` —
      # which therefore has no expectation here: it must never be invoked.
      ToolFullMock
      |> stub(:info, fn :name, :validated_tool -> "ValidatedTool" end)
      |> expect(:validate_request, fn req, :validated_tool ->
        assert %MCP.CallToolRequest{params: %{name: "ValidatedTool"}} = req
        {:error, JSV.ValidationError.of([])}
      end)

      state = init_suite(tools: [{ToolFullMock, :validated_tool}])

      assert {:error, {:invalid_params, %JSV.ValidationError{}} = err} =
               Suite.handle_request(
                 call_tool_req("ValidatedTool", %{"invalid" => "args"}),
                 build_channel(),
                 state
               )

      assert {200,
              %{code: -32_602, data: %{valid: false, details: []}, message: "Invalid Parameters"}} =
               check_error(err)
    end

    test "tool returning an error string" do
      ToolMock
      |> stub(:info, fn :name, :error_tool -> "ErrorTool" end)
      |> expect(:call, fn _req, _channel, _arg ->
        {:error, "Something went wrong in the tool"}
      end)

      state = init_suite(tools: [{ToolMock, :error_tool}])

      assert {:error, "Something went wrong in the tool" = err} =
               Suite.handle_request(call_tool_req("ErrorTool"), build_channel(), state)

      assert {500, %{code: -32_603, message: "Something went wrong in the tool"}} =
               check_error(err)
    end

    test "tool returning an exception" do
      ToolMock
      |> stub(:info, fn :name, :error_tool -> "ErrorTool" end)
      |> expect(:call, fn _req, _channel, _arg ->
        {:error, %KeyError{key: :foo}}
      end)

      state = init_suite(tools: [{ToolMock, :error_tool}])

      assert {:error, err} =
               Suite.handle_request(call_tool_req("ErrorTool"), build_channel(), state)

      assert {500, %{code: -32_603, message: "key :foo not found"}} =
               check_error(err)
    end

    test "tool returning {:invalid_params, _}" do
      ToolMock
      |> stub(:info, fn :name, :error_tool -> "ErrorTool" end)
      |> expect(:call, fn _req, _channel, _arg ->
        {:error, {:invalid_params, :foo}}
      end)

      state = init_suite(tools: [{ToolMock, :error_tool}])

      assert {:error, {:invalid_params, :foo} = err} =
               Suite.handle_request(call_tool_req("ErrorTool"), build_channel(), state)

      assert {200, %{code: -32_602, message: "Invalid Parameters"}} = check_error(err)
    end
  end

  describe "multi round-trip (MRTR) tool calls" do
    # Spec 007. The stateless core cannot hold a stream open to ask the client
    # for sampling/elicitation/roots, so a tool returns
    # `{:input_required, requests, client_state}` (3-tuple — no channel, tools
    # no longer return one). MRTR is "just a result": the Suite (in `Tool`)
    # transforms that convenience tuple into a plain
    # `{:result, %InputRequiredResult{}}`, encrypting `client_state` into an
    # opaque, AEAD-protected `requestState` bound to `{tool, arguments}` via
    # `GenMCP.Token` (`{:reqstate, %{tool, args}}`). The runner (`GenMCP.Server`)
    # stays generic — it forwards the result like any other, with no MRTR
    # knowledge. On the retry the client echoes `requestState`; the Suite
    # decrypts it (bound to the retry's own name + arguments) and resumes. The
    # binding is on `arguments`, NOT the whole params: the retry params differ
    # from the initial by the added `requestState` / `inputResponses` fields,
    # while `arguments` is the stably-echoed business input.

    @mrtr_requests %{"elicit-1" => %{"method" => "elicitation/create"}}

    test "a tool's {:input_required, requests, client_state} becomes an InputRequiredResult" do
      client_state = %{step: :await_confirmation, pending: 100}

      ToolMock
      |> stub(:info, fn :name, :mrtr -> "TransferTool" end)
      |> expect(:call, fn _req, _channel, :mrtr ->
        {:input_required, @mrtr_requests, client_state}
      end)

      state = init_suite(tools: [{ToolMock, :mrtr}])
      req = call_tool_req("TransferTool", %{"to" => "alice"}, 1)

      # The tool's convenience tuple becomes a plain result: `inputRequests`
      # passed through untouched, `client_state` encrypted into the opaque
      # `requestState`, and `resultType` the only place "input-required" is set.
      assert {:result,
              %MCP.InputRequiredResult{
                resultType: "input-required",
                inputRequests: @mrtr_requests,
                requestState: request_state
              }} = Suite.handle_request(req, build_channel(), state)

      assert is_binary(request_state)
      # Opaque: the kept term is encrypted, never visible in the blob.
      refute request_state =~ "await_confirmation"

      # Node-portable + bound to {tool, args}: a DIFFERENT channel (another node
      # sharing only secret_key_base) decrypts it back to the kept term under
      # the exact tool + arguments that minted it.
      assert {:ok, ^client_state} =
               GenMCP.Token.decrypt(
                 build_channel(),
                 {:reqstate,
                  Suite.tool_request_state_unicity_data(Tool.expand({ToolMock, :mrtr}), req)},
                 request_state
               )
    end

    test "a valid retry decrypts the requestState and resumes the tool to a final result" do
      # The success path. The Suite decrypts `requestState` (bound to {tool,
      # arguments}) and re-invokes `call/3` with the SAME request — no new
      # callback, no extra argument — except `req.params.requestState` now
      # carries the decrypted `client_state` TERM in place of the opaque wire
      # blob. The crypto stays in the Suite: the encrypted blob never reaches
      # the tool. The tool digs into the request: `requestState` is its kept
      # state (nil on the initial call), `inputResponses` the client's answers.
      client_state = %{step: :await_confirmation, pending: 100}

      ToolMock
      |> stub(:info, fn :name, :mrtr -> "TransferTool" end)
      |> expect(:call, fn req, _channel, :mrtr ->
        # Decrypted state and the client's answers are both on the request.
        assert %MCP.CallToolRequest{
                 params: %MCP.CallToolRequestParams{
                   requestState: ^client_state,
                   inputResponses: %{"elicit-1" => %{"action" => "accept"}}
                 }
               } = req

        {:result, MCP.call_tool_result(text: "transferred 100 to alice")}
      end)

      tool = Tool.expand({ToolMock, :mrtr})

      req_1 =
        retry_tool_req("TransferTool", %{"to" => "alice"}, nil, 1, %{
          "elicit-1" => %{"action" => "accept"}
        })

      # Mint the blob exactly as the Suite would have on the initial call —
      # on another node, bound to {tool, arguments}.
      request_state =
        GenMCP.Token.encrypt(
          build_channel(),
          {:reqstate, Suite.tool_request_state_unicity_data(tool, req_1)},
          client_state
        )

      state = init_suite(tools: [tool])

      req_2 =
        retry_tool_req("TransferTool", %{"to" => "alice"}, request_state, 2, %{
          "elicit-1" => %{"action" => "accept"}
        })

      assert {:result, result} = Suite.handle_request(req_2, build_channel(), state)

      assert %MCP.CallToolResult{content: [%MCP.TextContent{text: "transferred 100 to alice"}]} =
               result
    end

    test "a retry carrying a requestState minted for another tool is rejected" do
      # Cross-tool reuse fails closed: the blob is bound to the tool (+ args),
      # so one minted for a different tool is cryptographically invalid here.
      # The tool has NO `:call` expectation — decode must reject before any
      # dispatch. The binding payload comes from the Suite helper, so this test
      # never hardcodes how the unicity data is built.
      stub(ToolMock, :info, fn
        :name, :mrtr -> "TransferTool"
        :name, :other -> "OtherTool"
      end)

      other_tool = Tool.expand({ToolMock, :other})
      mint_req = call_tool_req("TransferTool", %{})

      foreign =
        GenMCP.Token.encrypt(
          build_channel(),
          {:reqstate, Suite.tool_request_state_unicity_data(other_tool, mint_req)},
          %{step: 1}
        )

      state = init_suite(tools: [{ToolMock, :mrtr}])
      req = retry_tool_req("TransferTool", %{}, foreign)

      assert {:error, :invalid_request_state} =
               Suite.handle_request(req, build_channel(), state)

      assert {200, %{code: -32_602, message: "Invalid request state"}} =
               check_error(:invalid_request_state)
    end

    test "a retry carrying a requestState minted for different arguments is rejected" do
      stub(ToolMock, :info, fn :name, :mrtr -> "TransferTool" end)

      tool = Tool.expand({ToolMock, :mrtr})
      mint_req = call_tool_req("TransferTool", %{"to" => "bob"})

      foreign =
        GenMCP.Token.encrypt(
          build_channel(),
          {:reqstate, Suite.tool_request_state_unicity_data(tool, mint_req)},
          %{step: 1}
        )

      state = init_suite(tools: [{ToolMock, :mrtr}])
      req = retry_tool_req("TransferTool", %{"to" => "alice"}, foreign)

      assert {:error, :invalid_request_state} =
               Suite.handle_request(req, build_channel(), state)
    end

    test "a retry carrying an expired requestState is rejected" do
      stub(ToolMock, :info, fn :name, :mrtr -> "TransferTool" end)

      # Same tool + args as the retry, so the binding matches and only the TTL
      # triggers rejection.
      tool = Tool.expand({ToolMock, :mrtr})
      mint_req = call_tool_req("TransferTool", %{"to" => "alice"})

      expired =
        GenMCP.Token.encrypt(
          build_channel(),
          {:reqstate, Suite.tool_request_state_unicity_data(tool, mint_req)},
          %{step: 1},
          signed_at: System.system_time(:second) - 21 * 60
        )

      state = init_suite(tools: [{ToolMock, :mrtr}])
      req = retry_tool_req("TransferTool", %{"to" => "alice"}, expired)

      assert {:error, :expired_request_state} =
               Suite.handle_request(req, build_channel(), state)

      assert {200, %{code: -32_602, message: "Expired request state"}} =
               check_error(:expired_request_state)
    end
  end

  describe "streaming tools" do
    # The `{:async, {tag, ref}}` machinery is gone. The per-request worker owns
    # its process, so a slow tool simply blocks in `call/3`; a tool that needs
    # to receive messages (spawned tasks, subscriptions, ...) returns
    # `{:stream, tool_state}` and the Suite forwards every subsequent worker
    # message to the matched tool's `handle_message(message, channel,
    # tool_state, arg)`, which shares the `call/3` return vocabulary.

    test "a tool opting into streaming produces its result from handle_message/4" do
      ToolMock
      |> stub(:info, fn :name, :stream_tool -> "StreamTool" end)
      |> expect(:call, fn _req, _channel, :stream_tool ->
        {:stream, :tool_state_0}
      end)
      |> expect(:handle_message, fn {:work_done, 42}, _channel, :tool_state_0, :stream_tool ->
        {:result, MCP.call_tool_result(text: "Result: 42")}
      end)

      state = init_suite(tools: [{ToolMock, :stream_tool}])
      channel = build_channel()

      assert {:stream, state} =
               Suite.handle_request(call_tool_req("StreamTool"), channel, state)

      # The worker delivers any process message to handle_message/3, which
      # routes it to the streaming tool.
      assert {:result, result} = Suite.handle_message({:work_done, 42}, channel, state)
      assert %MCP.CallToolResult{content: [%MCP.TextContent{text: "Result: 42"}]} = result
    end

    test "a streaming tool can keep streaming, carrying its own state" do
      ToolMock
      |> stub(:info, fn :name, :stream_tool -> "StreamTool" end)
      |> expect(:call, fn _req, _channel, :stream_tool ->
        {:stream, {:acc, []}}
      end)
      |> expect(:handle_message, fn {:chunk, "a"}, _channel, {:acc, []}, :stream_tool ->
        {:stream, {:acc, ["a"]}}
      end)
      |> expect(:handle_message, fn {:chunk, "b"}, _channel, {:acc, ["a"]}, :stream_tool ->
        {:stream, {:acc, ["b", "a"]}}
      end)
      |> expect(:handle_message, fn :eof, _channel, {:acc, ["b", "a"]}, :stream_tool ->
        {:result, MCP.call_tool_result(text: "ab")}
      end)

      state = init_suite(tools: [{ToolMock, :stream_tool}])
      channel = build_channel()

      assert {:stream, state} =
               Suite.handle_request(call_tool_req("StreamTool"), channel, state)

      assert {:stream, state} = Suite.handle_message({:chunk, "a"}, channel, state)
      assert {:stream, state} = Suite.handle_message({:chunk, "b"}, channel, state)

      assert {:result, %MCP.CallToolResult{content: [%MCP.TextContent{text: "ab"}]}} =
               Suite.handle_message(:eof, channel, state)
    end

    test "a streaming tool can emit progress from handle_message/4" do
      ToolMock
      |> stub(:info, fn :name, :stream_tool -> "StreamTool" end)
      |> expect(:call, fn _req, _channel, :stream_tool ->
        {:stream, nil}
      end)
      |> expect(:handle_message, fn :tick, channel, nil, :stream_tool ->
        :ok = Channel.send_progress(channel, 1, 2, "halfway")
        {:stream, nil}
      end)
      |> expect(:handle_message, fn :done, _channel, nil, :stream_tool ->
        {:result, MCP.call_tool_result(text: "done")}
      end)

      state = init_suite(tools: [{ToolMock, :stream_tool}])

      # The channel is built from the request so it carries the progress token;
      # the test process plays the transport relay role.
      req = %MCP.CallToolRequest{
        id: 1,
        params: %MCP.CallToolRequestParams{
          name: "StreamTool",
          arguments: %{},
          _meta: %{progressToken: "tok"}
        }
      }

      channel = Channel.from_request(nil, req, %{})

      assert {:stream, state} = Suite.handle_request(req, channel, state)
      assert {:stream, state} = Suite.handle_message(:tick, channel, state)

      assert_receive {:"$gen_mcp", :notification, notif}
      assert %{params: %{progressToken: "tok", progress: 1, total: 2}} = notif

      assert {:result, _} = Suite.handle_message(:done, channel, state)
    end

    test "an error from handle_message/4 terminates the request" do
      ToolMock
      |> stub(:info, fn :name, :stream_tool -> "StreamTool" end)
      |> expect(:call, fn _req, _channel, :stream_tool ->
        {:stream, nil}
      end)
      |> expect(:handle_message, fn :boom, _channel, nil, :stream_tool ->
        {:error, "stream failed"}
      end)

      state = init_suite(tools: [{ToolMock, :stream_tool}])
      channel = build_channel()

      assert {:stream, state} = Suite.handle_request(call_tool_req("StreamTool"), channel, state)
      assert {:error, "stream failed"} = Suite.handle_message(:boom, channel, state)
    end

    test "handle_close forwards to the active streaming tool's handle_close/3" do
      test_pid = self()

      ToolFullMock
      |> stub(:info, fn :name, :stream_tool -> "StreamTool" end)
      |> stub(:validate_request, fn req, :stream_tool -> {:ok, req} end)
      |> expect(:call, fn _req, _channel, :stream_tool -> {:stream, :tool_state_0} end)
      |> expect(:handle_close, fn channel, :tool_state_0, :stream_tool ->
        send(test_pid, {:tool_closed, channel.status})
        :ok
      end)

      state = init_suite(tools: [{ToolFullMock, :stream_tool}])
      channel = build_channel()

      assert {:stream, state} =
               Suite.handle_request(call_tool_req("StreamTool"), channel, state)

      # The worker passes the channel already marked closed; the Suite routes it
      # to the streaming tool's handle_close (return ignored).
      closed = %{channel | status: :closed}
      assert :ok = Suite.handle_close(closed, state)

      assert_receive {:tool_closed, :closed}
    end

    test "handle_close is a no-op when no streaming tool is active" do
      state = init_suite()
      assert :ok = Suite.handle_close(build_channel(), state)
    end
  end

  describe "lazy provider resolution" do
    # Statelessly there is no init to amortize a full catalog expansion: it
    # would re-run on every request. Single-target operations must resolve
    # providers lazily and stop at the first match; only the `*/list` operations
    # and `server/discover` are total.
    #
    # Mox is the spy here: a call to a mock with no matching expectation fails
    # the test, so "the extension is never invoked" is asserted by simply not
    # stubbing it.

    test "tools/call for a config tool invokes no extension provider" do
      ToolMock
      |> stub(:info, fn :name, :cfg_tool -> "CfgTool" end)
      |> expect(:call, fn _req, _channel, :cfg_tool ->
        {:result, MCP.call_tool_result(text: "from config")}
      end)

      # No ExtensionMock stubs at all: any provider call fails the test.
      state =
        init_suite(
          tools: [{ToolMock, :cfg_tool}],
          extensions: [{ExtensionMock, :ext1}, {ExtensionMock, :ext2}]
        )

      assert {:result, %MCP.CallToolResult{content: [%MCP.TextContent{text: "from config"}]}} =
               Suite.handle_request(call_tool_req("CfgTool"), build_channel(), state)
    end

    test "tools/call stops at the first extension defining the tool" do
      ToolMock
      |> stub(:info, fn :name, :t1 -> "Tool1" end)
      |> expect(:call, fn _req, _channel, :t1 ->
        {:result, MCP.call_tool_result(text: "from ext1")}
      end)

      # Only ext1 may be asked for tools; a call with :ext2 has no matching
      # clause and fails the test.
      expect(ExtensionMock, :tools, fn _channel, :ext1 -> [{ToolMock, :t1}] end)

      state = init_suite(extensions: [{ExtensionMock, :ext1}, {ExtensionMock, :ext2}])

      assert {:result, %MCP.CallToolResult{content: [%MCP.TextContent{text: "from ext1"}]}} =
               Suite.handle_request(call_tool_req("Tool1"), build_channel(), state)
    end

    test "tools/list is total over extensions but never invokes resource or prompt providers" do
      ExtensionMock
      |> expect(:tools, fn _channel, :ext1 -> [] end)
      |> expect(:tools, fn _channel, :ext2 -> [] end)

      state = init_suite(extensions: [{ExtensionMock, :ext1}, {ExtensionMock, :ext2}])

      assert {:result, %MCP.ListToolsResult{tools: []}} =
               Suite.handle_request(list_tools_req(), build_channel(), state)
    end

    test "resources/read for a config repo invokes no extension provider" do
      ResourceRepoMock
      |> stub(:prefix, fn :cfg_repo -> "file:///" end)
      |> expect(:read, fn "file:///readme.txt", _channel, :cfg_repo ->
        {:ok, MCP.read_resource_result(uri: "file:///readme.txt", text: "Hello")}
      end)

      state =
        init_suite(
          resources: [{ResourceRepoMock, :cfg_repo}],
          extensions: [{ExtensionMock, :ext1}]
        )

      assert {:result, %MCP.ReadResourceResult{}} =
               Suite.handle_request(
                 read_resource_req("file:///readme.txt"),
                 build_channel(),
                 state
               )
    end

    test "resources/read stops at the first extension whose repo prefix matches" do
      ResourceRepoMock
      |> stub(:prefix, fn :ext1_repo -> "ext1://" end)
      |> expect(:read, fn "ext1://doc.txt", _channel, :ext1_repo ->
        {:ok, MCP.read_resource_result(uri: "ext1://doc.txt", text: "Doc")}
      end)

      expect(ExtensionMock, :resources, fn _channel, :ext1 ->
        [{ResourceRepoMock, :ext1_repo}]
      end)

      state = init_suite(extensions: [{ExtensionMock, :ext1}, {ExtensionMock, :ext2}])

      assert {:result, %MCP.ReadResourceResult{}} =
               Suite.handle_request(read_resource_req("ext1://doc.txt"), build_channel(), state)
    end

    test "prompts/get for a config repo invokes no extension provider" do
      result = MCP.get_prompt_result(text: "Hello!")

      PromptRepoMock
      |> stub(:prefix, fn :cfg_prompts -> "greet" end)
      |> expect(:get, fn "greeting", _args, _channel, :cfg_prompts -> {:ok, result} end)

      state =
        init_suite(
          prompts: [{PromptRepoMock, :cfg_prompts}],
          extensions: [{ExtensionMock, :ext1}]
        )

      assert {:result, ^result} =
               Suite.handle_request(get_prompt_req("greeting"), build_channel(), state)
    end
  end

  describe "precedence: first-match-wins" do
    # Resolution stops at the first matching name/prefix; SelfExtension (the
    # config :tools/:resources/:prompts) is prepended, so explicit config wins
    # over extensions on a name collision. This flips the previous `Map.new`
    # last-wins semantics (migration note in spec 006). All paths must agree:
    # the expansion paths (tools/list, server/discover) must dedup first-wins,
    # otherwise a clash could be *called* as config but *listed/advertised* as
    # the extension's tool.

    defp clash_setup do
      ToolMock
      |> stub(:info, fn
        :name, :cfg_tool -> "Clash"
        :description, :cfg_tool -> "config tool"
        :title, :cfg_tool -> nil
        :annotations, :cfg_tool -> nil
        :_meta, :cfg_tool -> nil
        #
        :name, :ext_tool -> "Clash"
        :description, :ext_tool -> "extension tool"
        :title, :ext_tool -> nil
        :annotations, :ext_tool -> nil
        :_meta, :ext_tool -> nil
      end)
      |> stub(:input_schema, fn _ -> %{type: :object} end)
      |> stub(:output_schema, fn _ -> nil end)

      stub(ExtensionMock, :tools, fn _channel, :ext -> [{ToolMock, :ext_tool}] end)

      init_suite(
        tools: [{ToolMock, :cfg_tool}],
        extensions: [{ExtensionMock, :ext}]
      )
    end

    test "tools/list lists a clashing name once, with the config tool's metadata" do
      state = clash_setup()

      assert {:result, %MCP.ListToolsResult{tools: tools}} =
               Suite.handle_request(list_tools_req(), build_channel(), state)

      # Exactly one entry for the clashing name (no duplicate)...
      assert ["Clash"] = Enum.map(tools, & &1.name)

      # ...and it is the config one. With the old last-wins Map.new dedup this
      # would advertise "extension tool" while tools/call resolves the config
      # tool — the paths must agree.
      assert [%{description: "config tool"}] = tools
    end

    test "tools/call on a clashing name invokes the config tool" do
      state = clash_setup()

      expect(ToolMock, :call, fn _req, _channel, :cfg_tool ->
        {:result, MCP.call_tool_result(text: "from config")}
      end)

      assert {:result, %MCP.CallToolResult{content: [%MCP.TextContent{text: "from config"}]}} =
               Suite.handle_request(call_tool_req("Clash"), build_channel(), state)
    end

    test "server/discover expands a clashing catalog without error and advertises consistent capabilities" do
      state = clash_setup()

      # The full-expansion path must dedup first-wins too (not crash or flip
      # the winner). Capabilities only expose presence, so this also pins that
      # the expansion completes with the clash present.
      expect(ExtensionMock, :resources, fn _channel, :ext -> [] end)
      expect(ExtensionMock, :prompts, fn _channel, :ext -> [] end)

      assert {:result, %MCP.DiscoverResult{capabilities: caps}} =
               Suite.handle_request(discover_req(), build_channel(), state)

      assert %MCP.ServerCapabilities{tools: %{}, resources: nil, prompts: nil} = caps
    end

    test "an earlier extension wins a name clash on tools/list" do
      ToolMock
      |> stub(:info, fn
        :name, :ext1_tool -> "Clash"
        :description, :ext1_tool -> "ext1 tool"
        :name, :ext2_tool -> "Clash"
        :description, :ext2_tool -> "ext2 tool"
        :title, _ -> nil
        :annotations, _ -> nil
        :_meta, _ -> nil
      end)
      |> stub(:input_schema, fn _ -> %{type: :object} end)
      |> stub(:output_schema, fn _ -> nil end)

      ExtensionMock
      |> expect(:tools, fn _channel, :ext1 -> [{ToolMock, :ext1_tool}] end)
      |> expect(:tools, fn _channel, :ext2 -> [{ToolMock, :ext2_tool}] end)

      state = init_suite(extensions: [{ExtensionMock, :ext1}, {ExtensionMock, :ext2}])

      assert {:result, %MCP.ListToolsResult{tools: [%{description: "ext1 tool"}]}} =
               Suite.handle_request(list_tools_req(), build_channel(), state)
    end

    test "a config resource repo wins a prefix clash on resources/read" do
      ResourceRepoMock
      |> stub(:prefix, fn :cfg_repo -> "file:///" end)
      |> expect(:read, fn "file:///readme.txt", _channel, :cfg_repo ->
        {:ok, MCP.read_resource_result(uri: "file:///readme.txt", text: "from config")}
      end)

      # The extension repo declares the same prefix but is never reached: the
      # config repo matches first, so the extension provider is not even
      # invoked (no stub).
      state =
        init_suite(
          resources: [{ResourceRepoMock, :cfg_repo}],
          extensions: [{ExtensionMock, :ext}]
        )

      assert {:result,
              %MCP.ReadResourceResult{contents: [%MCP.TextResourceContents{text: "from config"}]}} =
               Suite.handle_request(
                 read_resource_req("file:///readme.txt"),
                 build_channel(),
                 state
               )
    end
  end

  describe "listing resources" do
    test "lists resources from a direct resource repository" do
      ResourceRepoMock
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> expect(:list, fn nil, _channel, :repo1 ->
        {[
           %{uri: "file:///readme.txt", name: "README", description: "Project readme"},
           %{uri: "file:///config.json", name: "Config"}
         ], nil}
      end)

      state = init_suite(resources: [{ResourceRepoMock, :repo1}])

      assert {:result, result} =
               Suite.handle_request(list_resources_req(), build_channel(), state)

      assert %MCP.ListResourcesResult{
               resources: [
                 %{uri: "file:///readme.txt", name: "README", description: "Project readme"},
                 %{uri: "file:///config.json", name: "Config"}
               ],
               nextCursor: nil
             } = result
    end

    test "pagination cursors are self-contained and survive across per-request states" do
      # Statelessly there is no per-session token key or salt: the cursor must
      # be verifiable by a brand new state built for the next request (possibly
      # on another node). The signing key is server-wide (see the cursor
      # signing task under spec 004).
      ResourceRepoMock
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> expect(:list, fn nil, _channel, :repo1 ->
        {[%{uri: "file:///page1.txt", name: "Page 1"}], "repo-token"}
      end)
      |> expect(:list, fn "repo-token", _channel, :repo1 ->
        {[%{uri: "file:///page2.txt", name: "Page 2"}], nil}
      end)

      opts = [resources: [{ResourceRepoMock, :repo1}]]

      state1 = init_suite(opts)

      assert {:result,
              %MCP.ListResourcesResult{resources: [%{name: "Page 1"}], nextCursor: cursor}} =
               Suite.handle_request(list_resources_req(), build_channel(), state1)

      assert is_binary(cursor)

      # Fresh state, as another worker would build it.
      state2 = init_suite(opts)

      assert {:result, %MCP.ListResourcesResult{resources: [%{name: "Page 2"}], nextCursor: nil}} =
               Suite.handle_request(list_resources_req(cursor), build_channel(), state2)
    end

    test "walks the config repo first, then extension repos in declaration order across pages" do
      ResourceRepoMock
      |> stub(:prefix, fn
        :direct_repo -> "file:///"
        :ext1_repo -> "http://ext1/"
        :ext2_repo -> "http://ext2/"
      end)
      |> expect(:list, fn nil, _channel, :direct_repo ->
        {[%{uri: "file:///direct.txt", name: "Direct Resource"}], nil}
      end)
      |> expect(:list, fn nil, _channel, :ext1_repo ->
        {[%{uri: "http://ext1/r1.txt", name: "Ext1 Resource 1"}], "ext1-page-2"}
      end)
      |> expect(:list, fn "ext1-page-2", _channel, :ext1_repo ->
        {[%{uri: "http://ext1/r2.txt", name: "Ext1 Resource 2"}], nil}
      end)
      |> expect(:list, fn nil, _channel, :ext2_repo ->
        {[%{uri: "http://ext2/r.txt", name: "Ext2 Resource"}], nil}
      end)

      # The listing walk re-invokes the extension providers on each request
      # (there is no cached catalog), so allow as many calls as pages.
      stub(ExtensionMock, :resources, fn
        _channel, :ext1 -> [{ResourceRepoMock, :ext1_repo}]
        _channel, :ext2 -> [{ResourceRepoMock, :ext2_repo}]
      end)

      opts = [
        resources: [{ResourceRepoMock, :direct_repo}],
        extensions: [{ExtensionMock, :ext1}, {ExtensionMock, :ext2}]
      ]

      # Each page is a brand new request with a brand new state.
      fetch_page = fn cursor ->
        assert {:result, %MCP.ListResourcesResult{resources: page, nextCursor: next}} =
                 Suite.handle_request(
                   list_resources_req(cursor),
                   build_channel(),
                   init_suite(opts)
                 )

        {page, next}
      end

      {page1, cursor} = fetch_page.(nil)
      {page2, cursor} = fetch_page.(cursor)
      {page3, cursor} = fetch_page.(cursor)
      {page4, last_cursor} = fetch_page.(cursor)

      assert [%{name: "Direct Resource"}] = page1
      assert [%{name: "Ext1 Resource 1"}] = page2
      assert [%{name: "Ext1 Resource 2"}] = page3
      assert [%{name: "Ext2 Resource"}] = page4
      assert nil == last_cursor
    end

    test "skips empty repositories" do
      ResourceRepoMock
      |> stub(:prefix, fn
        :repo1 -> "file:///"
        :repo2 -> "http://localhost/"
        :repo3 -> "s3://bucket/"
      end)
      |> expect(:list, fn nil, _channel, :repo1 -> {[], nil} end)
      |> expect(:list, fn nil, _channel, :repo2 -> {[], nil} end)
      |> expect(:list, fn nil, _channel, :repo3 ->
        {[%{uri: "s3://bucket/file1.txt", name: "File 1"}], nil}
      end)

      state =
        init_suite(
          resources: [
            {ResourceRepoMock, :repo1},
            {ResourceRepoMock, :repo2},
            {ResourceRepoMock, :repo3}
          ]
        )

      assert {:result, %MCP.ListResourcesResult{resources: [%{name: "File 1"}], nextCursor: nil}} =
               Suite.handle_request(list_resources_req(), build_channel(), state)
    end

    test "returns empty list when no resources available" do
      ResourceRepoMock
      |> stub(:prefix, fn _ -> "file:///" end)
      |> expect(:list, 2, fn nil, _channel, _ -> {[], nil} end)

      state = init_suite(resources: [{ResourceRepoMock, :repo1}, {ResourceRepoMock, :repo2}])

      assert {:result, %MCP.ListResourcesResult{resources: [], nextCursor: nil}} =
               Suite.handle_request(list_resources_req(), build_channel(), state)
    end

    test "rejects an invalid pagination token" do
      stub(ResourceRepoMock, :prefix, fn :repo1 -> "file:///" end)

      state = init_suite(resources: [{ResourceRepoMock, :repo1}])

      assert {:error, :invalid_cursor} =
               Suite.handle_request(
                 list_resources_req("made-up-token-from-client"),
                 build_channel(),
                 state
               )

      assert {200, %{code: -32_602, message: "Invalid pagination cursor"}} =
               check_error(:invalid_cursor)
    end
  end

  describe "reading resources" do
    test "reads a direct text resource" do
      ResourceRepoMock
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> expect(:read, fn "file:///readme.txt", _channel, :repo1 ->
        {:ok,
         MCP.read_resource_result(
           uri: "file:///readme.txt",
           text: "# Welcome\n\nThis is the readme."
         )}
      end)

      state = init_suite(resources: [{ResourceRepoMock, :repo1}])

      assert {:result, result} =
               Suite.handle_request(
                 read_resource_req("file:///readme.txt"),
                 build_channel(),
                 state
               )

      assert %MCP.ReadResourceResult{
               contents: [
                 %MCP.TextResourceContents{
                   uri: "file:///readme.txt",
                   text: "# Welcome\n\nThis is the readme."
                 }
               ]
             } = result
    end

    test "reads a blob resource with custom MIME type" do
      blob_data = Base.encode64(<<1, 2, 3, 4, 5>>)

      ResourceRepoMock
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> expect(:read, fn "file:///data.bin", _channel, :repo1 ->
        {:ok,
         MCP.read_resource_result(
           uri: "file:///data.bin",
           blob: blob_data,
           mime_type: "application/octet-stream"
         )}
      end)

      state = init_suite(resources: [{ResourceRepoMock, :repo1}])

      assert {:result, %MCP.ReadResourceResult{contents: [content]}} =
               Suite.handle_request(read_resource_req("file:///data.bin"), build_channel(), state)

      assert %MCP.BlobResourceContents{blob: ^blob_data, mimeType: "application/octet-stream"} =
               content
    end

    test "returns not found error for missing resource" do
      ResourceRepoMock
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> expect(:read, fn "file:///missing.txt", _channel, :repo1 ->
        {:error, :not_found}
      end)

      state = init_suite(resources: [{ResourceRepoMock, :repo1}])

      assert {:error, {:resource_not_found, "file:///missing.txt"} = err} =
               Suite.handle_request(
                 read_resource_req("file:///missing.txt"),
                 build_channel(),
                 state
               )

      # Missing-resource uses the standard -32602 (invalid params) under the
      # 2026 semantics; the old MCP-specific -32002 is retired (spec 005).
      assert {200, %{code: -32_602}} = check_error(err)
    end

    test "returns not found error when no repository matches the URI prefix" do
      stub(ResourceRepoMock, :prefix, fn :repo1 -> "file:///" end)

      state = init_suite(resources: [{ResourceRepoMock, :repo1}])

      assert {:error, {:resource_not_found, "ftp://example.com/file"}} =
               Suite.handle_request(
                 read_resource_req("ftp://example.com/file"),
                 build_channel(),
                 state
               )
    end

    test "matches repository prefixes in declaration order, not by longest match" do
      # Declaration order: private, general, trash. Routing uses the first
      # matching prefix:
      # * "file:///private/..." -> private repo
      # * "file:///trash/..."   -> general repo ("file:///" matches first)

      ResourceRepoMock
      |> stub(:prefix, fn
        :private_repo -> "file:///private/"
        :general_repo -> "file:///"
        :trash_repo -> "file:///trash/"
      end)
      |> expect(:read, fn "file:///private/secret.txt", _channel, :private_repo ->
        {:ok, MCP.read_resource_result(uri: "file:///private/secret.txt", text: "Secret")}
      end)
      |> expect(:read, fn "file:///trash/deleted.txt", _channel, :general_repo ->
        {:ok, MCP.read_resource_result(uri: "file:///trash/deleted.txt", text: "Deleted")}
      end)

      state =
        init_suite(
          resources: [
            {ResourceRepoMock, :private_repo},
            {ResourceRepoMock, :general_repo},
            {ResourceRepoMock, :trash_repo}
          ]
        )

      assert {:result, %MCP.ReadResourceResult{contents: [%{text: "Secret"}]}} =
               Suite.handle_request(
                 read_resource_req("file:///private/secret.txt"),
                 build_channel(),
                 state
               )

      assert {:result, %MCP.ReadResourceResult{contents: [%{text: "Deleted"}]}} =
               Suite.handle_request(
                 read_resource_req("file:///trash/deleted.txt"),
                 build_channel(),
                 state
               )
    end

    test "reads a template-based resource" do
      # The library parses URI template parameters and passes them to read.
      ResourceRepoMockTpl
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> stub(:template, fn :repo1 ->
        %{uriTemplate: "file://{/path*}", name: "FileTemplate"}
      end)
      |> expect(:read, fn %{"path" => ["config", "app.json"]}, _channel, :repo1 ->
        {:ok,
         MCP.read_resource_result(
           uri: "file:///config/app.json",
           text: ~s({"port": 3000}),
           mime_type: "application/json"
         )}
      end)

      state = init_suite(resources: [{ResourceRepoMockTpl, :repo1}])

      assert {:result, %MCP.ReadResourceResult{contents: [content]}} =
               Suite.handle_request(
                 read_resource_req("file:///config/app.json"),
                 build_channel(),
                 state
               )

      assert %MCP.TextResourceContents{text: ~s({"port": 3000}), mimeType: "application/json"} =
               content
    end

    test "returns error when URI does not match the template pattern" do
      ResourceRepoMockTpl
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> stub(:template, fn :repo1 ->
        %{uriTemplate: "file://someprefix{/path*}", name: "FileTemplate"}
      end)

      state = init_suite(resources: [{ResourceRepoMockTpl, :repo1}])

      assert {:error, "expected uri matching" <> _ = err} =
               Suite.handle_request(
                 read_resource_req("file:///otherprefix"),
                 build_channel(),
                 state
               )

      assert {500, %{code: -32_603}} = check_error(err)
    end
  end

  describe "cache hints wiring (spec 005)" do
    # The four list builders take their cacheScope/ttlMs from an optional
    # `cache_control/1` callback on the contributing providers (Tool / ResourceRepo
    # / PromptRepo). Two shapes:
    #
    #   * `resources/list` and `prompts/list` are paginated one repo per page
    #     (`paginate_repos` returns on the first non-empty repo), so a page just
    #     carries THAT repo's hint. Different pages may carry different hints —
    #     each page is its own cacheable result. No combination.
    #
    #   * `tools/list` and `resources/templates/list` aggregate every provider
    #     into one result, so the Suite combines: scope is :public only if EVERY
    #     contributor is :public, ttl is the minimum clamped to >= 0, and a
    #     provider that does not implement `cache_control` contributes {:private, 0}
    #     (forcing the merged result to no-cache).
    #
    # A page/result with no contributing provider defaults to {:private, 0}.
    # `resources/read` is unaffected: the repo builds its own ReadResourceResult
    # and sets cache opts directly. RED until the callback + Suite wiring land.

    test "resources/list: a repo's cache_control flows to the result" do
      ResourceRepoCacheMock
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> stub(:cache_control, fn :repo1 -> {:public, 60_000} end)
      |> expect(:list, fn nil, _channel, :repo1 ->
        {[%{uri: "file:///a.txt", name: "A"}], nil}
      end)

      state = init_suite(resources: [{ResourceRepoCacheMock, :repo1}])

      assert {:result, %MCP.ListResourcesResult{cacheScope: :public, ttlMs: 60_000}} =
               Suite.handle_request(list_resources_req(), build_channel(), state)
    end

    test "resources/list: each page carries its own repository's cache_control" do
      # repo1 yields page 1 (exhausted, not last) -> next page points at repo2;
      # repo2 yields page 2. Each page is single-repo, so each carries that
      # repo's own hint — and the two differ.
      ResourceRepoCacheMock
      |> stub(:prefix, fn
        :repo1 -> "file:///"
        :repo2 -> "s3://bucket/"
      end)
      |> stub(:cache_control, fn
        :repo1 -> {:public, 60_000}
        :repo2 -> {:private, 0}
      end)
      |> stub(:list, fn
        nil, _channel, :repo1 -> {[%{uri: "file:///a.txt", name: "A"}], nil}
        nil, _channel, :repo2 -> {[%{uri: "s3://bucket/b", name: "B"}], nil}
      end)

      opts = [resources: [{ResourceRepoCacheMock, :repo1}, {ResourceRepoCacheMock, :repo2}]]

      # Page 1 — from repo1 only.
      assert {:result,
              %MCP.ListResourcesResult{cacheScope: :public, ttlMs: 60_000, nextCursor: cursor}} =
               Suite.handle_request(list_resources_req(), build_channel(), init_suite(opts))

      assert is_binary(cursor)

      # Page 2 — from repo2 only, with its own (different) hint.
      assert {:result, result} =
               Suite.handle_request(list_resources_req(cursor), build_channel(), init_suite(opts))

      assert %MCP.ListResourcesResult{cacheScope: :private, ttlMs: 0, nextCursor: nil} = result
    end

    test "resources/list: defaults to no-cache when no repo implements cache_control" do
      ResourceRepoMock
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> expect(:list, fn nil, _channel, :repo1 -> {[], nil} end)

      state = init_suite(resources: [{ResourceRepoMock, :repo1}])

      assert {:result, %MCP.ListResourcesResult{cacheScope: :private, ttlMs: 0}} =
               Suite.handle_request(list_resources_req(), build_channel(), state)
    end

    test "resources/templates/list: combines the contributing repos (public iff all, min ttl)" do
      # templates/list aggregates every template repo into ONE result, so its
      # hint is combined across the contributors.
      ResourceRepoTplCacheMock
      |> stub(:prefix, fn
        :repo1 -> "http://a/"
        :repo2 -> "http://b/"
      end)
      |> stub(:template, fn
        :repo1 -> %{uriTemplate: "http://a/{path}", name: "A"}
        :repo2 -> %{uriTemplate: "http://b/{path}", name: "B"}
      end)
      |> stub(:cache_control, fn
        :repo1 -> {:public, 45_000}
        :repo2 -> {:public, 30_000}
      end)

      state =
        init_suite(
          resources: [{ResourceRepoTplCacheMock, :repo1}, {ResourceRepoTplCacheMock, :repo2}]
        )

      assert {:result, %MCP.ListResourceTemplatesResult{cacheScope: :public, ttlMs: 30_000}} =
               Suite.handle_request(list_resource_templates_req(), build_channel(), state)
    end

    test "resources/templates/list: any private contributor makes the result private" do
      ResourceRepoTplCacheMock
      |> stub(:prefix, fn
        :repo1 -> "http://a/"
        :repo2 -> "http://b/"
      end)
      |> stub(:template, fn
        :repo1 -> %{uriTemplate: "http://a/{path}", name: "A"}
        :repo2 -> %{uriTemplate: "http://b/{path}", name: "B"}
      end)
      |> stub(:cache_control, fn
        :repo1 -> {:public, 45_000}
        :repo2 -> {:private, 90_000}
      end)

      state =
        init_suite(
          resources: [{ResourceRepoTplCacheMock, :repo1}, {ResourceRepoTplCacheMock, :repo2}]
        )

      assert {:result, %MCP.ListResourceTemplatesResult{cacheScope: :private, ttlMs: 45_000}} =
               Suite.handle_request(list_resource_templates_req(), build_channel(), state)
    end

    test "prompts/list: the producing repo's cache_control sets the page hint" do
      # The repo must actually produce items: an empty page would be discarded by
      # paginate_repos, leaving no producing repo and the default {:private, 0}.
      PromptRepoCacheMock
      |> stub(:prefix, fn :repo1 -> "greet" end)
      |> stub(:cache_control, fn :repo1 -> {:public, 60_000} end)
      |> expect(:list, fn nil, _channel, :repo1 ->
        {[%{name: "greeting", description: "Say hello"}], nil}
      end)

      state = init_suite(prompts: [{PromptRepoCacheMock, :repo1}])

      assert {:result, %MCP.ListPromptsResult{cacheScope: :public, ttlMs: 60_000}} =
               Suite.handle_request(list_prompts_req(), build_channel(), state)
    end

    test "resources/list: an empty listing is no-cache even if the repo advertises a hint" do
      # paginate_repos discards empty `{[], _}` pages and advances; with no
      # producing repo the result falls back to {:private, 0}, regardless of the
      # repo's cache_control.
      ResourceRepoCacheMock
      |> stub(:prefix, fn :repo1 -> "file:///" end)
      |> stub(:cache_control, fn :repo1 -> {:public, 60_000} end)
      |> expect(:list, fn nil, _channel, :repo1 -> {[], nil} end)

      state = init_suite(resources: [{ResourceRepoCacheMock, :repo1}])

      assert {:result, %MCP.ListResourcesResult{cacheScope: :private, ttlMs: 0}} =
               Suite.handle_request(list_resources_req(), build_channel(), state)
    end

    test "tools/list: combines the tools' cache_controls (public iff all, min ttl)" do
      # tools/list aggregates every tool into ONE result, so the hint is
      # combined across the listed tools.
      ToolFullMock
      |> stub(:info, fn
        :name, :t1 -> "T1"
        :name, :t2 -> "T2"
        _kind, _arg -> nil
      end)
      |> stub(:input_schema, fn _arg -> %{type: :object} end)
      |> stub(:output_schema, fn _arg -> nil end)
      |> stub(:cache_control, fn
        :t1 -> {:public, 60_000}
        :t2 -> {:public, 30_000}
      end)

      state = init_suite(tools: [{ToolFullMock, :t1}, {ToolFullMock, :t2}])

      assert {:result, %MCP.ListToolsResult{cacheScope: :public, ttlMs: 30_000}} =
               Suite.handle_request(list_tools_req(), build_channel(), state)
    end

    test "tools/list: a tool without cache_control forces no-cache" do
      # ToolFullMock implements cache_control; ToolMock (skips it) does not, so it
      # contributes {:private, 0} and poisons the aggregated result.
      ToolFullMock
      |> stub(:info, fn
        :name, :cached -> "Cached"
        _kind, :cached -> nil
      end)
      |> stub(:input_schema, fn :cached -> %{type: :object} end)
      |> stub(:output_schema, fn :cached -> nil end)
      |> stub(:cache_control, fn :cached -> {:public, 60_000} end)

      ToolMock
      |> stub(:info, fn
        :name, :plain -> "Plain"
        _kind, :plain -> nil
      end)
      |> stub(:input_schema, fn :plain -> %{type: :object} end)
      |> stub(:output_schema, fn :plain -> nil end)

      state = init_suite(tools: [{ToolFullMock, :cached}, {ToolMock, :plain}])

      assert {:result, %MCP.ListToolsResult{cacheScope: :private, ttlMs: 0}} =
               Suite.handle_request(list_tools_req(), build_channel(), state)
    end
  end

  describe "listing resource templates" do
    test "lists templates and skips repositories without one" do
      ResourceRepoMockTpl
      |> stub(:prefix, fn :repo2 -> "http://localhost/" end)
      |> stub(:template, fn :repo2 ->
        %{uriTemplate: "http://localhost/{path}", name: "HTTPTemplate"}
      end)

      stub(ResourceRepoMock, :prefix, fn
        :repo1 -> "file:///"
        :repo3 -> "s3://bucket/"
      end)

      state =
        init_suite(
          resources: [
            {ResourceRepoMock, :repo1},
            {ResourceRepoMockTpl, :repo2},
            {ResourceRepoMock, :repo3}
          ]
        )

      assert {:result, %MCP.ListResourceTemplatesResult{resourceTemplates: templates}} =
               Suite.handle_request(list_resource_templates_req(), build_channel(), state)

      assert [%{uriTemplate: "http://localhost/{path}", name: "HTTPTemplate"}] = templates
    end

    test "returns empty list when no templates available" do
      stub(ResourceRepoMock, :prefix, fn _ -> "file:///" end)

      state = init_suite(resources: [{ResourceRepoMock, :repo1}])

      assert {:result, %MCP.ListResourceTemplatesResult{resourceTemplates: []}} =
               Suite.handle_request(list_resource_templates_req(), build_channel(), state)
    end
  end

  describe "listing prompts" do
    test "lists prompts from a single repository" do
      prompts = [
        %{name: "greeting", description: "Say hello"},
        %{
          name: "analysis",
          description: "Analyze data",
          arguments: [%{name: "dataset", required: true}]
        }
      ]

      PromptRepoMock
      |> stub(:prefix, fn :arg -> "some_prefix" end)
      |> expect(:list, fn nil, _channel, :arg -> {prompts, nil} end)

      state = init_suite(prompts: [{PromptRepoMock, :arg}])

      assert {:result, %MCP.ListPromptsResult{prompts: ^prompts, nextCursor: nil}} =
               Suite.handle_request(list_prompts_req(), build_channel(), state)
    end

    test "prompt pagination cursors survive across per-request states" do
      page1 = [%{name: "prompt1"}, %{name: "prompt2"}]
      page2 = [%{name: "prompt3"}]

      PromptRepoMock
      |> stub(:prefix, fn :repo1 -> "some_prefix" end)
      |> expect(:list, fn nil, _channel, :repo1 -> {page1, "repo_cursor_2"} end)
      |> expect(:list, fn "repo_cursor_2", _channel, :repo1 -> {page2, nil} end)

      opts = [prompts: [{PromptRepoMock, :repo1}]]

      assert {:result, %MCP.ListPromptsResult{prompts: ^page1, nextCursor: cursor}} =
               Suite.handle_request(list_prompts_req(), build_channel(), init_suite(opts))

      assert is_binary(cursor)

      assert {:result, %MCP.ListPromptsResult{prompts: ^page2, nextCursor: nil}} =
               Suite.handle_request(list_prompts_req(cursor), build_channel(), init_suite(opts))
    end

    test "returns empty list when no prompts configured" do
      state = init_suite(prompts: [])

      assert {:result, %MCP.ListPromptsResult{prompts: [], nextCursor: nil}} =
               Suite.handle_request(list_prompts_req(), build_channel(), state)
    end
  end

  describe "getting prompts" do
    test "gets prompt without arguments" do
      result = MCP.get_prompt_result(description: "A greeting", text: "Hello!")

      PromptRepoMock
      |> stub(:prefix, fn :repo1 -> "gre" end)
      |> expect(:get, fn "greeting", args, _channel, :repo1 ->
        assert args == %{}
        {:ok, result}
      end)

      state = init_suite(prompts: [{PromptRepoMock, :repo1}])

      assert {:result, ^result} =
               Suite.handle_request(get_prompt_req("greeting"), build_channel(), state)
    end

    test "gets prompt with arguments" do
      result = MCP.get_prompt_result(text: "Analyze: test.csv")

      PromptRepoMock
      |> stub(:prefix, fn :repo1 -> "an" end)
      |> expect(:get, fn "analysis", args, _channel, :repo1 ->
        assert args == %{"dataset" => "test.csv"}
        {:ok, result}
      end)

      state = init_suite(prompts: [{PromptRepoMock, :repo1}])

      assert {:result, ^result} =
               Suite.handle_request(
                 get_prompt_req("analysis", %{"dataset" => "test.csv"}),
                 build_channel(),
                 state
               )
    end

    test "returns error for non-existent prompt" do
      PromptRepoMock
      |> stub(:prefix, fn :repo1 -> "unknown" end)
      |> expect(:get, fn "unknown", _, _channel, :repo1 -> {:error, :not_found} end)

      state = init_suite(prompts: [{PromptRepoMock, :repo1}])

      assert {:error, {:prompt_not_found, "unknown"}} =
               Suite.handle_request(get_prompt_req("unknown"), build_channel(), state)

      assert {200,
              %{code: -32_602, data: %{name: "unknown"}, message: "Prompt not found: unknown"}} =
               check_error({:prompt_not_found, "unknown"})
    end

    test "routes by prefix across multiple repos" do
      result = MCP.get_prompt_result([])

      PromptRepoMock
      |> stub(:prefix, fn
        :repo1 -> "prompt1"
        :repo2 -> "prompt2"
      end)
      |> expect(:get, fn "prompt2", _, _channel, :repo2 -> {:ok, result} end)

      state = init_suite(prompts: [{PromptRepoMock, :repo1}, {PromptRepoMock, :repo2}])

      assert {:result, ^result} =
               Suite.handle_request(get_prompt_req("prompt2"), build_channel(), state)
    end
  end

  describe "notifications" do
    test "cancelled notification is acknowledged and ignored" do
      # `handle_notification/3` returns `:ok`: a notification POST gets a 202
      # with no body and never streams, so there is no state to carry. The
      # channel is passed in (read-only context for trust) but the Suite ignores
      # the notification — statelessly there is nothing to act on.
      state = init_suite()

      notif = %MCP.CancelledNotification{
        params: %MCP.CancelledNotificationParams{
          requestId: "some-request-id",
          reason: "User cancelled the operation"
        }
      }

      assert :ok = Suite.handle_notification(notif, build_channel(), state)
    end
  end

  describe "unsupported requests" do
    # The Suite implements every request the validator currently accepts, so the
    # catch-all is defensive: a validable-but-unhandled method must return a
    # JSON-RPC "method not found" rather than crash the per-request worker.
    test "a legal request the Suite does not implement returns method-not-found" do
      state = init_suite()
      req = %GenMCP.Support.UnsupportedRequest{id: 1, params: %{}}

      assert {:error, {:unsupported_method, "test/unsupported"}} =
               Suite.handle_request(req, build_channel(), state)
    end

    test "the method-not-found reason casts to a 200 / -32601 JSON-RPC error" do
      assert {200,
              %{
                code: -32_601,
                message: "Method not supported: test/unsupported",
                data: %{method: "test/unsupported"}
              }} = GenMCP.Error.cast_error({:unsupported_method, "test/unsupported"})
    end
  end
end
