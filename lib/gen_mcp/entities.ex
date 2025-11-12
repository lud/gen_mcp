require GenMCP.JsonDerive, as: JsonDerive

# Support modkit renaming
defmodule GenMCP.Entities do
  @moduledoc false
end

defmodule GenMCP.Entities.Meta do
  use JSV.Schema

  def json_schema do
    %{
      additionalProperties: %{},
      description:
        "See [General Fields](https://modelcontextprotocol.io/specification/2025-06-18/basic#general-fields) for notes on _meta usage.",
      properties: %{progressToken: GenMCP.Entities.ProgressToken},
      type: "object"
    }
  end
end

defmodule GenMCP.Entities.RequestMeta do
  use JSV.Schema

  def json_schema do
    %{
      additionalProperties: %{},
      description:
        "See [General Fields](https://modelcontextprotocol.io/specification/2025-06-18/basic#general-fields) for notes on _meta usage.",
      properties: %{progressToken: GenMCP.Entities.ProgressToken},
      type: "object"
    }
  end
end

defmodule GenMCP.Entities.ModMap do
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
        "Annotations" => GenMCP.Entities.Annotations,
        "AudioContent" => GenMCP.Entities.AudioContent,
        "BaseMetadata" => GenMCP.Entities.BaseMetadata,
        "BlobResourceContents" => GenMCP.Entities.BlobResourceContents,
        "BooleanSchema" => GenMCP.Entities.BooleanSchema,
        "CallToolRequest" => GenMCP.Entities.CallToolRequest,
        "CallToolRequestParams" => GenMCP.Entities.CallToolRequestParams,
        "CallToolResult" => GenMCP.Entities.CallToolResult,
        "CancelledNotification" => GenMCP.Entities.CancelledNotification,
        "ClientCapabilities" => GenMCP.Entities.ClientCapabilities,
        "ClientNotification" => GenMCP.Entities.ClientNotification,
        "ClientRequest" => GenMCP.Entities.ClientRequest,
        "ClientResult" => GenMCP.Entities.ClientResult,
        "CompleteRequest" => GenMCP.Entities.CompleteRequest,
        "CompleteResult" => GenMCP.Entities.CompleteResult,
        "ContentBlock" => GenMCP.Entities.ContentBlock,
        "CreateMessageRequest" => GenMCP.Entities.CreateMessageRequest,
        "CreateMessageResult" => GenMCP.Entities.CreateMessageResult,
        "Cursor" => GenMCP.Entities.Cursor,
        "ElicitRequest" => GenMCP.Entities.ElicitRequest,
        "ElicitResult" => GenMCP.Entities.ElicitResult,
        "EmbeddedResource" => GenMCP.Entities.EmbeddedResource,
        "EmptyResult" => GenMCP.Entities.EmptyResult,
        "EnumSchema" => GenMCP.Entities.EnumSchema,
        "GetPromptRequest" => GenMCP.Entities.GetPromptRequest,
        "GetPromptRequestParams" => GenMCP.Entities.GetPromptRequestParams,
        "GetPromptResult" => GenMCP.Entities.GetPromptResult,
        "ImageContent" => GenMCP.Entities.ImageContent,
        "Implementation" => GenMCP.Entities.Implementation,
        "InitializeRequest" => GenMCP.Entities.InitializeRequest,
        "InitializeRequestParams" => GenMCP.Entities.InitializeRequestParams,
        "InitializeResult" => GenMCP.Entities.InitializeResult,
        "InitializedNotification" => GenMCP.Entities.InitializedNotification,
        "JSONRPCError" => GenMCP.Entities.JSONRPCError,
        "JSONRPCMessage" => GenMCP.Entities.JSONRPCMessage,
        "JSONRPCNotification" => GenMCP.Entities.JSONRPCNotification,
        "JSONRPCRequest" => GenMCP.Entities.JSONRPCRequest,
        "JSONRPCResponse" => GenMCP.Entities.JSONRPCResponse,
        "ListPromptsRequest" => GenMCP.Entities.ListPromptsRequest,
        "ListPromptsRequestParams" => GenMCP.Entities.ListPromptsRequestParams,
        "ListPromptsResult" => GenMCP.Entities.ListPromptsResult,
        "ListResourceTemplatesRequest" => GenMCP.Entities.ListResourceTemplatesRequest,
        "ListResourceTemplatesResult" => GenMCP.Entities.ListResourceTemplatesResult,
        "ListResourcesRequest" => GenMCP.Entities.ListResourcesRequest,
        "ListResourcesRequestParams" => GenMCP.Entities.ListResourcesRequestParams,
        "ListResourcesResult" => GenMCP.Entities.ListResourcesResult,
        "ListRootsRequest" => GenMCP.Entities.ListRootsRequest,
        "ListRootsResult" => GenMCP.Entities.ListRootsResult,
        "ListToolsRequest" => GenMCP.Entities.ListToolsRequest,
        "ListToolsResult" => GenMCP.Entities.ListToolsResult,
        "LoggingLevel" => GenMCP.Entities.LoggingLevel,
        "LoggingMessageNotification" => GenMCP.Entities.LoggingMessageNotification,
        "ModelHint" => GenMCP.Entities.ModelHint,
        "ModelPreferences" => GenMCP.Entities.ModelPreferences,
        "Notification" => GenMCP.Entities.Notification,
        "NumberSchema" => GenMCP.Entities.NumberSchema,
        "PaginatedRequest" => GenMCP.Entities.PaginatedRequest,
        "PaginatedResult" => GenMCP.Entities.PaginatedResult,
        "PingRequest" => GenMCP.Entities.PingRequest,
        "PrimitiveSchemaDefinition" => GenMCP.Entities.PrimitiveSchemaDefinition,
        "ProgressNotification" => GenMCP.Entities.ProgressNotification,
        "ProgressToken" => GenMCP.Entities.ProgressToken,
        "Prompt" => GenMCP.Entities.Prompt,
        "PromptArgument" => GenMCP.Entities.PromptArgument,
        "PromptListChangedNotification" => GenMCP.Entities.PromptListChangedNotification,
        "PromptMessage" => GenMCP.Entities.PromptMessage,
        "PromptReference" => GenMCP.Entities.PromptReference,
        "ReadResourceRequest" => GenMCP.Entities.ReadResourceRequest,
        "ReadResourceRequestParams" => GenMCP.Entities.ReadResourceRequestParams,
        "ReadResourceResult" => GenMCP.Entities.ReadResourceResult,
        "Request" => GenMCP.Entities.Request,
        "RequestId" => GenMCP.Entities.RequestId,
        "Resource" => GenMCP.Entities.Resource,
        "ResourceContents" => GenMCP.Entities.ResourceContents,
        "ResourceLink" => GenMCP.Entities.ResourceLink,
        "ResourceListChangedNotification" => GenMCP.Entities.ResourceListChangedNotification,
        "ResourceTemplate" => GenMCP.Entities.ResourceTemplate,
        "ResourceTemplateReference" => GenMCP.Entities.ResourceTemplateReference,
        "ResourceUpdatedNotification" => GenMCP.Entities.ResourceUpdatedNotification,
        "Result" => GenMCP.Entities.Result,
        "Role" => GenMCP.Entities.Role,
        "Root" => GenMCP.Entities.Root,
        "RootsListChangedNotification" => GenMCP.Entities.RootsListChangedNotification,
        "SamplingMessage" => GenMCP.Entities.SamplingMessage,
        "ServerCapabilities" => GenMCP.Entities.ServerCapabilities,
        "ServerNotification" => GenMCP.Entities.ServerNotification,
        "ServerRequest" => GenMCP.Entities.ServerRequest,
        "ServerResult" => GenMCP.Entities.ServerResult,
        "SetLevelRequest" => GenMCP.Entities.SetLevelRequest,
        "StringSchema" => GenMCP.Entities.StringSchema,
        "SubscribeRequest" => GenMCP.Entities.SubscribeRequest,
        "TextContent" => GenMCP.Entities.TextContent,
        "TextResourceContents" => GenMCP.Entities.TextResourceContents,
        "Tool" => GenMCP.Entities.Tool,
        "ToolAnnotations" => GenMCP.Entities.ToolAnnotations,
        "ToolListChangedNotification" => GenMCP.Entities.ToolListChangedNotification,
        "UnsubscribeRequest" => GenMCP.Entities.UnsubscribeRequest
      }
    }
  end
end

defmodule GenMCP.Entities.Annotations do
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
        items: GenMCP.Entities.Role,
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

defmodule GenMCP.Entities.AudioContent do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Audio provided to or from an LLM.",
    properties: %{
      _meta: GenMCP.Entities.Meta,
      annotations: GenMCP.Entities.Annotations,
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
    title: "AudioContent",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.BaseMetadata do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Base interface for metadata with name (identifier) and title (display
    name) properties.
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
        )
    },
    required: [:name],
    title: "BaseMetadata",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.BlobResourceContents do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMCP.Entities.Meta,
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

defmodule GenMCP.Entities.BooleanSchema do
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

defmodule GenMCP.Entities.CallToolRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Used by the client to invoke a tool provided by the server.
    """,
    properties: %{
      id: GenMCP.Entities.RequestId,
      method: const("tools/call", default: "tools/call"),
      params: GenMCP.Entities.CallToolRequestParams
    },
    required: [:params],
    title: "CallToolRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.CallToolRequestParams do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMCP.Entities.RequestMeta,
      arguments: %{additionalProperties: %{}, type: "object"},
      name: string()
    },
    required: [:name],
    title: "CallToolRequestParams",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.CallToolResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "The server's response to a tool call.",
    properties: %{
      _meta: GenMCP.Entities.Meta,
      content: %{
        description: ~SD"""
        A list of content objects that represent the unstructured result of
        the tool call.
        """,
        items: GenMCP.Entities.ContentBlock,
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

defmodule GenMCP.Entities.CancelledNotification do
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
      params: %{
        properties: %{
          reason:
            string(
              description: ~SD"""
              An optional string describing the reason for the cancellation. This
              MAY be logged or presented to the user.
              """
            ),
          requestId: GenMCP.Entities.RequestId
        },
        required: ["requestId"],
        type: "object"
      }
    },
    required: [:method, :params],
    title: "CancelledNotification",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ClientCapabilities do
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

defmodule GenMCP.Entities.ClientNotification do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMCP.Entities.CancelledNotification,
        GenMCP.Entities.InitializedNotification,
        GenMCP.Entities.ProgressNotification,
        GenMCP.Entities.RootsListChangedNotification
      ]
    }
  end
end

defmodule GenMCP.Entities.ClientRequest do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMCP.Entities.InitializeRequest,
        GenMCP.Entities.PingRequest,
        GenMCP.Entities.ListResourcesRequest,
        GenMCP.Entities.ListResourceTemplatesRequest,
        GenMCP.Entities.ReadResourceRequest,
        GenMCP.Entities.SubscribeRequest,
        GenMCP.Entities.UnsubscribeRequest,
        GenMCP.Entities.ListPromptsRequest,
        GenMCP.Entities.GetPromptRequest,
        GenMCP.Entities.ListToolsRequest,
        GenMCP.Entities.CallToolRequest,
        GenMCP.Entities.SetLevelRequest,
        GenMCP.Entities.CompleteRequest
      ]
    }
  end
end

defmodule GenMCP.Entities.ClientResult do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMCP.Entities.Result,
        GenMCP.Entities.CreateMessageResult,
        GenMCP.Entities.ListRootsResult,
        GenMCP.Entities.ElicitResult
      ]
    }
  end
end

defmodule GenMCP.Entities.CompleteRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    A request from the client to the server, to ask for completion
    options.
    """,
    properties: %{
      id: GenMCP.Entities.RequestId,
      method: const("completion/complete", default: "completion/complete"),
      params: %{
        properties: %{
          _meta: GenMCP.Entities.RequestMeta,
          argument: %{
            description: "The argument's information",
            properties: %{
              name: string(description: "The name of the argument"),
              value:
                string(
                  description: ~SD"""
                  The value of the argument to use for completion matching.
                  """
                )
            },
            required: ["name", "value"],
            type: "object"
          },
          context: %{
            description: "Additional, optional context for completions",
            properties: %{
              arguments: %{
                additionalProperties: string(),
                description: ~SD"""
                Previously-resolved variables in a URI template or prompt.
                """,
                type: "object"
              }
            },
            type: "object"
          },
          ref: %{
            anyOf: [GenMCP.Entities.PromptReference, GenMCP.Entities.ResourceTemplateReference]
          }
        },
        required: ["argument", "ref"],
        type: "object"
      }
    },
    required: [:params],
    title: "CompleteRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.CompleteResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    The server's response to a completion/complete request
    """,
    properties: %{
      _meta: GenMCP.Entities.Meta,
      completion: %{
        properties: %{
          hasMore:
            boolean(
              description: ~SD"""
              Indicates whether there are additional completion options beyond those
              provided in the current response, even if the exact total is unknown.
              """
            ),
          total:
            integer(
              description: ~SD"""
              The total number of completion options available. This can exceed the
              number of values actually sent in the response.
              """
            ),
          values: %{
            description: ~SD"""
            An array of completion values. Must not exceed 100 items.
            """,
            items: string(),
            type: "array"
          }
        },
        required: ["values"],
        type: "object"
      }
    },
    required: [:completion],
    title: "CompleteResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ContentBlock do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMCP.Entities.TextContent,
        GenMCP.Entities.ImageContent,
        GenMCP.Entities.AudioContent,
        GenMCP.Entities.ResourceLink,
        GenMCP.Entities.EmbeddedResource
      ]
    }
  end
end

defmodule GenMCP.Entities.CreateMessageRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    A request from the server to sample an LLM via the client. The client
    has full discretion over which model to select. The client should also
    inform the user before beginning sampling, to allow them to inspect
    the request (human in the loop) and decide whether to approve it.
    """,
    properties: %{
      method: const("sampling/createMessage"),
      params: %{
        properties: %{
          includeContext: string_enum_to_atom([:allServers, :none, :thisServer]),
          maxTokens:
            integer(
              description: ~SD"""
              The maximum number of tokens to sample, as requested by the server.
              The client MAY choose to sample fewer tokens than requested.
              """
            ),
          messages: array_of(GenMCP.Entities.SamplingMessage),
          metadata: %{
            additionalProperties: true,
            description: ~SD"""
            Optional metadata to pass through to the LLM provider. The format of
            this metadata is provider-specific.
            """,
            properties: %{},
            type: "object"
          },
          modelPreferences: GenMCP.Entities.ModelPreferences,
          stopSequences: array_of(string()),
          systemPrompt:
            string(
              description: ~SD"""
              An optional system prompt the server wants to use for sampling. The
              client MAY modify or omit this prompt.
              """
            ),
          temperature: number()
        },
        required: ["maxTokens", "messages"],
        type: "object"
      }
    },
    required: [:method, :params],
    title: "CreateMessageRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.CreateMessageResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    The client's response to a sampling/create_message request from the
    server. The client should inform the user before returning the sampled
    message, to allow them to inspect the response (human in the loop) and
    decide whether to allow the server to see it.
    """,
    properties: %{
      _meta: GenMCP.Entities.Meta,
      content: %{
        anyOf: [
          GenMCP.Entities.TextContent,
          GenMCP.Entities.ImageContent,
          GenMCP.Entities.AudioContent
        ]
      },
      model: string(description: "The name of the model that generated the message."),
      role: GenMCP.Entities.Role,
      stopReason: string(description: "The reason why sampling stopped, if known.")
    },
    required: [:content, :model, :role],
    title: "CreateMessageResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.Cursor do
  use JSV.Schema

  def json_schema do
    string(
      description: ~SD"""
      An opaque token used to represent a cursor for pagination.
      """
    )
  end
end

defmodule GenMCP.Entities.ElicitRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    A request from the server to elicit additional information from the
    user via the client.
    """,
    properties: %{
      method: const("elicitation/create"),
      params: %{
        properties: %{
          message: string(description: "The message to present to the user."),
          requestedSchema: %{
            description: ~SD"""
            A restricted subset of JSON Schema. Only top-level properties are
            allowed, without nesting.
            """,
            properties: %{
              properties: %{
                additionalProperties: GenMCP.Entities.PrimitiveSchemaDefinition,
                type: "object"
              },
              required: array_of(string()),
              type: const("object")
            },
            required: ["properties", "type"],
            type: "object"
          }
        },
        required: ["message", "requestedSchema"],
        type: "object"
      }
    },
    required: [:method, :params],
    title: "ElicitRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ElicitResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "The client's response to an elicitation request.",
    properties: %{
      _meta: GenMCP.Entities.Meta,
      action: string_enum_to_atom([:accept, :cancel, :decline]),
      content: %{
        additionalProperties: %{type: ["string", "integer", "boolean"]},
        description: ~SD"""
        The submitted form data, only present when action is "accept".
        Contains values matching the requested schema.
        """,
        type: "object"
      }
    },
    required: [:action],
    title: "ElicitResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.EmbeddedResource do
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
      _meta: GenMCP.Entities.Meta,
      annotations: GenMCP.Entities.Annotations,
      resource: %{
        anyOf: [GenMCP.Entities.TextResourceContents, GenMCP.Entities.BlobResourceContents]
      },
      type: const("resource")
    },
    required: [:resource, :type],
    title: "EmbeddedResource",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.EmptyResult do
  use JSV.Schema

  def json_schema do
    GenMCP.Entities.Result
  end
end

defmodule GenMCP.Entities.EnumSchema do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      description: string(),
      enum: array_of(string()),
      enumNames: array_of(string()),
      title: string(),
      type: const("string")
    },
    required: [:enum, :type],
    title: "EnumSchema",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.GetPromptRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Used by the client to get a prompt provided by the server.
    """,
    properties: %{
      id: GenMCP.Entities.RequestId,
      method: const("prompts/get", default: "prompts/get"),
      params: GenMCP.Entities.GetPromptRequestParams
    },
    required: [:params],
    title: "GetPromptRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.GetPromptRequestParams do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMCP.Entities.RequestMeta,
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

defmodule GenMCP.Entities.GetPromptResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    The server's response to a prompts/get request from the client.
    """,
    properties: %{
      _meta: GenMCP.Entities.Meta,
      description: string(description: "An optional description for the prompt."),
      messages: array_of(GenMCP.Entities.PromptMessage)
    },
    required: [:messages],
    title: "GetPromptResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ImageContent do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "An image provided to or from an LLM.",
    properties: %{
      _meta: GenMCP.Entities.Meta,
      annotations: GenMCP.Entities.Annotations,
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
    title: "ImageContent",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.Implementation do
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

defmodule GenMCP.Entities.InitializeRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    This request is sent from the client to the server when it first
    connects, asking it to begin initialization.
    """,
    properties: %{
      id: GenMCP.Entities.RequestId,
      method: const("initialize", default: "initialize"),
      params: GenMCP.Entities.InitializeRequestParams
    },
    required: [:params],
    title: "InitializeRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.InitializeRequestParams do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMCP.Entities.RequestMeta,
      capabilities: GenMCP.Entities.ClientCapabilities,
      clientInfo: GenMCP.Entities.Implementation,
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

defmodule GenMCP.Entities.InitializeResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    After receiving an initialize request from the client, the server
    sends this response.
    """,
    properties: %{
      _meta: GenMCP.Entities.Meta,
      capabilities: GenMCP.Entities.ServerCapabilities,
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
      serverInfo: GenMCP.Entities.Implementation
    },
    required: [:capabilities, :protocolVersion, :serverInfo],
    title: "InitializeResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.InitializedNotification do
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
        properties: %{_meta: GenMCP.Entities.Meta},
        type: "object"
      }
    },
    required: [:method],
    title: "InitializedNotification",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.JSONRPCError do
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
      id: GenMCP.Entities.RequestId,
      jsonrpc: const("2.0")
    },
    required: [:error, :id, :jsonrpc],
    title: "JSONRPCError",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.JSONRPCMessage do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMCP.Entities.JSONRPCRequest,
        GenMCP.Entities.JSONRPCNotification,
        GenMCP.Entities.JSONRPCResponse,
        GenMCP.Entities.JSONRPCError
      ],
      description: ~SD"""
      Refers to any valid JSON-RPC object that can be decoded off the wire,
      or encoded to be sent.
      """
    }
  end
end

defmodule GenMCP.Entities.JSONRPCNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "A notification which does not expect a response.",
    properties: %{
      jsonrpc: const("2.0"),
      method: string(),
      params: %{
        additionalProperties: %{},
        properties: %{_meta: GenMCP.Entities.Meta},
        type: "object"
      }
    },
    required: [:jsonrpc, :method],
    title: "JSONRPCNotification",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.JSONRPCRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "A request that expects a response.",
    properties: %{
      id: GenMCP.Entities.RequestId,
      jsonrpc: const("2.0"),
      method: string(),
      params: %{
        additionalProperties: %{},
        properties: %{
          _meta: %{
            additionalProperties: %{},
            description: ~SD"""
            See [specification/2025-06-18/basic/index#general-fields] for notes on
            _meta usage.
            """,
            properties: %{progressToken: GenMCP.Entities.ProgressToken},
            type: "object"
          }
        },
        type: "object"
      }
    },
    required: [:id, :jsonrpc, :method],
    title: "JSONRPCRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.JSONRPCResponse do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "A successful (non-error) response to a request.",
    properties: %{
      id: GenMCP.Entities.RequestId,
      jsonrpc: const("2.0"),
      result: GenMCP.Entities.Result
    },
    required: [:id, :jsonrpc, :result],
    title: "JSONRPCResponse",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ListPromptsRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Sent from the client to request a list of prompts and prompt templates
    the server has.
    """,
    properties: %{
      id: GenMCP.Entities.RequestId,
      method: const("prompts/list", default: "prompts/list"),
      params: GenMCP.Entities.ListPromptsRequestParams
    },
    required: [],
    title: "ListPromptsRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ListPromptsRequestParams do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMCP.Entities.RequestMeta,
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

defmodule GenMCP.Entities.ListPromptsResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    The server's response to a prompts/list request from the client.
    """,
    properties: %{
      _meta: GenMCP.Entities.Meta,
      nextCursor:
        string(
          description: ~SD"""
          An opaque token representing the pagination position after the last
          returned result. If present, there may be more results available.
          """
        ),
      prompts: array_of(GenMCP.Entities.Prompt)
    },
    required: [:prompts],
    title: "ListPromptsResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ListResourceTemplatesRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Sent from the client to request a list of resource templates the
    server has.
    """,
    properties: %{
      id: GenMCP.Entities.RequestId,
      method: const("resources/templates/list", default: "resources/templates/list"),
      params: %{
        properties: %{
          _meta: GenMCP.Entities.RequestMeta,
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

defmodule GenMCP.Entities.ListResourceTemplatesResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    The server's response to a resources/templates/list request from the
    client.
    """,
    properties: %{
      _meta: GenMCP.Entities.Meta,
      nextCursor:
        string(
          description: ~SD"""
          An opaque token representing the pagination position after the last
          returned result. If present, there may be more results available.
          """
        ),
      resourceTemplates: array_of(GenMCP.Entities.ResourceTemplate)
    },
    required: [:resourceTemplates],
    title: "ListResourceTemplatesResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ListResourcesRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Sent from the client to request a list of resources the server has.
    """,
    properties: %{
      id: GenMCP.Entities.RequestId,
      method: const("resources/list", default: "resources/list"),
      params: GenMCP.Entities.ListResourcesRequestParams
    },
    required: [],
    title: "ListResourcesRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ListResourcesRequestParams do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMCP.Entities.RequestMeta,
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

defmodule GenMCP.Entities.ListResourcesResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    The server's response to a resources/list request from the client.
    """,
    properties: %{
      _meta: GenMCP.Entities.Meta,
      nextCursor:
        string(
          description: ~SD"""
          An opaque token representing the pagination position after the last
          returned result. If present, there may be more results available.
          """
        ),
      resources: array_of(GenMCP.Entities.Resource)
    },
    required: [:resources],
    title: "ListResourcesResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ListRootsRequest do
  use JSV.Schema
  JsonDerive.auto()

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
      params: %{
        additionalProperties: %{},
        properties: %{
          _meta: %{
            additionalProperties: %{},
            description: ~SD"""
            See [specification/2025-06-18/basic/index#general-fields] for notes on
            _meta usage.
            """,
            properties: %{progressToken: GenMCP.Entities.ProgressToken},
            type: "object"
          }
        },
        type: "object"
      }
    },
    required: [:method],
    title: "ListRootsRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ListRootsResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    The client's response to a roots/list request from the server. This
    result contains an array of Root objects, each representing a root
    directory or file that the server can operate on.
    """,
    properties: %{
      _meta: GenMCP.Entities.Meta,
      roots: array_of(GenMCP.Entities.Root)
    },
    required: [:roots],
    title: "ListRootsResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ListToolsRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Sent from the client to request a list of tools the server has.
    """,
    properties: %{
      id: GenMCP.Entities.RequestId,
      method: const("tools/list", default: "tools/list"),
      params: %{
        properties: %{
          _meta: GenMCP.Entities.RequestMeta,
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

defmodule GenMCP.Entities.ListToolsResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    The server's response to a tools/list request from the client.
    """,
    properties: %{
      _meta: GenMCP.Entities.Meta,
      nextCursor:
        string(
          description: ~SD"""
          An opaque token representing the pagination position after the last
          returned result. If present, there may be more results available.
          """
        ),
      tools: array_of(GenMCP.Entities.Tool)
    },
    required: [:tools],
    title: "ListToolsResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.LoggingLevel do
  use JSV.Schema

  def json_schema do
    string_enum_to_atom([:alert, :critical, :debug, :emergency, :error, :info, :notice, :warning])
  end
end

defmodule GenMCP.Entities.LoggingMessageNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Notification of a log message passed from server to client. If no
    logging/setLevel request has been sent from the client, the server MAY
    decide which messages to send automatically.
    """,
    properties: %{
      method: const("notifications/message"),
      params: %{
        properties: %{
          data: %{
            description: ~SD"""
            The data to be logged, such as a string message or an object. Any JSON
            serializable type is allowed here.
            """
          },
          level: GenMCP.Entities.LoggingLevel,
          logger:
            string(
              description: ~SD"""
              An optional name of the logger issuing this message.
              """
            )
        },
        required: ["data", "level"],
        type: "object"
      }
    },
    required: [:method, :params],
    title: "LoggingMessageNotification",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ModelHint do
  use JSV.Schema
  JsonDerive.auto()

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
    title: "ModelHint",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ModelPreferences do
  use JSV.Schema
  JsonDerive.auto()

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
        items: GenMCP.Entities.ModelHint,
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
    title: "ModelPreferences",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.Notification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      method: string(),
      params: %{
        additionalProperties: %{},
        properties: %{_meta: GenMCP.Entities.Meta},
        type: "object"
      }
    },
    required: [:method],
    title: "Notification",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.NumberSchema do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      description: string(),
      maximum: integer(),
      minimum: integer(),
      title: string(),
      type: string_enum_to_atom([:integer, :number])
    },
    required: [:type],
    title: "NumberSchema",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.PaginatedRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      method: string(),
      params: %{
        properties: %{
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
    required: [:method],
    title: "PaginatedRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.PaginatedResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMCP.Entities.Meta,
      nextCursor:
        string(
          description: ~SD"""
          An opaque token representing the pagination position after the last
          returned result. If present, there may be more results available.
          """
        )
    },
    title: "PaginatedResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.PingRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    A ping, issued by either the server or the client, to check that the
    other party is still alive. The receiver must promptly respond, or
    else may be disconnected.
    """,
    properties: %{
      id: GenMCP.Entities.RequestId,
      method: const("ping", default: "ping"),
      params: %{
        additionalProperties: %{},
        properties: %{_meta: GenMCP.Entities.RequestMeta},
        type: "object"
      }
    },
    required: [],
    title: "PingRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.PrimitiveSchemaDefinition do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMCP.Entities.StringSchema,
        GenMCP.Entities.NumberSchema,
        GenMCP.Entities.BooleanSchema,
        GenMCP.Entities.EnumSchema
      ],
      description: ~SD"""
      Restricted schema definitions that only allow primitive types without
      nested objects or arrays.
      """
    }
  end
end

defmodule GenMCP.Entities.ProgressNotification do
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
          progressToken: GenMCP.Entities.ProgressToken,
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

defmodule GenMCP.Entities.ProgressToken do
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

defmodule GenMCP.Entities.Prompt do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    A prompt or prompt template that the server offers.
    """,
    properties: %{
      _meta: GenMCP.Entities.Meta,
      arguments: %{
        description: ~SD"""
        A list of arguments to use for templating the prompt.
        """,
        items: GenMCP.Entities.PromptArgument,
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

defmodule GenMCP.Entities.PromptArgument do
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

defmodule GenMCP.Entities.PromptListChangedNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    An optional notification from the server to the client, informing it
    that the list of prompts it offers has changed. This may be issued by
    servers without any previous subscription from the client.
    """,
    properties: %{
      method: const("notifications/prompts/list_changed"),
      params: %{
        additionalProperties: %{},
        properties: %{_meta: GenMCP.Entities.Meta},
        type: "object"
      }
    },
    required: [:method],
    title: "PromptListChangedNotification",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.PromptMessage do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Describes a message returned as part of a prompt.

    This is similar to `SamplingMessage`, but also supports the embedding
    of resources from the MCP server.
    """,
    properties: %{
      content: GenMCP.Entities.ContentBlock,
      role: GenMCP.Entities.Role
    },
    required: [:content, :role],
    title: "PromptMessage",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.PromptReference do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Identifies a prompt.",
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
      type: const("ref/prompt")
    },
    required: [:name, :type],
    title: "PromptReference",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ReadResourceRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Sent from the client to the server, to read a specific resource URI.
    """,
    properties: %{
      id: GenMCP.Entities.RequestId,
      method: const("resources/read", default: "resources/read"),
      params: GenMCP.Entities.ReadResourceRequestParams
    },
    required: [:params],
    title: "ReadResourceRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ReadResourceRequestParams do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMCP.Entities.RequestMeta,
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

defmodule GenMCP.Entities.ReadResourceResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    The server's response to a resources/read request from the client.
    """,
    properties: %{
      _meta: GenMCP.Entities.Meta,
      contents:
        array_of(%{
          anyOf: [GenMCP.Entities.TextResourceContents, GenMCP.Entities.BlobResourceContents]
        })
    },
    required: [:contents],
    title: "ReadResourceResult",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.Request do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      method: string(),
      params: %{
        additionalProperties: %{},
        properties: %{
          _meta: %{
            additionalProperties: %{},
            description: ~SD"""
            See [specification/2025-06-18/basic/index#general-fields] for notes on
            _meta usage.
            """,
            properties: %{progressToken: GenMCP.Entities.ProgressToken},
            type: "object"
          }
        },
        type: "object"
      }
    },
    required: [:method],
    title: "Request",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.RequestId do
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

defmodule GenMCP.Entities.Resource do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    A known resource that the server is capable of reading.
    """,
    properties: %{
      _meta: GenMCP.Entities.Meta,
      annotations: GenMCP.Entities.Annotations,
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

defmodule GenMCP.Entities.ResourceContents do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    The contents of a specific resource or sub-resource.
    """,
    properties: %{
      _meta: GenMCP.Entities.Meta,
      mimeType: string(description: "The MIME type of this resource, if known."),
      uri: uri(description: "The URI of this resource.")
    },
    required: [:uri],
    title: "ResourceContents",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ResourceLink do
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
      _meta: GenMCP.Entities.Meta,
      annotations: GenMCP.Entities.Annotations,
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
      type: const("resource_link"),
      uri: uri(description: "The URI of this resource.")
    },
    required: [:name, :type, :uri],
    title: "ResourceLink",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ResourceListChangedNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    An optional notification from the server to the client, informing it
    that the list of resources it can read from has changed. This may be
    issued by servers without any previous subscription from the client.
    """,
    properties: %{
      method: const("notifications/resources/list_changed"),
      params: %{
        additionalProperties: %{},
        properties: %{_meta: GenMCP.Entities.Meta},
        type: "object"
      }
    },
    required: [:method],
    title: "ResourceListChangedNotification",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ResourceTemplate do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    A template description for resources available on the server.
    """,
    properties: %{
      _meta: GenMCP.Entities.Meta,
      annotations: GenMCP.Entities.Annotations,
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

defmodule GenMCP.Entities.ResourceTemplateReference do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    A reference to a resource or resource template definition.
    """,
    properties: %{
      type: const("ref/resource"),
      uri: string_of("uri-template", description: "The URI or URI template of the resource.")
    },
    required: [:type, :uri],
    title: "ResourceTemplateReference",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ResourceUpdatedNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    A notification from the server to the client, informing it that a
    resource has changed and may need to be read again. This should only
    be sent if the client previously sent a resources/subscribe request.
    """,
    properties: %{
      method: const("notifications/resources/updated"),
      params: %{
        properties: %{
          uri:
            uri(
              description: ~SD"""
              The URI of the resource that has been updated. This might be a
              sub-resource of the one that the client actually subscribed to.
              """
            )
        },
        required: ["uri"],
        type: "object"
      }
    },
    required: [:method, :params],
    title: "ResourceUpdatedNotification",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.Result do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    additionalProperties: %{},
    properties: %{_meta: GenMCP.Entities.Meta},
    title: "Result",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.Role do
  use JSV.Schema

  def json_schema do
    string_enum_to_atom([:assistant, :user])
  end
end

defmodule GenMCP.Entities.Root do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Represents a root directory or file that the server can operate on.
    """,
    properties: %{
      _meta: GenMCP.Entities.Meta,
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
          The URI identifying the root. This *must* start with file:// for now.
          This restriction may be relaxed in future versions of the protocol to
          allow other URI schemes.
          """
        )
    },
    required: [:uri],
    title: "Root",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.RootsListChangedNotification do
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
        properties: %{_meta: GenMCP.Entities.Meta},
        type: "object"
      }
    },
    required: [:method],
    title: "RootsListChangedNotification",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.SamplingMessage do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Describes a message issued to or received from an LLM API.
    """,
    properties: %{
      content: %{
        anyOf: [
          GenMCP.Entities.TextContent,
          GenMCP.Entities.ImageContent,
          GenMCP.Entities.AudioContent
        ]
      },
      role: GenMCP.Entities.Role
    },
    required: [:content, :role],
    title: "SamplingMessage",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.ServerCapabilities do
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

defmodule GenMCP.Entities.ServerNotification do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMCP.Entities.CancelledNotification,
        GenMCP.Entities.ProgressNotification,
        GenMCP.Entities.ResourceListChangedNotification,
        GenMCP.Entities.ResourceUpdatedNotification,
        GenMCP.Entities.PromptListChangedNotification,
        GenMCP.Entities.ToolListChangedNotification,
        GenMCP.Entities.LoggingMessageNotification
      ]
    }
  end
end

defmodule GenMCP.Entities.ServerRequest do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMCP.Entities.PingRequest,
        GenMCP.Entities.CreateMessageRequest,
        GenMCP.Entities.ListRootsRequest,
        GenMCP.Entities.ElicitRequest
      ]
    }
  end
end

defmodule GenMCP.Entities.ServerResult do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMCP.Entities.Result,
        GenMCP.Entities.InitializeResult,
        GenMCP.Entities.ListResourcesResult,
        GenMCP.Entities.ListResourceTemplatesResult,
        GenMCP.Entities.ReadResourceResult,
        GenMCP.Entities.ListPromptsResult,
        GenMCP.Entities.GetPromptResult,
        GenMCP.Entities.ListToolsResult,
        GenMCP.Entities.CallToolResult,
        GenMCP.Entities.CompleteResult
      ]
    }
  end
end

defmodule GenMCP.Entities.SetLevelRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    A request from the client to the server, to enable or adjust logging.
    """,
    properties: %{
      id: GenMCP.Entities.RequestId,
      method: const("logging/setLevel", default: "logging/setLevel"),
      params: %{
        properties: %{
          _meta: GenMCP.Entities.RequestMeta,
          level: GenMCP.Entities.LoggingLevel
        },
        required: ["level"],
        type: "object"
      }
    },
    required: [:params],
    title: "SetLevelRequest",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.StringSchema do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      description: string(),
      format: string_enum_to_atom([:date, :"date-time", :email, :uri]),
      maxLength: integer(),
      minLength: integer(),
      title: string(),
      type: const("string")
    },
    required: [:type],
    title: "StringSchema",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.SubscribeRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Sent from the client to request resources/updated notifications from
    the server whenever a particular resource changes.
    """,
    properties: %{
      id: GenMCP.Entities.RequestId,
      method: const("resources/subscribe", default: "resources/subscribe"),
      params: %{
        properties: %{
          _meta: GenMCP.Entities.RequestMeta,
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

defmodule GenMCP.Entities.TextContent do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Text provided to or from an LLM.",
    properties: %{
      _meta: GenMCP.Entities.Meta,
      annotations: GenMCP.Entities.Annotations,
      text: string(description: "The text content of the message."),
      type: const("text")
    },
    required: [:text, :type],
    title: "TextContent",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.TextResourceContents do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMCP.Entities.Meta,
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

defmodule GenMCP.Entities.Tool do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Definition for a tool the client can call.",
    properties: %{
      _meta: GenMCP.Entities.Meta,
      annotations: GenMCP.Entities.ToolAnnotations,
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

defmodule GenMCP.Entities.ToolAnnotations do
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

defmodule GenMCP.Entities.ToolListChangedNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    An optional notification from the server to the client, informing it
    that the list of tools it offers has changed. This may be issued by
    servers without any previous subscription from the client.
    """,
    properties: %{
      method: const("notifications/tools/list_changed"),
      params: %{
        additionalProperties: %{},
        properties: %{_meta: GenMCP.Entities.Meta},
        type: "object"
      }
    },
    required: [:method],
    title: "ToolListChangedNotification",
    type: "object"
  }

  @type t :: %__MODULE__{}
end

defmodule GenMCP.Entities.UnsubscribeRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: ~SD"""
    Sent from the client to request cancellation of resources/updated
    notifications from the server. This should follow a previous
    resources/subscribe request.
    """,
    properties: %{
      id: GenMCP.Entities.RequestId,
      method: const("resources/unsubscribe", default: "resources/unsubscribe"),
      params: %{
        properties: %{
          _meta: GenMCP.Entities.RequestMeta,
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
