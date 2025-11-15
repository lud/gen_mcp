defmodule GenMCP.MixProject do
  use Mix.Project

  @source_url "https://github.com/lud/gen_mcp"
  @version "0.1.0"
  def project do
    [
      app: :gen_mcp,
      version: @version,
      description:
        "A generic MCP server behaviour, plus predefined server implementations and plugs to get started immediately.",
      elixir: "~> 1.18",
      start_permanent: true,
      elixirc_paths: elixirc_paths(Mix.env()),
      source_url: @source_url,
      deps: deps(),
      dialyzer: dialyzer(),
      aliases: aliases(),
      modkit: modkit(),
      package: package()
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
      # {:texture, ">= 0.3.0"},
      {:texture, path: "../texture", override: true},

      # Resources
      mcp_schemas(),

      # Test
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
      {:sobelow, ">= 0.14.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp mcp_schemas do
    {:modelcontextprotocol,
     git: "https://github.com/modelcontextprotocol/modelcontextprotocol.git",
     sparse: "schema/2025-06-18",
     ref: "2025-06-18",
     only: [:dev, :test],
     compile: false,
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
        "Github" => @source_url,
        "Changelog" => "https://github.com/lud/gen_mcp/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp dialyzer do
    [
      flags: [:unmatched_returns, :error_handling, :unknown, :extra_return],
      list_unused_filters: true,
      plt_local_path: "_build/plts"
    ]
  end
end
