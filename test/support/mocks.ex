alias GenMCP.Suite.PromptRepo
alias GenMCP.Suite.ResourceRepo
alias GenMCP.Suite.Tool
alias GenMCP.Server

Mox.defmock(GenMCP.Support.ServerMock, for: Server)
Mox.defmock(GenMCP.Support.ToolMock, for: Tool)
Mox.defmock(GenMCP.Support.ResourceRepoMock, for: ResourceRepo, skip_optional_callbacks: true)

IO.warn("""
we should validate that parse URI is correcly called and export the default
implementation to reuse it in tests to test that default implementation
""")

Mox.defmock(GenMCP.Support.ResourceRepoMockTpl,
  for: ResourceRepo,
  skip_optional_callbacks: [parse_uri: 2]
)

Mox.defmock(GenMCP.Support.PromptRepoMock, for: PromptRepo)
Mox.defmock(GenMCP.Support.AuthorizationMock, for: Plug)
