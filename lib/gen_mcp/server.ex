defmodule GenMcp.Server do
  alias GenMcp.Mcp.Entities
  alias GenMcp.Mux.Channel
  alias GenMcp.Tool

  require(Elixir.GenMcp.Mcp.Entities.ModMap).require_all()

  @type state :: term

  @callback init(term) :: {:ok, state}

  @type request :: Entities.InitializeRequest.t()
  @type result :: Entities.InitializeResult.t()
  @type notification :: Entities.InitializedNotification.t()
  @type server_reply :: {:result, result} | :stream | {:error, term}

  @callback handle_request(request, Channel.chan_info(), state) ::
              {:reply, server_reply, state} | {:stop, reason :: term, server_reply, state}
  @callback handle_notification(notification, state) :: {:noreply, state}
  @callback handle_info(term, state) :: {:noreply, state}

  def intialize_result(opts) do
    %Entities.InitializeResult{
      capabilities: Keyword.get(opts, :capabilities, %{}),
      serverInfo: Keyword.fetch!(opts, :server_info),
      protocolVersion: "2025-06-18"
    }
  end

  def capabilities(opts) do
    attrs =
      Enum.flat_map(opts, fn
        {key, value} when is_map(value) -> [{key, value}]
        {key, true} -> [{key, %{}}]
        _ -> []
      end)

    struct!(Entities.ServerCapabilities, attrs)
  end

  def server_info(opts) do
    %Entities.Implementation{
      name: Keyword.fetch!(opts, :name),
      version: Keyword.fetch!(opts, :version),
      title: Keyword.get(opts, :title, nil)
    }
  end

  # TODO handle cursor?
  @doc """
  Returns a description of the given tools. Tools already described (as a
  `#{inspect(Entities.Tool)}` struct) are included as they are in the result's
  list of tools.
  """
  @spec list_tools_result([Tool.tool() | Entities.Tool.t()]) :: Entities.ListToolsResult.t()
  def list_tools_result(tools) do
    %Entities.ListToolsResult{
      tools:
        Enum.map(tools, fn
          %Entities.Tool{} = tool -> tool
          tool -> GenMcp.Tool.describe(tool)
        end)
    }
  end

  IO.warn("move as a helper in the Tool module and implement better API")
  # supports error: true
  # TODO support error: binary() -> add the error in the content as text
  # TODO support error: term -> add the inspected term in the content as text
  # TODO test that isError is nil unless we specify true or false
  def call_tool_result(all_content) when is_list(all_content) do
    {content, structured_content, error_or_nil?} =
      Enum.reduce(all_content, {[], nil, nil}, &reduce_tool_result/2)

    content = :lists.reverse(content)

    %Entities.CallToolResult{
      content: content,
      structuredContent: structured_content,
      isError: error_or_nil?
    }
  end

  defp reduce_tool_result({:text, text}, {content, structured_content, error_or_nil?})
       when is_binary(text) do
    {[%Entities.TextContent{type: :text, text: text} | content], structured_content,
     error_or_nil?}
  end

  defp reduce_tool_result({:is_error, error?}, {content, structured_content, error_or_nil?})
       when is_boolean(error?) do
    {content, structured_content, error? || error_or_nil?}
  end

  def list_resources_result(resources, next_cursor) do
    %Entities.ListResourcesResult{
      nextCursor: next_cursor,
      resources: resources
    }
  end

  def list_resource_templates_result(templates) do
    %Entities.ListResourceTemplatesResult{
      resourceTemplates: templates
    }
  end

  @doc """
  Helper function to create resource contents for testing and implementation.

  ## Examples

      # Text resource
      read_resource_result(uri: "file:///readme.txt", text: "# Welcome")

      # Text resource with MIME type
      read_resource_result(uri: "file:///index.html", text: "<p>Hello</p>", mime_type: "text/html")

      # Blob resource
      read_resource_result(uri: "file:///image.png", blob: Base.encode64(binary_data))

      # Blob resource with MIME type
      read_resource_result(uri: "file:///doc.pdf", blob: encoded_data, mime_type: "application/pdf")
  """
  def read_resource_result(opts) do
    uri = Keyword.fetch!(opts, :uri)
    mime_type = Keyword.get(opts, :mime_type)

    contents =
      cond do
        Keyword.has_key?(opts, :text) ->
          text = Keyword.fetch!(opts, :text)

          [
            %Entities.TextResourceContents{
              uri: uri,
              text: text,
              mimeType: mime_type
            }
          ]

        Keyword.has_key?(opts, :blob) ->
          blob = Keyword.fetch!(opts, :blob)

          [
            %Entities.BlobResourceContents{
              uri: uri,
              blob: blob,
              mimeType: mime_type
            }
          ]

        true ->
          raise ArgumentError, "resource_contents/1 requires either :text or :blob option"
      end

    %Entities.ReadResourceResult{contents: contents}
  end
end
