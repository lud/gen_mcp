# credo:disable-for-this-file Credo.Check.Readability.Specs
# credo:disable-for-this-file Credo.Check.Readability.ModuleDoc
defmodule Mix.Tasks.Mcp.UpdateSchema do
  @moduledoc false
  use Mix.Task

  @dep_dir "deps/modelcontextprotocol"

  @impl true
  def run(_argv) do
    IO.puts("pulling main on #{@dep_dir}")

    current_ref = current_ref()
    {_, 0} = git(~w(reset --hard HEAD))
    {_, 0} = git(~w(fetch origin main))
    {_, 0} = git(~w(checkout -B main origin/main))
    {new_ref, 0} = git(~w(rev-parse HEAD))
    new_ref = String.trim(new_ref)

    if new_ref == current_ref do
      Mix.Shell.IO.error("modelcontextprotocol already up-to-date on #{new_ref}")
      System.halt(1)
    end

    {log, 0} = git(~w(log --oneline #{current_ref}..#{new_ref}))
    IO.puts([IO.ANSI.magenta(), log, IO.ANSI.reset()])

    IO.puts("updating mix.exs")

    "mix.exs"
    |> File.read!()
    |> String.replace(~r/@schemas_ref "[^"]+"/, ~s(@schemas_ref "#{new_ref}"))
    |> then(&File.write!("mix.exs", &1))

    IO.puts("done")
  end

  defp current_ref do
    Mix.Project.config()
    |> Keyword.fetch!(:deps)
    |> List.keyfind!(:modelcontextprotocol, 0)
    |> elem(1)
    |> Keyword.fetch!(:ref)
  end

  defp git(argv) do
    System.cmd("git", argv, cd: @dep_dir)
  end
end
