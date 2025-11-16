# GenMCP

MCP server building blocks for Elixir.

This library packs two main features:

* `GenMCP` itself - a low level behaviour to implement your own MCP server
  logic.
* `GenMCP.Suite` - a high level suite of components to build tools, resources
  and prompts with the default server `GenMCP` implementation.

## Installation

The usual tuple for mix.exs!

```elixir
def deps do
  [
    {:gen_mcp, "~> 0.1.0"}
  ]
end
```

## Documentation

On [hexdocs.pm](https://hexdocs.pm/gen_mcp).

## Supported Features

* Streamable http transport
* Session initialization with distributed Erlang supprt
* Tool calling with support for concurrency execution (`Task` or custom
  processes)
* Tools listing (no pagination)
* Resources (with pagination)
* Prompts (with pagination)

## Roadmap

* Server requests (elicitation, sampling and roots)
* Stdio transport and burrito wrapping tools
* Messages resumability
* Resources subscription