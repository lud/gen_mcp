defmodule GenMcp.McpComplianceTest do
  use ExUnit.Case, async: true

  @tag :skip
  test "run the mcp-validator test suite" do
    {output, _} = System.cmd("bash", ["test/support/mcp-validator.sh"], stderr_to_stdout: true)
    IO.puts(output)
    [_, report_path] = Regex.run(~r{Compliance report generated: ([^\s]+)}, output)
    report = File.read!(report_path)

    IO.puts(report)
    assert report =~ "- Failed: 0"
  end
end
