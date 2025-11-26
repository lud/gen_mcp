# Changelog

All notable changes to this project will be documented in this file.

## [0.3.1] - 2025-11-26

### 📚 Documentation

- Updated getting started doc for example tool to work (#6)

## [0.3.0] - 2025-11-26

### 🚀 Features

- Extract module based schemas for tool describe
- Make all RPC request objects serialize as valid requests

### 🐛 Bug Fixes

- Change error code for unsupported protocol version

### 📚 Documentation

- Started to document some modules
- Added bare documentation for some behaviours
- Added example implementations in behaviours

### ⚙️ Miscellaneous Tasks

- Handle formatter variations accross Elixir versions
- Handle formatter variations accross Elixir versions 2
- Added LICENSE
- Remove .tool-versions
- Prevent dialyzer to start on localcluster
- Using Quokka formatter

## [0.2.0] - 2025-11-17

### 🚀 Features

- Node ID prototype
- Added the mcp-validator test suite
- Generated schemas for protocol entities
- Ensure keepalive for streams
- Store async tool state in parent state
- New http connection implementation with multiplexing
- New, simpler server implementation and behaviour
- Added support for resources and URI templates
- Added support for async Tasks in tools
- Added support for prompts and arguments
- Added support for authorization layer
- Added Tool using macros and fixed session node retrieval
- Encode unknown method errors
- Session termination and timeout
- Session initialization failure handling
- Added helpers to create MCP entities
- Support extensions in Suite init phases
- Allow invalid_params tuples from tool and prompt calls
- Support node ID configuration
- Accept and ignore cancelled notification
- Accept and ignore roots notification

### 🐛 Bug Fixes

- Capabilities rendering when no tool is there
- Declare capabilities based on suite components

### 🚜 Refactor

- Node disconnect cleanup
- Use session ID as salt for pagination tokens
- Moved MCP entities to the MCP namespace
- Inline JSON serializers for MCP structs

### 🧪 Testing

- Initialized tests for the statful server
- Fix warnings on module delegations
- Ensure resource and prompt repos receive channel assigns
- Added tests to fix ResourceRepo behaviour

### ⚙️ Miscellaneous Tasks

- Move test namespace
- Rename plug derivation to defplug
- Setup mcp jest tool for later
- Tools shoud be initializable
- Tool storage using map
- Renaming namespaces
- Wrap node sync in its own supervisor
- Credo and dialyzer fixes


