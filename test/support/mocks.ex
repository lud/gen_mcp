alias GenMCP.Suite.Extension
alias GenMCP.Suite.PromptRepo
alias GenMCP.Suite.ResourceRepo
alias GenMCP.Suite.Tool

#
# -- Server -------------------------------------------------------------------

Mox.defmock(GenMCP.Support.ServerMock, for: GenMCP)

#
# -- Extensions ---------------------------------------------------------------

Mox.defmock(GenMCP.Support.ExtensionMock, for: Extension)

#
# -- Tools --------------------------------------------------------------------

Mox.defmock(GenMCP.Support.ToolMock, for: Tool, skip_optional_callbacks: [validate_request: 2])

# Implements all optional callbacks, for tests exercising the optional
# `validate_request/2` path (the dispatcher only invokes it when exported).
Mox.defmock(GenMCP.Support.ToolFullMock, for: Tool)

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
