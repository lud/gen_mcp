alias GenMcp.PromptRepo
alias GenMcp.ResourceRepo
alias GenMcp.Tool
alias GenMcp.Server

Mox.defmock(GenMcp.Support.ServerMock, for: Server)
Mox.defmock(GenMcp.Support.ToolMock, for: Tool)
Mox.defmock(GenMcp.Support.ResourceRepoMock, for: ResourceRepo, skip_optional_callbacks: true)

IO.warn("""
we should validate that parse URI is correcly called and export the default
implementation to reuse it in tests to test that default implementation
""")

Mox.defmock(GenMcp.Support.ResourceRepoMockTpl,
  for: ResourceRepo,
  skip_optional_callbacks: [parse_uri: 2]
)

Mox.defmock(GenMcp.Support.PromptRepoMock, for: PromptRepo)
