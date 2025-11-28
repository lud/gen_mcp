defmodule GenMCP.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def env do
    Process.get(:never_defined, unquote(Mix.env()))
  end

  @impl true
  def start(_type, _args) do
    children = children(env())
    opts = [strategy: :one_for_one, name: GenMCP.Supervisor]

    Supervisor.start_link(children, opts)
  end

  defp children(:prod) do
    [
      GenMCP.Cluster,
      {Registry, name: GenMCP.Mux.registry(), keys: :unique},
      GenMCP.Mux.SessionSupervisor
    ]
  end

  if Mix.env() != :prod do
    defp children(_) do
      :ok =
        GenMCP.attach_default_logger([
          # min_log_level: :error,
          # prefixes: [
          #   [:gen_mcp, :session],
          #   [:gen_mcp, :suite]
          # ]
        ])

      children(:prod) ++
        [
          GenMCP.Support.Dev,
          GenMCP.TestWeb.Endpoint
        ]
    end
  end
end
