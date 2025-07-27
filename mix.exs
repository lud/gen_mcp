defmodule GenMcp.MixProject do
  use Mix.Project

  def project do
    [
      app: :gen_mcp,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: true,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      modkit: modkit()
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
      {:jsv, path: "../jsv"},
      {:abnf_parsec, "~> 2.0"},

      # Test
      {:req, "~> 0.5", only: :test},
      {:local_cluster, "~> 2.0", only: [:test]},
      {:bandit, "~> 1.0", only: [:dev, :test]},
      {:jason, "~> 1.0", only: [:dev, :test]},
      mcp_validator(),
      mcp_schemas()
    ]
  end

  defp mcp_validator do
    {:mcp_validator,
     git: "https://github.com/Janix-ai/mcp-validator.git",
     ref: "v0.3.1",
     only: [:dev, :test],
     compile: false,
     app: false}
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
end
