defmodule GenMCP.Suite.SubscriptionHandlerTest do
  use ExUnit.Case, async: true

  alias GenMCP.Suite.SubscriptionHandler
  alias GenMCP.Support.SubscriptionHandlerMock

  describe "expand/1" do
    test "expands a module atom (arg defaults to [])" do
      assert %{mod: SubscriptionHandlerMock, arg: []} =
               SubscriptionHandler.expand(SubscriptionHandlerMock)
    end

    test "expands a {module, arg} tuple" do
      assert %{mod: SubscriptionHandlerMock, arg: :custom} =
               SubscriptionHandler.expand({SubscriptionHandlerMock, :custom})
    end

    test "returns an already-expanded descriptor unchanged" do
      descriptor = %{mod: SubscriptionHandlerMock, arg: :test}
      assert ^descriptor = SubscriptionHandler.expand(descriptor)
    end
  end
end
