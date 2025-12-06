defmodule GenMCP.SuiteSessionTest do
  use ExUnit.Case, async: true

  import GenMCP.Test.Helpers
  import Mox

  alias GenMCP.MCP
  alias GenMCP.Mux.Channel
  alias GenMCP.Suite
  alias GenMCP.Support.ExtensionMock
  alias GenMCP.Support.PromptRepoMock
  alias GenMCP.Support.ResourceRepoMock
  alias GenMCP.Support.SessionControllerMock
  alias GenMCP.Support.ToolMock

  setup :verify_on_exit!

  @sid "ABCD-some-session-id"

  @default_opts [
    server_name: "Test Server",
    server_version: "0",

    # All tests start with the same mock data when not restored
    session_controller: {SessionControllerMock, %{log: [:arg]}}
  ]

  # Add the given "event" in the session data :log key
  defp data_event(session_data, event) do
    %{session_data | log: [event | session_data.log]}
  end

  # Add the given "event" in the assigns data :log key
  defp assign_event(channel, event) do
    logs =
      case Map.fetch(channel.assigns, :log) do
        {:ok, logs} -> logs
        :error -> []
      end

    Channel.assign(channel, :log, [event | logs])
  end

  defp init_server(opts \\ []) do
    {:ok, state} = Suite.init(@sid, Keyword.merge(@default_opts, opts))
    state
  end

  defp init_req(opts \\ []) do
    %MCP.InitializeRequest{
      id: "setup-init-1",
      params: %MCP.InitializeRequestParams{
        capabilities: opts[:capabilities] || %MCP.ClientCapabilities{},
        clientInfo: %{name: "test", version: "1.0.0"},
        protocolVersion: "2025-06-18"
      }
    }
  end

  defp init_notif do
    %MCP.InitializedNotification{
      method: "notifications/initialized",
      params: %{}
    }
  end

  # ---------------------------------------------------------------------------
  # Regular initialization
  # ---------------------------------------------------------------------------

  describe "regular initialization" do
    test "session controller create callback is called on initialization request" do
      state = init_server()

      expect(SessionControllerMock, :create, fn @sid, norm_client, channel, arg ->
        assert %{
                 "client_capabilities" => %{
                   "elicitation" => %{"eli" => "cit!"},
                   "experimental" => %{"foo" => %{"bar" => 123}}
                 },
                 "client_initialized" => false
               } = norm_client

        assert %{foo: :bar} = channel.assigns
        assert %{log: [:arg]} == arg
        {:ok, channel, arg}
      end)

      assert {:reply, {:result, _}, _} =
               Suite.handle_request(
                 init_req(
                   capabilities: %MCP.ClientCapabilities{
                     experimental: %{"foo" => %{"bar" => 123}},
                     elicitation: %{"eli" => "cit!"}
                   }
                 ),
                 build_channel(%{foo: :bar}),
                 state
               )
    end
  end

  # ---------------------------------------------------------------------------
  # With initialization - channel default assigns
  # ---------------------------------------------------------------------------

  describe "with initialization - channel default assigns" do
    # suite is initialized with a regular initialize request, which triggers the
    # session creation
    #
    # session creation will add an assign in the channel

    defp init_initialize_create(opts \\ []) do
      expect(SessionControllerMock, :create, fn @sid, norm_client, channel, arg ->
        assert %{"client_capabilities" => %{}, "client_initialized" => false} = norm_client
        assert nil == channel.assigns[:log]
        assert %{log: [:arg]} == arg

        {:ok, assign_event(channel, :called_create), data_event(arg, :called_create)}
      end)

      state = init_server(opts)

      assert {:reply, {:result, _}, state} =
               Suite.handle_request(init_req(), build_channel(), state)

      expect(SessionControllerMock, :update, fn @sid, norm_client, channel, session_state ->
        assert %{"client_capabilities" => %{}, "client_initialized" => true} = norm_client
        assert [:called_create] == channel.assigns[:log]
        assert [:called_create, :arg] == session_state.log

        {:ok, assign_event(channel, :called_update), data_event(session_state, :called_update)}
      end)

      assert {:noreply, state} = Suite.handle_notification(init_notif(), state)

      assert true == state.client_initialized

      state
    end

    test "extension mock receives updated channel" do
      # Extensions init happens before notifications/initialized, we will not
      # have the updated capabilities

      ExtensionMock
      |> expect(:tools, fn channel, _ext_arg ->
        assert [:called_create] = channel.assigns.log
        []
      end)
      |> expect(:resources, fn channel, _ext_arg ->
        assert [:called_create] = channel.assigns.log
        []
      end)
      |> expect(:prompts, fn channel, _ext_arg ->
        assert [:called_create] = channel.assigns.log
        []
      end)

      state = init_initialize_create(extensions: [ExtensionMock])

      assert {:reply, {:result, _}, _} =
               Suite.handle_request(%MCP.ListToolsRequest{}, build_channel(), state)

      assert {:reply, {:result, _}, _} =
               Suite.handle_request(%MCP.ListResourcesRequest{}, build_channel(), state)

      assert {:reply, {:result, _}, _} =
               Suite.handle_request(%MCP.ListPromptsRequest{}, build_channel(), state)
    end

    test "tool mock receives updated channel on CallToolRequest" do
      ToolMock
      |> stub(:info, fn :name, _tool_arg -> "TestTool" end)
      |> stub(:input_schema, fn _ -> %{type: :object} end)

      state = init_initialize_create(tools: [ToolMock])

      expect(ToolMock, :call, fn _req, channel, _tool_arg ->
        assert [:called_update, :called_create] = channel.assigns.log
        {:result, MCP.call_tool_result(text: "ok"), channel}
      end)

      tool_call_req = %MCP.CallToolRequest{
        id: 1,
        params: %MCP.CallToolRequestParams{
          name: "TestTool",
          arguments: %{}
        }
      }

      assert {:reply, {:result, _}, _} =
               Suite.handle_request(tool_call_req, build_channel(), state)
    end

    test "resource repo mock receives updated channel on list resources" do
      stub(ResourceRepoMock, :prefix, fn _repo_arg -> "file:///" end)

      state = init_initialize_create(resources: [ResourceRepoMock])

      expect(ResourceRepoMock, :list, fn _cursor, channel, _repo_arg ->
        assert [:called_update, :called_create] = channel.assigns.log
        {[], nil}
      end)

      assert {:reply, {:result, _}, _} =
               Suite.handle_request(%MCP.ListResourcesRequest{}, build_channel(), state)
    end

    test "prompt repo mock receives updated channel on list prompts" do
      stub(PromptRepoMock, :prefix, fn _repo_arg -> "test_" end)
      state = init_initialize_create(prompts: [PromptRepoMock])

      expect(PromptRepoMock, :list, fn _cursor, channel, _repo_arg ->
        assert [:called_update, :called_create] = channel.assigns.log
        {[], nil}
      end)

      assert {:reply, {:result, _}, _} =
               Suite.handle_request(%MCP.ListPromptsRequest{}, build_channel(), state)
    end

    test "session controller handle_info callback is called with new arg" do
      state = init_initialize_create()

      expect(SessionControllerMock, :handle_info, fn :custom_info, channel, session_data ->
        assert [:called_update, :called_create] = channel.assigns.log
        assert [:called_update, :called_create, :arg] == session_data.log
        {:noreply, channel, session_data}
      end)

      assert {:noreply, _state} = Suite.handle_info(:custom_info, state)
    end

    test "session controller handle_info can return just session_state without channel" do
      state = init_initialize_create()

      expect(SessionControllerMock, :handle_info, fn :custom_info, channel, session_data ->
        assert [:called_update, :called_create] = channel.assigns.log
        assert [:called_update, :called_create, :arg] == session_data.log
        {:noreply, data_event(session_data, :called_info)}
      end)

      assert {:noreply, state} = Suite.handle_info(:custom_info, state)

      # In that case the cannel is not updated

      expect(SessionControllerMock, :handle_info, fn :custom_info_2, channel, session_data ->
        assert [:called_update, :called_create] = channel.assigns.log
        assert [:called_info, :called_update, :called_create, :arg] == session_data.log
        {:noreply, session_data}
      end)

      assert {:noreply, _state} = Suite.handle_info(:custom_info_2, state)
    end
  end

  # ---------------------------------------------------------------------------
  # With initialization - updated info
  # ---------------------------------------------------------------------------

  describe "with initialization - updated info" do
    defp init_initialize_create_and_handle_info(info_msg, opts \\ []) do
      state = init_initialize_create(opts)

      expect(SessionControllerMock, :handle_info, fn ^info_msg, channel, session_data ->
        assert [:called_update, :called_create] = channel.assigns.log
        assert [:called_update, :called_create, :arg] == session_data.log

        {:noreply, assign_event(channel, {:called_info, info_msg}),
         data_event(session_data, {:called_info, info_msg})}
      end)

      {:noreply, state} = Suite.handle_info(info_msg, state)

      state
    end

    test "tool mock receives cumulative assigns and latest arg on CallToolRequest" do
      ToolMock
      |> stub(:info, fn :name, :test_tool -> "TestTool" end)
      |> stub(:input_schema, fn _ -> %{type: :object} end)

      state = init_initialize_create_and_handle_info(:some_info, tools: [{ToolMock, :test_tool}])

      expect(ToolMock, :call, fn _req, channel, _tool_arg ->
        assert [{:called_info, :some_info}, :called_update, :called_create] = channel.assigns.log

        {:result, MCP.call_tool_result(text: "ok"), channel}
      end)

      tool_call_req = %MCP.CallToolRequest{
        id: 1,
        params: %MCP.CallToolRequestParams{
          name: "TestTool",
          arguments: %{}
        }
      }

      assert {:reply, {:result, _}, _} =
               Suite.handle_request(tool_call_req, build_channel(), state)
    end

    test "session controller receives latest data on subsequent handle_info" do
      state = init_initialize_create_and_handle_info(:first_info)

      expect(SessionControllerMock, :handle_info, fn :second_info, channel, session_data ->
        assert [{:called_info, :first_info}, :called_update, :called_create] = channel.assigns.log

        assert [{:called_info, :first_info}, :called_update, :called_create, :arg] ==
                 session_data.log

        {:noreply, assign_event(channel, :second_info), data_event(session_data, :second_info)}
      end)

      assert {:noreply, state} = Suite.handle_info(:second_info, state)

      # Another handle info to verify

      expect(SessionControllerMock, :handle_info, fn :second_info, channel, session_data ->
        assert [
                 :second_info,
                 {:called_info, :first_info},
                 :called_update,
                 :called_create
               ] =
                 channel.assigns.log

        assert [
                 :second_info,
                 {:called_info, :first_info},
                 :called_update,
                 :called_create,
                 :arg
               ] ==
                 session_data.log

        {:noreply, assign_event(channel, :second_info), data_event(session_data, :second_info)}
      end)

      assert {:noreply, _state} = Suite.handle_info(:second_info, state)
    end
  end

  # ---------------------------------------------------------------------------
  # Session restore
  # ---------------------------------------------------------------------------

  defp normalized_client do
    %{
      "client_capabilities" => %{
        "elicitation" => %{"some" => "stuff"},
        "experimental" => %{"foo" => %{"bar" => 123}}
      },
      "client_initialized" => false
    }
  end

  describe "session restore" do
    test "restore callback is called via Suite.session_restore" do
      expect(SessionControllerMock, :restore, fn restore_data, channel, arg ->
        # restore data given to session_restore is given
        assert :some_restore_data == restore_data

        # Channel is fresh
        assert nil == channel.assigns[:log]

        # we get the arg from the :session_controller option
        assert %{log: [:arg]} == arg

        {:ok, normalized_client(), channel, :foo}
      end)

      state = init_server()

      assert {:noreply, _state} =
               Suite.session_restore(:some_restore_data, build_channel(), state)
    end

    test "restore callback returns invalid client info" do
      expect(SessionControllerMock, :restore, fn restore_data, channel, arg ->
        # restore data given to session_restore is given
        assert :some_restore_data == restore_data

        # Channel is fresh
        assert nil == channel.assigns[:log]

        # we get the arg from the :session_controller option
        assert %{log: [:arg]} == arg
        {:ok, %{}, channel, :foo}
      end)

      state = init_server()

      assert {:stop, {:invalid_restored_client_info, %JSV.ValidationError{}}, _} =
               Suite.session_restore(:some_restore_data, build_channel(), state)
    end
  end

  # ---------------------------------------------------------------------------
  # With restore - channel default assigns
  # ---------------------------------------------------------------------------

  describe "with restore - channel default assigns" do
    defp init_with_restore(opts \\ []) do
      expect(SessionControllerMock, :restore, fn restore_data, channel, arg ->
        assert :some_restore_data == restore_data
        assert nil == channel.assigns[:log]
        assert %{log: [:arg]} == arg

        {
          :ok,
          normalized_client(),
          assign_event(channel, :called_restore),
          data_event(arg, :called_restore)
        }
      end)

      state = init_server(opts)

      {:noreply, state} = Suite.session_restore(:some_restore_data, build_channel(), state)
      state
    end

    test "extension mock receives updated channel" do
      ExtensionMock
      |> expect(:tools, fn channel, _ext_arg ->
        assert [:called_restore] = channel.assigns.log
        []
      end)
      |> expect(:resources, fn channel, _ext_arg ->
        assert [:called_restore] = channel.assigns.log
        []
      end)
      |> expect(:prompts, fn channel, _ext_arg ->
        assert [:called_restore] = channel.assigns.log
        []
      end)

      state = init_with_restore(extensions: [ExtensionMock])

      assert {:reply, {:result, _}, state} =
               Suite.handle_request(%MCP.ListToolsRequest{}, build_channel(), state)

      assert {:reply, {:result, _}, state} =
               Suite.handle_request(%MCP.ListResourcesRequest{}, build_channel(), state)

      assert {:reply, {:result, _}, _state} =
               Suite.handle_request(%MCP.ListPromptsRequest{}, build_channel(), state)
    end

    test "tool mock receives updated channel on CallToolRequest" do
      ToolMock
      |> stub(:info, fn :name, _ -> "TestTool" end)
      |> stub(:input_schema, fn _ -> %{type: :object} end)

      state = init_with_restore(tools: [ToolMock])

      expect(ToolMock, :call, fn _req, channel, _tool_arg ->
        assert [:called_restore] = channel.assigns.log
        {:result, MCP.call_tool_result(text: "ok"), channel}
      end)

      tool_call_req = %MCP.CallToolRequest{
        id: 1,
        params: %MCP.CallToolRequestParams{
          name: "TestTool",
          arguments: %{}
        }
      }

      assert {:reply, {:result, _}, _} =
               Suite.handle_request(tool_call_req, build_channel(), state)
    end

    test "resource repo mock receives updated channel on list resources" do
      stub(ResourceRepoMock, :prefix, fn _ -> "file:///" end)
      state = init_with_restore(resources: [ResourceRepoMock])

      expect(ResourceRepoMock, :list, fn _cursor, channel, _repo_arg ->
        assert [:called_restore] = channel.assigns.log
        {[], nil}
      end)

      assert {:reply, {:result, _}, _} =
               Suite.handle_request(%MCP.ListResourcesRequest{}, build_channel(), state)
    end

    test "prompt repo mock receives updated channel on list prompts" do
      stub(PromptRepoMock, :prefix, fn _ -> "test_" end)

      state = init_with_restore(prompts: [PromptRepoMock])

      expect(PromptRepoMock, :list, fn _cursor, channel, _repo_arg ->
        assert [:called_restore] = channel.assigns.log
        {[], nil}
      end)

      assert {:reply, {:result, _}, _} =
               Suite.handle_request(%MCP.ListPromptsRequest{}, build_channel(), state)
    end

    test "session controller handle_info callback is called with new arg" do
      state = init_with_restore()

      expect(SessionControllerMock, :handle_info, fn :custom_info, channel, session_data ->
        assert [:called_restore] = channel.assigns.log
        assert [:called_restore, :arg] == session_data.log
        {:noreply, channel, session_data}
      end)

      assert {:noreply, _state} = Suite.handle_info(:custom_info, state)
    end

    test "session controller handle_info can return just session_state without channel" do
      state = init_with_restore()

      expect(SessionControllerMock, :handle_info, fn :custom_info, channel, session_data ->
        assert [:called_restore] = channel.assigns.log
        assert [:called_restore, :arg] == session_data.log
        {:noreply, data_event(session_data, :first_handle_info)}
      end)

      assert {:noreply, state} = Suite.handle_info(:custom_info, state)

      expect(SessionControllerMock, :handle_info, fn :next_info, channel, session_data ->
        # session data is updated but not channel
        assert [:called_restore] = channel.assigns.log
        assert [:first_handle_info, :called_restore, :arg] == session_data.log

        {:noreply, session_data}
      end)

      assert {:noreply, _state} = Suite.handle_info(:next_info, state)
    end
  end

  # ---------------------------------------------------------------------------
  # With restore - updated info
  # ---------------------------------------------------------------------------

  describe "with restore - updated info" do
    defp init_with_restore_and_handle_info(info_msg, opts \\ []) do
      state = init_with_restore(opts)

      expect(SessionControllerMock, :handle_info, fn ^info_msg, channel, session_data ->
        assert [:called_restore] = channel.assigns.log
        assert [:called_restore, :arg] == session_data.log

        {
          :noreply,
          assign_event(channel, {:called_info, info_msg}),
          data_event(session_data, {:called_info, info_msg})
        }
      end)

      {:noreply, state} = Suite.handle_info(info_msg, state)
      state
    end

    test "tool mock receives cumulative assigns and latest arg on CallToolRequest" do
      ToolMock
      |> stub(:info, fn :name, _ -> "TestTool" end)
      |> stub(:input_schema, fn _ -> %{type: :object} end)

      state = init_with_restore_and_handle_info(:hello, tools: [ToolMock])

      expect(ToolMock, :call, fn _req, channel, _tool_arg ->
        assert [{:called_info, :hello}, :called_restore] = channel.assigns.log

        {:result, MCP.call_tool_result(text: "ok"), channel}
      end)

      tool_call_req = %MCP.CallToolRequest{
        id: 1,
        params: %MCP.CallToolRequestParams{
          name: "TestTool",
          arguments: %{}
        }
      }

      assert {:reply, {:result, _}, _} =
               Suite.handle_request(tool_call_req, build_channel(), state)
    end

    test "session controller receives latest data on subsequent handle_info" do
      state = init_with_restore_and_handle_info(:first_info)

      expect(SessionControllerMock, :handle_info, fn :second_info, channel, session_data ->
        assert [{:called_info, :first_info}, :called_restore] = channel.assigns.log
        assert [{:called_info, :first_info}, :called_restore, :arg] == session_data.log

        {:noreply, assign_event(channel, :called_info_second),
         data_event(session_data, :called_info_second)}
      end)

      assert {:noreply, state} = Suite.handle_info(:second_info, state)

      expect(SessionControllerMock, :handle_info, fn :second_info, channel, session_data ->
        assert [:called_info_second, {:called_info, :first_info}, :called_restore] =
                 channel.assigns.log

        assert [:called_info_second, {:called_info, :first_info}, :called_restore, :arg] ==
                 session_data.log

        {:noreply, channel, session_data}
      end)

      assert {:noreply, _state} = Suite.handle_info(:second_info, state)
    end
  end

  # ---------------------------------------------------------------------------
  # Session callback error handling
  # ---------------------------------------------------------------------------

  describe "session callback error handling" do
    test "create callback returning stop tuple stops the session" do
      expect(SessionControllerMock, :create, fn @sid, norm_client, channel, arg ->
        assert %{"client_capabilities" => _, "client_initialized" => _} = norm_client
        assert nil == channel.assigns[:log]
        assert %{log: [:arg]} == arg
        {:stop, :some_custom_error}
      end)

      state = init_server()

      init_req = %MCP.InitializeRequest{
        id: "init-1",
        params: %MCP.InitializeRequestParams{
          capabilities: %MCP.ClientCapabilities{},
          clientInfo: %{name: "test", version: "1.0.0"},
          protocolVersion: "2025-06-18"
        }
      }

      assert {:stop, {:shutdown, {:init_failure, :some_custom_error}},
              {:error, :some_custom_error}, _state} =
               Suite.handle_request(init_req, build_channel(), state)
    end

    test "update callback returning stop tuple stops the session" do
      expect(SessionControllerMock, :create, fn @sid, norm_client, channel, arg ->
        assert %{"client_capabilities" => _, "client_initialized" => false} = norm_client
        assert nil == channel.assigns[:log]
        assert %{log: [:arg]} == arg
        {:ok, assign_event(channel, :called_create), data_event(arg, :called_create)}
      end)

      expect(SessionControllerMock, :update, fn @sid, norm_client, channel, session_state ->
        assert %{"client_capabilities" => _, "client_initialized" => true} = norm_client
        assert [:called_create] == channel.assigns[:log]
        assert [:called_create, :arg] == session_state.log
        {:stop, :some_custom_error}
      end)

      state = init_server()

      assert {:reply, _, state} =
               Suite.handle_request(init_req(), build_channel(), state)

      assert {:stop, :some_custom_error} = Suite.handle_notification(init_notif(), state)
    end

    test "restore callback returning stop tuple stops the session" do
      expect(SessionControllerMock, :restore, fn restore_data, channel, arg ->
        assert :some_restore_data == restore_data
        assert nil == channel.assigns[:log]
        assert %{log: [:arg]} == arg
        {:stop, {:shutdown, :restore_failed}}
      end)

      state = init_server()

      assert {:stop, {:shutdown, :restore_failed}, _state} =
               Suite.session_restore(:some_restore_data, build_channel(), state)
    end

    test "handle_info callback returning stop tuple stops the session" do
      state = init_initialize_create()

      expect(SessionControllerMock, :handle_info, fn :some_message, channel, session_data ->
        assert [:called_update, :called_create] = channel.assigns.log
        assert [:called_update, :called_create, :arg] == session_data.log
        {:stop, {:shutdown, :handle_info_failed}}
      end)

      assert {:stop, {:shutdown, :handle_info_failed}, _state} =
               Suite.handle_info(:some_message, state)
    end
  end

  # ---------------------------------------------------------------------------
  # Session delete
  # ---------------------------------------------------------------------------

  describe "session delete" do
    test "delete callback is called via Suite.session_delete" do
      expect(SessionControllerMock, :delete, fn @sid, session_data ->
        assert [:called_update, :called_create, :arg] == session_data.log
        :ok
      end)

      state = init_initialize_create()

      assert :ok = Suite.session_delete(state)
    end
  end

  describe "session fetching" do
    test "delegates to the session controller when set" do
      expect(SessionControllerMock, :fetch, fn @sid, channel, arg ->
        assert nil == channel.assigns[:log]
        assert %{log: [:arg]} == arg
        {:ok, :some_data}
      end)

      assert {:ok, :some_data} = Suite.session_fetch(@sid, build_channel(), @default_opts)

      expect(SessionControllerMock, :fetch, fn @sid, _, _ ->
        {:error, :not_found}
      end)

      assert {:error, :not_found} = Suite.session_fetch(@sid, build_channel(), @default_opts)
    end

    test "without session_controller it's not found" do
      opts = [
        server_name: "Test Server",
        server_version: "0"
      ]

      assert {:error, :not_found} = Suite.session_fetch(@sid, build_channel(), opts)
    end
  end

  @tag :skip
  # TODO we must implement channel monitoring, and channel tagging
  # this should come with the support for GET requests
  test "after initialize http process :DOWN," <>
         " session controller receives a disabled channel in handle_info"

  @tag :skip
  test "session controller is called on session timeout"
end
