defmodule GenMCP.Suite.Extension do
  @moduledoc """
  Behaviour for contributing tools, resource repositories, and prompt
  repositories to a `GenMCP.Suite` based on the request.

  A plain Suite serves the providers you list in its `:tools`, `:resources`, and
  `:prompts` options. An extension serves the same kinds of providers, but it
  computes them per request from the `t:GenMCP.Mux.Channel.t/0` it is given.
  This is the place to vary what the server exposes by request context, most
  often the caller's authorization, since the channel carries the read-only
  client `meta` and the auth assigns merged into it.

  An extension answers three questions, one per callback: which tools, which
  resource repositories, and which prompt repositories to add. Each callback
  returns provider specs (bare modules or `{module, arg}` tuples), not built
  results. The Suite invokes the extension while gathering capabilities and while
  listing or dispatching, then expands and runs the providers it returns.

  ## Minimal implementation

  An extension that exposes an `add` tool to everyone and an extra admin tool
  only when the request was authenticated as an administrator. The tools are
  ordinary `GenMCP.Suite.Tool` modules the application defines elsewhere; the
  extension only decides which ones to surface, reading the auth assign that the
  router merged into the channel `meta` (see `GenMCP.Mux.Channel.from_request/3`):

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

  ### Wiring an extension into the server

  An extension is given to the Suite through its `:extensions` option. Because
  the Suite is the default `:server`, those options are passed straight to the
  transport plug in your router. Each entry is a bare module or a `{module, arg}`
  tuple, where `arg` is handed back to every callback as the trailing argument:

      # In your router
      forward "/mcp", GenMCP.Transport.StreamableHTTP,
        server_name: "My App",
        server_version: "1.0.0",
        extensions: [{MyApp.AdminExtension, []}]

  ## Ordering

  The providers configured directly on the Suite (`:tools`, `:resources`,
  `:prompts`) always come first, ahead of any extension. Extensions then
  contribute in the order they appear in the `:extensions` list. This ordering
  is what `tools/list` and the resource and prompt listings reflect, and it
  decides precedence when two providers define the same tool: the first one wins.

  ## Provider arguments

  The two arguments every callback receives follow the conventions shared by all
  Suite providers, documented in `GenMCP.Suite`:

  * `channel` is the request-scoped `t:GenMCP.Mux.Channel.t/0`, carrying
    read-only client `meta` and auth assigns. Use it to tailor what the
    extension exposes per request.
  * `arg` is the value configured alongside the module as `{module, arg}` (a bare
    module is treated as `{module, []}`). It lets one generic extension module be
    configured differently in different Suites.
  """
  alias GenMCP.Mux.Channel
  alias GenMCP.Suite

  @type extension :: module | {module, arg} | extension_descriptor
  @type extension_descriptor :: %{
          required(:mod) => module,
          required(:arg) => arg
        }
  @type arg :: term

  @doc """
  Returns the tools this extension contributes for the request.

  Each entry is a `GenMCP.Suite.Tool` spec, a bare module or a `{module, arg}`
  tuple. Return an empty list to contribute nothing. The `channel` carries the
  request context (client `meta` and auth assigns), and `arg` is the value
  configured next to the extension module.

  Tailor the list to the request by reading the channel, for example exposing an
  extra tool only to an authenticated administrator:

      @impl true
      def tools(channel, _arg) do
        case channel.meta do
          %{current_user: %{role: :admin}} -> [MyApp.AddTool, MyApp.AdminTool]
          _ -> [MyApp.AddTool]
        end
      end
  """
  @callback tools(Channel.t(), arg) :: [Suite.Tool.tool()]

  @doc """
  Returns the resource repositories this extension contributes for the request.

  Each entry is a `GenMCP.Suite.ResourceRepo` spec, a bare module or a
  `{module, arg}` tuple. Return an empty list to contribute nothing. The
  `channel` carries the request context, and `arg` is the value configured next
  to the extension module.

      @impl true
      def resources(_channel, arg) do
        [{MyApp.FileResources, root: arg[:root]}]
      end
  """
  @callback resources(Channel.t(), arg) :: [Suite.ResourceRepo.resource_repo()]

  @doc """
  Returns the prompt repositories this extension contributes for the request.

  Each entry is a `GenMCP.Suite.PromptRepo` spec, a bare module or a
  `{module, arg}` tuple. Return an empty list to contribute nothing. The
  `channel` carries the request context, and `arg` is the value configured next
  to the extension module.

      @impl true
      def prompts(_channel, _arg), do: [MyApp.SupportPrompts]
  """
  @callback prompts(Channel.t(), arg) :: [Suite.PromptRepo.prompt_repo()]

  @doc """
  Normalizes an extension spec into a descriptor map.

  Accepts the three forms an extension may be configured as and returns a
  `t:extension_descriptor/0`, the `%{mod: module, arg: term}` shape the Suite
  works with internally:

  * a bare `module`, treated as `{module, []}`,
  * a `{module, arg}` tuple,
  * an already-built descriptor map, returned unchanged.

  For the bare module and tuple forms the module is loaded with
  `Code.ensure_loaded!/1`, so this raises if the module does not exist.
  """
  @spec expand(extension) :: extension_descriptor
  def expand(%{mod: _} = extension) do
    extension
  end

  def expand(mod) when is_atom(mod) do
    expand({mod, []})
  end

  def expand({mod, arg}) when is_atom(mod) do
    Code.ensure_loaded!(mod)
    %{mod: mod, arg: arg}
  end

  @doc """
  Invokes the `c:tools/2` callback of the extension `descriptor` for `channel`.

  Given a descriptor from `expand/1` and the request channel, calls the
  extension module's `c:tools/2` with the channel and the descriptor's `arg`,
  and returns the tool specs it produces. `GenMCP.Suite` uses this to gather
  every extension's tools.
  """
  def tools(%{mod: mod, arg: arg}, channel) do
    mod.tools(channel, arg)
  end

  @doc """
  Invokes the `c:resources/2` callback of the extension `descriptor` for `channel`.

  Counterpart of `tools/2` for resource repositories.
  """
  def resources(%{mod: mod, arg: arg}, channel) do
    mod.resources(channel, arg)
  end

  @doc """
  Invokes the `c:prompts/2` callback of the extension `descriptor` for `channel`.

  Counterpart of `tools/2` for prompt repositories.
  """
  def prompts(%{mod: mod, arg: arg}, channel) do
    mod.prompts(channel, arg)
  end
end
