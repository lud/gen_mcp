defmodule GenMCP.TestOrderedCLIFormatter do
  use GenServer

  @impl true
  def init(opts) do
    {:ok, cli_formatter} = GenServer.start_link(ExUnit.CLIFormatter, opts)
    {:ok, %{cli_formatter: cli_formatter, delayed_events: []}}
  end

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{state: {:failed, _}}} = event, state) do
    {:noreply, delay(event, state)}
  end

  def handle_cast({:module_finished, %ExUnit.TestModule{state: {:failed, _}}} = event, state) do
    {:noreply, delay(event, state)}
  end

  def handle_cast({:suite_finished, _} = event, state) do
    state = flush_delayed(state)
    GenServer.cast(state.cli_formatter, event)
    {:noreply, state}
  end

  def handle_cast({:sigquit, _} = event, state) do
    state = flush_delayed(state)
    GenServer.cast(state.cli_formatter, event)
    {:noreply, state}
  end

  def handle_cast(:max_failures_reached = event, state) do
    state = flush_delayed(state)
    GenServer.cast(state.cli_formatter, event)
    {:noreply, state}
  end

  def handle_cast(event, state) do
    GenServer.cast(state.cli_formatter, event)
    {:noreply, state}
  end

  defp delay(event, state) do
    update_in(state.delayed_events, &[event | &1])
  end

  defp flush_delayed(%{delayed_events: []} = state) do
    state
  end

  defp flush_delayed(state) do
    Enum.each(Enum.reverse(state.delayed_events), &GenServer.cast(state.cli_formatter, &1))
    %{state | delayed_events: []}
  end
end
