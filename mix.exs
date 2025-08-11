defmodule GenMcp.MixProject do
  use Mix.Project

@source_url "https://github.com/lud/gen_mcp"
@version "0.1.0"
  def project do
    [
      app: :gen_mcp,
      version: @version,
      description: "A generic MCP server behaviour, plus predefined server implementations and plugs to get started immediately.",
      elixir: "~> 1.18",
      start_permanent: true,
      elixirc_paths: elixirc_paths(Mix.env()),
      source_url: @source_url,
      deps: deps(),
      aliases: aliases(),
      modkit: modkit(),
      package: package(),
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
      mod: {GenMcp.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix, ">= 1.7.0"},
      {:jsv, "~> 0.10.1"},
      {:abnf_parsec, "~> 2.0"},

      # Test
      {:req, "~> 0.5", only: :test},
      {:local_cluster, "~> 2.0", only: [:test]},
      {:bandit, "~> 1.0", only: [:dev, :test]},
      {:jason, "~> 1.0", only: [:dev, :test]},
      {:libdev, "~> 0.1.2", only: [:dev, :test]},
      mcp_schemas()
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
        {GenMcp.TestWeb, "test/support/test_web", flavor: :phoenix},
        {GenMcp.Test, "test/support"},
        {GenMcp.ConnCase, "test/support/conn_case"},
        {GenMcp, "lib/gen_mcp"},
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
        "Changelog" => "https://github.com/lud/gen_mcl/blob/main/CHANGELOG.md"
      }
    ]
  end
end
