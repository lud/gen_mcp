defmodule GenMCP.Suite.Extension do
  @moduledoc """
  A behaviour describing extensions to the `GenMCP.Suite` server.

  Extensions can be added by providing the `:extensions` option when plugging
  `GenMCP.Transport.StreamableHttp` in the router.

  They are called when the server initializes (or when the server handles
  `listChanged` notifications from the session controller but this is not
  implemeted yet).

  Order of call follows the order of the :extensions options, except that direct
  options like :resources, :tools given directly to the plug will be treated as
  another extension that is called fist, so its tools, resources and prompts are
  listed first when the client reuquests a list.

  Extensions receive the channel from the initialize request on server
  initialization, or the channel from the client listener (GET http method) if
  any. The channel bears session controller assigns and assigns copied from the
  Plug.Conn, which can be used to filter tools or resource repos based on the
  assigns added by you authorization layer in the plug pipeline.

  Extensions should not send notifications to that channel.
  """
  alias GenMCP.Mux.Channel
  alias GenMCP.Suite

  @type extension :: module | {module, arg} | extension_descriptor
  @type extension_descriptor :: %{
          required(:mod) => module,
          required(:arg) => arg
        }
  @type arg :: term

  @callback tools(Channel.t(), arg) :: [Suite.Tool.tool()]
  @callback resources(Channel.t(), arg) :: [Suite.ResourceRepo.resource_repo()]
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
