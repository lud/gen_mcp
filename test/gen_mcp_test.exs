defmodule GenMcpTest do
  use ExUnit.Case
  doctest GenMcp

  test "greets the world" do
    assert GenMcp.hello() == :world
  end
end
