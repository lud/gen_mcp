defmodule GenMcp.MixProject do
  use Mix.Project

  def project do
    [
      app: :gen_mcp,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: true,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {GenMcp.Application, []}
    ]
  end

  defp deps do
    []
  end
end
