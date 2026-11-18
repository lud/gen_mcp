defmodule GenMCP.Suite.SkillRepo.StaticTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Support.StaticSkills

  @tmp_dir "priv/test_skills/tmp"

  defmodule MarkdownOnly do
    use GenMCP.Suite.SkillRepo.Static,
      otp_app: :gen_mcp,
      dir: "test_skills/main",
      prefix: "skill://md/",
      extensions: [".md"]
  end

  defmodule PythonOnly do
    use GenMCP.Suite.SkillRepo.Static,
      otp_app: :gen_mcp,
      dir: "test_skills/main",
      prefix: "skill://py",
      extensions: [".py"]
  end

  defmodule SmallPages do
    use GenMCP.Suite.SkillRepo.Static,
      otp_app: :gen_mcp,
      dir: "test_skills/main",
      prefix: "skill://pages/",
      page_size: 2
  end

  defmodule Cached do
    use GenMCP.Suite.SkillRepo.Static,
      otp_app: :gen_mcp,
      dir: "test_skills/main",
      prefix: "skill://cached/"

    def cache_control(:public_arg) do
      {:public, 60_000}
    end
  end

  defp all_skills(mod) do
    {skills, nil} = mod.list_skills(nil, nil, [])
    skills
  end

  defp manifest_uris(%MCP.Skill{resources: resources}) do
    Enum.map(resources, & &1.uri)
  end

  defp read_bytes(mod, uri) do
    {:ok, %MCP.ReadResourceResult{contents: [content]}} = mod.read(uri, nil, [])

    case content do
      %MCP.TextResourceContents{text: text} -> text
      %MCP.BlobResourceContents{blob: blob} -> Base.decode64!(blob)
    end
  end

  defp compile_repo(module, dir, extra_opts \\ []) do
    opts = Keyword.merge([otp_app: :gen_mcp, dir: dir, prefix: "skill://tmp/"], extra_opts)

    [{mod, _}] =
      Code.compile_string("""
      defmodule #{inspect(module)} do
        use GenMCP.Suite.SkillRepo.Static, #{inspect(opts)}

        @external_resources_for_test Module.get_attribute(__MODULE__, :external_resource)
        def external_resources_for_test, do: @external_resources_for_test
      end
      """)

    mod
  end

  describe "skill discovery" do
    test "skills are the direct subdirectories with a SKILL.md, served under their name" do
      assert [
               "skill://test/alpha/SKILL.md",
               "skill://test/beta/SKILL.md",
               "skill://test/gamma/SKILL.md"
             ] == Enum.map(all_skills(StaticSkills), & &1.uri)
    end

    test "a deeper SKILL.md is a companion file of its skill" do
      [alpha | _] = all_skills(StaticSkills)

      assert [
               "skill://test/alpha/SKILL.md",
               "skill://test/alpha/assets/logo.bin",
               "skill://test/alpha/nested/SKILL.md",
               "skill://test/alpha/scripts/run.py"
             ] == Enum.sort(manifest_uris(alpha))

      assert {:error, :not_found} =
               StaticSkills.get_skill("skill://test/alpha/nested/SKILL.md", nil, [])

      assert {:error, :not_found} =
               StaticSkills.get_skill("skill://test/nested-inner/SKILL.md", nil, [])
    end

    test "directories without a SKILL.md and files at the top of dir are not served" do
      for uri <- [
            "skill://test/no-skill/README.md",
            "skill://test/top-level.md",
            "skill://test/no-skill/SKILL.md"
          ] do
        assert {:error, :not_found} = StaticSkills.read(uri, nil, [])
      end
    end

    test "the frontmatter passes through verbatim" do
      assert {:ok, %MCP.Skill{frontmatter: frontmatter}} =
               StaticSkills.get_skill("skill://test/beta/SKILL.md", nil, [])

      assert %{
               "name" => "beta",
               "description" => "Beta: frontmatter passes through",
               "license" => nil,
               "allowed-tools" => ["Read", "Grep"],
               "metadata" => %{"owner" => %{"team" => "docs", "oncall" => nil}, "version" => 2},
               "1" => "one"
             } == frontmatter
    end

    test "a prefix without a trailing slash gets one, for skill URIs and routing" do
      assert ["skill://py/alpha/SKILL.md" | _] = Enum.map(all_skills(PythonOnly), & &1.uri)
      assert "skill://py/" == PythonOnly.prefix([])
    end
  end

  describe "manifests and reads" do
    test "digests and sizes match the bytes resources/read returns" do
      for skill <- all_skills(StaticSkills), resource <- skill.resources do
        bytes = read_bytes(StaticSkills, resource.uri)

        assert resource.size == byte_size(bytes)

        assert resource.digest ==
                 "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
      end
    end

    test "the bytes served are the files on disk" do
      assert File.read!("priv/test_skills/main/alpha-dir/assets/logo.bin") ==
               read_bytes(StaticSkills, "skill://test/alpha/assets/logo.bin")
    end

    test "UTF-8 files are served as text and others as blob, with a MIME type" do
      assert {:ok,
              %MCP.ReadResourceResult{
                contents: [
                  %MCP.TextResourceContents{
                    uri: "skill://test/alpha/SKILL.md",
                    mimeType: "text/markdown"
                  }
                ]
              }} = StaticSkills.read("skill://test/alpha/SKILL.md", nil, [])

      assert {:ok,
              %MCP.ReadResourceResult{
                contents: [
                  %MCP.BlobResourceContents{
                    uri: "skill://test/alpha/assets/logo.bin",
                    mimeType: "application/octet-stream"
                  }
                ]
              }} = StaticSkills.read("skill://test/alpha/assets/logo.bin", nil, [])
    end

    test "files excluded by :extensions are neither in the manifest nor readable" do
      [alpha | _] = all_skills(MarkdownOnly)

      assert ["skill://md/alpha/SKILL.md", "skill://md/alpha/nested/SKILL.md"] ==
               Enum.sort(manifest_uris(alpha))

      assert {:error, :not_found} = MarkdownOnly.read("skill://md/alpha/scripts/run.py", nil, [])
      assert {:error, :not_found} = MarkdownOnly.read("skill://md/alpha/assets/logo.bin", nil, [])
    end

    test "the root SKILL.md is always kept" do
      [alpha | _] = all_skills(PythonOnly)

      assert ["skill://py/alpha/SKILL.md", "skill://py/alpha/scripts/run.py"] ==
               Enum.sort(manifest_uris(alpha))
    end

    test "results carry the no-cache default without cache_control/1" do
      assert {:ok, %MCP.ReadResourceResult{cacheScope: :private, ttlMs: 0}} =
               StaticSkills.read("skill://test/alpha/SKILL.md", nil, [])
    end

    test "read results carry the module's cache_control/1" do
      assert {:ok, %MCP.ReadResourceResult{cacheScope: :public, ttlMs: 60_000}} =
               Cached.read("skill://cached/alpha/SKILL.md", nil, :public_arg)
    end
  end

  describe "repository callbacks" do
    test "prefix/1 is the :prefix option" do
      assert "skill://test/" == StaticSkills.prefix([])
    end

    test "list/3 lists no resources" do
      assert {[], nil} == StaticSkills.list(nil, nil, [])
    end

    test "list_skills/3 pages by :page_size" do
      assert {[%{uri: "skill://pages/alpha/SKILL.md"}, %{uri: "skill://pages/beta/SKILL.md"}],
              cursor} = SmallPages.list_skills(nil, nil, [])

      assert cursor != nil

      assert {[%{uri: "skill://pages/gamma/SKILL.md"}], nil} =
               SmallPages.list_skills(cursor, nil, [])
    end

    test "get_skill/3 answers known and unknown URIs" do
      assert {:ok, %MCP.Skill{uri: "skill://test/gamma/SKILL.md"}} =
               StaticSkills.get_skill("skill://test/gamma/SKILL.md", nil, [])

      assert {:error, :not_found} = StaticSkills.get_skill("skill://test/delta/SKILL.md", nil, [])
    end
  end

  describe "compilation" do
    test "a SKILL.md without a description fails compilation" do
      assert_raise ArgumentError, ~r/"description"/, fn ->
        compile_repo(__MODULE__.MissingDescription, "test_skills/missing_description")
      end
    end

    test "a SKILL.md without frontmatter fails compilation" do
      assert_raise ArgumentError, ~r/missing YAML frontmatter/, fn ->
        compile_repo(__MODULE__.NoFrontmatter, "test_skills/no_frontmatter")
      end
    end

    test "two directories declaring the same name fail compilation" do
      assert_raise ArgumentError, ~r/skill:\/\/tmp\/same\/SKILL.md/, fn ->
        compile_repo(__MODULE__.DuplicateNames, "test_skills/duplicate_names")
      end
    end

    test "extensions must start with a dot" do
      assert_raise ArgumentError, ~r/must start with a dot, got: "md"/, fn ->
        compile_repo(__MODULE__.NoDot, "test_skills/main", extensions: ["md"])
      end
    end

    test ":otp_app must be the application being compiled" do
      assert_raise ArgumentError,
                   ~r/priv directory of :gen_mcp, but :otp_app is :other_app/,
                   fn ->
                     compile_repo(__MODULE__.OtherApp, "test_skills/main", otp_app: :other_app)
                   end
    end

    test "a name breaking the naming rules warns and is still served" do
      stderr =
        capture_io(:stderr, fn ->
          mod = compile_repo(__MODULE__.BadName, "test_skills/bad_name")
          send(self(), {:compiled, mod})
        end)

      assert stderr =~ ~s("Bad_Name")
      assert stderr =~ "naming rules"

      assert_received {:compiled, mod}
      assert {:ok, %MCP.Skill{}} = mod.get_skill("skill://tmp/Bad_Name/SKILL.md", nil, [])
    end
  end

  describe "recompilation" do
    setup do
      File.rm_rf!(@tmp_dir)
      File.mkdir_p!(@tmp_dir)
      File.cp_r!("priv/test_skills/main", Path.join(@tmp_dir, "skills"))
      on_exit(fn -> File.rm_rf!(@tmp_dir) end)
      :ok
    end

    test "every served file is an external resource" do
      mod = compile_repo(__MODULE__.ExternalResources, "test_skills/tmp/skills")

      assert Enum.sort([
               Path.expand("priv/test_skills/tmp/skills/alpha-dir/SKILL.md"),
               Path.expand("priv/test_skills/tmp/skills/alpha-dir/assets/logo.bin"),
               Path.expand("priv/test_skills/tmp/skills/alpha-dir/nested/SKILL.md"),
               Path.expand("priv/test_skills/tmp/skills/alpha-dir/scripts/run.py"),
               Path.expand("priv/test_skills/tmp/skills/beta/SKILL.md"),
               Path.expand("priv/test_skills/tmp/skills/gamma/SKILL.md")
             ]) == Enum.sort(mod.external_resources_for_test())
    end

    test "adding a file requires recompilation" do
      mod = compile_repo(__MODULE__.AddFile, "test_skills/tmp/skills")
      refute mod.__mix_recompile__?()

      File.write!(Path.join(@tmp_dir, "skills/gamma/notes.md"), "notes")
      assert mod.__mix_recompile__?()
    end

    test "adding a skill requires recompilation" do
      mod = compile_repo(__MODULE__.AddSkill, "test_skills/tmp/skills")

      File.mkdir_p!(Path.join(@tmp_dir, "skills/delta"))

      File.write!(
        Path.join(@tmp_dir, "skills/delta/SKILL.md"),
        "---\nname: delta\ndescription: Delta.\n---\n"
      )

      assert mod.__mix_recompile__?()
    end

    test "symlinked directories are not followed" do
      File.ln_s!("..", Path.join(@tmp_dir, "skills/gamma/loop"))
      mod = compile_repo(__MODULE__.SymlinkLoop, "test_skills/tmp/skills")

      assert {:ok, %MCP.Skill{resources: [%{uri: "skill://tmp/gamma/SKILL.md"}]}} =
               mod.get_skill("skill://tmp/gamma/SKILL.md", nil, [])
    end

    test "removing a file requires recompilation" do
      mod = compile_repo(__MODULE__.RemoveFile, "test_skills/tmp/skills")
      File.rm!(Path.join(@tmp_dir, "skills/alpha-dir/scripts/run.py"))
      assert mod.__mix_recompile__?()
    end
  end
end
