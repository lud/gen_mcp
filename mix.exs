defmodule GenMCP.MixProject do
  use Mix.Project

  @source_url "https://github.com/lud/gen_mcp"
  @version "0.2.0"
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
      source_url: @source_url,
      deps: deps(),
      dialyzer: dialyzer(),
      aliases: aliases(),
      modkit: modkit(),
      package: package(),
      docs: docs()
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
      {:jsv, "~> 0.11"},
      {:abnf_parsec, "~> 2.0"},
      {:texture, ">= 0.3.2"},
      {:nimble_options, "~> 1.1"},

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
      {:nvir, "~> 0.13.4", only: [:dev, :test]},
      {:readmix, "~> 0.6", only: [:dev, :test], runtime: false},
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
          GenMCP.Suite.Extension
        ],
        Sessions: [
          ~r/GenMCP\.Mux\..*/
        ],
        Utilities: [
          GenMCP.RpcError
        ],
        Protocol: [
          ~r/GenMCP\.MCP\..*/
        ],
        # Should not be displayed in hexdocs
        Dev: [
          ~r/GenMCP\.Test/
        ]
      ],
      extras: [
        "guides/getting_started.md"
      ]
    ]
  end
end
