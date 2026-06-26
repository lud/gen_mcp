# MCP schema update log

A running record of decisions made while following the MCP schema draft, kept by
the [follow-mcp-schema](SKILL.md) skill.

**What goes here:** decisions and architecture changes only — started/stopped
supporting a request, added or removed a generated schema, deliberately ignored a
class of change, removed a capability. One or two lines each, newest on top, with
the upstream `@schemas_ref` (short SHA) it was decided against.

**What does not:** churn. Renamed keys, reworded descriptions, reordered defs,
formatting. If you wouldn't mention it in a standup, leave it out.

---

<!-- New entries on top. Format:

## YYYY-MM-DD — short title (schemas_ref: <short-sha>)

One or two lines: what was decided and why.

-->

## 2026-06-26 — generate SubscriptionsListenResult (schemas_ref: ead35b5)

Draft added a Result type to the `subscriptions/listen` channel: `SubscriptionsListenResult`
(carries `resultType`, default `"complete"`, sent on graceful stream teardown) plus its
`_meta` shape `SubscriptionsListenResultMeta` (holds `io.modelcontextprotocol/subscriptionId`).
Both configured `[]` in `mod_config`, matching the other `ServerResult` union members and the
`*MetaObject` types. Codegen only — the `subscriptions/listen` request is still not in
`validator.ex`, so the channel remains unsupported surface. Tests green.

## 2026-06-26 — log started (schemas_ref: 15b1974)

Baseline. Supported request surface as wired in `lib/gen_mcp/validator.ex`:
resources list/templates/read, prompts list/get, tools list/call, `server/discover`,
and the `cancelled` notification. Ping, subscribe/unsubscribe, set-level, complete,
and several notifications are present in the generated entities but intentionally
left unsupported (commented out).
