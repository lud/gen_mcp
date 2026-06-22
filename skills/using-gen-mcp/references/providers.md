# Suite providers beyond tools

All examples alias `GenMCP.MCP.V2607, as: MCP`. Callback arg order is always
subject first, `channel` second-to-last, `arg` last. Each provider entry in the
Suite options is a bare `module` or `{module, arg}`.

## Resource repositories — `GenMCP.Suite.ResourceRepo`

A repo groups resources under a **URI prefix**, answers `resources/list` to
advertise them, and `resources/read` to return contents. The Suite routes a read
to the repo whose `prefix/1` the URI starts with — prefixes must not collide.

### Static resources

```elixir
defmodule MyApp.DocsResources do
  @behaviour GenMCP.Suite.ResourceRepo
  alias GenMCP.MCP.V2607, as: MCP

  @pages %{
    "file:///docs/intro.md" => "# Introduction\n\nWelcome.",
    "file:///docs/guide.md" => "# Guide\n\nStep one."
  }

  @impl true
  def prefix(_arg), do: "file:///docs/"

  @impl true
  def list(_cursor, _channel, _arg) do
    resources =
      for {uri, _body} <- @pages do
        %{uri: uri, name: Path.basename(uri), mimeType: "text/markdown"}
      end
    {resources, nil}   # {items, next_cursor}
  end

  @impl true
  def read(uri, _channel, _arg) do
    case @pages do
      %{^uri => body} ->
        {:ok, MCP.read_resource_result(uri: uri, text: body, mime_type: "text/markdown")}
      _ ->
        {:error, :not_found}
    end
  end
end
```

Wire it: `resources: [MyApp.DocsResources]`.

### Templated resources (a whole URI family)

Implement the optional `template/1` with an [RFC 6570](https://www.rfc-editor.org/rfc/rfc6570)
URI template. `read/3` then receives the parsed variables as a map instead of the
raw URI:

```elixir
@impl true
def template(_arg), do: %{uriTemplate: "file:///users/{id}", name: "User record"}

@impl true
def read(%{"id" => id}, _channel, _arg) do
  case MyApp.Accounts.fetch_user(id) do
    {:ok, user} -> {:ok, MCP.read_resource_result(uri: "file:///users/#{id}", text: user.bio)}
    :error -> {:error, :not_found}
  end
end
```

To control parsing yourself, implement `parse_uri/2` returning `{:ok, value}` or
`{:error, message}`; its result is passed straight to `read/3`.

### Pagination

`list/3`'s first argument is the cursor (`nil` on the first page). Return
`{items, next_cursor}`; `nil` cursor means last page. The cursor is whatever
token you choose — the client sends it back:

```elixir
@impl true
def list(nil, _channel, _arg), do: {first_page(), "page-2"}
def list("page-2", _channel, _arg), do: {second_page(), nil}
```

(Prompt repos paginate identically.)

### Caching

Optional `cache_control/1` returns `{:public | :private, ttl_ms}` for the
listing. Default is no-cache.

## Prompt repositories — `GenMCP.Suite.PromptRepo`

Prompts are reusable message templates. A repo groups them under a **name
prefix**, advertises via `list/3`, and builds one in `get/4` from the client's
arguments (passed through unvalidated — match and check the keys you need).

```elixir
defmodule MyApp.SupportPrompts do
  @behaviour GenMCP.Suite.PromptRepo
  alias GenMCP.MCP.V2607, as: MCP

  @impl true
  def prefix(_arg), do: "support/"

  @impl true
  def list(_cursor, _channel, _arg) do
    prompts = [
      %{
        name: "support/greeting",
        description: "Greet a customer by name",
        arguments: [%{name: "name", description: "Customer name", required: true}]
      }
    ]
    {prompts, nil}
  end

  @impl true
  def get("support/greeting", %{"name" => name}, _channel, _arg) do
    {:ok, MCP.get_prompt_result(
      description: "Greet a customer by name",
      text: "Greet #{name} warmly and ask how you can help."
    )}
  end

  def get(_name, _args, _channel, _arg), do: {:error, :not_found}
end
```

Wire it: `prompts: [MyApp.SupportPrompts]`.

## Extensions — `GenMCP.Suite.Extension`

An extension computes providers **per request** from the channel — the place to
vary exposure by auth/tenant. Three callbacks return provider specs (not built
results): `tools/2`, `resources/2`, `prompts/2`.

```elixir
defmodule MyApp.AdminExtension do
  @behaviour GenMCP.Suite.Extension

  @impl true
  def tools(channel, _arg) do
    case channel.meta do
      %{current_user: %{role: :admin}} -> [MyApp.AddTool, MyApp.AdminTool]
      _ -> [MyApp.AddTool]
    end
  end

  @impl true
  def resources(_channel, _arg), do: []
  @impl true
  def prompts(_channel, _arg), do: []
end
```

Wire it: `extensions: [{MyApp.AdminExtension, []}]`. Providers listed directly on
the Suite come first; extensions add after, in list order; first definition of a
duplicate name wins. (See SKILL.md "Passing per-request data" for how
`current_user` lands in `channel.meta`.)

## Subscription handler — `GenMCP.Suite.SubscriptionHandler`

Serves `subscriptions/listen`: one long-lived SSE stream carrying server-driven
notifications (`tools/list_changed`, `resources/updated`, ...). A Suite has **one**
handler. Lifecycle mirrors streaming tools: `subscribe/3` sets up the source,
`handle_message/4` turns events into notifications, `handle_close/3` tears down.

```elixir
defmodule MyApp.ToolChanges do
  @behaviour GenMCP.Suite.SubscriptionHandler
  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.Mux.Channel

  @impl true
  def subscribe(%MCP.SubscriptionFilter{toolsListChanged: true}, _channel, _arg) do
    Phoenix.PubSub.subscribe(MyApp.PubSub, "tools")
    {:stream, %{}}
  end

  def subscribe(_filter, _channel, _arg), do: {:stop, :nothing_to_watch}

  @impl true
  def handle_message(:tools_changed, channel, state, _arg) do
    Channel.send_notification(channel, %MCP.ToolListChangedNotification{})
    {:stream, state}
  end

  # Advertise the notification types you emit; the Suite puts these in
  # server/discover, which is what prompts clients to subscribe.
  @impl true
  def subscription_capabilities(_channel, _arg), do: %{tools_list_changed: true}
end
```

Wire it (single module, not a list): `subscription_handler: MyApp.ToolChanges`.

Notes:
- The Suite sends the first `notifications/subscriptions/acknowledged` message,
  not the handler. `{:stream, state}` acks the full filter; `{:stream, honored,
  state}` acks a narrowed `honored` filter (partial auth/capabilities).
- Events come from your app (PubSub, GenStage, a GenServer) — `subscribe/3` joins
  the worker process to that source.
