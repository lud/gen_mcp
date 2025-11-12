defmodule GenMcp.PromptRepoTest do
  use ExUnit.Case, async: true

  alias GenMcp.PromptRepo
  alias GenMcp.Support.PromptRepoMock

  import Mox

  setup :verify_on_exit!

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

      expect(PromptRepoMock, :list, fn nil, :test_arg ->
        {prompts, nil}
      end)

      assert {^prompts, nil} = PromptRepo.list_prompts(repo, nil)
    end

    test "handles pagination cursor" do
      repo = %{mod: PromptRepoMock, arg: []}

      expect(PromptRepoMock, :list, fn "page2", [] ->
        {[%{name: "prompt3"}], "page3"}
      end)

      assert {[%{name: "prompt3"}], "page3"} = PromptRepo.list_prompts(repo, "page2")
    end

    test "exits on invalid return value" do
      repo = %{mod: PromptRepoMock, arg: []}

      expect(PromptRepoMock, :list, fn _, _ ->
        :invalid
      end)

      assert catch_exit(PromptRepo.list_prompts(repo, nil)) ==
               {:bad_return_value, :invalid}
    end
  end

  describe "get_prompt/3" do
    test "returns prompt result" do
      repo = %{mod: PromptRepoMock, arg: :test_arg}

      result = %GenMcp.Mcp.Entities.GetPromptResult{
        description: "Test prompt",
        messages: []
      }

      expect(PromptRepoMock, :get, fn "greeting", %{}, :test_arg ->
        {:ok, result}
      end)

      assert {:ok, ^result} = PromptRepo.get_prompt(repo, "greeting", %{})
    end

    test "transforms :not_found to {:prompt_not_found, name}" do
      repo = %{mod: PromptRepoMock, arg: []}

      expect(PromptRepoMock, :get, fn "unknown", %{}, [] ->
        {:error, :not_found}
      end)

      assert {:error, {:prompt_not_found, "unknown"}} =
               PromptRepo.get_prompt(repo, "unknown", %{})
    end

    test "passes through string error messages" do
      repo = %{mod: PromptRepoMock, arg: []}

      expect(PromptRepoMock, :get, fn "test", %{}, [] ->
        {:error, "Missing required argument: dataset"}
      end)

      assert {:error, "Missing required argument: dataset"} =
               PromptRepo.get_prompt(repo, "test", %{})
    end

    test "exits on invalid return value" do
      repo = %{mod: PromptRepoMock, arg: []}

      expect(PromptRepoMock, :get, fn _, _, _ ->
        {:ok, :not_a_result}
      end)

      assert catch_exit(PromptRepo.get_prompt(repo, "test", %{})) ==
               {:bad_return_value, {:ok, :not_a_result}}
    end
  end
end
