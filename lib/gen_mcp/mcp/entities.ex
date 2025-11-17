require GenMCP.JsonDerive, as: JsonDerive

defmodule GenMCP.MCP.Meta do
  use JSV.Schema

  def json_schema do
    %{
      additionalProperties: %{},
      description:
        "See [General Fields](https://modelcontextprotocol.io/specification/2025-06-18/basic#general-fields) for notes on _meta usage.",
      properties: %{progressToken: GenMCP.MCP.ProgressToken},
      type: "object"
    }
  end
end

defmodule GenMCP.MCP.RequestMeta do
  use JSV.Schema

  def json_schema do
    %{
      additionalProperties: %{},
      description:
        "See [General Fields](https://modelcontextprotocol.io/specification/2025-06-18/basic#general-fields) for notes on _meta usage.",
      properties: %{progressToken: GenMCP.MCP.ProgressToken},
      type: "object"
    }
  end
end

defmodule GenMCP.MCP.ModMap do
  defmacro require_all do
    Enum.map(json_schema().definitions, fn {_, mod} ->
      quote do
        require unquote(mod)
      end
    end)
  end

  def json_schema do
    %{
      "$schema": "http://json-schema.org/draft-07/schema#",
      definitions: %{
        "Annotations" => GenMCP.MCP.Annotations,
        "AudioContent" => GenMCP.MCP.AudioContent,
        "BlobResourceContents" => GenMCP.MCP.BlobResourceContents,
        "BooleanSchema" => GenMCP.MCP.BooleanSchema,
        "CallToolRequest" => GenMCP.MCP.CallToolRequest,
        "CallToolRequestParams" => GenMCP.MCP.CallToolRequestParams,
        "CallToolResult" => GenMCP.MCP.CallToolResult,
        "CancelledNotification" => GenMCP.MCP.CancelledNotification,
        "CancelledNotificationParams" => GenMCP.MCP.CancelledNotificationParams,
        "ClientCapabilities" => GenMCP.MCP.ClientCapabilities,
        "ContentBlock" => GenMCP.MCP.ContentBlock,
        "EmbeddedResource" => GenMCP.MCP.EmbeddedResource,
        "GetPromptRequest" => GenMCP.MCP.GetPromptRequest,
        "GetPromptRequestParams" => GenMCP.MCP.GetPromptRequestParams,
        "GetPromptResult" => GenMCP.MCP.GetPromptResult,
        "ImageContent" => GenMCP.MCP.ImageContent,
        "Implementation" => GenMCP.MCP.Implementation,
        "InitializeRequest" => GenMCP.MCP.InitializeRequest,
        "InitializeRequestParams" => GenMCP.MCP.InitializeRequestParams,
        "InitializeResult" => GenMCP.MCP.InitializeResult,
        "InitializedNotification" => GenMCP.MCP.InitializedNotification,
        "JSONRPCError" => GenMCP.MCP.JSONRPCError,
        "JSONRPCResponse" => GenMCP.MCP.JSONRPCResponse,
        "ListPromptsRequest" => GenMCP.MCP.ListPromptsRequest,
        "ListPromptsRequestParams" => GenMCP.MCP.ListPromptsRequestParams,
        "ListPromptsResult" => GenMCP.MCP.ListPromptsResult,
        "ListResourceTemplatesRequest" => GenMCP.MCP.ListResourceTemplatesRequest,
        "ListResourceTemplatesResult" => GenMCP.MCP.ListResourceTemplatesResult,
        "ListResourcesRequest" => GenMCP.MCP.ListResourcesRequest,
        "ListResourcesRequestParams" => GenMCP.MCP.ListResourcesRequestParams,
        "ListResourcesResult" => GenMCP.MCP.ListResourcesResult,
        "ListToolsRequest" => GenMCP.MCP.ListToolsRequest,
        "ListToolsResult" => GenMCP.MCP.ListToolsResult,
        "PingRequest" => GenMCP.MCP.PingRequest,
        "ProgressNotification" => GenMCP.MCP.ProgressNotification,
        "ProgressToken" => GenMCP.MCP.ProgressToken,
        "Prompt" => GenMCP.MCP.Prompt,
        "PromptArgument" => GenMCP.MCP.PromptArgument,
        "PromptMessage" => GenMCP.MCP.PromptMessage,
        "ReadResourceRequest" => GenMCP.MCP.ReadResourceRequest,
        "ReadResourceRequestParams" => GenMCP.MCP.ReadResourceRequestParams,
        "ReadResourceResult" => GenMCP.MCP.ReadResourceResult,
        "RequestId" => GenMCP.MCP.RequestId,
        "Resource" => GenMCP.MCP.Resource,
        "ResourceLink" => GenMCP.MCP.ResourceLink,
        "ResourceTemplate" => GenMCP.MCP.ResourceTemplate,
        "Result" => GenMCP.MCP.Result,
        "Role" => GenMCP.MCP.Role,
        "RootsListChangedNotification" => GenMCP.MCP.RootsListChangedNotification,
        "ServerCapabilities" => GenMCP.MCP.ServerCapabilities,
        "SubscribeRequest" => GenMCP.MCP.SubscribeRequest,
        "TextContent" => GenMCP.MCP.TextContent,
        "TextResourceContents" => GenMCP.MCP.TextResourceContents,
        "Tool" => GenMCP.MCP.Tool,
        "ToolAnnotations" => GenMCP.MCP.ToolAnnotations,
        "UnsubscribeRequest" => GenMCP.MCP.UnsubscribeRequest
      }
    }
  end
end

defmodule GenMCP.MCP.Annotations do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Optional annotations for the client. The client can use annotations to
    inform how objects are used or displayed
    """,
    properties: %{
      audience: %{
        description: ~SD"""
        Describes who the intended customer of this object or data is.

        It can include multiple entries to indicate content useful for
        multiple audiences (e.g., `["user", "assistant"]`).
        """,
        items: GenMCP.MCP.Role,
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
    title: "Annotations",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.AudioContent do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Audio provided to or from an LLM.",
    properties: %{
      _meta: GenMCP.MCP.Meta,
      annotations: GenMCP.MCP.Annotations,
      data: string_of("byte", description: "The base64-encoded audio data."),
      mimeType:
        string(
          description: ~SD"""
          The MIME type of the audio. Different providers may support different
          audio types.
          """
        ),
      type: const("audio", default: "audio")
    },
    required: [:data, :mimeType],
    title: "AudioContent",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.BlobResourceContents do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMCP.MCP.Meta,
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
    title: "BlobResourceContents",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.BooleanSchema do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      default: boolean(),
      description: string(),
      title: string(),
      type: const("boolean")
    },
    required: [:type],
    title: "BooleanSchema",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.CallToolRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Used by the client to invoke a tool provided by the server.
    """,
    properties: %{
      id: GenMCP.MCP.RequestId,
      method: const("tools/call", default: "tools/call"),
      params: GenMCP.MCP.CallToolRequestParams
    },
    required: [:params],
    title: "CallToolRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.CallToolRequestParams do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMCP.MCP.RequestMeta,
      arguments: %{additionalProperties: %{}, type: "object"},
      name: string()
    },
    required: [:name],
    title: "CallToolRequestParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.CallToolResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "The server's response to a tool call.",
    properties: %{
      _meta: GenMCP.MCP.Meta,
      content: %{
        description: ~SD"""
        A list of content objects that represent the unstructured result of
        the tool call.
        """,
        items: GenMCP.MCP.ContentBlock,
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
      structuredContent: %{
        additionalProperties: %{},
        description: ~SD"""
        An optional JSON object that represents the structured result of the
        tool call.
        """,
        type: "object"
      }
    },
    required: [:content],
    title: "CallToolResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.CancelledNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    This notification can be sent by either side to indicate that it is
    cancelling a previously-issued request.

    The request SHOULD still be in-flight, but due to communication
    latency, it is always possible that this notification MAY arrive after
    the request has already finished.

    This notification indicates that the result will be unused, so any
    associated processing SHOULD cease.

    A client MUST NOT attempt to cancel its `initialize` request.
    """,
    properties: %{
      method: const("notifications/cancelled"),
      params: GenMCP.MCP.CancelledNotificationParams
    },
    required: [:method, :params],
    title: "CancelledNotification",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.CancelledNotificationParams do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      reason:
        string(
          description: ~SD"""
          An optional string describing the reason for the cancellation. This
          MAY be logged or presented to the user.
          """
        ),
      requestId: GenMCP.MCP.RequestId
    },
    required: [:requestId],
    title: "CancelledNotificationParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ClientCapabilities do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Capabilities a client may support. Known capabilities are defined
    here, in this schema, but this is not a closed set: any client can
    define its own, additional capabilities.
    """,
    properties: %{
      elicitation: %{
        additionalProperties: true,
        description: ~SD"""
        Present if the client supports elicitation from the server.
        """,
        properties: %{},
        type: "object"
      },
      experimental: %{
        additionalProperties: %{
          additionalProperties: true,
          properties: %{},
          type: "object"
        },
        description: ~SD"""
        Experimental, non-standard capabilities that the client supports.
        """,
        type: "object"
      },
      roots: %{
        description: "Present if the client supports listing roots.",
        properties: %{
          listChanged:
            boolean(
              description: ~SD"""
              Whether the client supports notifications for changes to the roots
              list.
              """
            )
        },
        type: "object"
      },
      sampling: %{
        additionalProperties: true,
        description: ~SD"""
        Present if the client supports sampling from an LLM.
        """,
        properties: %{},
        type: "object"
      }
    },
    title: "ClientCapabilities",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ContentBlock do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMCP.MCP.TextContent,
        GenMCP.MCP.ImageContent,
        GenMCP.MCP.AudioContent,
        GenMCP.MCP.ResourceLink,
        GenMCP.MCP.EmbeddedResource
      ]
    }
  end
end

defmodule GenMCP.MCP.EmbeddedResource do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    The contents of a resource, embedded into a prompt or tool call
    result.

    It is up to the client how best to render embedded resources for the
    benefit of the LLM and/or the user.
    """,
    properties: %{
      _meta: GenMCP.MCP.Meta,
      annotations: GenMCP.MCP.Annotations,
      resource: %{
        anyOf: [GenMCP.MCP.TextResourceContents, GenMCP.MCP.BlobResourceContents]
      },
      type: const("resource", default: "resource")
    },
    required: [:resource],
    title: "EmbeddedResource",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.GetPromptRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Used by the client to get a prompt provided by the server.
    """,
    properties: %{
      id: GenMCP.MCP.RequestId,
      method: const("prompts/get", default: "prompts/get"),
      params: GenMCP.MCP.GetPromptRequestParams
    },
    required: [:params],
    title: "GetPromptRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.GetPromptRequestParams do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMCP.MCP.RequestMeta,
      arguments: %{
        additionalProperties: string(),
        description: "Arguments to use for templating the prompt.",
        type: "object"
      },
      name: string(description: "The name of the prompt or prompt template.")
    },
    required: [:name],
    title: "GetPromptRequestParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.GetPromptResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    The server's response to a prompts/get request from the client.
    """,
    properties: %{
      _meta: GenMCP.MCP.Meta,
      description: string(description: "An optional description for the prompt."),
      messages: array_of(GenMCP.MCP.PromptMessage)
    },
    required: [:messages],
    title: "GetPromptResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ImageContent do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "An image provided to or from an LLM.",
    properties: %{
      _meta: GenMCP.MCP.Meta,
      annotations: GenMCP.MCP.Annotations,
      data: string_of("byte", description: "The base64-encoded image data."),
      mimeType:
        string(
          description: ~SD"""
          The MIME type of the image. Different providers may support different
          image types.
          """
        ),
      type: const("image", default: "image")
    },
    required: [:data, :mimeType],
    title: "ImageContent",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.Implementation do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Describes the name and version of an MCP implementation, with an
    optional title for UI representation.
    """,
    properties: %{
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

          If not provided, the name should be used for display (except for Tool,
          where `annotations.title` should be given precedence over using
          `name`, if present).
          """
        ),
      version: string()
    },
    required: [:name, :version],
    title: "Implementation",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.InitializeRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    This request is sent from the client to the server when it first
    connects, asking it to begin initialization.
    """,
    properties: %{
      id: GenMCP.MCP.RequestId,
      method: const("initialize", default: "initialize"),
      params: GenMCP.MCP.InitializeRequestParams
    },
    required: [:params],
    title: "InitializeRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.InitializeRequestParams do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMCP.MCP.RequestMeta,
      capabilities: GenMCP.MCP.ClientCapabilities,
      clientInfo: GenMCP.MCP.Implementation,
      protocolVersion:
        string(
          description: ~SD"""
          The latest version of the Model Context Protocol that the client
          supports. The client MAY decide to support older versions as well.
          """
        )
    },
    required: [:capabilities, :clientInfo, :protocolVersion],
    title: "InitializeRequestParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.InitializeResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    After receiving an initialize request from the client, the server
    sends this response.
    """,
    properties: %{
      _meta: GenMCP.MCP.Meta,
      capabilities: GenMCP.MCP.ServerCapabilities,
      instructions:
        string(
          description: ~SD"""
          Instructions describing how to use the server and its features.

          This can be used by clients to improve the LLM's understanding of
          available tools, resources, etc. It can be thought of like a "hint" to
          the model. For example, this information MAY be added to the system
          prompt.
          """
        ),
      protocolVersion:
        string(
          description: ~SD"""
          The version of the Model Context Protocol that the server wants to
          use. This may not match the version that the client requested. If the
          client cannot support this version, it MUST disconnect.
          """
        ),
      serverInfo: GenMCP.MCP.Implementation
    },
    required: [:capabilities, :protocolVersion, :serverInfo],
    title: "InitializeResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.InitializedNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    This notification is sent from the client to the server after
    initialization has finished.
    """,
    properties: %{
      method: const("notifications/initialized"),
      params: %{
        additionalProperties: %{},
        properties: %{_meta: GenMCP.MCP.Meta},
        type: "object"
      }
    },
    required: [:method],
    title: "InitializedNotification",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.JSONRPCError do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    A response to a request that indicates an error occurred.
    """,
    properties: %{
      error: %{
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
        required: ["code", "message"],
        type: "object"
      },
      id: GenMCP.MCP.RequestId,
      jsonrpc: const("2.0")
    },
    required: [:error, :id, :jsonrpc],
    title: "JSONRPCError",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.JSONRPCResponse do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "A successful (non-error) response to a request.",
    properties: %{
      id: GenMCP.MCP.RequestId,
      jsonrpc: const("2.0"),
      result: GenMCP.MCP.Result
    },
    required: [:id, :jsonrpc, :result],
    title: "JSONRPCResponse",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ListPromptsRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Sent from the client to request a list of prompts and prompt templates
    the server has.
    """,
    properties: %{
      id: GenMCP.MCP.RequestId,
      method: const("prompts/list", default: "prompts/list"),
      params: GenMCP.MCP.ListPromptsRequestParams
    },
    required: [],
    title: "ListPromptsRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ListPromptsRequestParams do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMCP.MCP.RequestMeta,
      cursor:
        string(
          description: ~SD"""
          An opaque token representing the current pagination position. If
          provided, the server should return results starting after this cursor.
          """
        )
    },
    title: "ListPromptsRequestParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ListPromptsResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    The server's response to a prompts/list request from the client.
    """,
    properties: %{
      _meta: GenMCP.MCP.Meta,
      nextCursor:
        string(
          description: ~SD"""
          An opaque token representing the pagination position after the last
          returned result. If present, there may be more results available.
          """
        ),
      prompts: array_of(GenMCP.MCP.Prompt)
    },
    required: [:prompts],
    title: "ListPromptsResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ListResourceTemplatesRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Sent from the client to request a list of resource templates the
    server has.
    """,
    properties: %{
      id: GenMCP.MCP.RequestId,
      method: const("resources/templates/list", default: "resources/templates/list"),
      params: %{
        properties: %{
          _meta: GenMCP.MCP.RequestMeta,
          cursor:
            string(
              description: ~SD"""
              An opaque token representing the current pagination position. If
              provided, the server should return results starting after this cursor.
              """
            )
        },
        type: "object"
      }
    },
    required: [],
    title: "ListResourceTemplatesRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ListResourceTemplatesResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    The server's response to a resources/templates/list request from the
    client.
    """,
    properties: %{
      _meta: GenMCP.MCP.Meta,
      nextCursor:
        string(
          description: ~SD"""
          An opaque token representing the pagination position after the last
          returned result. If present, there may be more results available.
          """
        ),
      resourceTemplates: array_of(GenMCP.MCP.ResourceTemplate)
    },
    required: [:resourceTemplates],
    title: "ListResourceTemplatesResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ListResourcesRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Sent from the client to request a list of resources the server has.
    """,
    properties: %{
      id: GenMCP.MCP.RequestId,
      method: const("resources/list", default: "resources/list"),
      params: GenMCP.MCP.ListResourcesRequestParams
    },
    required: [],
    title: "ListResourcesRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ListResourcesRequestParams do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMCP.MCP.RequestMeta,
      cursor:
        string(
          description: ~SD"""
          An opaque token representing the current pagination position. If
          provided, the server should return results starting after this cursor.
          """
        )
    },
    title: "ListResourcesRequestParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ListResourcesResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    The server's response to a resources/list request from the client.
    """,
    properties: %{
      _meta: GenMCP.MCP.Meta,
      nextCursor:
        string(
          description: ~SD"""
          An opaque token representing the pagination position after the last
          returned result. If present, there may be more results available.
          """
        ),
      resources: array_of(GenMCP.MCP.Resource)
    },
    required: [:resources],
    title: "ListResourcesResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ListToolsRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Sent from the client to request a list of tools the server has.
    """,
    properties: %{
      id: GenMCP.MCP.RequestId,
      method: const("tools/list", default: "tools/list"),
      params: %{
        properties: %{
          _meta: GenMCP.MCP.RequestMeta,
          cursor:
            string(
              description: ~SD"""
              An opaque token representing the current pagination position. If
              provided, the server should return results starting after this cursor.
              """
            )
        },
        type: "object"
      }
    },
    required: [],
    title: "ListToolsRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ListToolsResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    The server's response to a tools/list request from the client.
    """,
    properties: %{
      _meta: GenMCP.MCP.Meta,
      nextCursor:
        string(
          description: ~SD"""
          An opaque token representing the pagination position after the last
          returned result. If present, there may be more results available.
          """
        ),
      tools: array_of(GenMCP.MCP.Tool)
    },
    required: [:tools],
    title: "ListToolsResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.PingRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    A ping, issued by either the server or the client, to check that the
    other party is still alive. The receiver must promptly respond, or
    else may be disconnected.
    """,
    properties: %{
      id: GenMCP.MCP.RequestId,
      method: const("ping", default: "ping"),
      params: %{
        additionalProperties: %{},
        properties: %{_meta: GenMCP.MCP.RequestMeta},
        type: "object"
      }
    },
    required: [],
    title: "PingRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ProgressNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    An out-of-band notification used to inform the receiver of a progress
    update for a long-running request.
    """,
    properties: %{
      method: const("notifications/progress"),
      params: %{
        properties: %{
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
          progressToken: GenMCP.MCP.ProgressToken,
          total:
            number(
              description: ~SD"""
              Total number of items to process (or total progress required), if
              known.
              """
            )
        },
        required: ["progress", "progressToken"],
        type: "object"
      }
    },
    required: [:method, :params],
    title: "ProgressNotification",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ProgressToken do
  use JSV.Schema

  def json_schema do
    %{
      description: ~SD"""
      A progress token, used to associate progress notifications with the
      original request.
      """,
      type: ["string", "integer"]
    }
  end
end

defmodule GenMCP.MCP.Prompt do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    A prompt or prompt template that the server offers.
    """,
    properties: %{
      _meta: GenMCP.MCP.Meta,
      arguments: %{
        description: ~SD"""
        A list of arguments to use for templating the prompt.
        """,
        items: GenMCP.MCP.PromptArgument,
        type: "array"
      },
      description:
        string(
          description: ~SD"""
          An optional description of what this prompt provides
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

          If not provided, the name should be used for display (except for Tool,
          where `annotations.title` should be given precedence over using
          `name`, if present).
          """
        )
    },
    required: [:name],
    title: "Prompt",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.PromptArgument do
  use JSV.Schema
  JsonDerive.auto()

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

          If not provided, the name should be used for display (except for Tool,
          where `annotations.title` should be given precedence over using
          `name`, if present).
          """
        )
    },
    required: [:name],
    title: "PromptArgument",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.PromptMessage do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Describes a message returned as part of a prompt.

    This is similar to `SamplingMessage`, but also supports the embedding
    of resources from the MCP server.
    """,
    properties: %{content: GenMCP.MCP.ContentBlock, role: GenMCP.MCP.Role},
    required: [:content, :role],
    title: "PromptMessage",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ReadResourceRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Sent from the client to the server, to read a specific resource URI.
    """,
    properties: %{
      id: GenMCP.MCP.RequestId,
      method: const("resources/read", default: "resources/read"),
      params: GenMCP.MCP.ReadResourceRequestParams
    },
    required: [:params],
    title: "ReadResourceRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ReadResourceRequestParams do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMCP.MCP.RequestMeta,
      uri:
        uri(
          description: ~SD"""
          The URI of the resource to read. The URI can use any protocol; it is
          up to the server how to interpret it.
          """
        )
    },
    required: [:uri],
    title: "ReadResourceRequestParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ReadResourceResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    The server's response to a resources/read request from the client.
    """,
    properties: %{
      _meta: GenMCP.MCP.Meta,
      contents:
        array_of(%{anyOf: [GenMCP.MCP.TextResourceContents, GenMCP.MCP.BlobResourceContents]})
    },
    required: [:contents],
    title: "ReadResourceResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.RequestId do
  use JSV.Schema

  def json_schema do
    %{
      description: ~SD"""
      A uniquely identifying ID for a request in JSON-RPC.
      """,
      type: ["string", "integer"]
    }
  end
end

defmodule GenMCP.MCP.Resource do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    A known resource that the server is capable of reading.
    """,
    properties: %{
      _meta: GenMCP.MCP.Meta,
      annotations: GenMCP.MCP.Annotations,
      description:
        string(
          description: ~SD"""
          A description of what this resource represents.

          This can be used by clients to improve the LLM's understanding of
          available resources. It can be thought of like a "hint" to the model.
          """
        ),
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

          If not provided, the name should be used for display (except for Tool,
          where `annotations.title` should be given precedence over using
          `name`, if present).
          """
        ),
      uri: uri(description: "The URI of this resource.")
    },
    required: [:name, :uri],
    title: "Resource",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ResourceLink do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    A resource that the server is capable of reading, included in a prompt
    or tool call result.

    Note: resource links returned by tools are not guaranteed to appear in
    the results of `resources/list` requests.
    """,
    properties: %{
      _meta: GenMCP.MCP.Meta,
      annotations: GenMCP.MCP.Annotations,
      description:
        string(
          description: ~SD"""
          A description of what this resource represents.

          This can be used by clients to improve the LLM's understanding of
          available resources. It can be thought of like a "hint" to the model.
          """
        ),
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

          If not provided, the name should be used for display (except for Tool,
          where `annotations.title` should be given precedence over using
          `name`, if present).
          """
        ),
      type: const("resource_link", default: "resource_link"),
      uri: uri(description: "The URI of this resource.")
    },
    required: [:name, :uri],
    title: "ResourceLink",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ResourceTemplate do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    A template description for resources available on the server.
    """,
    properties: %{
      _meta: GenMCP.MCP.Meta,
      annotations: GenMCP.MCP.Annotations,
      description:
        string(
          description: ~SD"""
          A description of what this template is for.

          This can be used by clients to improve the LLM's understanding of
          available resources. It can be thought of like a "hint" to the model.
          """
        ),
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

          If not provided, the name should be used for display (except for Tool,
          where `annotations.title` should be given precedence over using
          `name`, if present).
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
    title: "ResourceTemplate",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.Result do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    additionalProperties: %{},
    properties: %{_meta: GenMCP.MCP.Meta},
    title: "Result",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.Role do
  use JSV.Schema

  def json_schema do
    string_enum_to_atom([:assistant, :user])
  end
end

defmodule GenMCP.MCP.RootsListChangedNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    A notification from the client to the server, informing it that the
    list of roots has changed. This notification should be sent whenever
    the client adds, removes, or modifies any root. The server should then
    request an updated list of roots using the ListRootsRequest.
    """,
    properties: %{
      method: const("notifications/roots/list_changed"),
      params: %{
        additionalProperties: %{},
        properties: %{_meta: GenMCP.MCP.Meta},
        type: "object"
      }
    },
    required: [:method],
    title: "RootsListChangedNotification",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ServerCapabilities do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Capabilities that a server may support. Known capabilities are defined
    here, in this schema, but this is not a closed set: any server can
    define its own, additional capabilities.
    """,
    properties: %{
      completions: %{
        additionalProperties: true,
        description: ~SD"""
        Present if the server supports argument autocompletion suggestions.
        """,
        properties: %{},
        type: "object"
      },
      experimental: %{
        additionalProperties: %{
          additionalProperties: true,
          properties: %{},
          type: "object"
        },
        description: ~SD"""
        Experimental, non-standard capabilities that the server supports.
        """,
        type: "object"
      },
      logging: %{
        additionalProperties: true,
        description: ~SD"""
        Present if the server supports sending log messages to the client.
        """,
        properties: %{},
        type: "object"
      },
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
    title: "ServerCapabilities",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.SubscribeRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Sent from the client to request resources/updated notifications from
    the server whenever a particular resource changes.
    """,
    properties: %{
      id: GenMCP.MCP.RequestId,
      method: const("resources/subscribe", default: "resources/subscribe"),
      params: %{
        properties: %{
          _meta: GenMCP.MCP.RequestMeta,
          uri:
            uri(
              description: ~SD"""
              The URI of the resource to subscribe to. The URI can use any protocol;
              it is up to the server how to interpret it.
              """
            )
        },
        required: ["uri"],
        type: "object"
      }
    },
    required: [:params],
    title: "SubscribeRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.TextContent do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Text provided to or from an LLM.",
    properties: %{
      _meta: GenMCP.MCP.Meta,
      annotations: GenMCP.MCP.Annotations,
      text: string(description: "The text content of the message."),
      type: const("text", default: "text")
    },
    required: [:text],
    title: "TextContent",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.TextResourceContents do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMCP.MCP.Meta,
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
    title: "TextResourceContents",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.Tool do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Definition for a tool the client can call.",
    properties: %{
      _meta: GenMCP.MCP.Meta,
      annotations: GenMCP.MCP.ToolAnnotations,
      description:
        string(
          description: ~SD"""
          A human-readable description of the tool.

          This can be used by clients to improve the LLM's understanding of
          available tools. It can be thought of like a "hint" to the model.
          """
        ),
      inputSchema: %{
        description: ~SD"""
        A JSON Schema object defining the expected parameters for the tool.
        """,
        properties: %{
          properties: %{
            additionalProperties: %{
              additionalProperties: true,
              properties: %{},
              type: "object"
            },
            type: "object"
          },
          required: array_of(string()),
          type: const("object")
        },
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
        description: ~SD"""
        An optional JSON Schema object defining the structure of the tool's
        output returned in the structuredContent field of a CallToolResult.
        """,
        properties: %{
          properties: %{
            additionalProperties: %{
              additionalProperties: true,
              properties: %{},
              type: "object"
            },
            type: "object"
          },
          required: array_of(string()),
          type: const("object")
        },
        required: ["type"],
        type: "object"
      },
      title:
        string(
          description: ~SD"""
          Intended for UI and end-user contexts — optimized to be human-readable
          and easily understood, even by those unfamiliar with domain-specific
          terminology.

          If not provided, the name should be used for display (except for Tool,
          where `annotations.title` should be given precedence over using
          `name`, if present).
          """
        )
    },
    required: [:inputSchema, :name],
    title: "Tool",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.ToolAnnotations do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Additional properties describing a Tool to clients.

    NOTE: all properties in ToolAnnotations are **hints**. They are not
    guaranteed to provide a faithful description of tool behavior
    (including descriptive properties like `title`).

    Clients should never make tool use decisions based on ToolAnnotations
    received from untrusted servers.
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
          no additional effect on the its environment.

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
    title: "ToolAnnotations",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.MCP.UnsubscribeRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Sent from the client to request cancellation of resources/updated
    notifications from the server. This should follow a previous
    resources/subscribe request.
    """,
    properties: %{
      id: GenMCP.MCP.RequestId,
      method: const("resources/unsubscribe", default: "resources/unsubscribe"),
      params: %{
        properties: %{
          _meta: GenMCP.MCP.RequestMeta,
          uri: uri(description: "The URI of the resource to unsubscribe from.")
        },
        required: ["uri"],
        type: "object"
      }
    },
    required: [:params],
    title: "UnsubscribeRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end
