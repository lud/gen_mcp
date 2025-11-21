# Getting Started

`GenMCP` provides a complete framework for building [Model Context Protocol (MCP)](https://modelcontextprotocol.io) servers in Elixir.

It includes:
- A robust protocol implementation (`GenMCP`).
- A high-level suite for managing tools, resources, and prompts (`GenMCP.Suite`).
- A transport plug with Server-Sent Events (SSE) support (`GenMCP.Transport.StreamableHTTP`).

## Installation

Add `gen_mcp` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:gen_mcp, "~> 0.2.0"}
  ]
end
```

## Quick Start

The easiest way to start an MCP server is to use `GenMCP.Suite` with the `GenMCP.Transport.StreamableHTTP` plug.

### 1. Define your Tools

Create a module that implements the `GenMCP.Suite.Tool` behaviour.

```elixir
defmodule MyApp.Tools.Calculator do
  use GenMCP.Suite.Tool

  @impl true
  def info(:name, _arg), do: "add"
  def info(:description, _arg), do: "Adds two numbers"

  @impl true
  def input_schema(_arg) do
    %{
      type: "object",
      properties: %{
        a: %{type: "number"},
        b: %{type: "number"}
      },
      required: ["a", "b"]
    }
  end

  @impl true
  def call(_request, %{"a" => a, "b" => b}, _channel) do
    result = GenMCP.MCP.call_tool_result(text: "#{a + b}")
    {:result, result}
  end
end
```

### 2. Mount the Server in your Router

Add the `GenMCP.Transport.StreamableHTTP` plug to your Phoenix or Plug router. You configure the server details and register your tools here.

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/mcp" do
    pipe_through :api

    forward "/", GenMCP.Transport.StreamableHTTP,
      server_name: "My Calculator Server",
      server_version: "1.0.0",
      tools: [MyApp.Tools.Calculator]
  end
end
```

Your MCP server is now available at `/mcp`!

## Next Steps

- Explore `GenMCP.Suite.Tool` to learn more about building tools, including asynchronous ones.
- Check out `GenMCP.Suite.ResourceRepo` to expose data as resources.
- Use `GenMCP.Suite.PromptRepo` to provide reusable prompts.
- Learn about `GenMCP.Suite.Extension` to compose functionality from multiple modules.

> [!NOTE]
> While you can implement the `GenMCP` behaviour directly for low-level control, `GenMCP.Suite` is designed to handle most use cases with less boilerplate.
