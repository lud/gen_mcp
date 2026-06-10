# quokka:skip-module-directives

require GenMCP.JsonDerive, as: JsonDerive

defmodule GenMCP.MCP.V2607.Meta do
  use JSV.Schema

  def json_schema do
    %{
      additionalProperties: %{},
      description:
        "See [General Fields](https://modelcontextprotocol.io/specification/2025-11-25/basic#general-fields) for notes on _meta usage.",
      properties: %{progressToken: GenMCP.MCP.V2607.ProgressToken},
      type: "object"
    }
  end
end

defmodule GenMCP.MCP.V2607.ListenerRequest do
  @moduledoc """
  Represents a GET request from the StreamableHTTP client.
  """

  defstruct []
  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ModMap do
  defmacro require_all do
    Enum.map(json_schema().definitions, fn {_, mod} ->
      quote do
        require unquote(mod)
      end
    end)
  end

  def json_schema do
    %{
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      definitions: %{
        "Annotations" => GenMCP.MCP.V2607.Annotations,
        "AudioContent" => GenMCP.MCP.V2607.AudioContent,
        "BlobResourceContents" => GenMCP.MCP.V2607.BlobResourceContents,
        "CacheableResult" => GenMCP.MCP.V2607.CacheableResult,
        "CallToolRequest" => GenMCP.MCP.V2607.CallToolRequest,
        "CallToolRequestParams" => GenMCP.MCP.V2607.CallToolRequestParams,
        "CallToolResult" => GenMCP.MCP.V2607.CallToolResult,
        "CancelledNotification" => GenMCP.MCP.V2607.CancelledNotification,
        "CancelledNotificationParams" => GenMCP.MCP.V2607.CancelledNotificationParams,
        "ClientCapabilities" => GenMCP.MCP.V2607.ClientCapabilities,
        "ContentBlock" => GenMCP.MCP.V2607.ContentBlock,
        "CreateMessageRequest" => GenMCP.MCP.V2607.CreateMessageRequest,
        "CreateMessageRequestParams" => GenMCP.MCP.V2607.CreateMessageRequestParams,
        "CreateMessageResult" => GenMCP.MCP.V2607.CreateMessageResult,
        "DiscoverRequest" => GenMCP.MCP.V2607.DiscoverRequest,
        "DiscoverResult" => GenMCP.MCP.V2607.DiscoverResult,
        "ElicitRequest" => GenMCP.MCP.V2607.ElicitRequest,
        "ElicitRequestFormParams" => GenMCP.MCP.V2607.ElicitRequestFormParams,
        "ElicitRequestParams" => GenMCP.MCP.V2607.ElicitRequestParams,
        "ElicitRequestURLParams" => GenMCP.MCP.V2607.ElicitRequestURLParams,
        "ElicitResult" => GenMCP.MCP.V2607.ElicitResult,
        "EmbeddedResource" => GenMCP.MCP.V2607.EmbeddedResource,
        "Error" => GenMCP.MCP.V2607.Error,
        "GetPromptRequest" => GenMCP.MCP.V2607.GetPromptRequest,
        "GetPromptRequestParams" => GenMCP.MCP.V2607.GetPromptRequestParams,
        "GetPromptResult" => GenMCP.MCP.V2607.GetPromptResult,
        "Icon" => GenMCP.MCP.V2607.Icon,
        "Icons" => GenMCP.MCP.V2607.Icons,
        "ImageContent" => GenMCP.MCP.V2607.ImageContent,
        "Implementation" => GenMCP.MCP.V2607.Implementation,
        "InputRequest" => GenMCP.MCP.V2607.InputRequest,
        "InputRequests" => GenMCP.MCP.V2607.InputRequests,
        "InputRequiredResult" => GenMCP.MCP.V2607.InputRequiredResult,
        "InputResponse" => GenMCP.MCP.V2607.InputResponse,
        "InputResponseRequestParams" => GenMCP.MCP.V2607.InputResponseRequestParams,
        "InputResponses" => GenMCP.MCP.V2607.InputResponses,
        "JSONArray" => GenMCP.MCP.V2607.JSONArray,
        "JSONObject" => GenMCP.MCP.V2607.JSONObject,
        "JSONRPCErrorResponse" => GenMCP.MCP.V2607.JSONRPCErrorResponse,
        "JSONRPCRequest" => GenMCP.MCP.V2607.JSONRPCRequest,
        "JSONRPCResponse" => GenMCP.MCP.V2607.JSONRPCResponse,
        "JSONRPCResultResponse" => GenMCP.MCP.V2607.JSONRPCResultResponse,
        "JSONValue" => GenMCP.MCP.V2607.JSONValue,
        "ListPromptsRequest" => GenMCP.MCP.V2607.ListPromptsRequest,
        "ListPromptsResult" => GenMCP.MCP.V2607.ListPromptsResult,
        "ListResourceTemplatesRequest" => GenMCP.MCP.V2607.ListResourceTemplatesRequest,
        "ListResourceTemplatesResult" => GenMCP.MCP.V2607.ListResourceTemplatesResult,
        "ListResourcesRequest" => GenMCP.MCP.V2607.ListResourcesRequest,
        "ListResourcesResult" => GenMCP.MCP.V2607.ListResourcesResult,
        "ListRootsRequest" => GenMCP.MCP.V2607.ListRootsRequest,
        "ListRootsResult" => GenMCP.MCP.V2607.ListRootsResult,
        "ListToolsRequest" => GenMCP.MCP.V2607.ListToolsRequest,
        "ListToolsResult" => GenMCP.MCP.V2607.ListToolsResult,
        "LoggingLevel" => GenMCP.MCP.V2607.LoggingLevel,
        "LoggingMessageNotification" => GenMCP.MCP.V2607.LoggingMessageNotification,
        "LoggingMessageNotificationParams" => GenMCP.MCP.V2607.LoggingMessageNotificationParams,
        "MetaObject" => GenMCP.MCP.V2607.MetaObject,
        "ModelHint" => GenMCP.MCP.V2607.ModelHint,
        "ModelPreferences" => GenMCP.MCP.V2607.ModelPreferences,
        "NotificationParams" => GenMCP.MCP.V2607.NotificationParams,
        "PaginatedRequestParams" => GenMCP.MCP.V2607.PaginatedRequestParams,
        "ProgressNotification" => GenMCP.MCP.V2607.ProgressNotification,
        "ProgressNotificationParams" => GenMCP.MCP.V2607.ProgressNotificationParams,
        "ProgressToken" => GenMCP.MCP.V2607.ProgressToken,
        "Prompt" => GenMCP.MCP.V2607.Prompt,
        "PromptArgument" => GenMCP.MCP.V2607.PromptArgument,
        "PromptMessage" => GenMCP.MCP.V2607.PromptMessage,
        "ReadResourceRequest" => GenMCP.MCP.V2607.ReadResourceRequest,
        "ReadResourceRequestParams" => GenMCP.MCP.V2607.ReadResourceRequestParams,
        "ReadResourceResult" => GenMCP.MCP.V2607.ReadResourceResult,
        "RequestId" => GenMCP.MCP.V2607.RequestId,
        "RequestMetaObject" => GenMCP.MCP.V2607.RequestMetaObject,
        "RequestParams" => GenMCP.MCP.V2607.RequestParams,
        "Resource" => GenMCP.MCP.V2607.Resource,
        "ResourceLink" => GenMCP.MCP.V2607.ResourceLink,
        "ResourceTemplate" => GenMCP.MCP.V2607.ResourceTemplate,
        "Result" => GenMCP.MCP.V2607.Result,
        "Role" => GenMCP.MCP.V2607.Role,
        "Root" => GenMCP.MCP.V2607.Root,
        "SamplingMessage" => GenMCP.MCP.V2607.SamplingMessage,
        "SamplingMessageContentBlock" => GenMCP.MCP.V2607.SamplingMessageContentBlock,
        "ServerCapabilities" => GenMCP.MCP.V2607.ServerCapabilities,
        "SubscriptionFilter" => GenMCP.MCP.V2607.SubscriptionFilter,
        "SubscriptionsAcknowledgedNotification" =>
          GenMCP.MCP.V2607.SubscriptionsAcknowledgedNotification,
        "SubscriptionsAcknowledgedNotificationParams" =>
          GenMCP.MCP.V2607.SubscriptionsAcknowledgedNotificationParams,
        "SubscriptionsListenRequest" => GenMCP.MCP.V2607.SubscriptionsListenRequest,
        "SubscriptionsListenRequestParams" => GenMCP.MCP.V2607.SubscriptionsListenRequestParams,
        "TextContent" => GenMCP.MCP.V2607.TextContent,
        "TextResourceContents" => GenMCP.MCP.V2607.TextResourceContents,
        "Tool" => GenMCP.MCP.V2607.Tool,
        "ToolAnnotations" => GenMCP.MCP.V2607.ToolAnnotations,
        "ToolChoice" => GenMCP.MCP.V2607.ToolChoice,
        "ToolResultContent" => GenMCP.MCP.V2607.ToolResultContent,
        "ToolUseContent" => GenMCP.MCP.V2607.ToolUseContent
      }
    }
  end
end

defmodule GenMCP.MCP.V2607.Annotations do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [])

  defschema %{
    description: ~SD"""
    Optional annotations for the client. The client can use annotations to
    inform how objects are used or displayed
    """,
    properties: %{
      audience: %{
        description: ~SD"""
        Describes who the intended audience of this object or data is.

        It can include multiple entries to indicate content useful for
        multiple audiences (e.g., `["user", "assistant"]`).
        """,
        items: GenMCP.MCP.V2607.Role,
        type: "array"
      },
      lastModified:
        string(
          description: ~SD"""
          The moment the resource was last modified, as an ISO 8601 formatted
          string.

          Should be an ISO 8601 formatted string (e.g., "2025-01-12T15:00:58Z").

          Examples: last activity timestamp in an open file, timestamp when the
          resource was attached, etc.
          """
        ),
      priority: %{
        description: ~SD"""
        Describes how important this data is for operating the server.

        A value of 1 means "most important," and indicates that the data is
        effectively required, while 0 means "least important," and indicates
        that the data is entirely optional.
        """,
        maximum: 1,
        minimum: 0,
        type: "number"
      }
    },
    title: "MCP:Annotations",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.AudioContent do
  use JSV.Schema

  JsonDerive.auto(_merge = %{type: "audio"}, _keep_nils = [:data, :mimeType])

  @skip_keys [:type]

  defschema %{
    description: "Audio provided to or from an LLM.",
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      annotations: GenMCP.MCP.V2607.Annotations,
      data: string_of("byte", description: "The base64-encoded audio data."),
      mimeType:
        string(
          description: ~SD"""
          The MIME type of the audio. Different providers may support different
          audio types.
          """
        ),
      type: const("audio")
    },
    required: [:data, :mimeType, :type],
    title: "MCP:AudioContent",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.BlobResourceContents do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:blob, :uri])

  defschema %{
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      blob:
        string_of("byte",
          description: ~SD"""
          A base64-encoded string representing the binary data of the item.
          """
        ),
      mimeType: string(description: "The MIME type of this resource, if known."),
      uri: uri(description: "The URI of this resource.")
    },
    required: [:blob, :uri],
    title: "MCP:BlobResourceContents",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.CacheableResult do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:cacheScope, :resultType, :ttlMs])

  defschema %{
    description: ~SD"""
    A result that supports a time-to-live (TTL) hint for client-side
    caching.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      cacheScope: string_enum_to_atom([:private, :public]),
      resultType:
        string(
          description: ~SD"""
          Indicates the type of the result, which allows the client to determine
          how to parse the result object.

          Servers implementing this protocol version MUST include this field.
          For backward compatibility, when a client receives a result from a
          server implementing an earlier protocol version (which does not
          include `resultType`), the client MUST treat the absent field as
          `"complete"`.
          """
        ),
      ttlMs: %{
        description: ~SD"""
        A hint from the server indicating how long (in milliseconds) the
        client MAY cache this response before re-fetching. Semantics are
        analogous to HTTP Cache-Control max-age.

        - If 0, The response SHOULD be considered immediately stale, The
        client MAY re-fetch every time the result is needed. - If positive,
        the client SHOULD consider the result fresh for this many milliseconds
        after receiving the response.
        """,
        minimum: 0,
        type: "integer"
      }
    },
    required: [:cacheScope, :resultType, :ttlMs],
    title: "MCP:CacheableResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.CallToolRequest do
  use JSV.Schema

  JsonDerive.auto(_merge = %{method: "tools/call", jsonrpc: "2.0"}, _keep_nils = [:id, :params])

  @skip_keys [:jsonrpc, :method]

  defschema %{
    description: ~SD"""
    Used by the client to invoke a tool provided by the server.
    """,
    properties: %{
      id: GenMCP.MCP.V2607.RequestId,
      jsonrpc: const("2.0"),
      method: const("tools/call"),
      params: GenMCP.MCP.V2607.CallToolRequestParams
    },
    required: [:id, :jsonrpc, :method, :params],
    title: "MCP:CallToolRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.CallToolRequestParams do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:_meta, :name])

  defschema %{
    description: "Parameters for a `tools/call` request.",
    properties: %{
      _meta: GenMCP.MCP.V2607.RequestMetaObject,
      arguments: %{
        additionalProperties: %{},
        description: "Arguments to use for the tool call.",
        type: "object"
      },
      inputResponses: GenMCP.MCP.V2607.InputResponses,
      name: string(description: "The name of the tool."),
      requestState: string()
    },
    required: [:_meta, :name],
    title: "MCP:CallToolRequestParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.CallToolResult do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:content, :resultType])

  defschema %{
    description: ~SD"""
    The result returned by the server for a {@link
    CallToolRequesttools/call} request.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      content: %{
        description: ~SD"""
        A list of content objects that represent the unstructured result of
        the tool call.
        """,
        items: GenMCP.MCP.V2607.ContentBlock,
        type: "array"
      },
      isError:
        boolean(
          description: ~SD"""
          Whether the tool call ended in an error.

          If not set, this is assumed to be false (the call was successful).

          Any errors that originate from the tool SHOULD be reported inside the
          result object, with `isError` set to true, _not_ as an MCP
          protocol-level error response. Otherwise, the LLM would not be able to
          see that an error occurred and self-correct.

          However, any errors in _finding_ the tool, an error indicating that
          the server does not support tool calls, or any other exceptional
          conditions, should be reported as an MCP error response.
          """
        ),
      resultType:
        string(
          description: ~SD"""
          Indicates the type of the result, which allows the client to determine
          how to parse the result object.

          Servers implementing this protocol version MUST include this field.
          For backward compatibility, when a client receives a result from a
          server implementing an earlier protocol version (which does not
          include `resultType`), the client MUST treat the absent field as
          `"complete"`.
          """
        ),
      structuredContent: %{
        description: ~SD"""
        An optional JSON value that represents the structured result of the
        tool call.

        This can be any JSON value (object, array, string, number, boolean, or
        null) that conforms to the tool's outputSchema if one is defined.
        """
      }
    },
    required: [:content, :resultType],
    title: "MCP:CallToolResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.CancelledNotification do
  use JSV.Schema

  JsonDerive.auto(
    _merge = %{method: "notifications/cancelled", jsonrpc: "2.0"},
    _keep_nils = [:params]
  )

  @skip_keys [:jsonrpc, :method]

  defschema %{
    description: ~SD"""
    This notification can be sent by either side to indicate that it is
    cancelling a previously-issued request.

    The request SHOULD still be in-flight, but due to communication
    latency, it is always possible that this notification MAY arrive after
    the request has already finished.

    This notification indicates that the result will be unused, so any
    associated processing SHOULD cease.
    """,
    properties: %{
      jsonrpc: const("2.0"),
      method: const("notifications/cancelled"),
      params: GenMCP.MCP.V2607.CancelledNotificationParams
    },
    required: [:jsonrpc, :method, :params],
    title: "MCP:CancelledNotification",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.CancelledNotificationParams do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [])

  defschema %{
    description: ~SD"""
    Parameters for a `notifications/cancelled` notification.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      reason:
        string(
          description: ~SD"""
          An optional string describing the reason for the cancellation. This
          MAY be logged or presented to the user.
          """
        ),
      requestId: GenMCP.MCP.V2607.RequestId
    },
    title: "MCP:CancelledNotificationParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ClientCapabilities do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [])

  defschema %{
    description: ~SD"""
    Capabilities a client may support. Known capabilities are defined
    here, in this schema, but this is not a closed set: any client can
    define its own, additional capabilities.
    """,
    properties: %{
      elicitation: %{
        description: ~SD"""
        Present if the client supports elicitation from the server.
        """,
        properties: %{
          form: GenMCP.MCP.V2607.JSONObject,
          url: GenMCP.MCP.V2607.JSONObject
        },
        type: "object"
      },
      experimental: %{
        additionalProperties: GenMCP.MCP.V2607.JSONObject,
        description: ~SD"""
        Experimental, non-standard capabilities that the client supports.
        """,
        type: "object"
      },
      extensions: %{
        additionalProperties: GenMCP.MCP.V2607.JSONObject,
        description: ~SD"""
        Optional MCP extensions that the client supports. Keys are extension
        identifiers (e.g.,
        "io.modelcontextprotocol/oauth-client-credentials"), and values are
        per-extension settings objects. An empty object indicates support with
        no settings.
        """,
        type: "object"
      },
      roots: %{
        description: "Present if the client supports listing roots.",
        properties: %{},
        type: "object"
      },
      sampling: %{
        description: ~SD"""
        Present if the client supports sampling from an LLM.
        """,
        properties: %{
          context: GenMCP.MCP.V2607.JSONObject,
          tools: GenMCP.MCP.V2607.JSONObject
        },
        type: "object"
      }
    },
    title: "MCP:ClientCapabilities",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ContentBlock do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMCP.MCP.V2607.TextContent,
        GenMCP.MCP.V2607.ImageContent,
        GenMCP.MCP.V2607.AudioContent,
        GenMCP.MCP.V2607.ResourceLink,
        GenMCP.MCP.V2607.EmbeddedResource
      ],
      title: "MCP:ContentBlock"
    }
  end
end

defmodule GenMCP.MCP.V2607.CreateMessageRequest do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:method, :params])

  defschema %{
    description: ~SD"""
    A request from the server to sample an LLM via the client. The client
    has full discretion over which model to select. The client should also
    inform the user before beginning sampling, to allow them to inspect
    the request (human in the loop) and decide whether to approve it.
    """,
    properties: %{
      method: const("sampling/createMessage"),
      params: GenMCP.MCP.V2607.CreateMessageRequestParams
    },
    required: [:method, :params],
    title: "MCP:CreateMessageRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.CreateMessageRequestParams do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:maxTokens, :messages])

  defschema %{
    description: "Parameters for a `sampling/createMessage` request.",
    properties: %{
      includeContext: string_enum_to_atom([:allServers, :none, :thisServer]),
      maxTokens:
        integer(
          description: ~SD"""
          The requested maximum number of tokens to sample (to prevent runaway
          completions).

          The client MAY choose to sample fewer tokens than the requested
          maximum.
          """
        ),
      messages: array_of(GenMCP.MCP.V2607.SamplingMessage),
      metadata: GenMCP.MCP.V2607.JSONObject,
      modelPreferences: GenMCP.MCP.V2607.ModelPreferences,
      stopSequences: array_of(string()),
      systemPrompt:
        string(
          description: ~SD"""
          An optional system prompt the server wants to use for sampling. The
          client MAY modify or omit this prompt.
          """
        ),
      temperature: number(),
      toolChoice: GenMCP.MCP.V2607.ToolChoice,
      tools: %{
        description: ~SD"""
        Tools that the model may use during generation. The client MUST return
        an error if this field is provided but {@link
        ClientCapabilities.sampling.tools} is not declared.
        """,
        items: GenMCP.MCP.V2607.Tool,
        type: "array"
      }
    },
    required: [:maxTokens, :messages],
    title: "MCP:CreateMessageRequestParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.CreateMessageResult do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:content, :model, :role])

  defschema %{
    description: ~SD"""
    The result returned by the client for a {@link
    CreateMessageRequestsampling/createMessage} request. The client should
    inform the user before returning the sampled message, to allow them to
    inspect the response (human in the loop) and decide whether to allow
    the server to see it.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      content: %{
        anyOf: [
          GenMCP.MCP.V2607.TextContent,
          GenMCP.MCP.V2607.ImageContent,
          GenMCP.MCP.V2607.AudioContent,
          GenMCP.MCP.V2607.ToolUseContent,
          GenMCP.MCP.V2607.ToolResultContent,
          array_of(GenMCP.MCP.V2607.SamplingMessageContentBlock)
        ]
      },
      model: string(description: "The name of the model that generated the message."),
      role: GenMCP.MCP.V2607.Role,
      stopReason:
        string(
          description: ~SD"""
          The reason why sampling stopped, if known.

          Standard values: - `"endTurn"`: Natural end of the assistant's turn -
          `"stopSequence"`: A stop sequence was encountered - `"maxTokens"`:
          Maximum token limit was reached - `"toolUse"`: The model wants to use
          one or more tools

          This field is an open string to allow for provider-specific stop
          reasons.
          """
        )
    },
    required: [:content, :model, :role],
    title: "MCP:CreateMessageResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.DiscoverRequest do
  use JSV.Schema

  JsonDerive.auto(
    _merge = %{method: "server/discover", jsonrpc: "2.0"},
    _keep_nils = [:id, :params]
  )

  @skip_keys [:jsonrpc, :method]

  defschema %{
    description: ~SD"""
    A request from the client asking the server to advertise its supported
    protocol versions, capabilities, and other metadata. Servers **MUST**
    implement `server/discover`. Clients **MAY** call it but are not
    required to — version negotiation can also happen inline via
    per-request `_meta`.
    """,
    properties: %{
      id: GenMCP.MCP.V2607.RequestId,
      jsonrpc: const("2.0"),
      method: const("server/discover"),
      params: GenMCP.MCP.V2607.RequestParams
    },
    required: [:id, :jsonrpc, :method, :params],
    title: "MCP:DiscoverRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.DiscoverResult do
  use JSV.Schema

  JsonDerive.auto(
    _merge = %{},
    _keep_nils = [:capabilities, :resultType, :serverInfo, :supportedVersions]
  )

  defschema %{
    description: ~SD"""
    The result returned by the server for a {@link
    DiscoverRequestserver/discover} request.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      capabilities: GenMCP.MCP.V2607.ServerCapabilities,
      instructions:
        string(
          description: ~SD"""
          Natural-language guidance describing the server and its features.

          This can be used by clients to improve an LLM's understanding of
          available tools (e.g., by including it in a system prompt). It should
          focus on information that helps the model use the server effectively
          and should not duplicate information already in tool descriptions.
          """
        ),
      resultType:
        string(
          description: ~SD"""
          Indicates the type of the result, which allows the client to determine
          how to parse the result object.

          Servers implementing this protocol version MUST include this field.
          For backward compatibility, when a client receives a result from a
          server implementing an earlier protocol version (which does not
          include `resultType`), the client MUST treat the absent field as
          `"complete"`.
          """
        ),
      serverInfo: GenMCP.MCP.V2607.Implementation,
      supportedVersions: %{
        description: ~SD"""
        MCP Protocol Versions this server supports. The client should choose a
        version from this list for use in subsequent requests.
        """,
        items: string(),
        type: "array"
      }
    },
    required: [:capabilities, :resultType, :serverInfo, :supportedVersions],
    title: "MCP:DiscoverResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ElicitRequest do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:method, :params])

  defschema %{
    description: ~SD"""
    A request from the server to elicit additional information from the
    user via the client.
    """,
    properties: %{
      method: const("elicitation/create"),
      params: GenMCP.MCP.V2607.ElicitRequestParams
    },
    required: [:method, :params],
    title: "MCP:ElicitRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ElicitRequestFormParams do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:message, :requestedSchema])

  defschema %{
    description: ~SD"""
    The parameters for a request to elicit non-sensitive information from
    the user via a form in the client.
    """,
    properties: %{
      message:
        string(
          description: ~SD"""
          The message to present to the user describing what information is
          being requested.
          """
        ),
      mode: const("form", description: "The elicitation mode."),
      requestedSchema: %{
        description: ~SD"""
        A restricted subset of JSON Schema. Only top-level properties are
        allowed, without nesting.
        """,
        properties: %{
          "$schema": string(),
          properties: %{additionalProperties: %{}, type: "object"},
          required: array_of(string()),
          type: const("object")
        },
        required: ["properties", "type"],
        type: "object"
      }
    },
    required: [:message, :requestedSchema],
    title: "MCP:ElicitRequestFormParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ElicitRequestParams do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [GenMCP.MCP.V2607.ElicitRequestFormParams, GenMCP.MCP.V2607.ElicitRequestURLParams],
      description: ~SD"""
      The parameters for a request to elicit additional information from the
      user via the client.
      """,
      title: "MCP:ElicitRequestParams"
    }
  end
end

defmodule GenMCP.MCP.V2607.ElicitRequestURLParams do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:elicitationId, :message, :mode, :url])

  defschema %{
    description: ~SD"""
    The parameters for a request to elicit information from the user via a
    URL in the client.
    """,
    properties: %{
      elicitationId:
        string(
          description: ~SD"""
          The ID of the elicitation, which must be unique within the context of
          the server. The client MUST treat this ID as an opaque value.
          """
        ),
      message:
        string(
          description: ~SD"""
          The message to present to the user explaining why the interaction is
          needed.
          """
        ),
      mode: const("url", description: "The elicitation mode."),
      url: uri(description: "The URL that the user should navigate to.")
    },
    required: [:elicitationId, :message, :mode, :url],
    title: "MCP:ElicitRequestURLParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ElicitResult do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:action])

  defschema %{
    description: ~SD"""
    The result returned by the client for an {@link
    ElicitRequestelicitation/create} request.
    """,
    properties: %{
      action: string_enum_to_atom([:accept, :cancel, :decline]),
      content: %{
        additionalProperties: %{
          anyOf: [array_of(string()), %{type: ["string", "integer", "boolean"]}]
        },
        description: ~SD"""
        The submitted form data, only present when action is `"accept"` and
        mode was `"form"`. Contains values matching the requested schema.
        Omitted for out-of-band mode responses.
        """,
        type: "object"
      }
    },
    required: [:action],
    title: "MCP:ElicitResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.EmbeddedResource do
  use JSV.Schema

  JsonDerive.auto(_merge = %{type: "resource"}, _keep_nils = [:resource])

  @skip_keys [:type]

  defschema %{
    description: ~SD"""
    The contents of a resource, embedded into a prompt or tool call
    result.

    It is up to the client how best to render embedded resources for the
    benefit of the LLM and/or the user.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      annotations: GenMCP.MCP.V2607.Annotations,
      resource: %{
        anyOf: [GenMCP.MCP.V2607.TextResourceContents, GenMCP.MCP.V2607.BlobResourceContents]
      },
      type: const("resource")
    },
    required: [:resource, :type],
    title: "MCP:EmbeddedResource",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.Error do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:code, :message])

  defschema %{
    properties: %{
      code: integer(description: "The error type that occurred."),
      data: %{
        description: ~SD"""
        Additional information about the error. The value of this member is
        defined by the sender (e.g. detailed error information, nested errors
        etc.).
        """
      },
      message:
        string(
          description: ~SD"""
          A short description of the error. The message SHOULD be limited to a
          concise single sentence.
          """
        )
    },
    required: [:code, :message],
    title: "MCP:Error",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.GetPromptRequest do
  use JSV.Schema

  JsonDerive.auto(_merge = %{method: "prompts/get", jsonrpc: "2.0"}, _keep_nils = [:id, :params])

  @skip_keys [:jsonrpc, :method]

  defschema %{
    description: ~SD"""
    Used by the client to get a prompt provided by the server.
    """,
    properties: %{
      id: GenMCP.MCP.V2607.RequestId,
      jsonrpc: const("2.0"),
      method: const("prompts/get"),
      params: GenMCP.MCP.V2607.GetPromptRequestParams
    },
    required: [:id, :jsonrpc, :method, :params],
    title: "MCP:GetPromptRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.GetPromptRequestParams do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:_meta, :name])

  defschema %{
    description: "Parameters for a `prompts/get` request.",
    properties: %{
      _meta: GenMCP.MCP.V2607.RequestMetaObject,
      arguments: %{
        additionalProperties: string(),
        description: "Arguments to use for templating the prompt.",
        type: "object"
      },
      inputResponses: GenMCP.MCP.V2607.InputResponses,
      name: string(description: "The name of the prompt or prompt template."),
      requestState: string()
    },
    required: [:_meta, :name],
    title: "MCP:GetPromptRequestParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.GetPromptResult do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:messages, :resultType])

  defschema %{
    description: ~SD"""
    The result returned by the server for a {@link
    GetPromptRequestprompts/get} request.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      description: string(description: "An optional description for the prompt."),
      messages: array_of(GenMCP.MCP.V2607.PromptMessage),
      resultType:
        string(
          description: ~SD"""
          Indicates the type of the result, which allows the client to determine
          how to parse the result object.

          Servers implementing this protocol version MUST include this field.
          For backward compatibility, when a client receives a result from a
          server implementing an earlier protocol version (which does not
          include `resultType`), the client MUST treat the absent field as
          `"complete"`.
          """
        )
    },
    required: [:messages, :resultType],
    title: "MCP:GetPromptResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.Icon do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:src])

  defschema %{
    description: ~SD"""
    An optionally-sized icon that can be displayed in a user interface.
    """,
    properties: %{
      mimeType:
        string(
          description: ~SD"""
          Optional MIME type override if the source MIME type is missing or
          generic. For example: `"image/png"`, `"image/jpeg"`, or
          `"image/svg+xml"`.
          """
        ),
      sizes: %{
        description: ~SD"""
        Optional array of strings that specify sizes at which the icon can be
        used. Each string should be in WxH format (e.g., `"48x48"`, `"96x96"`)
        or `"any"` for scalable formats like SVG.

        If not provided, the client should assume that the icon can be used at
        any size.
        """,
        items: string(),
        type: "array"
      },
      src:
        uri(
          description: ~SD"""
          A standard URI pointing to an icon resource. May be an HTTP/HTTPS URL
          or a `data:` URI with Base64-encoded image data.

          Consumers SHOULD take steps to ensure URLs serving icons are from the
          same domain as the client/server or a trusted domain.

          Consumers SHOULD take appropriate precautions when consuming SVGs as
          they can contain executable JavaScript.
          """
        ),
      theme: string_enum_to_atom([:dark, :light])
    },
    required: [:src],
    title: "MCP:Icon",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.Icons do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [])

  defschema %{
    description: "Base interface to add `icons` property.",
    properties: %{
      icons: %{
        description: ~SD"""
        Optional set of sized icons that the client can display in a user
        interface.

        Clients that support rendering icons MUST support at least the
        following MIME types: - `image/png` - PNG images (safe, universal
        compatibility) - `image/jpeg` (and `image/jpg`) - JPEG images (safe,
        universal compatibility)

        Clients that support rendering icons SHOULD also support: -
        `image/svg+xml` - SVG images (scalable but requires security
        precautions) - `image/webp` - WebP images (modern, efficient format)
        """,
        items: GenMCP.MCP.V2607.Icon,
        type: "array"
      }
    },
    title: "MCP:Icons",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ImageContent do
  use JSV.Schema

  JsonDerive.auto(_merge = %{type: "image"}, _keep_nils = [:data, :mimeType])

  @skip_keys [:type]

  defschema %{
    description: "An image provided to or from an LLM.",
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      annotations: GenMCP.MCP.V2607.Annotations,
      data: string_of("byte", description: "The base64-encoded image data."),
      mimeType:
        string(
          description: ~SD"""
          The MIME type of the image. Different providers may support different
          image types.
          """
        ),
      type: const("image")
    },
    required: [:data, :mimeType, :type],
    title: "MCP:ImageContent",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.Implementation do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:name, :version])

  defschema %{
    description: "Describes the MCP implementation.",
    properties: %{
      description:
        string(
          description: ~SD"""
          An optional human-readable description of what this implementation
          does.

          This can be used by clients or servers to provide context about their
          purpose and capabilities. For example, a server might describe the
          types of resources or tools it provides, while a client might describe
          its intended use case.
          """
        ),
      icons: %{
        description: ~SD"""
        Optional set of sized icons that the client can display in a user
        interface.

        Clients that support rendering icons MUST support at least the
        following MIME types: - `image/png` - PNG images (safe, universal
        compatibility) - `image/jpeg` (and `image/jpg`) - JPEG images (safe,
        universal compatibility)

        Clients that support rendering icons SHOULD also support: -
        `image/svg+xml` - SVG images (scalable but requires security
        precautions) - `image/webp` - WebP images (modern, efficient format)
        """,
        items: GenMCP.MCP.V2607.Icon,
        type: "array"
      },
      name:
        string(
          description: ~SD"""
          Intended for programmatic or logical use, but used as a display name
          in past specs or fallback (if title isn't present).
          """
        ),
      title:
        string(
          description: ~SD"""
          Intended for UI and end-user contexts — optimized to be human-readable
          and easily understood, even by those unfamiliar with domain-specific
          terminology.

          If not provided, the name should be used for display (except for
          {@link Tool}, where `annotations.title` should be given precedence
          over using `name`, if present).
          """
        ),
      version: string(description: "The version of this implementation."),
      websiteUrl:
        uri(
          description: ~SD"""
          An optional URL of the website for this implementation.
          """
        )
    },
    required: [:name, :version],
    title: "MCP:Implementation",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.InputRequest do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMCP.MCP.V2607.CreateMessageRequest,
        GenMCP.MCP.V2607.ListRootsRequest,
        GenMCP.MCP.V2607.ElicitRequest
      ],
      title: "MCP:InputRequest"
    }
  end
end

defmodule GenMCP.MCP.V2607.InputRequests do
  use JSV.Schema

  def json_schema do
    %{
      additionalProperties: GenMCP.MCP.V2607.InputRequest,
      description: ~SD"""
      A map of server-initiated requests that the client must fulfill. Keys
      are server-assigned identifiers; values are the request objects.
      """,
      title: "MCP:InputRequests",
      type: "object"
    }
  end
end

defmodule GenMCP.MCP.V2607.InputRequiredResult do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:resultType])

  defschema %{
    description: ~SD"""
    An InputRequiredResult sent by the server to indicate that additional
    input is needed before the request can be completed.

    At least one of `inputRequests` or `requestState` MUST be present.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      inputRequests: GenMCP.MCP.V2607.InputRequests,
      requestState: string(),
      resultType:
        string(
          description: ~SD"""
          Indicates the type of the result, which allows the client to determine
          how to parse the result object.

          Servers implementing this protocol version MUST include this field.
          For backward compatibility, when a client receives a result from a
          server implementing an earlier protocol version (which does not
          include `resultType`), the client MUST treat the absent field as
          `"complete"`.
          """
        )
    },
    required: [:resultType],
    title: "MCP:InputRequiredResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.InputResponse do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMCP.MCP.V2607.CreateMessageResult,
        GenMCP.MCP.V2607.ListRootsResult,
        GenMCP.MCP.V2607.ElicitResult
      ],
      title: "MCP:InputResponse"
    }
  end
end

defmodule GenMCP.MCP.V2607.InputResponseRequestParams do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:_meta])

  defschema %{
    properties: %{
      _meta: GenMCP.MCP.V2607.RequestMetaObject,
      inputResponses: GenMCP.MCP.V2607.InputResponses,
      requestState: string()
    },
    required: [:_meta],
    title: "MCP:InputResponseRequestParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.InputResponses do
  use JSV.Schema

  def json_schema do
    %{
      additionalProperties: GenMCP.MCP.V2607.InputResponse,
      description: ~SD"""
      A map of client responses to server-initiated requests. Keys
      correspond to the keys in the {@link InputRequests} map; values are
      the client's result for each request.
      """,
      title: "MCP:InputResponses",
      type: "object"
    }
  end
end

defmodule GenMCP.MCP.V2607.JSONArray do
  use JSV.Schema

  def json_schema do
    %{items: GenMCP.MCP.V2607.JSONValue, title: "MCP:JSONArray", type: "array"}
  end
end

defmodule GenMCP.MCP.V2607.JSONObject do
  use JSV.Schema

  def json_schema do
    %{
      additionalProperties: GenMCP.MCP.V2607.JSONValue,
      title: "MCP:JSONObject",
      type: "object"
    }
  end
end

defmodule GenMCP.MCP.V2607.JSONRPCErrorResponse do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:error, :id, :jsonrpc])

  defschema %{
    description: ~SD"""
    A response to a request that indicates an error occurred.
    """,
    properties: %{
      error: GenMCP.MCP.V2607.Error,
      id: GenMCP.MCP.V2607.RequestId,
      jsonrpc: const("2.0")
    },
    required: [:error, :jsonrpc],
    title: "MCP:JSONRPCErrorResponse",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.JSONRPCRequest do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:id, :jsonrpc, :method])

  defschema %{
    description: "A request that expects a response.",
    properties: %{
      id: GenMCP.MCP.V2607.RequestId,
      jsonrpc: const("2.0"),
      method: string(),
      params: %{additionalProperties: %{}, type: "object"}
    },
    required: [:id, :jsonrpc, :method],
    title: "MCP:JSONRPCRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.JSONRPCResponse do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [GenMCP.MCP.V2607.JSONRPCResultResponse, GenMCP.MCP.V2607.JSONRPCErrorResponse],
      description: ~SD"""
      A response to a request, containing either the result or error.
      """,
      title: "MCP:JSONRPCResponse"
    }
  end
end

defmodule GenMCP.MCP.V2607.JSONRPCResultResponse do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:id, :jsonrpc, :result])

  defschema %{
    description: "A successful (non-error) response to a request.",
    properties: %{
      id: GenMCP.MCP.V2607.RequestId,
      jsonrpc: const("2.0"),
      result: GenMCP.MCP.V2607.Result
    },
    required: [:id, :jsonrpc, :result],
    title: "MCP:JSONRPCResultResponse",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.JSONValue do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMCP.MCP.V2607.JSONObject,
        array_of(GenMCP.MCP.V2607.JSONValue),
        %{type: ["string", "integer", "boolean"]}
      ],
      title: "MCP:JSONValue"
    }
  end
end

defmodule GenMCP.MCP.V2607.ListPromptsRequest do
  use JSV.Schema

  JsonDerive.auto(_merge = %{method: "prompts/list", jsonrpc: "2.0"}, _keep_nils = [:id, :params])

  @skip_keys [:jsonrpc, :method]

  defschema %{
    description: ~SD"""
    Sent from the client to request a list of prompts and prompt templates
    the server has.
    """,
    properties: %{
      id: GenMCP.MCP.V2607.RequestId,
      jsonrpc: const("2.0"),
      method: const("prompts/list"),
      params: GenMCP.MCP.V2607.PaginatedRequestParams
    },
    required: [:id, :jsonrpc, :method, :params],
    title: "MCP:ListPromptsRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ListPromptsResult do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:cacheScope, :prompts, :resultType, :ttlMs])

  defschema %{
    description: ~SD"""
    The result returned by the server for a {@link
    ListPromptsRequestprompts/list} request.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      cacheScope: string_enum_to_atom([:private, :public]),
      nextCursor:
        string(
          description: ~SD"""
          An opaque token representing the pagination position after the last
          returned result. If present, there may be more results available.
          """
        ),
      prompts: array_of(GenMCP.MCP.V2607.Prompt),
      resultType:
        string(
          description: ~SD"""
          Indicates the type of the result, which allows the client to determine
          how to parse the result object.

          Servers implementing this protocol version MUST include this field.
          For backward compatibility, when a client receives a result from a
          server implementing an earlier protocol version (which does not
          include `resultType`), the client MUST treat the absent field as
          `"complete"`.
          """
        ),
      ttlMs: %{
        description: ~SD"""
        A hint from the server indicating how long (in milliseconds) the
        client MAY cache this response before re-fetching. Semantics are
        analogous to HTTP Cache-Control max-age.

        - If 0, The response SHOULD be considered immediately stale, The
        client MAY re-fetch every time the result is needed. - If positive,
        the client SHOULD consider the result fresh for this many milliseconds
        after receiving the response.
        """,
        minimum: 0,
        type: "integer"
      }
    },
    required: [:cacheScope, :prompts, :resultType, :ttlMs],
    title: "MCP:ListPromptsResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ListResourceTemplatesRequest do
  use JSV.Schema

  JsonDerive.auto(
    _merge = %{method: "resources/templates/list", jsonrpc: "2.0"},
    _keep_nils = [:id, :params]
  )

  @skip_keys [:jsonrpc, :method]

  defschema %{
    description: ~SD"""
    Sent from the client to request a list of resource templates the
    server has.
    """,
    properties: %{
      id: GenMCP.MCP.V2607.RequestId,
      jsonrpc: const("2.0"),
      method: const("resources/templates/list"),
      params: GenMCP.MCP.V2607.PaginatedRequestParams
    },
    required: [:id, :jsonrpc, :method, :params],
    title: "MCP:ListResourceTemplatesRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ListResourceTemplatesResult do
  use JSV.Schema

  JsonDerive.auto(
    _merge = %{},
    _keep_nils = [:cacheScope, :resourceTemplates, :resultType, :ttlMs]
  )

  defschema %{
    description: ~SD"""
    The result returned by the server for a {@link
    ListResourceTemplatesRequestresources/templates/list} request.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      cacheScope: string_enum_to_atom([:private, :public]),
      nextCursor:
        string(
          description: ~SD"""
          An opaque token representing the pagination position after the last
          returned result. If present, there may be more results available.
          """
        ),
      resourceTemplates: array_of(GenMCP.MCP.V2607.ResourceTemplate),
      resultType:
        string(
          description: ~SD"""
          Indicates the type of the result, which allows the client to determine
          how to parse the result object.

          Servers implementing this protocol version MUST include this field.
          For backward compatibility, when a client receives a result from a
          server implementing an earlier protocol version (which does not
          include `resultType`), the client MUST treat the absent field as
          `"complete"`.
          """
        ),
      ttlMs: %{
        description: ~SD"""
        A hint from the server indicating how long (in milliseconds) the
        client MAY cache this response before re-fetching. Semantics are
        analogous to HTTP Cache-Control max-age.

        - If 0, The response SHOULD be considered immediately stale, The
        client MAY re-fetch every time the result is needed. - If positive,
        the client SHOULD consider the result fresh for this many milliseconds
        after receiving the response.
        """,
        minimum: 0,
        type: "integer"
      }
    },
    required: [:cacheScope, :resourceTemplates, :resultType, :ttlMs],
    title: "MCP:ListResourceTemplatesResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ListResourcesRequest do
  use JSV.Schema

  JsonDerive.auto(
    _merge = %{method: "resources/list", jsonrpc: "2.0"},
    _keep_nils = [:id, :params]
  )

  @skip_keys [:jsonrpc, :method]

  defschema %{
    description: ~SD"""
    Sent from the client to request a list of resources the server has.
    """,
    properties: %{
      id: GenMCP.MCP.V2607.RequestId,
      jsonrpc: const("2.0"),
      method: const("resources/list"),
      params: GenMCP.MCP.V2607.PaginatedRequestParams
    },
    required: [:id, :jsonrpc, :method, :params],
    title: "MCP:ListResourcesRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ListResourcesResult do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:cacheScope, :resources, :resultType, :ttlMs])

  defschema %{
    description: ~SD"""
    The result returned by the server for a {@link
    ListResourcesRequestresources/list} request.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      cacheScope: string_enum_to_atom([:private, :public]),
      nextCursor:
        string(
          description: ~SD"""
          An opaque token representing the pagination position after the last
          returned result. If present, there may be more results available.
          """
        ),
      resources: array_of(GenMCP.MCP.V2607.Resource),
      resultType:
        string(
          description: ~SD"""
          Indicates the type of the result, which allows the client to determine
          how to parse the result object.

          Servers implementing this protocol version MUST include this field.
          For backward compatibility, when a client receives a result from a
          server implementing an earlier protocol version (which does not
          include `resultType`), the client MUST treat the absent field as
          `"complete"`.
          """
        ),
      ttlMs: %{
        description: ~SD"""
        A hint from the server indicating how long (in milliseconds) the
        client MAY cache this response before re-fetching. Semantics are
        analogous to HTTP Cache-Control max-age.

        - If 0, The response SHOULD be considered immediately stale, The
        client MAY re-fetch every time the result is needed. - If positive,
        the client SHOULD consider the result fresh for this many milliseconds
        after receiving the response.
        """,
        minimum: 0,
        type: "integer"
      }
    },
    required: [:cacheScope, :resources, :resultType, :ttlMs],
    title: "MCP:ListResourcesResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ListRootsRequest do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:method])

  defschema %{
    description: ~SD"""
    Sent from the server to request a list of root URIs from the client.
    Roots allow servers to ask for specific directories or files to
    operate on. A common example for roots is providing a set of
    repositories or directories a server should operate on.

    This request is typically used when the server needs to understand the
    file system structure or access specific locations that the client has
    permission to read from.
    """,
    properties: %{
      method: const("roots/list"),
      params: GenMCP.MCP.V2607.RequestParams
    },
    required: [:method],
    title: "MCP:ListRootsRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ListRootsResult do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:roots])

  defschema %{
    description: ~SD"""
    The result returned by the client for a {@link
    ListRootsRequestroots/list} request. This result contains an array of
    {@link Root} objects, each representing a root directory or file that
    the server can operate on.
    """,
    properties: %{roots: array_of(GenMCP.MCP.V2607.Root)},
    required: [:roots],
    title: "MCP:ListRootsResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ListToolsRequest do
  use JSV.Schema

  JsonDerive.auto(_merge = %{method: "tools/list", jsonrpc: "2.0"}, _keep_nils = [:id, :params])

  @skip_keys [:jsonrpc, :method]

  defschema %{
    description: ~SD"""
    Sent from the client to request a list of tools the server has.
    """,
    properties: %{
      id: GenMCP.MCP.V2607.RequestId,
      jsonrpc: const("2.0"),
      method: const("tools/list"),
      params: GenMCP.MCP.V2607.PaginatedRequestParams
    },
    required: [:id, :jsonrpc, :method, :params],
    title: "MCP:ListToolsRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ListToolsResult do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:cacheScope, :resultType, :tools, :ttlMs])

  defschema %{
    description: ~SD"""
    The result returned by the server for a {@link
    ListToolsRequesttools/list} request.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      cacheScope: string_enum_to_atom([:private, :public]),
      nextCursor:
        string(
          description: ~SD"""
          An opaque token representing the pagination position after the last
          returned result. If present, there may be more results available.
          """
        ),
      resultType:
        string(
          description: ~SD"""
          Indicates the type of the result, which allows the client to determine
          how to parse the result object.

          Servers implementing this protocol version MUST include this field.
          For backward compatibility, when a client receives a result from a
          server implementing an earlier protocol version (which does not
          include `resultType`), the client MUST treat the absent field as
          `"complete"`.
          """
        ),
      tools: array_of(GenMCP.MCP.V2607.Tool),
      ttlMs: %{
        description: ~SD"""
        A hint from the server indicating how long (in milliseconds) the
        client MAY cache this response before re-fetching. Semantics are
        analogous to HTTP Cache-Control max-age.

        - If 0, The response SHOULD be considered immediately stale, The
        client MAY re-fetch every time the result is needed. - If positive,
        the client SHOULD consider the result fresh for this many milliseconds
        after receiving the response.
        """,
        minimum: 0,
        type: "integer"
      }
    },
    required: [:cacheScope, :resultType, :tools, :ttlMs],
    title: "MCP:ListToolsResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.LoggingLevel do
  use JSV.Schema

  def json_schema do
    string_enum_to_atom([:alert, :critical, :debug, :emergency, :error, :info, :notice, :warning])
  end
end

defmodule GenMCP.MCP.V2607.LoggingMessageNotification do
  use JSV.Schema

  JsonDerive.auto(
    _merge = %{method: "notifications/message", jsonrpc: "2.0"},
    _keep_nils = [:params]
  )

  @skip_keys [:jsonrpc, :method]

  defschema %{
    description: ~SD"""
    JSONRPCNotification of a log message passed from server to client. The
    client opts in by setting `"io.modelcontextprotocol/logLevel"` in a
    request's `_meta`.
    """,
    properties: %{
      jsonrpc: const("2.0"),
      method: const("notifications/message"),
      params: GenMCP.MCP.V2607.LoggingMessageNotificationParams
    },
    required: [:jsonrpc, :method, :params],
    title: "MCP:LoggingMessageNotification",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.LoggingMessageNotificationParams do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:data, :level])

  defschema %{
    description: ~SD"""
    Parameters for a `notifications/message` notification.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      data: %{
        description: ~SD"""
        The data to be logged, such as a string message or an object. Any JSON
        serializable type is allowed here.
        """
      },
      level: GenMCP.MCP.V2607.LoggingLevel,
      logger:
        string(
          description: ~SD"""
          An optional name of the logger issuing this message.
          """
        )
    },
    required: [:data, :level],
    title: "MCP:LoggingMessageNotificationParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.MetaObject do
  use JSV.Schema

  def json_schema do
    %{
      description: ~SD"""
      Represents the contents of a `_meta` field, which clients and servers
      use to attach additional metadata to their interactions.

      Certain key names are reserved by MCP for protocol-level metadata;
      implementations MUST NOT make assumptions about values at these keys.
      Additionally, specific schema definitions may reserve particular names
      for purpose-specific metadata, as declared in those definitions.

      Valid keys have two segments:

      **Prefix:** - Optional — if specified, MUST be a series of _labels_
      separated by dots (`.`), followed by a slash (`/`). - Labels MUST
      start with a letter and end with a letter or digit. Interior
      characters may be letters, digits, or hyphens (`-`). - Implementations
      SHOULD use reverse DNS notation (e.g., `com.example/` rather than
      `example.com/`). - Any prefix where the second label is
      `modelcontextprotocol` or `mcp` is **reserved** for MCP use. For
      example: `io.modelcontextprotocol/`, `dev.mcp/`,
      `org.modelcontextprotocol.api/`, and `com.mcp.tools/` are all
      reserved. However, `com.example.mcp/` is NOT reserved, as the second
      label is `example`.

      **Name:** - Unless empty, MUST start and end with an alphanumeric
      character (`[a-z0-9A-Z]`). - Interior characters may be alphanumeric,
      hyphens (`-`), underscores (`_`), or dots (`.`).
      """,
      title: "MCP:MetaObject",
      type: "object"
    }
  end
end

defmodule GenMCP.MCP.V2607.ModelHint do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [])

  defschema %{
    description: ~SD"""
    Hints to use for model selection.

    Keys not declared here are currently left unspecified by the spec and
    are up to the client to interpret.
    """,
    properties: %{
      name:
        string(
          description: ~SD"""
          A hint for a model name.

          The client SHOULD treat this as a substring of a model name; for
          example: - `claude-3-5-sonnet` should match
          `claude-3-5-sonnet-20241022` - `sonnet` should match
          `claude-3-5-sonnet-20241022`, `claude-3-sonnet-20240229`, etc. -
          `claude` should match any Claude model

          The client MAY also map the string to a different provider's model
          name or a different model family, as long as it fills a similar niche;
          for example: - `gemini-1.5-flash` could match
          `claude-3-haiku-20240307`
          """
        )
    },
    title: "MCP:ModelHint",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ModelPreferences do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [])

  defschema %{
    description: ~SD"""
    The server's preferences for model selection, requested of the client
    during sampling.

    Because LLMs can vary along multiple dimensions, choosing the "best"
    model is rarely straightforward. Different models excel in different
    areas—some are faster but less capable, others are more capable but
    more expensive, and so on. This interface allows servers to express
    their priorities across multiple dimensions to help clients make an
    appropriate selection for their use case.

    These preferences are always advisory. The client MAY ignore them. It
    is also up to the client to decide how to interpret these preferences
    and how to balance them against other considerations.
    """,
    properties: %{
      costPriority: %{
        description: ~SD"""
        How much to prioritize cost when selecting a model. A value of 0 means
        cost is not important, while a value of 1 means cost is the most
        important factor.
        """,
        maximum: 1,
        minimum: 0,
        type: "number"
      },
      hints: %{
        description: ~SD"""
        Optional hints to use for model selection.

        If multiple hints are specified, the client MUST evaluate them in
        order (such that the first match is taken).

        The client SHOULD prioritize these hints over the numeric priorities,
        but MAY still use the priorities to select from ambiguous matches.
        """,
        items: GenMCP.MCP.V2607.ModelHint,
        type: "array"
      },
      intelligencePriority: %{
        description: ~SD"""
        How much to prioritize intelligence and capabilities when selecting a
        model. A value of 0 means intelligence is not important, while a value
        of 1 means intelligence is the most important factor.
        """,
        maximum: 1,
        minimum: 0,
        type: "number"
      },
      speedPriority: %{
        description: ~SD"""
        How much to prioritize sampling speed (latency) when selecting a
        model. A value of 0 means speed is not important, while a value of 1
        means speed is the most important factor.
        """,
        maximum: 1,
        minimum: 0,
        type: "number"
      }
    },
    title: "MCP:ModelPreferences",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.NotificationParams do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [])

  defschema %{
    description: "Common params for any notification.",
    properties: %{_meta: GenMCP.MCP.V2607.MetaObject},
    title: "MCP:NotificationParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.PaginatedRequestParams do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:_meta])

  defschema %{
    description: "Common params for paginated requests.",
    properties: %{
      _meta: GenMCP.MCP.V2607.RequestMetaObject,
      cursor:
        string(
          description: ~SD"""
          An opaque token representing the current pagination position. If
          provided, the server should return results starting after this cursor.
          """
        )
    },
    required: [:_meta],
    title: "MCP:PaginatedRequestParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ProgressNotification do
  use JSV.Schema

  JsonDerive.auto(
    _merge = %{method: "notifications/progress", jsonrpc: "2.0"},
    _keep_nils = [:params]
  )

  @skip_keys [:jsonrpc, :method]

  defschema %{
    description: ~SD"""
    An out-of-band notification used to inform the receiver of a progress
    update for a long-running request.
    """,
    properties: %{
      jsonrpc: const("2.0"),
      method: const("notifications/progress"),
      params: GenMCP.MCP.V2607.ProgressNotificationParams
    },
    required: [:jsonrpc, :method, :params],
    title: "MCP:ProgressNotification",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ProgressNotificationParams do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:progress, :progressToken])

  defschema %{
    description: ~SD"""
    Parameters for a {@link ProgressNotificationnotifications/progress}
    notification.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      message:
        string(
          description: ~SD"""
          An optional message describing the current progress.
          """
        ),
      progress:
        number(
          description: ~SD"""
          The progress thus far. This should increase every time progress is
          made, even if the total is unknown.
          """
        ),
      progressToken: GenMCP.MCP.V2607.ProgressToken,
      total:
        number(
          description: ~SD"""
          Total number of items to process (or total progress required), if
          known.
          """
        )
    },
    required: [:progress, :progressToken],
    title: "MCP:ProgressNotificationParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ProgressToken do
  use JSV.Schema

  def json_schema do
    %{
      description: ~SD"""
      A progress token, used to associate progress notifications with the
      original request.
      """,
      title: "MCP:ProgressToken",
      type: ["string", "integer"]
    }
  end
end

defmodule GenMCP.MCP.V2607.Prompt do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:name])

  defschema %{
    description: ~SD"""
    A prompt or prompt template that the server offers.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      arguments: %{
        description: ~SD"""
        A list of arguments to use for templating the prompt.
        """,
        items: GenMCP.MCP.V2607.PromptArgument,
        type: "array"
      },
      description:
        string(
          description: ~SD"""
          An optional description of what this prompt provides
          """
        ),
      icons: %{
        description: ~SD"""
        Optional set of sized icons that the client can display in a user
        interface.

        Clients that support rendering icons MUST support at least the
        following MIME types: - `image/png` - PNG images (safe, universal
        compatibility) - `image/jpeg` (and `image/jpg`) - JPEG images (safe,
        universal compatibility)

        Clients that support rendering icons SHOULD also support: -
        `image/svg+xml` - SVG images (scalable but requires security
        precautions) - `image/webp` - WebP images (modern, efficient format)
        """,
        items: GenMCP.MCP.V2607.Icon,
        type: "array"
      },
      name:
        string(
          description: ~SD"""
          Intended for programmatic or logical use, but used as a display name
          in past specs or fallback (if title isn't present).
          """
        ),
      title:
        string(
          description: ~SD"""
          Intended for UI and end-user contexts — optimized to be human-readable
          and easily understood, even by those unfamiliar with domain-specific
          terminology.

          If not provided, the name should be used for display (except for
          {@link Tool}, where `annotations.title` should be given precedence
          over using `name`, if present).
          """
        )
    },
    required: [:name],
    title: "MCP:Prompt",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.PromptArgument do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:name])

  defschema %{
    description: "Describes an argument that a prompt can accept.",
    properties: %{
      description: string(description: "A human-readable description of the argument."),
      name:
        string(
          description: ~SD"""
          Intended for programmatic or logical use, but used as a display name
          in past specs or fallback (if title isn't present).
          """
        ),
      required: boolean(description: "Whether this argument must be provided."),
      title:
        string(
          description: ~SD"""
          Intended for UI and end-user contexts — optimized to be human-readable
          and easily understood, even by those unfamiliar with domain-specific
          terminology.

          If not provided, the name should be used for display (except for
          {@link Tool}, where `annotations.title` should be given precedence
          over using `name`, if present).
          """
        )
    },
    required: [:name],
    title: "MCP:PromptArgument",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.PromptMessage do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:content, :role])

  defschema %{
    description: ~SD"""
    Describes a message returned as part of a prompt.

    This is similar to {@link SamplingMessage}, but also supports the
    embedding of resources from the MCP server.
    """,
    properties: %{
      content: GenMCP.MCP.V2607.ContentBlock,
      role: GenMCP.MCP.V2607.Role
    },
    required: [:content, :role],
    title: "MCP:PromptMessage",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ReadResourceRequest do
  use JSV.Schema

  JsonDerive.auto(
    _merge = %{method: "resources/read", jsonrpc: "2.0"},
    _keep_nils = [:id, :params]
  )

  @skip_keys [:jsonrpc, :method]

  defschema %{
    description: ~SD"""
    Sent from the client to the server, to read a specific resource URI.
    """,
    properties: %{
      id: GenMCP.MCP.V2607.RequestId,
      jsonrpc: const("2.0"),
      method: const("resources/read"),
      params: GenMCP.MCP.V2607.ReadResourceRequestParams
    },
    required: [:id, :jsonrpc, :method, :params],
    title: "MCP:ReadResourceRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ReadResourceRequestParams do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:_meta, :uri])

  defschema %{
    description: "Parameters for a `resources/read` request.",
    properties: %{
      _meta: GenMCP.MCP.V2607.RequestMetaObject,
      inputResponses: GenMCP.MCP.V2607.InputResponses,
      requestState: string(),
      uri:
        uri(
          description: ~SD"""
          The URI of the resource. The URI can use any protocol; it is up to the
          server how to interpret it.
          """
        )
    },
    required: [:_meta, :uri],
    title: "MCP:ReadResourceRequestParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ReadResourceResult do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:cacheScope, :contents, :resultType, :ttlMs])

  defschema %{
    description: ~SD"""
    The result returned by the server for a {@link
    ReadResourceRequestresources/read} request.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      cacheScope: string_enum_to_atom([:private, :public]),
      contents:
        array_of(%{
          anyOf: [GenMCP.MCP.V2607.TextResourceContents, GenMCP.MCP.V2607.BlobResourceContents]
        }),
      resultType:
        string(
          description: ~SD"""
          Indicates the type of the result, which allows the client to determine
          how to parse the result object.

          Servers implementing this protocol version MUST include this field.
          For backward compatibility, when a client receives a result from a
          server implementing an earlier protocol version (which does not
          include `resultType`), the client MUST treat the absent field as
          `"complete"`.
          """
        ),
      ttlMs: %{
        description: ~SD"""
        A hint from the server indicating how long (in milliseconds) the
        client MAY cache this response before re-fetching. Semantics are
        analogous to HTTP Cache-Control max-age.

        - If 0, The response SHOULD be considered immediately stale, The
        client MAY re-fetch every time the result is needed. - If positive,
        the client SHOULD consider the result fresh for this many milliseconds
        after receiving the response.
        """,
        minimum: 0,
        type: "integer"
      }
    },
    required: [:cacheScope, :contents, :resultType, :ttlMs],
    title: "MCP:ReadResourceResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.RequestId do
  use JSV.Schema

  def json_schema do
    %{
      description: ~SD"""
      A uniquely identifying ID for a request in JSON-RPC.
      """,
      title: "MCP:RequestId",
      type: ["string", "integer"]
    }
  end
end

defmodule GenMCP.MCP.V2607.RequestMetaObject do
  use JSV.Schema

  JsonDerive.auto(
    _merge = %{},
    _keep_nils = [
      :"io.modelcontextprotocol/clientCapabilities",
      :"io.modelcontextprotocol/clientInfo",
      :"io.modelcontextprotocol/protocolVersion"
    ]
  )

  defschema %{
    description: ~SD"""
    Extends {@link MetaObject} with additional request-specific fields.
    All key naming rules from `MetaObject` apply.
    """,
    properties: %{
      "io.modelcontextprotocol/clientCapabilities": GenMCP.MCP.V2607.ClientCapabilities,
      "io.modelcontextprotocol/clientInfo": GenMCP.MCP.V2607.Implementation,
      "io.modelcontextprotocol/logLevel": GenMCP.MCP.V2607.LoggingLevel,
      "io.modelcontextprotocol/protocolVersion":
        string(
          description: ~SD"""
          The MCP Protocol Version being used for this request. Required.

          For the HTTP transport, this value MUST match the
          `MCP-Protocol-Version` header; otherwise the server MUST return a `400
          Bad Request`. If the server does not support the requested version, it
          MUST return an {@link UnsupportedProtocolVersionError}.
          """
        ),
      progressToken: GenMCP.MCP.V2607.ProgressToken
    },
    required: [
      :"io.modelcontextprotocol/clientCapabilities",
      :"io.modelcontextprotocol/clientInfo",
      :"io.modelcontextprotocol/protocolVersion"
    ],
    title: "MCP:RequestMetaObject",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.RequestParams do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:_meta])

  defschema %{
    description: "Common params for any request.",
    properties: %{_meta: GenMCP.MCP.V2607.RequestMetaObject},
    required: [:_meta],
    title: "MCP:RequestParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.Resource do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:name, :uri])

  defschema %{
    description: ~SD"""
    A known resource that the server is capable of reading.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      annotations: GenMCP.MCP.V2607.Annotations,
      description:
        string(
          description: ~SD"""
          A description of what this resource represents.

          This can be used by clients to improve the LLM's understanding of
          available resources. It can be thought of like a "hint" to the model.
          """
        ),
      icons: %{
        description: ~SD"""
        Optional set of sized icons that the client can display in a user
        interface.

        Clients that support rendering icons MUST support at least the
        following MIME types: - `image/png` - PNG images (safe, universal
        compatibility) - `image/jpeg` (and `image/jpg`) - JPEG images (safe,
        universal compatibility)

        Clients that support rendering icons SHOULD also support: -
        `image/svg+xml` - SVG images (scalable but requires security
        precautions) - `image/webp` - WebP images (modern, efficient format)
        """,
        items: GenMCP.MCP.V2607.Icon,
        type: "array"
      },
      mimeType: string(description: "The MIME type of this resource, if known."),
      name:
        string(
          description: ~SD"""
          Intended for programmatic or logical use, but used as a display name
          in past specs or fallback (if title isn't present).
          """
        ),
      size:
        integer(
          description: ~SD"""
          The size of the raw resource content, in bytes (i.e., before base64
          encoding or any tokenization), if known.

          This can be used by Hosts to display file sizes and estimate context
          window usage.
          """
        ),
      title:
        string(
          description: ~SD"""
          Intended for UI and end-user contexts — optimized to be human-readable
          and easily understood, even by those unfamiliar with domain-specific
          terminology.

          If not provided, the name should be used for display (except for
          {@link Tool}, where `annotations.title` should be given precedence
          over using `name`, if present).
          """
        ),
      uri: uri(description: "The URI of this resource.")
    },
    required: [:name, :uri],
    title: "MCP:Resource",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ResourceLink do
  use JSV.Schema

  JsonDerive.auto(_merge = %{type: "resource_link"}, _keep_nils = [:name, :uri])

  @skip_keys [:type]

  defschema %{
    description: ~SD"""
    A resource that the server is capable of reading, included in a prompt
    or tool call result.

    Note: resource links returned by tools are not guaranteed to appear in
    the results of {@link ListResourcesRequestresources/list} requests.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      annotations: GenMCP.MCP.V2607.Annotations,
      description:
        string(
          description: ~SD"""
          A description of what this resource represents.

          This can be used by clients to improve the LLM's understanding of
          available resources. It can be thought of like a "hint" to the model.
          """
        ),
      icons: %{
        description: ~SD"""
        Optional set of sized icons that the client can display in a user
        interface.

        Clients that support rendering icons MUST support at least the
        following MIME types: - `image/png` - PNG images (safe, universal
        compatibility) - `image/jpeg` (and `image/jpg`) - JPEG images (safe,
        universal compatibility)

        Clients that support rendering icons SHOULD also support: -
        `image/svg+xml` - SVG images (scalable but requires security
        precautions) - `image/webp` - WebP images (modern, efficient format)
        """,
        items: GenMCP.MCP.V2607.Icon,
        type: "array"
      },
      mimeType: string(description: "The MIME type of this resource, if known."),
      name:
        string(
          description: ~SD"""
          Intended for programmatic or logical use, but used as a display name
          in past specs or fallback (if title isn't present).
          """
        ),
      size:
        integer(
          description: ~SD"""
          The size of the raw resource content, in bytes (i.e., before base64
          encoding or any tokenization), if known.

          This can be used by Hosts to display file sizes and estimate context
          window usage.
          """
        ),
      title:
        string(
          description: ~SD"""
          Intended for UI and end-user contexts — optimized to be human-readable
          and easily understood, even by those unfamiliar with domain-specific
          terminology.

          If not provided, the name should be used for display (except for
          {@link Tool}, where `annotations.title` should be given precedence
          over using `name`, if present).
          """
        ),
      type: const("resource_link"),
      uri: uri(description: "The URI of this resource.")
    },
    required: [:name, :type, :uri],
    title: "MCP:ResourceLink",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ResourceTemplate do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:name, :uriTemplate])

  defschema %{
    description: ~SD"""
    A template description for resources available on the server.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      annotations: GenMCP.MCP.V2607.Annotations,
      description:
        string(
          description: ~SD"""
          A description of what this template is for.

          This can be used by clients to improve the LLM's understanding of
          available resources. It can be thought of like a "hint" to the model.
          """
        ),
      icons: %{
        description: ~SD"""
        Optional set of sized icons that the client can display in a user
        interface.

        Clients that support rendering icons MUST support at least the
        following MIME types: - `image/png` - PNG images (safe, universal
        compatibility) - `image/jpeg` (and `image/jpg`) - JPEG images (safe,
        universal compatibility)

        Clients that support rendering icons SHOULD also support: -
        `image/svg+xml` - SVG images (scalable but requires security
        precautions) - `image/webp` - WebP images (modern, efficient format)
        """,
        items: GenMCP.MCP.V2607.Icon,
        type: "array"
      },
      mimeType:
        string(
          description: ~SD"""
          The MIME type for all resources that match this template. This should
          only be included if all resources matching this template have the same
          type.
          """
        ),
      name:
        string(
          description: ~SD"""
          Intended for programmatic or logical use, but used as a display name
          in past specs or fallback (if title isn't present).
          """
        ),
      title:
        string(
          description: ~SD"""
          Intended for UI and end-user contexts — optimized to be human-readable
          and easily understood, even by those unfamiliar with domain-specific
          terminology.

          If not provided, the name should be used for display (except for
          {@link Tool}, where `annotations.title` should be given precedence
          over using `name`, if present).
          """
        ),
      uriTemplate:
        string_of("uri-template",
          description: ~SD"""
          A URI template (according to RFC 6570) that can be used to construct
          resource URIs.
          """
        )
    },
    required: [:name, :uriTemplate],
    title: "MCP:ResourceTemplate",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.Result do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:resultType])

  defschema %{
    additionalProperties: %{},
    description: "Common result fields.",
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      resultType:
        string(
          description: ~SD"""
          Indicates the type of the result, which allows the client to determine
          how to parse the result object.

          Servers implementing this protocol version MUST include this field.
          For backward compatibility, when a client receives a result from a
          server implementing an earlier protocol version (which does not
          include `resultType`), the client MUST treat the absent field as
          `"complete"`.
          """
        )
    },
    required: [:resultType],
    title: "MCP:Result",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.Role do
  use JSV.Schema

  def json_schema do
    string_enum_to_atom([:assistant, :user])
  end
end

defmodule GenMCP.MCP.V2607.Root do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:uri])

  defschema %{
    description: ~SD"""
    Represents a root directory or file that the server can operate on.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      name:
        string(
          description: ~SD"""
          An optional name for the root. This can be used to provide a
          human-readable identifier for the root, which may be useful for
          display purposes or for referencing the root in other parts of the
          application.
          """
        ),
      uri:
        uri(
          description: ~SD"""
          The URI identifying the root. This *must* start with `file://` for
          now. This restriction may be relaxed in future versions of the
          protocol to allow other URI schemes.
          """
        )
    },
    required: [:uri],
    title: "MCP:Root",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.SamplingMessage do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:content, :role])

  defschema %{
    description: ~SD"""
    Describes a message issued to or received from an LLM API.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      content: %{
        anyOf: [
          GenMCP.MCP.V2607.TextContent,
          GenMCP.MCP.V2607.ImageContent,
          GenMCP.MCP.V2607.AudioContent,
          GenMCP.MCP.V2607.ToolUseContent,
          GenMCP.MCP.V2607.ToolResultContent,
          array_of(GenMCP.MCP.V2607.SamplingMessageContentBlock)
        ]
      },
      role: GenMCP.MCP.V2607.Role
    },
    required: [:content, :role],
    title: "MCP:SamplingMessage",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.SamplingMessageContentBlock do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMCP.MCP.V2607.TextContent,
        GenMCP.MCP.V2607.ImageContent,
        GenMCP.MCP.V2607.AudioContent,
        GenMCP.MCP.V2607.ToolUseContent,
        GenMCP.MCP.V2607.ToolResultContent
      ],
      title: "MCP:SamplingMessageContentBlock"
    }
  end
end

defmodule GenMCP.MCP.V2607.ServerCapabilities do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [])

  defschema %{
    description: ~SD"""
    Capabilities that a server may support. Known capabilities are defined
    here, in this schema, but this is not a closed set: any server can
    define its own, additional capabilities.
    """,
    properties: %{
      completions: GenMCP.MCP.V2607.JSONObject,
      experimental: %{
        additionalProperties: GenMCP.MCP.V2607.JSONObject,
        description: ~SD"""
        Experimental, non-standard capabilities that the server supports.
        """,
        type: "object"
      },
      extensions: %{
        additionalProperties: GenMCP.MCP.V2607.JSONObject,
        description: ~SD"""
        Optional MCP extensions that the server supports. Keys are extension
        identifiers (e.g., "io.modelcontextprotocol/tasks"), and values are
        per-extension settings objects. An empty object indicates support with
        no settings.
        """,
        type: "object"
      },
      logging: GenMCP.MCP.V2607.JSONObject,
      prompts: %{
        description: "Present if the server offers any prompt templates.",
        properties: %{
          listChanged:
            boolean(
              description: ~SD"""
              Whether this server supports notifications for changes to the prompt
              list.
              """
            )
        },
        type: "object"
      },
      resources: %{
        description: ~SD"""
        Present if the server offers any resources to read.
        """,
        properties: %{
          listChanged:
            boolean(
              description: ~SD"""
              Whether this server supports notifications for changes to the resource
              list.
              """
            ),
          subscribe:
            boolean(
              description: ~SD"""
              Whether this server supports subscribing to resource updates.
              """
            )
        },
        type: "object"
      },
      tools: %{
        description: "Present if the server offers any tools to call.",
        properties: %{
          listChanged:
            boolean(
              description: ~SD"""
              Whether this server supports notifications for changes to the tool
              list.
              """
            )
        },
        type: "object"
      }
    },
    title: "MCP:ServerCapabilities",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.SubscriptionFilter do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [])

  defschema %{
    description: ~SD"""
    The set of notification types a client may opt in to on a {@link
    SubscriptionsListenRequestsubscriptions/listen} request.

    Each notification type is **opt-in**; the server **MUST NOT** send
    notification types the client has not explicitly requested here.
    """,
    properties: %{
      promptsListChanged:
        boolean(
          description: ~SD"""
          If true, receive {@link
          PromptListChangedNotificationnotifications/prompts/list_changed}.
          """
        ),
      resourceSubscriptions: %{
        description: ~SD"""
        Subscribe to {@link
        ResourceUpdatedNotificationnotifications/resources/updated} for these
        resource URIs. Replaces the former `resources/subscribe` RPC.
        """,
        items: string(),
        type: "array"
      },
      resourcesListChanged:
        boolean(
          description: ~SD"""
          If true, receive {@link
          ResourceListChangedNotificationnotifications/resources/list_changed}.
          """
        ),
      toolsListChanged:
        boolean(
          description: ~SD"""
          If true, receive {@link
          ToolListChangedNotificationnotifications/tools/list_changed}.
          """
        )
    },
    title: "MCP:SubscriptionFilter",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.SubscriptionsAcknowledgedNotification do
  use JSV.Schema

  JsonDerive.auto(
    _merge = %{method: "notifications/subscriptions/acknowledged", jsonrpc: "2.0"},
    _keep_nils = [:params]
  )

  @skip_keys [:jsonrpc, :method]

  defschema %{
    description: ~SD"""
    Sent by the server as the first message on a {@link
    SubscriptionsListenRequestsubscriptions/listen} stream to acknowledge
    that the subscription has been established and to report which
    notification types it agreed to honor.
    """,
    properties: %{
      jsonrpc: const("2.0"),
      method: const("notifications/subscriptions/acknowledged"),
      params: GenMCP.MCP.V2607.SubscriptionsAcknowledgedNotificationParams
    },
    required: [:jsonrpc, :method, :params],
    title: "MCP:SubscriptionsAcknowledgedNotification",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.SubscriptionsAcknowledgedNotificationParams do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:notifications])

  defschema %{
    description: ~SD"""
    Parameters for a {@link
    SubscriptionsAcknowledgedNotificationnotifications/subscriptions/acknowledged}
    notification.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      notifications: GenMCP.MCP.V2607.SubscriptionFilter
    },
    required: [:notifications],
    title: "MCP:SubscriptionsAcknowledgedNotificationParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.SubscriptionsListenRequest do
  use JSV.Schema

  JsonDerive.auto(
    _merge = %{method: "subscriptions/listen", jsonrpc: "2.0"},
    _keep_nils = [:id, :params]
  )

  @skip_keys [:jsonrpc, :method]

  defschema %{
    description: ~SD"""
    Sent from the client to open a long-lived channel for receiving
    notifications outside the context of a specific request. Replaces the
    previous HTTP GET endpoint and ensures consistent behavior between
    HTTP and STDIO.
    """,
    properties: %{
      id: GenMCP.MCP.V2607.RequestId,
      jsonrpc: const("2.0"),
      method: const("subscriptions/listen"),
      params: GenMCP.MCP.V2607.SubscriptionsListenRequestParams
    },
    required: [:id, :jsonrpc, :method, :params],
    title: "MCP:SubscriptionsListenRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.SubscriptionsListenRequestParams do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:_meta, :notifications])

  defschema %{
    description: ~SD"""
    Parameters for a {@link
    SubscriptionsListenRequestsubscriptions/listen} request.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.RequestMetaObject,
      notifications: GenMCP.MCP.V2607.SubscriptionFilter
    },
    required: [:_meta, :notifications],
    title: "MCP:SubscriptionsListenRequestParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.TextContent do
  use JSV.Schema

  JsonDerive.auto(_merge = %{type: "text"}, _keep_nils = [:text])

  @skip_keys [:type]

  defschema %{
    description: "Text provided to or from an LLM.",
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      annotations: GenMCP.MCP.V2607.Annotations,
      text: string(description: "The text content of the message."),
      type: const("text")
    },
    required: [:text, :type],
    title: "MCP:TextContent",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.TextResourceContents do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:text, :uri])

  defschema %{
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      mimeType: string(description: "The MIME type of this resource, if known."),
      text:
        string(
          description: ~SD"""
          The text of the item. This must only be set if the item can actually
          be represented as text (not binary data).
          """
        ),
      uri: uri(description: "The URI of this resource.")
    },
    required: [:text, :uri],
    title: "MCP:TextResourceContents",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.Tool do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:inputSchema, :name])

  defschema %{
    description: "Definition for a tool the client can call.",
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      annotations: GenMCP.MCP.V2607.ToolAnnotations,
      description:
        string(
          description: ~SD"""
          A human-readable description of the tool.

          This can be used by clients to improve the LLM's understanding of
          available tools. It can be thought of like a "hint" to the model.
          """
        ),
      icons: %{
        description: ~SD"""
        Optional set of sized icons that the client can display in a user
        interface.

        Clients that support rendering icons MUST support at least the
        following MIME types: - `image/png` - PNG images (safe, universal
        compatibility) - `image/jpeg` (and `image/jpg`) - JPEG images (safe,
        universal compatibility)

        Clients that support rendering icons SHOULD also support: -
        `image/svg+xml` - SVG images (scalable but requires security
        precautions) - `image/webp` - WebP images (modern, efficient format)
        """,
        items: GenMCP.MCP.V2607.Icon,
        type: "array"
      },
      inputSchema: %{
        additionalProperties: %{},
        description: ~SD"""
        A JSON Schema object defining the expected parameters for the tool.

        Tool arguments are always JSON objects, so `type: "object"` is
        required at the root. Beyond that, any JSON Schema 2020-12 keyword may
        appear alongside `type` — including composition keywords (`oneOf`,
        `anyOf`, `allOf`, `not`), conditional keywords (`if`/`then`/`else`),
        reference keywords (`$ref`, `$defs`, `$anchor`), and any other
        standard validation or annotation keywords.

        Defaults to JSON Schema 2020-12 when no explicit `$schema` is
        provided.
        """,
        properties: %{"$schema": string(), type: const("object")},
        required: ["type"],
        type: "object"
      },
      name:
        string(
          description: ~SD"""
          Intended for programmatic or logical use, but used as a display name
          in past specs or fallback (if title isn't present).
          """
        ),
      outputSchema: %{
        additionalProperties: %{},
        description: ~SD"""
        An optional JSON Schema object defining the structure of the tool's
        output returned in the structuredContent field of a {@link
        CallToolResult}. This can be any valid JSON Schema 2020-12.

        Defaults to JSON Schema 2020-12 when no explicit `$schema` is
        provided.
        """,
        properties: %{"$schema": string()},
        type: "object"
      },
      title:
        string(
          description: ~SD"""
          Intended for UI and end-user contexts — optimized to be human-readable
          and easily understood, even by those unfamiliar with domain-specific
          terminology.

          If not provided, the name should be used for display (except for
          {@link Tool}, where `annotations.title` should be given precedence
          over using `name`, if present).
          """
        )
    },
    required: [:inputSchema, :name],
    title: "MCP:Tool",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ToolAnnotations do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [])

  defschema %{
    description: ~SD"""
    Additional properties describing a {@link Tool} to clients.

    NOTE: all properties in `ToolAnnotations` are **hints**. They are not
    guaranteed to provide a faithful description of tool behavior
    (including descriptive properties like `title`).

    Clients should never make tool use decisions based on
    `ToolAnnotations` received from untrusted servers.
    """,
    properties: %{
      destructiveHint:
        boolean(
          description: ~SD"""
          If true, the tool may perform destructive updates to its environment.
          If false, the tool performs only additive updates.

          (This property is meaningful only when `readOnlyHint == false`)

          Default: true
          """
        ),
      idempotentHint:
        boolean(
          description: ~SD"""
          If true, calling the tool repeatedly with the same arguments will have
          no additional effect on its environment.

          (This property is meaningful only when `readOnlyHint == false`)

          Default: false
          """
        ),
      openWorldHint:
        boolean(
          description: ~SD"""
          If true, this tool may interact with an "open world" of external
          entities. If false, the tool's domain of interaction is closed. For
          example, the world of a web search tool is open, whereas that of a
          memory tool is not.

          Default: true
          """
        ),
      readOnlyHint:
        boolean(
          description: ~SD"""
          If true, the tool does not modify its environment.

          Default: false
          """
        ),
      title: string(description: "A human-readable title for the tool.")
    },
    title: "MCP:ToolAnnotations",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ToolChoice do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [])

  defschema %{
    description: ~SD"""
    Controls tool selection behavior for sampling requests.
    """,
    properties: %{mode: string_enum_to_atom([:auto, :none, :required])},
    title: "MCP:ToolChoice",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ToolResultContent do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:content, :toolUseId, :type])

  defschema %{
    description: ~SD"""
    The result of a tool use, provided by the user back to the assistant.
    """,
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      content: %{
        description: ~SD"""
        The unstructured result content of the tool use.

        This has the same format as {@link CallToolResult.content} and can
        include text, images, audio, resource links, and embedded resources.
        """,
        items: GenMCP.MCP.V2607.ContentBlock,
        type: "array"
      },
      isError:
        boolean(
          description: ~SD"""
          Whether the tool use resulted in an error.

          If true, the content typically describes the error that occurred.
          Default: false
          """
        ),
      structuredContent: %{
        description: ~SD"""
        An optional structured result value.

        This can be any JSON value (object, array, string, number, boolean, or
        null). If the tool defined an {@link Tool.outputSchema}, this SHOULD
        conform to that schema.
        """
      },
      toolUseId:
        string(
          description: ~SD"""
          The ID of the tool use this result corresponds to.

          This MUST match the ID from a previous {@link ToolUseContent}.
          """
        ),
      type: const("tool_result")
    },
    required: [:content, :toolUseId, :type],
    title: "MCP:ToolResultContent",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.V2607.ToolUseContent do
  use JSV.Schema

  JsonDerive.auto(_merge = %{}, _keep_nils = [:id, :input, :name, :type])

  defschema %{
    description: "A request from the assistant to call a tool.",
    properties: %{
      _meta: GenMCP.MCP.V2607.MetaObject,
      id:
        string(
          description: ~SD"""
          A unique identifier for this tool use.

          This ID is used to match tool results to their corresponding tool
          uses.
          """
        ),
      input: %{
        additionalProperties: %{},
        description: ~SD"""
        The arguments to pass to the tool, conforming to the tool's input
        schema.
        """,
        type: "object"
      },
      name: string(description: "The name of the tool to call."),
      type: const("tool_use")
    },
    required: [:id, :input, :name, :type],
    title: "MCP:ToolUseContent",
    type: "object"
  }

  @type t :: %__MODULE__{}
end
