alias GenMcp.Tool
alias GenMcp.Server

Mox.defmock(GenMcp.Support.ServerMock, for: Server)
Mox.defmock(GenMcp.Support.ToolMock, for: Tool)
