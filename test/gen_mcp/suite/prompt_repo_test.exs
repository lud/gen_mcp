defmodule GenMCP.Suite.PromptRepoTest do
  use ExUnit.Case, async: true

  import Mox

  alias GenMCP.Suite.PromptRepo
  alias GenMCP.Support.PromptRepoMock

  setup :verify_on_exit!

  defp build_channel do
    %GenMCP.Mux.Channel{client: self(), progress_token: nil, assigns: %{}}
  end

  describe "expand/1" do
    test "expands module atom" do
      expect(PromptRepoMock, :prefix, fn [] -> "some_prefix" end)

      assert assert %{mod: PromptRepoMock, arg: [], prefix: "some_prefix"} =
                      PromptRepo.expand(PromptRepoMock)
    end

    test "expands {module, arg} tuple" do
      expect(PromptRepoMock, :prefix, fn :custom -> "some_prefix" end)

      assert %{mod: PromptRepoMock, arg: :custom, prefix: "some_prefix"} =
               PromptRepo.expand({PromptRepoMock, :custom})
    end

    test "incomplete descriptor" do
      descriptor = %{mod: PromptRepoMock, arg: :test}

      assert_raise FunctionClauseError, fn ->
        assert ^descriptor = PromptRepo.expand(descriptor)
      end
    end

    test "empty prefix is ok" do
      descriptor = %{mod: PromptRepoMock, arg: :test, prefix: ""}
      assert ^descriptor = PromptRepo.expand(descriptor)
    end
  end

  describe "list_prompts/2" do
    test "returns prompts from repository" do
      repo = %{mod: PromptRepoMock, arg: :test_arg}

      prompts = [
        %{name: "greeting", description: "Say hello"},
        %{name: "analysis", description: "Analyze data"}
      ]

      expect(PromptRepoMock, :list, fn nil, _channel, :test_arg ->
        {prompts, nil}
      end)

      channel = build_channel()
      assert {^prompts, nil} = PromptRepo.list_prompts(repo, nil, channel)
    end

    test "handles pagination cursor" do
      repo = %{mod: PromptRepoMock, arg: []}

      expect(PromptRepoMock, :list, fn "page2", _channel, [] ->
        {[%{name: "prompt3"}], "page3"}
      end)

      channel = build_channel()
      assert {[%{name: "prompt3"}], "page3"} = PromptRepo.list_prompts(repo, "page2", channel)
    end

    test "exits on invalid return value" do
      repo = %{mod: PromptRepoMock, arg: []}

      expect(PromptRepoMock, :list, fn _, _channel, _ ->
        :some_invalid_val
      end)

      channel = build_channel()

      assert %GenMCP.CallbackReturnError{
               behaviour: PromptRepo,
               mfa: {PromptRepoMock, :list, _},
               return_value: :some_invalid_val
             } = catch_error(PromptRepo.list_prompts(repo, nil, channel))
    end
  end

  describe "get_prompt/3" do
    test "returns prompt result" do
      repo = %{mod: PromptRepoMock, arg: :test_arg}

      result = %GenMCP.MCP.GetPromptResult{
        description: "Test prompt",
        messages: []
      }

      expect(PromptRepoMock, :get, fn "greeting", %{}, _channel, :test_arg ->
        {:ok, result}
      end)

      channel = build_channel()
      assert {:ok, ^result} = PromptRepo.get_prompt(repo, "greeting", %{}, channel)
    end

    test "transforms :not_found to {:prompt_not_found, name}" do
      repo = %{mod: PromptRepoMock, arg: []}

      expect(PromptRepoMock, :get, fn "unknown", %{}, _channel, [] ->
        {:error, :not_found}
      end)

      channel = build_channel()

      assert {:error, {:prompt_not_found, "unknown"}} =
               PromptRepo.get_prompt(repo, "unknown", %{}, channel)
    end

    test "passes through string error messages" do
      repo = %{mod: PromptRepoMock, arg: []}

      expect(PromptRepoMock, :get, fn "test", %{}, _channel, [] ->
        {:error, "Missing required argument: dataset"}
      end)

      channel = build_channel()

      assert {:error, "Missing required argument: dataset"} =
               PromptRepo.get_prompt(repo, "test", %{}, channel)
    end

    test "can return invalid params" do
      repo = %{mod: PromptRepoMock, arg: []}

      expect(PromptRepoMock, :get, fn "test", %{}, _channel, [] ->
        {:error, {:invalid_params, "some message"}}
      end)

      channel = build_channel()

      assert {:error, {:invalid_params, "some message"}} =
               PromptRepo.get_prompt(repo, "test", %{}, channel)
    end

    test "exits on invalid return value" do
      repo = %{mod: PromptRepoMock, arg: []}

      expect(PromptRepoMock, :get, fn _, _, _channel, _ ->
        {:ok, :not_a_result}
      end)

      channel = build_channel()

      assert %GenMCP.CallbackReturnError{
               behaviour: PromptRepo,
               mfa: {PromptRepoMock, :get, _},
               return_value: {:ok, :not_a_result}
             } =
               catch_error(PromptRepo.get_prompt(repo, "test", %{}, channel))
    end
  end
end
