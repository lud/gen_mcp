alias GenMCP.Suite.Extension
alias GenMCP.Suite.PromptRepo
alias GenMCP.Suite.ResourceRepo
alias GenMCP.Suite.Tool
alias GenMCP.Server

#
# -- Server -------------------------------------------------------------------

Mox.defmock(GenMCP.Support.ServerMock, for: Server)

#
# -- Extensions ---------------------------------------------------------------

Mox.defmock(GenMCP.Support.ExtensionMock, for: Extension)

#
# -- Tools --------------------------------------------------------------------

Mox.defmock(GenMCP.Support.ToolMock, for: Tool, skip_optional_callbacks: [validate_request: 2])

#
# -- Resources ----------------------------------------------------------------

Mox.defmock(GenMCP.Support.ResourceRepoMock, for: ResourceRepo, skip_optional_callbacks: true)

Mox.defmock(GenMCP.Support.ResourceRepoMockTpl,
  for: ResourceRepo,
  skip_optional_callbacks: [parse_uri: 2]
)

Mox.defmock(GenMCP.Support.ResourceRepoMockTplNoSkip, for: ResourceRepo)

#
# -- Prompts ------------------------------------------------------------------

Mox.defmock(GenMCP.Support.PromptRepoMock, for: PromptRepo)

#
# -- Plugs --------------------------------------------------------------------

Mox.defmock(GenMCP.Support.AuthorizationMock, for: Plug)
