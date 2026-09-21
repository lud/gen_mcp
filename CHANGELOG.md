# Changelog

All notable changes to this project will be documented in this file.

## [2.1.0] - 2026-09-21

### 🚀 Features

- Serve resources/* on the 2025 compatibility transport (#79) (_James Tippett_)

### 🐛 Bug Fixes

- Return HTTP 200 for unimplmented methods in 2025 support (_lud_)
- Send invalid RPC correct error code on RPC 1.0 messages (_lud_)
- Fix MRTR resultType spelling: input_required, not input-required (#80) (_James Tippett_)
- Fixed inspect print limit on codegen (_Ludovic Dem_)
- Show summary of JSON schema errors in JSONRPC error messages (_lud_)

### 📚 Documentation

- Do not use specific environment for docs (_lud_)

### 🧪 Testing

- Test 2025 compat resource page tokens (_lud_)
- Test full round trip of MRTR with Suite (_lud_)

### ⚙️ Miscellaneous Tasks

- Derive RPC error codes from MCP vendored JSON schema (_lud_)
- Limit justfile verbosity on mix.deps (_lud_)

## [2.0.0] - 2026-07-30

Implements the MCP `2026-07-28` protocol with a stateless transport.

`GenMCP.Transport.StreamableHTTP` now targets the `2026-07-28` protocol. There
is no session process, no `Mcp-Session-Id` header and no cluster
configuration. Each request is handled by its own worker process, spawned when
the request arrives and stopped once the request is answered.

Clients using the `2025-06-18` and `2025-11-25` protocols are handled by a
separate plug, `GenMCP.Transport.StreamableHTTP.V2511`, mounted on the route
those clients already call. Their requests and responses are unchanged, so
clients can be migrated one at a time.

Upgrade guide:
<https://gen-mcp.hexdocs.pm/090-upgrading-to-v2.html>

**Can I upgrade?**

* **Your clients need no changes.** Keep them on their current route and mount
  the 2025 plug there.
* **The 2025 plug handles tool calls.** It implements `initialize`,
  `notifications/initialized`, `ping`, `logging/setLevel`, `tools/list`,
  `tools/call` and the `GET` notification stream. Any other method returns a
  JSON-RPC `-32601`. Check this first if your 2025 clients read resources or
  prompts.
* **You still need Phoenix.** Both plugs read the encryption key from the
  `Phoenix.Endpoint` on the conn, and `:phoenix` remains a regular dependency.
  A plain `Plug.Router` mount raises on the first request that mints a token:
  a 2025 session id, a pagination cursor, or the `requestState` of an
  `input-required` result.
* **Your tool modules need edits.** The entity namespace, the `call/3` return
  tuples and the async API all changed. Two of the three changes only produce a
  compiler warning and fail at the first tool call, so compile the upgrade with
  `mix compile --warnings-as-errors` and read the guide.
* **Browser clients need an origin allowlist.** `:allowed_origins` defaults to
  `[]` and rejects unlisted origins with `403`. Requests with no `Origin`
  header are always accepted, so a test suite passes either way.

**What's new**

* Tools can block. Each request has its own worker process, so slow work runs
  inline in `c:GenMCP.Suite.Tool.call/3`. The `{:async, {tag, task}, channel}`
  return and the `continue/3` callback are removed. Tools driven by messages
  from another process return `{:stream, state}` and handle each message in
  `c:GenMCP.Suite.Tool.handle_message/4`.
* DNS rebinding protection on both plugs, through the `:allowed_origins` mount
  option.
* `GenMCP.SessionController.Token`, the default session controller for the 2025
  plug, uses an encrypted session token as the session id. Nothing is stored
  server-side and a session minted on one node is readable on any node sharing
  the `secret_key_base`.
* `GenMCP.Mux.Channel.send_notification/2` replaces `send_message/2` and takes
  a notification struct or map instead of an encoded binary.
* Telemetry events follow the per-request architecture:
  `[:gen_mcp, :server, :init]`, `[:gen_mcp, :server, :start_error]`,
  `[:gen_mcp, :transport, :request_rejected]`,
  `[:gen_mcp, :transport, :server_crashed]` and
  `[:gen_mcp, :transport, :version_rejected]` replace the
  `[:gen_mcp, :session, ...]` and `[:gen_mcp, :cluster, ...]` events.

**1.x maintenance**

1.x will only receive security fixes and dependency compatibility updates. It
implements the 2025 protocols and will not get new features or protocol work.

### 🚀 Features

- [**breaking**] Stateless MCP 2026-07-28 core with 2025 compatibility transport (_lud_)

## [1.0.0] - 2026-07-29

Freeze the stateful 2025 protocol line.

gen_mcp 1.0.0 is the 0.10.x codebase promoted to a stable major. It speaks the
stateful MCP protocol (2025-06-18 / 2025-11-25), and nothing about how it works
changes with this release. If you are running gen_mcp today, `{:gen_mcp, "~> 1.0"}`
keeps you exactly where you are, on a lane that stays supported.

The 1.x branch takes security fixes and dependency-compatibility fixes only. No
features and no protocol work: the 2025 protocol is frozen here.

Version 2 is a hard fork onto the stateless 2026-07-28 protocol, which removes
session handling from the core. Staying on 1.x is not the only way to keep your
current clients working — v2 ships a compatibility transport that serves 2025
clients from the same application, on their existing route, so upgrading does
not mean migrating every client at once.

One API removal since 0.10.0: the `GenMCP.MCP.RequestMeta` entity is gone,
dropped by the MCP schema codegen refactor. The rest of the public surface is
unchanged.

### ⚙️ Miscellaneous Tasks

- Refactor MCP schemas codegen (_lud_)
- *(doc)* Generate docs in :docs env (_lud_)

## [0.10.0] - 2026-05-25

### 🚀 Features

- Added :jsv_build_opts to customize Suite.Tool input schema validation (_lud_)
- Support returning structured content without mirrored text content from tools (_lud_)

## [0.9.1] - 2026-05-13

### 🐛 Bug Fixes

- Allow atom casting in compile-time tool schemas (_lud_)

## [0.9.0] - 2026-05-10

### 🚀 Features

- Upgrade to JSV 0.19 new cast system, support Decimal 3 (_lud_)

## [0.8.0] - 2026-03-30

### 🚀 Features

- Added support for logging capabilities (_lud_)

### 🚜 Refactor

- [**breaking**] Channel.send_progress/3 will not return :ok instead of {:ok, channel} (_lud_)

## [0.7.0] - 2026-03-16

### 🚀 Features

- Use a global registry to support restoring sessions on any node (_lud_)
- [**breaking**] Default protocol version is now 2025-11-25 (_lud_)

## [0.6.0] - 2026-03-16

### 🐛 Bug Fixes

- Return HTTP 200 codes for RPC-level errors (_lud_)

## [0.5.2] - 2026-01-26

### 🐛 Bug Fixes

- Fixed callback check macros for Elixir 1.20 (_lud_)

## [0.5.1] - 2026-01-06

### 🐛 Bug Fixes

- Use self-contained JSON Schemas when listing tools (_lud_)

## [0.5.0] - 2025-12-19

### 🚀 Features

- Added support for tools/list _meta in Suite (_lud_)
- Channels are now created by the HTTP client directly (_lud_)
- Added session controller support in suite (_lud_)
- Prepare channel struct for status indicator (_lud_)
- Pass listener channel to the session controller (_lud_)
- [**breaking**] Session controller channel assigns are not merged in all requests anymore (_lud_)

### 🚜 Refactor

- Do not handle file write errors in DevSessionStore (_lud_)

### 📚 Documentation

- Document need for constant node_id for DevSessionStore (_lud_)

## [0.4.2] - 2025-11-29

### 📚 Documentation

- Improvements on user guides (_lud_)

## [0.4.1] - 2025-11-29

### 🐛 Bug Fixes

- Fixed server name/title that was hardcoded with test values (_lud_)

## [0.4.0] - 2025-11-28

### 🚀 Features

- Updated MCP schemas generation to skip content blocks types in structs (_lud_)
- Removed logger calls, using telemetry instead (_lud_)

## [0.3.1] - 2025-11-26

### 📚 Documentation

- Updated getting started doc for example tool to work (#6) (_Conor Sinclair_)

## [0.3.0] - 2025-11-26

### 🚀 Features

- Extract module based schemas for tool describe (_lud_)
- Make all RPC request objects serialize as valid requests (_lud_)

### 🐛 Bug Fixes

- Change error code for unsupported protocol version (_lud_)

### 📚 Documentation

- Started to document some modules (_lud_)
- Added bare documentation for some behaviours (_lud_)
- Added example implementations in behaviours (_lud_)

### ⚙️ Miscellaneous Tasks

- Handle formatter variations accross Elixir versions (_lud_)
- Handle formatter variations accross Elixir versions 2 (_lud_)
- Added LICENSE (_lud_)
- Remove .tool-versions (_lud_)
- Prevent dialyzer to start on localcluster (_lud_)
- Using Quokka formatter (_lud_)

## [0.2.0] - 2025-11-17

### 🚀 Features

- Node ID prototype (_lud_)
- Added the mcp-validator test suite (_lud_)
- Generated schemas for protocol entities (_lud_)
- Ensure keepalive for streams (_lud_)
- Store async tool state in parent state (_lud_)
- New http connection implementation with multiplexing (_lud_)
- New, simpler server implementation and behaviour (_lud_)
- Added support for resources and URI templates (_lud_)
- Added support for async Tasks in tools (_lud_)
- Added support for prompts and arguments (_lud_)
- Added support for authorization layer (_lud_)
- Added Tool using macros and fixed session node retrieval (_lud_)
- Encode unknown method errors (_lud_)
- Session termination and timeout (_lud_)
- Session initialization failure handling (_lud_)
- Added helpers to create MCP entities (_lud_)
- Support extensions in Suite init phases (_lud_)
- Allow invalid_params tuples from tool and prompt calls (_lud_)
- Support node ID configuration (_lud_)
- Accept and ignore cancelled notification (_lud_)
- Accept and ignore roots notification (_lud_)

### 🐛 Bug Fixes

- Capabilities rendering when no tool is there (_lud_)
- Declare capabilities based on suite components (_lud_)

### 🚜 Refactor

- Node disconnect cleanup (_lud_)
- Use session ID as salt for pagination tokens (_lud_)
- Moved MCP entities to the MCP namespace (_lud_)
- Inline JSON serializers for MCP structs (_lud_)

### 🧪 Testing

- Initialized tests for the statful server (_lud_)
- Fix warnings on module delegations (_lud_)
- Ensure resource and prompt repos receive channel assigns (_lud_)
- Added tests to fix ResourceRepo behaviour (_lud_)

### ⚙️ Miscellaneous Tasks

- Move test namespace (_lud_)
- Rename plug derivation to defplug (_lud_)
- Setup mcp jest tool for later (_lud_)
- Tools shoud be initializable (_lud_)
- Tool storage using map (_lud_)
- Renaming namespaces (_lud_)
- Wrap node sync in its own supervisor (_lud_)
- Credo and dialyzer fixes (_lud_)

