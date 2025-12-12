defmodule GenMCP.Suite.SessionController.DevSessionStore do
  @moduledoc """
  An implementation of `GenMCP.Suite.SessionController` that persists the
  session to disk.

  This is useful during development to be able to stop and restart the Elixir
  runtime without losing the session. Many MCP clients do not support `404 Not
  Found` error for sessions and will need manual assistance to create a new
  session. This controller solves that.

  > #### Development Only {: .warning}
  >
  > Sessions are stored on the hard drive. There is no support for data
  > corruption prevention, distribution on multiple nodes, etc.
  >
  > **It is _not_ suited for production environments.**

  To use this controller, provide it as the `:session_controller` option to the
  transport plug. Optionally with a custom directory.

      forward "/real", McpReal,
        server_name: "Real Server",
        server_version: "0.0.1",
        server_title: "GenMCP own development server",
        tools: [GenMCP.Test.Tools.ErlangHasher, GenMCP.Test.Tools.Addition],
        extensions: [],
        session_controller:
          {GenMCP.Suite.SessionController.DevSessionStore, cache_dir: "tmp/sessions"}

  ## Options

  * `:cache_dir` - a directory path to store sessions as files. The directory
    will be created if it does not exist. The default value uses
    `System.tmp_dir!()` which will lead to sessions being lost after a while on
    most platforms.

  """
  @behaviour GenMCP.Suite.SessionController

  require Logger

  @impl true
  # sobelow_skip ["Misc.BinToTerm","Traversal.FileModule"]
  def fetch(session_id, _channel, opts) do
    session_path = session_path(session_id, opts)

    case File.read(session_path) do
      {:ok, content} -> {:ok, :erlang.binary_to_term(content, [:safe])}
      _ -> {:error, :not_found}
    end
  end

  @impl true
  def create(session_id, client_info, channel, opts) do
    session_path = write_session!(session_id, client_info, opts)
    Logger.debug("Created persisted session in #{session_path}", gen_mcp_session_id: session_id)

    {:ok, channel, opts}
  end

  @impl true
  def update(session_id, client_info, channel, opts) do
    session_path = write_session!(session_id, client_info, opts)
    Logger.debug("Updated persisted session in #{session_path}", gen_mcp_session_id: session_id)

    {:ok, channel, opts}
  end

  defp write_session!(session_id, client_info, opts) do
    session_path = session_path(session_id, opts)
    file_contents = encode_session(client_info)
    :ok = write_file!(session_path, file_contents)
    session_path
  end

  @impl true
  @spec restore(term, term, term) :: no_return
  def restore(restore_data, channel, opts) do
    client_info = decode_session(restore_data)
    {:ok, client_info, channel, opts}
  end

  @impl true
  def handle_info(msg, _channel, opts) do
    _ = GenMCP.Suite.log_unhandled_info(msg)
    {:noreply, opts}
  end

  @impl true
  # sobelow_skip ["Traversal.FileModule"]
  def delete(session_id, opts) do
    session_path = session_path(session_id, opts)

    :ok =
      case File.rm(session_path) do
        :ok ->
          :ok

        {:error, :enoent} ->
          :ok

        {:error, reason} ->
          Logger.error(
            "Could not delete persisted session in #{session_path}: #{inspect(reason)}"
          )
      end
  end

  defp cache_dir(state_or_opts) do
    case state_or_opts[:cache_dir] do
      path when is_binary(path) -> path
      nil -> default_cache_dir()
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp write_file!(session_path, file_contents) do
    File.mkdir_p!(Path.dirname(session_path))
    File.write!(session_path, file_contents)
  end

  defp session_path(session_id, opts) when is_binary(session_id) do
    Path.join(cache_dir(opts), session_id)
  end

  defp encode_session(client_info) do
    :erlang.term_to_binary(%{client_info: client_info})
  end

  defp decode_session(%{client_info: client_info}) do
    client_info
  end

  defp default_cache_dir do
    Path.join(System.tmp_dir!(), "gen-mcp-dev-session-store-cache")
  end
end
