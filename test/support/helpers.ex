defmodule GenMCP.Test.Helpers do
  @moduledoc false

  def check_error({:error, reason}) do
    check_error(reason)
  end

  def check_error(reason) do
    GenMCP.Error.cast_error(reason)
  end

  # Returns a channel owned by the calling process (the test process plays the
  # transport relay role). `meta_extras` are merged into the channel's
  # read-only `meta`, which is where per-request context (including the
  # transport `assigns`/`copy_assigns`) lives under the stateless contract.
  def build_channel(meta_extras \\ %{}) do
    channel = GenMCP.Mux.Channel.for_pid(self())

    %{
      channel
      | meta: Map.merge(channel.meta, Map.new(meta_extras)),
        endpoint: GenMCP.TestWeb.Endpoint
    }
  end
end
