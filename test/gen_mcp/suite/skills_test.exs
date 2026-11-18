defmodule GenMCP.Suite.SkillsTest do
  use ExUnit.Case, async: true

  import GenMCP.Test.Helpers
  import Mox

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Suite
  alias GenMCP.Support.ExtensionFullMock
  alias GenMCP.Support.ExtensionMock
  alias GenMCP.Support.ResourceRepoMock
  alias GenMCP.Support.ResourceRepoMockTpl
  alias GenMCP.Support.SkillRepoCacheMock
  alias GenMCP.Support.SkillRepoMock

  setup :verify_on_exit!

  @server_info [server_name: "Test Server", server_version: "0"]
  @digest "sha256:" <> String.duplicate("0", 64)

  defp init_suite(server_opts) do
    assert {:ok, state} = Suite.init(Keyword.merge(@server_info, server_opts))
    state
  end

  defp discover_req do
    %MCP.DiscoverRequest{id: 1, params: %MCP.RequestParams{_meta: nil}}
  end

  defp list_skills_req(cursor \\ nil) do
    %MCP.ListSkillsRequest{id: 1, params: %MCP.PaginatedRequestParams{_meta: nil, cursor: cursor}}
  end

  defp get_skill_req(uri) do
    %MCP.GetSkillRequest{id: 1, params: %MCP.GetSkillRequestParams{_meta: nil, uri: uri}}
  end

  defp list_resources_req do
    %MCP.ListResourcesRequest{id: 1, params: %MCP.PaginatedRequestParams{_meta: nil}}
  end

  defp list_resource_templates_req do
    %MCP.ListResourceTemplatesRequest{id: 1, params: %MCP.PaginatedRequestParams{_meta: nil}}
  end

  defp read_resource_req(uri) do
    %MCP.ReadResourceRequest{id: 1, params: %MCP.ReadResourceRequestParams{_meta: nil, uri: uri}}
  end

  defp skill(root_uri) do
    %MCP.Skill{
      uri: root_uri <> "/SKILL.md",
      frontmatter: %{"name" => Path.basename(root_uri), "description" => "A skill"},
      resources: [%MCP.SkillResource{uri: root_uri <> "/SKILL.md", digest: @digest, size: 0}]
    }
  end

  defp handle(req, state) do
    Suite.handle_request(req, build_channel(), state)
  end

  describe "skills/list" do
    test "lists the skills of a configured repository" do
      SkillRepoMock
      |> stub(:prefix, fn :repo1 -> "skill://acme/" end)
      |> expect(:list_skills, fn nil, _channel, :repo1 ->
        {[skill("skill://acme/billing"), skill("skill://acme/refunds")], nil}
      end)

      state = init_suite(skills: [{SkillRepoMock, :repo1}])

      assert {:result,
              %MCP.ListSkillsResult{
                resultType: "complete",
                cacheScope: :private,
                ttlMs: 0,
                nextCursor: nil,
                skills: [
                  %MCP.Skill{uri: "skill://acme/billing/SKILL.md"},
                  %MCP.Skill{uri: "skill://acme/refunds/SKILL.md"}
                ]
              }} = handle(list_skills_req(), state)
    end

    test "paginates across the configured repository, then extension repositories" do
      SkillRepoMock
      |> stub(:prefix, fn
        :direct -> "skill://direct/"
        :ext -> "skill://ext/"
      end)
      |> expect(:list_skills, fn nil, _channel, :direct ->
        {[skill("skill://direct/one")], "direct-page-2"}
      end)
      |> expect(:list_skills, fn "direct-page-2", _channel, :direct ->
        {[skill("skill://direct/two")], nil}
      end)
      |> expect(:list_skills, fn nil, _channel, :ext ->
        {[skill("skill://ext/three")], nil}
      end)

      stub(ExtensionFullMock, :skills, fn _channel, :ext -> [{SkillRepoMock, :ext}] end)

      opts = [skills: [{SkillRepoMock, :direct}], extensions: [{ExtensionFullMock, :ext}]]

      assert {:result,
              %MCP.ListSkillsResult{skills: [%{uri: "skill://direct/one/SKILL.md"}]} = r1} =
               handle(list_skills_req(), init_suite(opts))

      assert is_binary(r1.nextCursor)

      assert {:result,
              %MCP.ListSkillsResult{skills: [%{uri: "skill://direct/two/SKILL.md"}]} = r2} =
               handle(list_skills_req(r1.nextCursor), init_suite(opts))

      assert is_binary(r2.nextCursor)

      assert {:result,
              %MCP.ListSkillsResult{
                skills: [%{uri: "skill://ext/three/SKILL.md"}],
                nextCursor: nil
              }} = handle(list_skills_req(r2.nextCursor), init_suite(opts))
    end

    test "a resources/list cursor is not accepted by skills/list" do
      ResourceRepoMock
      |> stub(:prefix, fn _ -> "file:///" end)
      |> expect(:list, fn nil, _channel, :res -> {[%{uri: "file:///a", name: "a"}], nil} end)

      SkillRepoMock
      |> stub(:prefix, fn :repo1 -> "skill://acme/" end)
      |> stub(:list_skills, fn _, _channel, :repo1 -> {[], nil} end)

      opts = [
        resources: [{ResourceRepoMock, :res}, {ResourceRepoMock, :res2}],
        skills: [{SkillRepoMock, :repo1}]
      ]

      assert {:result, %MCP.ListResourcesResult{nextCursor: cursor}} =
               handle(list_resources_req(), init_suite(opts))

      assert is_binary(cursor)
      assert {:error, :invalid_cursor} = handle(list_skills_req(cursor), init_suite(opts))
    end

    test "carries the repository cache hint" do
      SkillRepoCacheMock
      |> stub(:prefix, fn :repo1 -> "skill://acme/" end)
      |> stub(:cache_control, fn :repo1 -> {:public, 60_000} end)
      |> expect(:list_skills, fn nil, _channel, :repo1 -> {[skill("skill://acme/a")], nil} end)

      state = init_suite(skills: [{SkillRepoCacheMock, :repo1}])

      assert {:result, %MCP.ListSkillsResult{cacheScope: :public, ttlMs: 60_000}} =
               handle(list_skills_req(), state)
    end

    test "is empty with no skill repository" do
      assert {:result,
              %MCP.ListSkillsResult{
                skills: [],
                nextCursor: nil,
                cacheScope: :private,
                ttlMs: 0
              }} = handle(list_skills_req(), init_suite([]))
    end
  end

  describe "skills/get" do
    test "returns the entry of a known skill, listed or not" do
      SkillRepoMock
      |> stub(:prefix, fn :repo1 -> "skill://acme/" end)
      |> expect(:get_skill, fn "skill://acme/hidden/SKILL.md", _channel, :repo1 ->
        {:ok, skill("skill://acme/hidden")}
      end)

      state = init_suite(skills: [{SkillRepoMock, :repo1}])

      assert {:result,
              %MCP.GetSkillResult{
                resultType: "complete",
                cacheScope: :private,
                ttlMs: 0,
                skill: %MCP.Skill{uri: "skill://acme/hidden/SKILL.md"}
              }} = handle(get_skill_req("skill://acme/hidden/SKILL.md"), state)
    end

    test "routes by prefix to the matching repository" do
      SkillRepoMock
      |> stub(:prefix, fn
        :repo1 -> "skill://one/"
        :repo2 -> "skill://two/"
      end)
      |> expect(:get_skill, fn "skill://two/x/SKILL.md", _channel, :repo2 ->
        {:ok, skill("skill://two/x")}
      end)

      state = init_suite(skills: [{SkillRepoMock, :repo1}, {SkillRepoMock, :repo2}])

      assert {:result, %MCP.GetSkillResult{skill: %{uri: "skill://two/x/SKILL.md"}}} =
               handle(get_skill_req("skill://two/x/SKILL.md"), state)
    end

    test "carries the repository cache hint" do
      SkillRepoCacheMock
      |> stub(:prefix, fn :repo1 -> "skill://acme/" end)
      |> stub(:cache_control, fn :repo1 -> {:public, 5_000} end)
      |> expect(:get_skill, fn _, _channel, :repo1 -> {:ok, skill("skill://acme/a")} end)

      state = init_suite(skills: [{SkillRepoCacheMock, :repo1}])

      assert {:result, %MCP.GetSkillResult{cacheScope: :public, ttlMs: 5_000}} =
               handle(get_skill_req("skill://acme/a/SKILL.md"), state)
    end

    test "a not-found from the matching repository is final" do
      SkillRepoMock
      |> stub(:prefix, fn
        :repo1 -> "skill://acme/"
        :repo2 -> "skill://acme/more/"
      end)
      |> expect(:get_skill, fn _, _channel, :repo1 -> {:error, :not_found} end)

      state = init_suite(skills: [{SkillRepoMock, :repo1}, {SkillRepoMock, :repo2}])

      assert {:error, {:skill_not_found, "skill://acme/more/x/SKILL.md"}} =
               handle(get_skill_req("skill://acme/more/x/SKILL.md"), state)
    end

    test "answers skill not found when no repository matches" do
      stub(SkillRepoMock, :prefix, fn :repo1 -> "skill://acme/" end)
      state = init_suite(skills: [{SkillRepoMock, :repo1}])

      assert {:error, {:skill_not_found, "skill://other/x/SKILL.md"}} =
               handle(get_skill_req("skill://other/x/SKILL.md"), state)
    end

    test "answers skill not found with no skill repository" do
      assert {:error, {:skill_not_found, "skill://acme/x/SKILL.md"}} =
               handle(get_skill_req("skill://acme/x/SKILL.md"), init_suite([]))
    end

    test "skill not found is a -32602 error" do
      assert {200,
              %{
                code: -32_602,
                message: "Skill not found: skill://acme/x/SKILL.md",
                data: %{uri: "skill://acme/x/SKILL.md"}
              }} = check_error({:skill_not_found, "skill://acme/x/SKILL.md"})
    end
  end

  describe "resources/read" do
    test "serves skill files from a skill repository" do
      SkillRepoMock
      |> stub(:prefix, fn :repo1 -> "skill://acme/" end)
      |> expect(:read, fn "skill://acme/a/SKILL.md", _channel, :repo1 ->
        {:ok, MCP.read_resource_result(uri: "skill://acme/a/SKILL.md", text: "# A")}
      end)

      state = init_suite(skills: [{SkillRepoMock, :repo1}])

      assert {:result, %MCP.ReadResourceResult{contents: [%{text: "# A"}]}} =
               handle(read_resource_req("skill://acme/a/SKILL.md"), state)
    end

    test "a skill repository wins over an overlapping resource repository" do
      stub(ResourceRepoMock, :prefix, fn :res -> "skill://" end)

      SkillRepoMock
      |> stub(:prefix, fn :skills -> "skill://acme/" end)
      |> expect(:read, fn "skill://acme/a/SKILL.md", _channel, :skills ->
        {:ok, MCP.read_resource_result(uri: "skill://acme/a/SKILL.md", text: "from skills")}
      end)

      state =
        init_suite(resources: [{ResourceRepoMock, :res}], skills: [{SkillRepoMock, :skills}])

      assert {:result, %MCP.ReadResourceResult{contents: [%{text: "from skills"}]}} =
               handle(read_resource_req("skill://acme/a/SKILL.md"), state)
    end

    test "falls through to resource repositories for other URIs" do
      ResourceRepoMock
      |> stub(:prefix, fn :res -> "file:///" end)
      |> expect(:read, fn "file:///a.txt", _channel, :res ->
        {:ok, MCP.read_resource_result(uri: "file:///a.txt", text: "a")}
      end)

      stub(SkillRepoMock, :prefix, fn :skills -> "skill://acme/" end)

      state =
        init_suite(resources: [{ResourceRepoMock, :res}], skills: [{SkillRepoMock, :skills}])

      assert {:result, %MCP.ReadResourceResult{contents: [%{text: "a"}]}} =
               handle(read_resource_req("file:///a.txt"), state)
    end

    test "serves skill files from extension skill repositories" do
      SkillRepoMock
      |> stub(:prefix, fn :ext_skills -> "skill://ext/" end)
      |> expect(:read, fn "skill://ext/a/SKILL.md", _channel, :ext_skills ->
        {:ok, MCP.read_resource_result(uri: "skill://ext/a/SKILL.md", text: "ext")}
      end)

      ExtensionFullMock
      |> stub(:resources, fn _channel, :ext -> [] end)
      |> stub(:skills, fn _channel, :ext -> [{SkillRepoMock, :ext_skills}] end)

      state = init_suite(extensions: [{ExtensionFullMock, :ext}])

      assert {:result, %MCP.ReadResourceResult{contents: [%{text: "ext"}]}} =
               handle(read_resource_req("skill://ext/a/SKILL.md"), state)
    end
  end

  describe "resource listings" do
    test "a repository given only in :skills is not listed" do
      stub(SkillRepoMock, :prefix, fn :skills -> "skill://acme/" end)
      state = init_suite(skills: [{SkillRepoMock, :skills}])

      assert {:result, %MCP.ListResourcesResult{resources: []}} =
               handle(list_resources_req(), state)

      assert {:result, %MCP.ListResourceTemplatesResult{resourceTemplates: []}} =
               handle(list_resource_templates_req(), state)
    end

    test "a templated repository given only in :skills is not in resources/templates/list" do
      ResourceRepoMockTpl
      |> stub(:prefix, fn :tpl -> "file:///users/" end)
      |> stub(:template, fn :tpl -> %{uriTemplate: "file:///users/{id}", name: "User"} end)

      stub(SkillRepoMock, :prefix, fn :skills -> "skill://acme/" end)

      state =
        init_suite(resources: [{ResourceRepoMockTpl, :tpl}], skills: [{SkillRepoMock, :skills}])

      assert {:result,
              %MCP.ListResourceTemplatesResult{
                resourceTemplates: [%MCP.ResourceTemplate{uriTemplate: "file:///users/{id}"}]
              }} = handle(list_resource_templates_req(), state)
    end

    test "a repository also given in :resources is listed through its list/3" do
      SkillRepoMock
      |> stub(:prefix, fn :skills -> "skill://acme/" end)
      |> expect(:list, fn nil, _channel, :skills ->
        {[%{uri: "skill://acme/a/SKILL.md", name: "a"}], nil}
      end)

      state =
        init_suite(resources: [{SkillRepoMock, :skills}], skills: [{SkillRepoMock, :skills}])

      assert {:result, %MCP.ListResourcesResult{resources: [%{uri: "skill://acme/a/SKILL.md"}]}} =
               handle(list_resources_req(), state)
    end
  end

  describe "server/discover" do
    test "declares resources and the skills extension when only :skills is configured" do
      stub(SkillRepoMock, :prefix, fn :skills -> "skill://acme/" end)
      state = init_suite(skills: [{SkillRepoMock, :skills}])

      assert {:result, %MCP.DiscoverResult{capabilities: caps}} = handle(discover_req(), state)

      assert %MCP.ServerCapabilities{
               resources: %{},
               tools: nil,
               prompts: nil,
               extensions: %{"io.modelcontextprotocol/skills" => %{}}
             } = caps
    end

    test "declares the skills extension for an extension contributing skills" do
      ExtensionFullMock
      |> stub(:tools, fn _channel, :ext -> [] end)
      |> stub(:resources, fn _channel, :ext -> [] end)
      |> stub(:prompts, fn _channel, :ext -> [] end)
      |> stub(:skills, fn _channel, :ext -> [{SkillRepoMock, :skills}] end)

      stub(SkillRepoMock, :prefix, fn :skills -> "skill://acme/" end)

      state = init_suite(extensions: [{ExtensionFullMock, :ext}])

      assert {:result, %MCP.DiscoverResult{capabilities: caps}} = handle(discover_req(), state)

      assert %MCP.ServerCapabilities{
               resources: %{},
               extensions: %{"io.modelcontextprotocol/skills" => %{}}
             } = caps
    end

    test "does not declare the skills extension without skill repositories" do
      stub(ResourceRepoMock, :prefix, fn :res -> "file:///" end)
      state = init_suite(resources: [{ResourceRepoMock, :res}])

      assert {:result, %MCP.DiscoverResult{capabilities: caps}} = handle(discover_req(), state)
      assert %MCP.ServerCapabilities{resources: %{}, extensions: nil} = caps
    end

    test "an extension without skills/2 still works" do
      ExtensionMock
      |> stub(:tools, fn _channel, :ext -> [] end)
      |> stub(:resources, fn _channel, :ext -> [] end)
      |> stub(:prompts, fn _channel, :ext -> [] end)

      state = init_suite(extensions: [{ExtensionMock, :ext}])

      assert {:result, %MCP.DiscoverResult{capabilities: %{extensions: nil, resources: nil}}} =
               handle(discover_req(), state)

      assert {:result, %MCP.ListSkillsResult{skills: []}} = handle(list_skills_req(), state)
    end
  end
end
