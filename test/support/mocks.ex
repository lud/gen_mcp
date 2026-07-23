alias GenMCP.Suite.Extension
alias GenMCP.Suite.PromptRepo
alias GenMCP.Suite.ResourceRepo
alias GenMCP.Suite.SubscriptionHandler
alias GenMCP.Suite.Tool

#
# -- Server -------------------------------------------------------------------

# The general-purpose server mock implements every callback, including the
# optional `handle_close/2` (spec 005), so the transport disconnect test can
# observe it on the normal route. Other tests never disconnect, so handle_close
# is simply never called on them.
Mox.defmock(GenMCP.Support.ServerMock, for: GenMCP)

# Skips `handle_close/2`, for the unit test that exercises the "not implemented
# -> stop immediately" path.
Mox.defmock(GenMCP.Support.ServerMockNoClose,
  for: GenMCP,
  skip_optional_callbacks: [handle_close: 2]
)

#
# -- Extensions ---------------------------------------------------------------

Mox.defmock(GenMCP.Support.ExtensionMock, for: Extension)

#
# -- Tools --------------------------------------------------------------------

Mox.defmock(GenMCP.Support.ToolMock,
  for: Tool,
  skip_optional_callbacks: [validate_request: 2, handle_close: 3, cache_control: 1]
)

# Implements all optional callbacks, for tests exercising the optional
# `validate_request/2` / `handle_close/3` paths (the dispatcher only invokes
# them when exported).
Mox.defmock(GenMCP.Support.ToolFullMock, for: Tool)

#
# -- Resources ----------------------------------------------------------------

Mox.defmock(GenMCP.Support.ResourceRepoMock, for: ResourceRepo, skip_optional_callbacks: true)

Mox.defmock(GenMCP.Support.ResourceRepoMockTpl,
  for: ResourceRepo,
  skip_optional_callbacks: [parse_uri: 2, cache_control: 1]
)

Mox.defmock(GenMCP.Support.ResourceRepoMockTplNoSkip, for: ResourceRepo)

# Implement the optional `cache_control/1` (spec 005) for the list-result
# cache-hint wiring. These `*CacheMock`s keep `cache_control` while skipping the
# other optionals, so they behave as a plain (resp. template) repo otherwise.
Mox.defmock(GenMCP.Support.ResourceRepoCacheMock,
  for: ResourceRepo,
  skip_optional_callbacks: [template: 1, parse_uri: 2]
)

Mox.defmock(GenMCP.Support.ResourceRepoTplCacheMock,
  for: ResourceRepo,
  skip_optional_callbacks: [parse_uri: 2]
)

#
# -- Prompts ------------------------------------------------------------------

Mox.defmock(GenMCP.Support.PromptRepoMock,
  for: PromptRepo,
  skip_optional_callbacks: [cache_control: 1]
)

# Keeps the optional `cache_control/1` (spec 005) for prompts/list cache tests.
Mox.defmock(GenMCP.Support.PromptRepoCacheMock, for: PromptRepo)

#
# -- Subscriptions ------------------------------------------------------------

# Skips the optional `handle_close/3` and `subscription_capabilities/1`, for
# tests that never disconnect, exercise the "not implemented -> stop
# immediately" path, or rely on the default (empty) capability advertisement.
Mox.defmock(GenMCP.Support.SubscriptionHandlerMock,
  for: SubscriptionHandler,
  skip_optional_callbacks: [handle_close: 3, subscription_capabilities: 2]
)

# Implements every optional callback (`handle_close/3`,
# `subscription_capabilities/1`) for the teardown and capability-advertisement
# tests.
Mox.defmock(GenMCP.Support.SubscriptionHandlerFullMock, for: SubscriptionHandler)

#
# -- Plugs --------------------------------------------------------------------

Mox.defmock(GenMCP.Support.AuthorizationMock, for: Plug)
