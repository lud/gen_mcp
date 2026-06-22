# GenMCP

<!-- rdmx :badges
    hexpm         : "gen_mcp?color=4e2a8e"
    github_action : "lud/gen_mcp/elixir.yaml?label=CI&branch=main"
    license       : gen_mcp
    -->
[![hex.pm Version](https://img.shields.io/hexpm/v/gen_mcp?color=4e2a8e)](https://hex.pm/packages/gen_mcp)
[![Build Status](https://img.shields.io/github/actions/workflow/status/lud/gen_mcp/elixir.yaml?label=CI&branch=main)](https://github.com/lud/gen_mcp/actions/workflows/elixir.yaml?query=branch%3Amain)
[![License](https://img.shields.io/hexpm/l/gen_mcp.svg)](https://hex.pm/packages/gen_mcp)
<!-- rdmx /:badges -->


MCP server building blocks for Elixir.

This library packs two main features:

* `GenMCP` itself - a low level behaviour to implement your own MCP server
  logic.
* `GenMCP.Suite` - a high level suite of components to build tools, resources
  and prompts with the default server implementation.

## Installation

The usual tuple for mix.exs!

<!-- rdmx :app_dep vsn:$app_vsn -->
```elixir
def deps do
  [
    {:gen_mcp, "~> 0.10"},
  ]
end
```
<!-- rdmx /:app_dep -->

## Documentation

On [hexdocs.pm](https://hexdocs.pm/gen_mcp).

## Example

A small memory server: a tool that saves a memory, and a resource repository
that lists the memories and serves each one by id from a URI template. Both keep
the real work in a plain `MyApp.Memory` module and stay thin adapters.

A tool is an operation a client invokes. This one validates its arguments against
the `:input_schema`, saves a memory, and returns its id:

<!-- rdmx :section name:create_post_tool format:true -->
```elixir
defmodule MyApp.Tools.CreateMemory do
  use GenMCP.Suite.Tool,
    name: "create_memory",
    description: "Saves a memory and returns its id.",
    input_schema: %{
      type: :object,
      properties: %{
        title: %{type: :string},
        content: %{type: :string}
      },
      required: [:title, :content]
    }

  alias GenMCP.MCP.V2607, as: MCP

  @impl true
  def call(request, _channel, _arg) do
    %{"title" => title, "content" => content} = request.params.arguments
    {:ok, memory} = MyApp.Memory.create(title, content)
    {:result, MCP.call_tool_result(text: "Saved memory #{memory.id}")}
  end
end
```
<!-- rdmx /:section -->

A resource is addressable content a client reads. A `:uriTemplate` lets one
repository serve a whole family of URIs: `list/3` advertises the memories that
exist, and a `resources/read` for a matching URI is parsed into the template
variables, so `read/3` receives `%{"id" => id}`:

<!-- rdmx :section name:posts_resource format:true -->
```elixir
defmodule MyApp.Resources.Memories do
  @behaviour GenMCP.Suite.ResourceRepo

  alias GenMCP.MCP.V2607, as: MCP

  @impl true
  def prefix(_arg), do: "memory:///"

  @impl true
  def template(_arg) do
    %{uriTemplate: "memory:///{id}", name: "Memory"}
  end

  @impl true
  def list(_cursor, _channel, _arg) do
    memories =
      for memory <- MyApp.Memory.list() do
        %{uri: "memory:///#{memory.id}", name: memory.title, mimeType: "text/markdown"}
      end

    {memories, _cursor = nil}
  end

  @impl true
  def read(%{"id" => id}, _channel, _arg) do
    case MyApp.Memory.fetch(id) do
      {:ok, memory} ->
        {:ok,
         MCP.read_resource_result(
           uri: "memory:///#{id}",
           text: memory.content,
           mime_type: "text/markdown"
         )}

      :error ->
        {:error, :not_found}
    end
  end
end
```
<!-- rdmx /:section -->

Mount the server in your router. The transport serves a `GenMCP.Suite` out of
the box, so you list the providers right in the plug options:

<!-- rdmx :section name:blog_router format:true -->
```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  scope "/mcp" do
    forward "/", GenMCP.Transport.StreamableHTTP,
      server_name: "My Memory Server",
      server_version: "1.0.0",
      tools: [MyApp.Tools.CreateMemory],
      resources: [MyApp.Resources.Memories]
  end
end
```
<!-- rdmx /:section -->
