defmodule GenMCP.SuiteSessionTest do
  use ExUnit.Case, async: false

  import GenMCP.Test.Helpers
  import Mox

  alias GenMCP.MCP
  alias GenMCP.Mux
  alias GenMCP.Mux.Channel
  alias GenMCP.Suite
  alias GenMCP.Support.ExtensionMock
  alias GenMCP.Support.SessionControllerMock

  setup [:set_mox_global, :verify_on_exit!]

  @sid "ABCD-some-session-id"

  @default_opts [
    server_name: "Test Server",
    server_version: "0",
    server: Suite,

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

  describe "with initialization" do
    # suite is initialized with a regular initialize request, which triggers the
    # session creation
    #
    # session creation will add an assign in the channel

    defp init_initialize_create(opts \\ []) do
      expect(SessionControllerMock, :create, fn @sid, norm_client, channel, arg ->
        assert %{"client_capabilities" => %{}, "client_initialized" => false} = norm_client

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

        # we get the arg from the :session_controller option
        assert %{log: [:arg]} == arg
        {:ok, %{}, channel, :foo}
      end)

      state = init_server()

      assert {:stop, {:invalid_restored_client_info, %JSV.ValidationError{}}, _} =
               Suite.session_restore(:some_restore_data, build_channel(), state)
    end
  end

  describe "with restore" do
    defp init_with_restore(opts \\ []) do
      expect(SessionControllerMock, :restore, fn restore_data, channel, arg ->
        assert :some_restore_data == restore_data

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

  describe "session callback error handling" do
    test "create callback returning stop tuple stops the session" do
      expect(SessionControllerMock, :create, fn @sid, norm_client, _channel, arg ->
        assert %{"client_capabilities" => _, "client_initialized" => _} = norm_client

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
      expect(SessionControllerMock, :restore, fn restore_data, _channel, arg ->
        assert :some_restore_data == restore_data

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
      expect(SessionControllerMock, :fetch, fn @sid, _channel, arg ->
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

  defp init_session do
    {:ok, session_id} = Mux.start_session(@default_opts)
    session_id
  end

  defp run_async(fun) do
    fun
    |> Task.async()
    |> Task.await()
  end

  describe "listener change events" do
    # To test listener changes we will send requests from tasks so they have
    # their own pid, and they exit, letting the suite server receive monitor
    # down messages.
    #
    # Also to test OTP processes in real environments we cannot just call the
    # Suite callbacks, we need to start a real session.

    test "session controller receives listener change event on init request down" do
      #
      # Server is first initialized

      session_id = init_session()
      test = self()
      # We should expect a session create event on initialization
      # We should get a channel change event as well

      SessionControllerMock
      |> expect(:create, fn ^session_id, _norm_client, channel, _arg ->
        assert :request = channel.status
        {:ok, assign_event(channel, :called_create), data_event(%{log: [:arg]}, :called_create)}
      end)
      |> expect(:listener_change, fn channel, session_data ->
        assert %{status: :closed, client: nil} = channel
        send(test, :listener_change_on_init)

        {:ok, assign_event(channel, :called_change_init),
         data_event(session_data, :called_change_init)}
      end)

      assert {:result, %MCP.InitializeResult{}} =
               run_async(fn -> Mux.request(session_id, init_req(), build_channel()) end)

      assert_receive :listener_change_on_init

      #
      # A new listener opens
      #
      # The callback will be called when the channel opens, it will send a
      # message and then close it, so the callback will be called again with a
      # closed channel

      SessionControllerMock
      |> expect(:listener_change, fn channel, session_data ->
        assert %{status: :request, client: p} = channel
        assert is_pid(p)
        send(test, :listener_change_on_open)

        {:ok, channel} = Channel.send_message(channel, "hello")
        {:ok, channel} = Channel.close(channel)

        {:ok, assign_event(channel, :called_change_open),
         data_event(session_data, :called_change_open)}
      end)
      |> expect(:listener_change, fn channel, session_data ->
        assert %{status: :closed, client: nil} = channel
        send(test, :listener_change_on_close)

        {:ok, assign_event(channel, :called_change_closed),
         data_event(session_data, :called_change_closed)}
      end)

      :ok =
        run_async(fn ->
          assert :stream = Mux.request(session_id, %MCP.ListenerRequest{}, build_channel())

          assert_receive {:"$gen_mcp", :raw_message, "hello"}
          assert_receive {:"$gen_mcp", :close}
          :ok
        end)

      assert_receive :listener_change_on_open
      assert_receive :listener_change_on_close
      # We should be able to stop the session as our callbacks return correct
      # values and will not crash the session

      assert :ok = GenServer.stop(Mux.whereis(session_id))
    end

    test "session controller receives listener change event on restore with any request" do
      session_id = random_session_id()
      test = self()

      SessionControllerMock
      |> expect(:fetch, fn ^session_id, _channel, _arg ->
        {:ok, :some_restore_data}
      end)
      |> expect(:restore, fn :some_restore_data, channel, arg ->
        {:ok, normalized_client(), channel, arg}
      end)
      |> expect(:listener_change, fn channel, _session_data ->
        assert %{status: :closed, client: nil} = channel
        send(test, :listener_change_on_restore_request)
        {:ok, channel}
      end)

      run_async(fn ->
        channel = build_channel()
        {:ok, session_pid} = Mux.ensure_started(session_id, channel, @default_opts)
        Mux.request(session_pid, %MCP.ListToolsRequest{}, channel)
      end)

      assert_receive :listener_change_on_restore_request
      assert :ok = GenServer.stop(Mux.whereis(session_id))
    end

    test "session controller receives listener change event on restore with any notification" do
      session_id = random_session_id()
      test = self()

      SessionControllerMock
      |> expect(:fetch, fn ^session_id, _channel, _arg ->
        {:ok, :some_restore_data}
      end)
      |> expect(:restore, fn :some_restore_data, channel, arg ->
        {:ok, normalized_client(), channel, arg}
      end)
      |> expect(:listener_change, fn channel, _session_data ->
        assert %{status: :closed, client: nil} = channel
        send(test, :listener_change_on_restore_notification)
        {:ok, channel}
      end)

      run_async(fn ->
        channel = build_channel()
        {:ok, session_pid} = Mux.ensure_started(session_id, channel, @default_opts)

        Mux.notify(
          session_pid,
          %MCP.CancelledNotification{
            method: "notifications/cancelled",
            params: %MCP.CancelledNotificationParams{requestId: "123", reason: "test"}
          }
        )
      end)

      assert_receive :listener_change_on_restore_notification
      assert :ok = GenServer.stop(Mux.whereis(session_id))
    end
  end
end
