defmodule GenMCP.MixProject do
  use Mix.Project

  @source_url "https://github.com/lud/gen_mcp"
  @version "0.5.0"
  def project do
    [
      app: :gen_mcp,
      version: @version,
      description:
        "A generic MCP server behaviour for the latest protocol version with a " <>
          "suite of components to build tools, resources and prompts.",
      elixir: "~> 1.18",
      start_permanent: true,
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() == :prod,
      source_url: @source_url,
      deps: deps(),
      dialyzer: dialyzer(),
      aliases: aliases(),
      modkit: modkit(),
      package: package(),
      docs: docs(),
      versioning: versioning(),
      test_coverage: test_coverage()
    ]
  end

  defp elixirc_paths(:prod) do
    ["lib"]
  end

  defp elixirc_paths(_) do
    ["lib", "test/support"]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {GenMCP.Application, []}
    ]
  end

  defp deps do
    [
      # App
      {:phoenix, ">= 1.7.0"},
      {:jsv, "~> 0.15.1"},
      {:abnf_parsec, "~> 2.0"},
      {:texture, ">= 0.3.2"},
      {:nimble_options, "~> 1.1"},
      {:telemetry, ">= 0.0.0"},

      # Resources
      mcp_schemas(),

      # Dev
      {:req, "~> 0.5", only: [:dev, :test]},
      {:local_cluster, "~> 2.0", only: [:test]},
      {:bandit, "~> 1.0", only: [:dev, :test]},
      {:jason, "~> 1.0", only: [:dev, :test]},
      {:mox, "~> 1.2", only: [:dev, :test]},
      {:credo, ">= 1.7.12", only: [:dev, :test], runtime: false},
      {:dialyxir, ">= 1.4.5", only: [:dev, :test], runtime: false},
      {:doctor, ">= 0.22.0", only: [:dev, :test], runtime: false},
      {:ex_check, ">= 0.16.0", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.38.2", only: [:dev, :test], runtime: false},
      {:mix_audit, ">= 2.1.5", only: [:dev, :test], runtime: false},
      {:sobelow, ">= 0.14.0", only: [:dev, :test], runtime: false},
      {:nvir, "~> 0.15.0", only: [:dev, :test]},
      {:readmix, "~> 0.7", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.11", only: [:dev, :test], runtime: false}
    ]
  end

  defp mcp_schemas do
    {:modelcontextprotocol,
     git: "https://github.com/modelcontextprotocol/modelcontextprotocol.git",
     sparse: "schema/2025-06-18",
     ref: "2025-06-18",
     only: [:dev, :test],
     compile: false,
     runtime: false,
     app: false}
  end

  defp aliases do
    [
      test: "test --no-start"
    ]
  end

  defp modkit do
    [
      mount: [
        {GenMCP.TestWeb, "test/support/test_web", flavor: :phoenix},
        {GenMCP.Test, "test/support"},
        {GenMCP.MCP, :ignore},
        {GenMCP.Support, "test/support"},
        {GenMCP.ConnCase, "test/support/conn_case"},
        {GenMCP, "lib/gen_mcp"},
        {Mix.Tasks, "lib/mix/tasks", flavor: :mix_task},
        {Plug, "test/support/test_web/plug"}
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "Changelog" => "https://github.com/lud/gen_mcp/blob/main/CHANGELOG.md",
        "Github" => @source_url
      }
    ]
  end

  def cli do
    [
      preferred_envs: [
        dialyzer: :test
      ]
    ]
  end

  defp dialyzer do
    [
      flags: [:unmatched_returns, :error_handling, :unknown, :extra_return],
      list_unused_filters: true,
      plt_add_deps: :app_tree,
      plt_add_apps: [:ex_unit],
      plt_local_path: "_build/plts"
    ]
  end

  defp docs do
    [
      main: "GenMCP",
      extra_section: "GUIDES",
      nest_modules_by_prefix: [GenMCP.MCP],
      groups_for_modules: [
        Core: [
          GenMCP,
          GenMCP.MCP,
          GenMCP.Transport.StreamableHTTP
        ],
        Suite: [
          GenMCP.Suite,
          GenMCP.Suite.Tool,
          GenMCP.Suite.PromptRepo,
          GenMCP.Suite.ResourceRepo,
          GenMCP.Suite.Extension,
          GenMCP.Suite.SessionController,
          GenMCP.Suite.PersistedClientInfo,
          ~r{^GenMCP\.Suite\.SessionController\..*}
        ],
        Sessions: [
          ~r/GenMCP\.Mux\..*/
        ],
        Utilities: [
          GenMCP.RpcError,
          GenMCP.TelemetryLogger
        ],
        Protocol: [
          ~r/GenMCP\.MCP\..*/
        ],
        # Should not be displayed in hexdocs
        Dev: [
          ~r/GenMCP\.Test/
        ]
      ],
      extras: doc_extras(),
      groups_for_extras: groups_for_extras(),
      before_closing_body_tag: fn
        :html ->
          """
          <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
          <script>mermaid.initialize({startOnLoad: true, theme: 'neutral'})</script>
          """

        _ ->
          ""
      end
    ]
  end

  def doc_extras do
    existing_guides = Path.wildcard("guides/**/*.md")

    defined_guides = [
      "CHANGELOG.md",
      "guides/001.getting-started.md",
      "guides/002.using-mcp-suite.md",
      "guides/009.system-configuration.md"
    ]

    case existing_guides -- defined_guides do
      [] ->
        :ok
        defined_guides

      missed ->
        IO.warn("""

        unreferenced guides

        #{Enum.map(missed, &[inspect(&1), ",\n"])}


        """)

        defined_guides ++ missed
    end
  end

  defp groups_for_extras do
    [
      Introduction: ~r{guides/.+}
    ]
  end

  defp test_coverage do
    [
      ignore_modules: [
        ~r{^Jason\.Encoder\.GenMCP\.MCP\.},
        ~r{^JSON\.Encoder\.GenMCP\.MCP\.},
        ~r{^JSV\.Normalizer\.Normalize\.GenMCP\.MCP\.},
        ~r{^GenMCP\.MCP\.}
      ]
    ]
  end

  defp versioning do
    [
      annotate: true,
      before_commit: [
        &readmix/1,
        {:add, "README.md"},
        {:add, "guides"},
        &gen_changelog/1,
        {:add, "CHANGELOG.md"}
      ]
    ]
  end

  def readmix(vsn) do
    rdmx = Readmix.new(vars: %{app_vsn: vsn})
    :ok = Readmix.update_file(rdmx, "README.md")

    :ok =
      Enum.each(Path.wildcard("guides/**/*.md"), fn path ->
        :ok = Readmix.update_file(rdmx, path)
      end)
  end

  defp gen_changelog(vsn) do
    case System.cmd("git", ["cliff", "--tag", vsn, "-o", "CHANGELOG.md"], stderr_to_stdout: true) do
      {_, 0} -> IO.puts("Updated CHANGELOG.md with #{vsn}")
      {out, _} -> {:error, "Could not update CHANGELOG.md:\n\n #{out}"}
    end
  end
end
