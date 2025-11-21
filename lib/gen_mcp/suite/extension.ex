defmodule GenMCP.Suite.Extension do
  @moduledoc """
  A behaviour describing extensions to the `GenMCP.Suite` server.

  Extensions allow modular addition of tools, resources, and prompts to the
  suite. They are configured via the `:extensions` option when plugging
  `GenMCP.Transport.StreamableHTTP`.

  ## Lifecycle

  Extensions are invoked during server initialization to gather the initial list
  of capabilities.

  The order of invocation follows the order in the `:extensions` list. However,
  tools, resources, and prompts defined directly on the configuration (via
  `:tools`, `:resources`, `:prompts` options) are always treated as the first
  extension, taking precedence in the listing order.

  ## Channel Access

  Extension callbacks receive the `GenMCP.Mux.Channel` from the initialization
  HTTP request.

  This allows extensions to filter or dynamically generate capabilities based on
  request context (e.g., user authorization).

  Future implementations to support `listChanged` notifications will pass the
  channel from the current GET HTTP request streaming server notifications.

  ## Example

      defmodule MyExtension do
        @behaviour GenMCP.Suite.Extension

        @impl true
        def tools(channel, _arg) do
          if channel.assigns.admin do
            [AdminTool]
          else
            []
          end
        end

        @impl true
        def resources(_channel, _arg), do: [MyResourceRepo]

        @impl true
        def prompts(_channel, _arg), do: []
      end

      # In Router
      plug GenMCP.Transport.StreamableHTTP,
        extensions: [{MyExtension, []}]
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
  Returns a list of tools to be added to the suite.

  ## Examples

      def tools(_channel, _arg), do: [MyTool, {AnotherTool, [opt: :val]}]
  """
  @callback tools(Channel.t(), arg) :: [Suite.Tool.tool()]

  @doc """
  Returns a list of resource repositories to be added to the suite.

  ## Examples

      def resources(_channel, _arg), do: [MyResourceRepo]
  """
  @callback resources(Channel.t(), arg) :: [Suite.ResourceRepo.resource_repo()]

  @doc """
  Returns a list of prompt repositories to be added to the suite.

  ## Examples

      def prompts(_channel, _arg), do: [MyPromptRepo]
  """
  @callback prompts(Channel.t(), arg) :: [Suite.PromptRepo.prompt_repo()]

  @doc false
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

  def tools(%{mod: mod, arg: arg}, channel) do
    mod.tools(channel, arg)
  end

  def resources(%{mod: mod, arg: arg}, channel) do
    mod.resources(channel, arg)
  end

  def prompts(%{mod: mod, arg: arg}, channel) do
    mod.prompts(channel, arg)
  end
end
