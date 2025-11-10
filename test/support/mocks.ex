alias GenMcp.ResourceRepo
alias GenMcp.Tool
alias GenMcp.Server

Mox.defmock(GenMcp.Support.ServerMock, for: Server)
Mox.defmock(GenMcp.Support.ToolMock, for: Tool)
Mox.defmock(GenMcp.Support.ResourceRepoMock, for: ResourceRepo, skip_optional_callbacks: true)

Mox.defmock(GenMcp.Support.ResourceRepoMockTpl,
  for: ResourceRepo,
  skip_optional_callbacks: [parse_uri: 2]
)
