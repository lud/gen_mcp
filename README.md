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
    {:gen_mcp, "~> 0.4"},
  ]
end
```
<!-- rdmx /:app_dep -->

## Documentation

On [hexdocs.pm](https://hexdocs.pm/gen_mcp).

## Supported Features

* Streamable http transport
* Session initialization with distributed Erlang supprt
* Tool calling with support for concurrency execution (Task or custom
  processes)
* Tools listing (no pagination)
* Resources (with pagination)
* Prompts (with pagination)
* Session storage and restoration

## Roadmap

* Server requests (elicitation, sampling and roots)
* Stdio transport and burrito wrapping tools
* Messages resumability
* Resources subscription
