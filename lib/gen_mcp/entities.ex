defmodule Elixir.GenMcp.Entities.ModMap do
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
        "Annotations" => GenMcp.Entities.Annotations,
        "AudioContent" => GenMcp.Entities.AudioContent,
        "BaseMetadata" => GenMcp.Entities.BaseMetadata,
        "BlobResourceContents" => GenMcp.Entities.BlobResourceContents,
        "BooleanSchema" => GenMcp.Entities.BooleanSchema,
        "CallToolRequest" => GenMcp.Entities.CallToolRequest,
        "CallToolRequestParams" => GenMcp.Entities.CallToolRequestParams,
        "CallToolResult" => GenMcp.Entities.CallToolResult,
        "CancelledNotification" => GenMcp.Entities.CancelledNotification,
        "ClientCapabilities" => GenMcp.Entities.ClientCapabilities,
        "ClientNotification" => GenMcp.Entities.ClientNotification,
        "ClientRequest" => GenMcp.Entities.ClientRequest,
        "ClientResult" => GenMcp.Entities.ClientResult,
        "CompleteRequest" => GenMcp.Entities.CompleteRequest,
        "CompleteResult" => GenMcp.Entities.CompleteResult,
        "ContentBlock" => GenMcp.Entities.ContentBlock,
        "CreateMessageRequest" => GenMcp.Entities.CreateMessageRequest,
        "CreateMessageResult" => GenMcp.Entities.CreateMessageResult,
        "Cursor" => GenMcp.Entities.Cursor,
        "ElicitRequest" => GenMcp.Entities.ElicitRequest,
        "ElicitResult" => GenMcp.Entities.ElicitResult,
        "EmbeddedResource" => GenMcp.Entities.EmbeddedResource,
        "EmptyResult" => GenMcp.Entities.EmptyResult,
        "EnumSchema" => GenMcp.Entities.EnumSchema,
        "GetPromptRequest" => GenMcp.Entities.GetPromptRequest,
        "GetPromptResult" => GenMcp.Entities.GetPromptResult,
        "ImageContent" => GenMcp.Entities.ImageContent,
        "Implementation" => GenMcp.Entities.Implementation,
        "InitializeRequest" => GenMcp.Entities.InitializeRequest,
        "InitializeRequestParams" => GenMcp.Entities.InitializeRequestParams,
        "InitializeResult" => GenMcp.Entities.InitializeResult,
        "InitializedNotification" => GenMcp.Entities.InitializedNotification,
        "JSONRPCError" => GenMcp.Entities.JSONRPCError,
        "JSONRPCMessage" => GenMcp.Entities.JSONRPCMessage,
        "JSONRPCNotification" => GenMcp.Entities.JSONRPCNotification,
        "JSONRPCRequest" => GenMcp.Entities.JSONRPCRequest,
        "JSONRPCResponse" => GenMcp.Entities.JSONRPCResponse,
        "ListPromptsRequest" => GenMcp.Entities.ListPromptsRequest,
        "ListPromptsResult" => GenMcp.Entities.ListPromptsResult,
        "ListResourceTemplatesRequest" => GenMcp.Entities.ListResourceTemplatesRequest,
        "ListResourceTemplatesResult" => GenMcp.Entities.ListResourceTemplatesResult,
        "ListResourcesRequest" => GenMcp.Entities.ListResourcesRequest,
        "ListResourcesResult" => GenMcp.Entities.ListResourcesResult,
        "ListRootsRequest" => GenMcp.Entities.ListRootsRequest,
        "ListRootsResult" => GenMcp.Entities.ListRootsResult,
        "ListToolsRequest" => GenMcp.Entities.ListToolsRequest,
        "ListToolsResult" => GenMcp.Entities.ListToolsResult,
        "LoggingLevel" => GenMcp.Entities.LoggingLevel,
        "LoggingMessageNotification" => GenMcp.Entities.LoggingMessageNotification,
        "ModelHint" => GenMcp.Entities.ModelHint,
        "ModelPreferences" => GenMcp.Entities.ModelPreferences,
        "Notification" => GenMcp.Entities.Notification,
        "NumberSchema" => GenMcp.Entities.NumberSchema,
        "PaginatedRequest" => GenMcp.Entities.PaginatedRequest,
        "PaginatedResult" => GenMcp.Entities.PaginatedResult,
        "PingRequest" => GenMcp.Entities.PingRequest,
        "PrimitiveSchemaDefinition" => GenMcp.Entities.PrimitiveSchemaDefinition,
        "ProgressNotification" => GenMcp.Entities.ProgressNotification,
        "ProgressToken" => GenMcp.Entities.ProgressToken,
        "Prompt" => GenMcp.Entities.Prompt,
        "PromptArgument" => GenMcp.Entities.PromptArgument,
        "PromptListChangedNotification" => GenMcp.Entities.PromptListChangedNotification,
        "PromptMessage" => GenMcp.Entities.PromptMessage,
        "PromptReference" => GenMcp.Entities.PromptReference,
        "ReadResourceRequest" => GenMcp.Entities.ReadResourceRequest,
        "ReadResourceResult" => GenMcp.Entities.ReadResourceResult,
        "Request" => GenMcp.Entities.Request,
        "RequestId" => GenMcp.Entities.RequestId,
        "Resource" => GenMcp.Entities.Resource,
        "ResourceContents" => GenMcp.Entities.ResourceContents,
        "ResourceLink" => GenMcp.Entities.ResourceLink,
        "ResourceListChangedNotification" => GenMcp.Entities.ResourceListChangedNotification,
        "ResourceTemplate" => GenMcp.Entities.ResourceTemplate,
        "ResourceTemplateReference" => GenMcp.Entities.ResourceTemplateReference,
        "ResourceUpdatedNotification" => GenMcp.Entities.ResourceUpdatedNotification,
        "Result" => GenMcp.Entities.Result,
        "Role" => GenMcp.Entities.Role,
        "Root" => GenMcp.Entities.Root,
        "RootsListChangedNotification" => GenMcp.Entities.RootsListChangedNotification,
        "SamplingMessage" => GenMcp.Entities.SamplingMessage,
        "ServerCapabilities" => GenMcp.Entities.ServerCapabilities,
        "ServerNotification" => GenMcp.Entities.ServerNotification,
        "ServerRequest" => GenMcp.Entities.ServerRequest,
        "ServerResult" => GenMcp.Entities.ServerResult,
        "SetLevelRequest" => GenMcp.Entities.SetLevelRequest,
        "StringSchema" => GenMcp.Entities.StringSchema,
        "SubscribeRequest" => GenMcp.Entities.SubscribeRequest,
        "TextContent" => GenMcp.Entities.TextContent,
        "TextResourceContents" => GenMcp.Entities.TextResourceContents,
        "Tool" => GenMcp.Entities.Tool,
        "ToolAnnotations" => GenMcp.Entities.ToolAnnotations,
        "ToolListChangedNotification" => GenMcp.Entities.ToolListChangedNotification,
        "UnsubscribeRequest" => GenMcp.Entities.UnsubscribeRequest
      }
    }
  end
end

require GenMcp.JsonDerive, as: JsonDerive

defmodule Elixir.GenMcp.Entities.Meta do
  use JSV.Schema

  def json_schema do
    %{
      additionalProperties: %{},
      description:
        "See [General Fields](https://modelcontextprotocol.io/specification/2025-06-18/basic#general-fields) for notes on _meta usage.",
      properties: %{progressToken: GenMcp.Entities.ProgressToken},
      type: "object"
    }
  end
end

defmodule Elixir.GenMcp.Entities.RequestMeta do
  use JSV.Schema

  def json_schema do
    %{
      additionalProperties: %{},
      description:
        "See [General Fields](https://modelcontextprotocol.io/specification/2025-06-18/basic#general-fields) for notes on _meta usage.",
      properties: %{progressToken: GenMcp.Entities.ProgressToken},
      type: "object"
    }
  end
end

defmodule GenMcp.Entities.Annotations do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "Optional annotations for the client. The client can use annotations to inform how objects are used or displayed",
    properties: %{
      audience: %{
        description:
          "Describes who the intended customer of this object or data is.\n\nIt can include multiple entries to indicate content useful for multiple audiences (e.g., `[\"user\", \"assistant\"]`).",
        items: GenMcp.Entities.Role,
        type: "array"
      },
      lastModified:
        string(
          description:
            "The moment the resource was last modified, as an ISO 8601 formatted string.\n\nShould be an ISO 8601 formatted string (e.g., \"2025-01-12T15:00:58Z\").\n\nExamples: last activity timestamp in an open file, timestamp when the resource\nwas attached, etc."
        ),
      priority: %{
        description:
          "Describes how important this data is for operating the server.\n\nA value of 1 means \"most important,\" and indicates that the data is\neffectively required, while 0 means \"least important,\" and indicates that\nthe data is entirely optional.",
        maximum: 1,
        minimum: 0,
        type: "number"
      }
    },
    title: "Annotations",
    type: "object"
  }
end

defmodule GenMcp.Entities.AudioContent do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Audio provided to or from an LLM.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      annotations: GenMcp.Entities.Annotations,
      data: string_of("byte", description: "The base64-encoded audio data."),
      mimeType:
        string(
          description:
            "The MIME type of the audio. Different providers may support different audio types."
        ),
      type: const("audio")
    },
    required: [:data, :mimeType, :type],
    title: "AudioContent",
    type: "object"
  }
end

defmodule GenMcp.Entities.BaseMetadata do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "Base interface for metadata with name (identifier) and title (display name) properties.",
    properties: %{
      name:
        string(
          description:
            "Intended for programmatic or logical use, but used as a display name in past specs or fallback (if title isn't present)."
        ),
      title:
        string(
          description:
            "Intended for UI and end-user contexts — optimized to be human-readable and easily understood,\neven by those unfamiliar with domain-specific terminology.\n\nIf not provided, the name should be used for display (except for Tool,\nwhere `annotations.title` should be given precedence over using `name`,\nif present)."
        )
    },
    required: [:name],
    title: "BaseMetadata",
    type: "object"
  }
end

defmodule GenMcp.Entities.BlobResourceContents do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMcp.Entities.Meta,
      blob:
        string_of("byte",
          description: "A base64-encoded string representing the binary data of the item."
        ),
      mimeType: string(description: "The MIME type of this resource, if known."),
      uri: uri(description: "The URI of this resource.")
    },
    required: [:blob, :uri],
    title: "BlobResourceContents",
    type: "object"
  }
end

defmodule GenMcp.Entities.BooleanSchema do
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
end

defmodule GenMcp.Entities.CallToolRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Used by the client to invoke a tool provided by the server.",
    properties: %{
      id: GenMcp.Entities.RequestId,
      method: const("tools/call"),
      params: GenMcp.Entities.CallToolRequestParams
    },
    required: [:method, :params],
    title: "CallToolRequest",
    type: "object"
  }
end

defmodule GenMcp.Entities.CallToolRequestParams do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMcp.Entities.RequestMeta,
      arguments: %{additionalProperties: %{}, type: "object"},
      name: string()
    },
    required: [:name],
    title: "CallToolRequestParams",
    type: "object"
  }
end

defmodule GenMcp.Entities.CallToolResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "The server's response to a tool call.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      content: %{
        description:
          "A list of content objects that represent the unstructured result of the tool call.",
        items: GenMcp.Entities.ContentBlock,
        type: "array"
      },
      isError:
        boolean(
          description:
            "Whether the tool call ended in an error.\n\nIf not set, this is assumed to be false (the call was successful).\n\nAny errors that originate from the tool SHOULD be reported inside the result\nobject, with `isError` set to true, _not_ as an MCP protocol-level error\nresponse. Otherwise, the LLM would not be able to see that an error occurred\nand self-correct.\n\nHowever, any errors in _finding_ the tool, an error indicating that the\nserver does not support tool calls, or any other exceptional conditions,\nshould be reported as an MCP error response."
        ),
      structuredContent: %{
        additionalProperties: %{},
        description:
          "An optional JSON object that represents the structured result of the tool call.",
        type: "object"
      }
    },
    required: [:content],
    title: "CallToolResult",
    type: "object"
  }
end

defmodule GenMcp.Entities.CancelledNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "This notification can be sent by either side to indicate that it is cancelling a previously-issued request.\n\nThe request SHOULD still be in-flight, but due to communication latency, it is always possible that this notification MAY arrive after the request has already finished.\n\nThis notification indicates that the result will be unused, so any associated processing SHOULD cease.\n\nA client MUST NOT attempt to cancel its `initialize` request.",
    properties: %{
      method: const("notifications/cancelled"),
      params: %{
        properties: %{
          reason:
            string(
              description:
                "An optional string describing the reason for the cancellation. This MAY be logged or presented to the user."
            ),
          requestId: GenMcp.Entities.RequestId
        },
        required: ["requestId"],
        type: "object"
      }
    },
    required: [:method, :params],
    title: "CancelledNotification",
    type: "object"
  }
end

defmodule GenMcp.Entities.ClientCapabilities do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "Capabilities a client may support. Known capabilities are defined here, in this schema, but this is not a closed set: any client can define its own, additional capabilities.",
    properties: %{
      elicitation: %{
        additionalProperties: true,
        description: "Present if the client supports elicitation from the server.",
        properties: %{},
        type: "object"
      },
      experimental: %{
        additionalProperties: %{
          additionalProperties: true,
          properties: %{},
          type: "object"
        },
        description: "Experimental, non-standard capabilities that the client supports.",
        type: "object"
      },
      roots: %{
        description: "Present if the client supports listing roots.",
        properties: %{
          listChanged:
            boolean(
              description:
                "Whether the client supports notifications for changes to the roots list."
            )
        },
        type: "object"
      },
      sampling: %{
        additionalProperties: true,
        description: "Present if the client supports sampling from an LLM.",
        properties: %{},
        type: "object"
      }
    },
    title: "ClientCapabilities",
    type: "object"
  }
end

defmodule GenMcp.Entities.ClientNotification do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMcp.Entities.CancelledNotification,
        GenMcp.Entities.InitializedNotification,
        GenMcp.Entities.ProgressNotification,
        GenMcp.Entities.RootsListChangedNotification
      ]
    }
  end
end

defmodule GenMcp.Entities.ClientRequest do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMcp.Entities.InitializeRequest,
        GenMcp.Entities.PingRequest,
        GenMcp.Entities.ListResourcesRequest,
        GenMcp.Entities.ListResourceTemplatesRequest,
        GenMcp.Entities.ReadResourceRequest,
        GenMcp.Entities.SubscribeRequest,
        GenMcp.Entities.UnsubscribeRequest,
        GenMcp.Entities.ListPromptsRequest,
        GenMcp.Entities.GetPromptRequest,
        GenMcp.Entities.ListToolsRequest,
        GenMcp.Entities.CallToolRequest,
        GenMcp.Entities.SetLevelRequest,
        GenMcp.Entities.CompleteRequest
      ]
    }
  end
end

defmodule GenMcp.Entities.ClientResult do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMcp.Entities.Result,
        GenMcp.Entities.CreateMessageResult,
        GenMcp.Entities.ListRootsResult,
        GenMcp.Entities.ElicitResult
      ]
    }
  end
end

defmodule GenMcp.Entities.CompleteRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "A request from the client to the server, to ask for completion options.",
    properties: %{
      id: GenMcp.Entities.RequestId,
      method: const("completion/complete"),
      params: %{
        properties: %{
          _meta: GenMcp.Entities.RequestMeta,
          argument: %{
            description: "The argument's information",
            properties: %{
              name: string(description: "The name of the argument"),
              value:
                string(description: "The value of the argument to use for completion matching.")
            },
            required: ["name", "value"],
            type: "object"
          },
          context: %{
            description: "Additional, optional context for completions",
            properties: %{
              arguments: %{
                additionalProperties: string(),
                description: "Previously-resolved variables in a URI template or prompt.",
                type: "object"
              }
            },
            type: "object"
          },
          ref: %{
            anyOf: [GenMcp.Entities.PromptReference, GenMcp.Entities.ResourceTemplateReference]
          }
        },
        required: ["argument", "ref"],
        type: "object"
      }
    },
    required: [:method, :params],
    title: "CompleteRequest",
    type: "object"
  }
end

defmodule GenMcp.Entities.CompleteResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "The server's response to a completion/complete request",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      completion: %{
        properties: %{
          hasMore:
            boolean(
              description:
                "Indicates whether there are additional completion options beyond those provided in the current response, even if the exact total is unknown."
            ),
          total:
            integer(
              description:
                "The total number of completion options available. This can exceed the number of values actually sent in the response."
            ),
          values: %{
            description: "An array of completion values. Must not exceed 100 items.",
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
end

defmodule GenMcp.Entities.ContentBlock do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMcp.Entities.TextContent,
        GenMcp.Entities.ImageContent,
        GenMcp.Entities.AudioContent,
        GenMcp.Entities.ResourceLink,
        GenMcp.Entities.EmbeddedResource
      ]
    }
  end
end

defmodule GenMcp.Entities.CreateMessageRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "A request from the server to sample an LLM via the client. The client has full discretion over which model to select. The client should also inform the user before beginning sampling, to allow them to inspect the request (human in the loop) and decide whether to approve it.",
    properties: %{
      method: const("sampling/createMessage"),
      params: %{
        properties: %{
          includeContext: string_enum_to_atom([:allServers, :none, :thisServer]),
          maxTokens:
            integer(
              description:
                "The maximum number of tokens to sample, as requested by the server. The client MAY choose to sample fewer tokens than requested."
            ),
          messages: array_of(GenMcp.Entities.SamplingMessage),
          metadata: %{
            additionalProperties: true,
            description:
              "Optional metadata to pass through to the LLM provider. The format of this metadata is provider-specific.",
            properties: %{},
            type: "object"
          },
          modelPreferences: GenMcp.Entities.ModelPreferences,
          stopSequences: array_of(string()),
          systemPrompt:
            string(
              description:
                "An optional system prompt the server wants to use for sampling. The client MAY modify or omit this prompt."
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
end

defmodule GenMcp.Entities.CreateMessageResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "The client's response to a sampling/create_message request from the server. The client should inform the user before returning the sampled message, to allow them to inspect the response (human in the loop) and decide whether to allow the server to see it.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      content: %{
        anyOf: [
          GenMcp.Entities.TextContent,
          GenMcp.Entities.ImageContent,
          GenMcp.Entities.AudioContent
        ]
      },
      model: string(description: "The name of the model that generated the message."),
      role: GenMcp.Entities.Role,
      stopReason: string(description: "The reason why sampling stopped, if known.")
    },
    required: [:content, :model, :role],
    title: "CreateMessageResult",
    type: "object"
  }
end

defmodule GenMcp.Entities.Cursor do
  use JSV.Schema

  def json_schema do
    string(description: "An opaque token used to represent a cursor for pagination.")
  end
end

defmodule GenMcp.Entities.ElicitRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "A request from the server to elicit additional information from the user via the client.",
    properties: %{
      method: const("elicitation/create"),
      params: %{
        properties: %{
          message: string(description: "The message to present to the user."),
          requestedSchema: %{
            description:
              "A restricted subset of JSON Schema.\nOnly top-level properties are allowed, without nesting.",
            properties: %{
              properties: %{
                additionalProperties: GenMcp.Entities.PrimitiveSchemaDefinition,
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
end

defmodule GenMcp.Entities.ElicitResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "The client's response to an elicitation request.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      action: string_enum_to_atom([:accept, :cancel, :decline]),
      content: %{
        additionalProperties: %{type: ["string", "integer", "boolean"]},
        description:
          "The submitted form data, only present when action is \"accept\".\nContains values matching the requested schema.",
        type: "object"
      }
    },
    required: [:action],
    title: "ElicitResult",
    type: "object"
  }
end

defmodule GenMcp.Entities.EmbeddedResource do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "The contents of a resource, embedded into a prompt or tool call result.\n\nIt is up to the client how best to render embedded resources for the benefit\nof the LLM and/or the user.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      annotations: GenMcp.Entities.Annotations,
      resource: %{
        anyOf: [GenMcp.Entities.TextResourceContents, GenMcp.Entities.BlobResourceContents]
      },
      type: const("resource")
    },
    required: [:resource, :type],
    title: "EmbeddedResource",
    type: "object"
  }
end

defmodule GenMcp.Entities.EmptyResult do
  use JSV.Schema

  def json_schema do
    GenMcp.Entities.Result
  end
end

defmodule GenMcp.Entities.EnumSchema do
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
end

defmodule GenMcp.Entities.GetPromptRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Used by the client to get a prompt provided by the server.",
    properties: %{
      id: GenMcp.Entities.RequestId,
      method: const("prompts/get"),
      params: %{
        properties: %{
          _meta: GenMcp.Entities.RequestMeta,
          arguments: %{
            additionalProperties: string(),
            description: "Arguments to use for templating the prompt.",
            type: "object"
          },
          name: string(description: "The name of the prompt or prompt template.")
        },
        required: ["name"],
        type: "object"
      }
    },
    required: [:method, :params],
    title: "GetPromptRequest",
    type: "object"
  }
end

defmodule GenMcp.Entities.GetPromptResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "The server's response to a prompts/get request from the client.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      description: string(description: "An optional description for the prompt."),
      messages: array_of(GenMcp.Entities.PromptMessage)
    },
    required: [:messages],
    title: "GetPromptResult",
    type: "object"
  }
end

defmodule GenMcp.Entities.ImageContent do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "An image provided to or from an LLM.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      annotations: GenMcp.Entities.Annotations,
      data: string_of("byte", description: "The base64-encoded image data."),
      mimeType:
        string(
          description:
            "The MIME type of the image. Different providers may support different image types."
        ),
      type: const("image")
    },
    required: [:data, :mimeType, :type],
    title: "ImageContent",
    type: "object"
  }
end

defmodule GenMcp.Entities.Implementation do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "Describes the name and version of an MCP implementation, with an optional title for UI representation.",
    properties: %{
      name:
        string(
          description:
            "Intended for programmatic or logical use, but used as a display name in past specs or fallback (if title isn't present)."
        ),
      title:
        string(
          description:
            "Intended for UI and end-user contexts — optimized to be human-readable and easily understood,\neven by those unfamiliar with domain-specific terminology.\n\nIf not provided, the name should be used for display (except for Tool,\nwhere `annotations.title` should be given precedence over using `name`,\nif present)."
        ),
      version: string()
    },
    required: [:name, :version],
    title: "Implementation",
    type: "object"
  }
end

defmodule GenMcp.Entities.InitializeRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "This request is sent from the client to the server when it first connects, asking it to begin initialization.",
    properties: %{
      id: GenMcp.Entities.RequestId,
      method: const("initialize"),
      params: GenMcp.Entities.InitializeRequestParams
    },
    required: [:method, :params],
    title: "InitializeRequest",
    type: "object"
  }
end

defmodule GenMcp.Entities.InitializeRequestParams do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMcp.Entities.RequestMeta,
      capabilities: GenMcp.Entities.ClientCapabilities,
      clientInfo: GenMcp.Entities.Implementation,
      protocolVersion:
        string(
          description:
            "The latest version of the Model Context Protocol that the client supports. The client MAY decide to support older versions as well."
        )
    },
    required: [:capabilities, :clientInfo, :protocolVersion],
    title: "InitializeRequestParams",
    type: "object"
  }
end

defmodule GenMcp.Entities.InitializeResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "After receiving an initialize request from the client, the server sends this response.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      capabilities: GenMcp.Entities.ServerCapabilities,
      instructions:
        string(
          description:
            "Instructions describing how to use the server and its features.\n\nThis can be used by clients to improve the LLM's understanding of available tools, resources, etc. It can be thought of like a \"hint\" to the model. For example, this information MAY be added to the system prompt."
        ),
      protocolVersion:
        string(
          description:
            "The version of the Model Context Protocol that the server wants to use. This may not match the version that the client requested. If the client cannot support this version, it MUST disconnect."
        ),
      serverInfo: GenMcp.Entities.Implementation
    },
    required: [:capabilities, :protocolVersion, :serverInfo],
    title: "InitializeResult",
    type: "object"
  }
end

defmodule GenMcp.Entities.InitializedNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "This notification is sent from the client to the server after initialization has finished.",
    properties: %{
      method: const("notifications/initialized"),
      params: %{
        additionalProperties: %{},
        properties: %{_meta: GenMcp.Entities.Meta},
        type: "object"
      }
    },
    required: [:method],
    title: "InitializedNotification",
    type: "object"
  }
end

defmodule GenMcp.Entities.JSONRPCError do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "A response to a request that indicates an error occurred.",
    properties: %{
      error: %{
        properties: %{
          code: integer(description: "The error type that occurred."),
          data: %{
            description:
              "Additional information about the error. The value of this member is defined by the sender (e.g. detailed error information, nested errors etc.)."
          },
          message:
            string(
              description:
                "A short description of the error. The message SHOULD be limited to a concise single sentence."
            )
        },
        required: ["code", "message"],
        type: "object"
      },
      id: GenMcp.Entities.RequestId,
      jsonrpc: const("2.0")
    },
    required: [:error, :id, :jsonrpc],
    title: "JSONRPCError",
    type: "object"
  }
end

defmodule GenMcp.Entities.JSONRPCMessage do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMcp.Entities.JSONRPCRequest,
        GenMcp.Entities.JSONRPCNotification,
        GenMcp.Entities.JSONRPCResponse,
        GenMcp.Entities.JSONRPCError
      ],
      description:
        "Refers to any valid JSON-RPC object that can be decoded off the wire, or encoded to be sent."
    }
  end
end

defmodule GenMcp.Entities.JSONRPCNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "A notification which does not expect a response.",
    properties: %{
      jsonrpc: const("2.0"),
      method: string(),
      params: %{
        additionalProperties: %{},
        properties: %{_meta: GenMcp.Entities.Meta},
        type: "object"
      }
    },
    required: [:jsonrpc, :method],
    title: "JSONRPCNotification",
    type: "object"
  }
end

defmodule GenMcp.Entities.JSONRPCRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "A request that expects a response.",
    properties: %{
      id: GenMcp.Entities.RequestId,
      jsonrpc: const("2.0"),
      method: string(),
      params: %{
        additionalProperties: %{},
        properties: %{
          _meta: %{
            additionalProperties: %{},
            description:
              "See [specification/2025-06-18/basic/index#general-fields] for notes on _meta usage.",
            properties: %{progressToken: GenMcp.Entities.ProgressToken},
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
end

defmodule GenMcp.Entities.JSONRPCResponse do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "A successful (non-error) response to a request.",
    properties: %{
      id: GenMcp.Entities.RequestId,
      jsonrpc: const("2.0"),
      result: GenMcp.Entities.Result
    },
    required: [:id, :jsonrpc, :result],
    title: "JSONRPCResponse",
    type: "object"
  }
end

defmodule GenMcp.Entities.ListPromptsRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "Sent from the client to request a list of prompts and prompt templates the server has.",
    properties: %{
      id: GenMcp.Entities.RequestId,
      method: const("prompts/list"),
      params: %{
        properties: %{
          _meta: GenMcp.Entities.RequestMeta,
          cursor:
            string(
              description:
                "An opaque token representing the current pagination position.\nIf provided, the server should return results starting after this cursor."
            )
        },
        type: "object"
      }
    },
    required: [:method],
    title: "ListPromptsRequest",
    type: "object"
  }
end

defmodule GenMcp.Entities.ListPromptsResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "The server's response to a prompts/list request from the client.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      nextCursor:
        string(
          description:
            "An opaque token representing the pagination position after the last returned result.\nIf present, there may be more results available."
        ),
      prompts: array_of(GenMcp.Entities.Prompt)
    },
    required: [:prompts],
    title: "ListPromptsResult",
    type: "object"
  }
end

defmodule GenMcp.Entities.ListResourceTemplatesRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Sent from the client to request a list of resource templates the server has.",
    properties: %{
      id: GenMcp.Entities.RequestId,
      method: const("resources/templates/list"),
      params: %{
        properties: %{
          _meta: GenMcp.Entities.RequestMeta,
          cursor:
            string(
              description:
                "An opaque token representing the current pagination position.\nIf provided, the server should return results starting after this cursor."
            )
        },
        type: "object"
      }
    },
    required: [:method],
    title: "ListResourceTemplatesRequest",
    type: "object"
  }
end

defmodule GenMcp.Entities.ListResourceTemplatesResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "The server's response to a resources/templates/list request from the client.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      nextCursor:
        string(
          description:
            "An opaque token representing the pagination position after the last returned result.\nIf present, there may be more results available."
        ),
      resourceTemplates: array_of(GenMcp.Entities.ResourceTemplate)
    },
    required: [:resourceTemplates],
    title: "ListResourceTemplatesResult",
    type: "object"
  }
end

defmodule GenMcp.Entities.ListResourcesRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Sent from the client to request a list of resources the server has.",
    properties: %{
      id: GenMcp.Entities.RequestId,
      method: const("resources/list"),
      params: %{
        properties: %{
          _meta: GenMcp.Entities.RequestMeta,
          cursor:
            string(
              description:
                "An opaque token representing the current pagination position.\nIf provided, the server should return results starting after this cursor."
            )
        },
        type: "object"
      }
    },
    required: [:method],
    title: "ListResourcesRequest",
    type: "object"
  }
end

defmodule GenMcp.Entities.ListResourcesResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "The server's response to a resources/list request from the client.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      nextCursor:
        string(
          description:
            "An opaque token representing the pagination position after the last returned result.\nIf present, there may be more results available."
        ),
      resources: array_of(GenMcp.Entities.Resource)
    },
    required: [:resources],
    title: "ListResourcesResult",
    type: "object"
  }
end

defmodule GenMcp.Entities.ListRootsRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "Sent from the server to request a list of root URIs from the client. Roots allow\nservers to ask for specific directories or files to operate on. A common example\nfor roots is providing a set of repositories or directories a server should operate\non.\n\nThis request is typically used when the server needs to understand the file system\nstructure or access specific locations that the client has permission to read from.",
    properties: %{
      method: const("roots/list"),
      params: %{
        additionalProperties: %{},
        properties: %{
          _meta: %{
            additionalProperties: %{},
            description:
              "See [specification/2025-06-18/basic/index#general-fields] for notes on _meta usage.",
            properties: %{progressToken: GenMcp.Entities.ProgressToken},
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
end

defmodule GenMcp.Entities.ListRootsResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "The client's response to a roots/list request from the server.\nThis result contains an array of Root objects, each representing a root directory\nor file that the server can operate on.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      roots: array_of(GenMcp.Entities.Root)
    },
    required: [:roots],
    title: "ListRootsResult",
    type: "object"
  }
end

defmodule GenMcp.Entities.ListToolsRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Sent from the client to request a list of tools the server has.",
    properties: %{
      id: GenMcp.Entities.RequestId,
      method: const("tools/list"),
      params: %{
        properties: %{
          _meta: GenMcp.Entities.RequestMeta,
          cursor:
            string(
              description:
                "An opaque token representing the current pagination position.\nIf provided, the server should return results starting after this cursor."
            )
        },
        type: "object"
      }
    },
    required: [:method],
    title: "ListToolsRequest",
    type: "object"
  }
end

defmodule GenMcp.Entities.ListToolsResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "The server's response to a tools/list request from the client.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      nextCursor:
        string(
          description:
            "An opaque token representing the pagination position after the last returned result.\nIf present, there may be more results available."
        ),
      tools: array_of(GenMcp.Entities.Tool)
    },
    required: [:tools],
    title: "ListToolsResult",
    type: "object"
  }
end

defmodule GenMcp.Entities.LoggingLevel do
  use JSV.Schema

  def json_schema do
    string_enum_to_atom([:alert, :critical, :debug, :emergency, :error, :info, :notice, :warning])
  end
end

defmodule GenMcp.Entities.LoggingMessageNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "Notification of a log message passed from server to client. If no logging/setLevel request has been sent from the client, the server MAY decide which messages to send automatically.",
    properties: %{
      method: const("notifications/message"),
      params: %{
        properties: %{
          data: %{
            description:
              "The data to be logged, such as a string message or an object. Any JSON serializable type is allowed here."
          },
          level: GenMcp.Entities.LoggingLevel,
          logger: string(description: "An optional name of the logger issuing this message.")
        },
        required: ["data", "level"],
        type: "object"
      }
    },
    required: [:method, :params],
    title: "LoggingMessageNotification",
    type: "object"
  }
end

defmodule GenMcp.Entities.ModelHint do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "Hints to use for model selection.\n\nKeys not declared here are currently left unspecified by the spec and are up\nto the client to interpret.",
    properties: %{
      name:
        string(
          description:
            "A hint for a model name.\n\nThe client SHOULD treat this as a substring of a model name; for example:\n - `claude-3-5-sonnet` should match `claude-3-5-sonnet-20241022`\n - `sonnet` should match `claude-3-5-sonnet-20241022`, `claude-3-sonnet-20240229`, etc.\n - `claude` should match any Claude model\n\nThe client MAY also map the string to a different provider's model name or a different model family, as long as it fills a similar niche; for example:\n - `gemini-1.5-flash` could match `claude-3-haiku-20240307`"
        )
    },
    title: "ModelHint",
    type: "object"
  }
end

defmodule GenMcp.Entities.ModelPreferences do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "The server's preferences for model selection, requested of the client during sampling.\n\nBecause LLMs can vary along multiple dimensions, choosing the \"best\" model is\nrarely straightforward.  Different models excel in different areas—some are\nfaster but less capable, others are more capable but more expensive, and so\non. This interface allows servers to express their priorities across multiple\ndimensions to help clients make an appropriate selection for their use case.\n\nThese preferences are always advisory. The client MAY ignore them. It is also\nup to the client to decide how to interpret these preferences and how to\nbalance them against other considerations.",
    properties: %{
      costPriority: %{
        description:
          "How much to prioritize cost when selecting a model. A value of 0 means cost\nis not important, while a value of 1 means cost is the most important\nfactor.",
        maximum: 1,
        minimum: 0,
        type: "number"
      },
      hints: %{
        description:
          "Optional hints to use for model selection.\n\nIf multiple hints are specified, the client MUST evaluate them in order\n(such that the first match is taken).\n\nThe client SHOULD prioritize these hints over the numeric priorities, but\nMAY still use the priorities to select from ambiguous matches.",
        items: GenMcp.Entities.ModelHint,
        type: "array"
      },
      intelligencePriority: %{
        description:
          "How much to prioritize intelligence and capabilities when selecting a\nmodel. A value of 0 means intelligence is not important, while a value of 1\nmeans intelligence is the most important factor.",
        maximum: 1,
        minimum: 0,
        type: "number"
      },
      speedPriority: %{
        description:
          "How much to prioritize sampling speed (latency) when selecting a model. A\nvalue of 0 means speed is not important, while a value of 1 means speed is\nthe most important factor.",
        maximum: 1,
        minimum: 0,
        type: "number"
      }
    },
    title: "ModelPreferences",
    type: "object"
  }
end

defmodule GenMcp.Entities.Notification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      method: string(),
      params: %{
        additionalProperties: %{},
        properties: %{_meta: GenMcp.Entities.Meta},
        type: "object"
      }
    },
    required: [:method],
    title: "Notification",
    type: "object"
  }
end

defmodule GenMcp.Entities.NumberSchema do
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
end

defmodule GenMcp.Entities.PaginatedRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      method: string(),
      params: %{
        properties: %{
          cursor:
            string(
              description:
                "An opaque token representing the current pagination position.\nIf provided, the server should return results starting after this cursor."
            )
        },
        type: "object"
      }
    },
    required: [:method],
    title: "PaginatedRequest",
    type: "object"
  }
end

defmodule GenMcp.Entities.PaginatedResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMcp.Entities.Meta,
      nextCursor:
        string(
          description:
            "An opaque token representing the pagination position after the last returned result.\nIf present, there may be more results available."
        )
    },
    title: "PaginatedResult",
    type: "object"
  }
end

defmodule GenMcp.Entities.PingRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "A ping, issued by either the server or the client, to check that the other party is still alive. The receiver must promptly respond, or else may be disconnected.",
    properties: %{
      id: GenMcp.Entities.RequestId,
      method: const("ping"),
      params: %{
        additionalProperties: %{},
        properties: %{_meta: GenMcp.Entities.RequestMeta},
        type: "object"
      }
    },
    required: [:method],
    title: "PingRequest",
    type: "object"
  }
end

defmodule GenMcp.Entities.PrimitiveSchemaDefinition do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMcp.Entities.StringSchema,
        GenMcp.Entities.NumberSchema,
        GenMcp.Entities.BooleanSchema,
        GenMcp.Entities.EnumSchema
      ],
      description:
        "Restricted schema definitions that only allow primitive types\nwithout nested objects or arrays."
    }
  end
end

defmodule GenMcp.Entities.ProgressNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "An out-of-band notification used to inform the receiver of a progress update for a long-running request.",
    properties: %{
      method: const("notifications/progress"),
      params: %{
        properties: %{
          message: string(description: "An optional message describing the current progress."),
          progress:
            number(
              description:
                "The progress thus far. This should increase every time progress is made, even if the total is unknown."
            ),
          progressToken: GenMcp.Entities.ProgressToken,
          total:
            number(
              description:
                "Total number of items to process (or total progress required), if known."
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
end

defmodule GenMcp.Entities.ProgressToken do
  use JSV.Schema

  def json_schema do
    %{
      description:
        "A progress token, used to associate progress notifications with the original request.",
      type: ["string", "integer"]
    }
  end
end

defmodule GenMcp.Entities.Prompt do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "A prompt or prompt template that the server offers.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      arguments: %{
        description: "A list of arguments to use for templating the prompt.",
        items: GenMcp.Entities.PromptArgument,
        type: "array"
      },
      description: string(description: "An optional description of what this prompt provides"),
      name:
        string(
          description:
            "Intended for programmatic or logical use, but used as a display name in past specs or fallback (if title isn't present)."
        ),
      title:
        string(
          description:
            "Intended for UI and end-user contexts — optimized to be human-readable and easily understood,\neven by those unfamiliar with domain-specific terminology.\n\nIf not provided, the name should be used for display (except for Tool,\nwhere `annotations.title` should be given precedence over using `name`,\nif present)."
        )
    },
    required: [:name],
    title: "Prompt",
    type: "object"
  }
end

defmodule GenMcp.Entities.PromptArgument do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Describes an argument that a prompt can accept.",
    properties: %{
      description: string(description: "A human-readable description of the argument."),
      name:
        string(
          description:
            "Intended for programmatic or logical use, but used as a display name in past specs or fallback (if title isn't present)."
        ),
      required: boolean(description: "Whether this argument must be provided."),
      title:
        string(
          description:
            "Intended for UI and end-user contexts — optimized to be human-readable and easily understood,\neven by those unfamiliar with domain-specific terminology.\n\nIf not provided, the name should be used for display (except for Tool,\nwhere `annotations.title` should be given precedence over using `name`,\nif present)."
        )
    },
    required: [:name],
    title: "PromptArgument",
    type: "object"
  }
end

defmodule GenMcp.Entities.PromptListChangedNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "An optional notification from the server to the client, informing it that the list of prompts it offers has changed. This may be issued by servers without any previous subscription from the client.",
    properties: %{
      method: const("notifications/prompts/list_changed"),
      params: %{
        additionalProperties: %{},
        properties: %{_meta: GenMcp.Entities.Meta},
        type: "object"
      }
    },
    required: [:method],
    title: "PromptListChangedNotification",
    type: "object"
  }
end

defmodule GenMcp.Entities.PromptMessage do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "Describes a message returned as part of a prompt.\n\nThis is similar to `SamplingMessage`, but also supports the embedding of\nresources from the MCP server.",
    properties: %{
      content: GenMcp.Entities.ContentBlock,
      role: GenMcp.Entities.Role
    },
    required: [:content, :role],
    title: "PromptMessage",
    type: "object"
  }
end

defmodule GenMcp.Entities.PromptReference do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Identifies a prompt.",
    properties: %{
      name:
        string(
          description:
            "Intended for programmatic or logical use, but used as a display name in past specs or fallback (if title isn't present)."
        ),
      title:
        string(
          description:
            "Intended for UI and end-user contexts — optimized to be human-readable and easily understood,\neven by those unfamiliar with domain-specific terminology.\n\nIf not provided, the name should be used for display (except for Tool,\nwhere `annotations.title` should be given precedence over using `name`,\nif present)."
        ),
      type: const("ref/prompt")
    },
    required: [:name, :type],
    title: "PromptReference",
    type: "object"
  }
end

defmodule GenMcp.Entities.ReadResourceRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Sent from the client to the server, to read a specific resource URI.",
    properties: %{
      id: GenMcp.Entities.RequestId,
      method: const("resources/read"),
      params: %{
        properties: %{
          _meta: GenMcp.Entities.RequestMeta,
          uri:
            uri(
              description:
                "The URI of the resource to read. The URI can use any protocol; it is up to the server how to interpret it."
            )
        },
        required: ["uri"],
        type: "object"
      }
    },
    required: [:method, :params],
    title: "ReadResourceRequest",
    type: "object"
  }
end

defmodule GenMcp.Entities.ReadResourceResult do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "The server's response to a resources/read request from the client.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      contents:
        array_of(%{
          anyOf: [GenMcp.Entities.TextResourceContents, GenMcp.Entities.BlobResourceContents]
        })
    },
    required: [:contents],
    title: "ReadResourceResult",
    type: "object"
  }
end

defmodule GenMcp.Entities.Request do
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
            description:
              "See [specification/2025-06-18/basic/index#general-fields] for notes on _meta usage.",
            properties: %{progressToken: GenMcp.Entities.ProgressToken},
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
end

defmodule GenMcp.Entities.RequestId do
  use JSV.Schema

  def json_schema do
    %{
      description: "A uniquely identifying ID for a request in JSON-RPC.",
      type: ["string", "integer"]
    }
  end
end

defmodule GenMcp.Entities.Resource do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "A known resource that the server is capable of reading.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      annotations: GenMcp.Entities.Annotations,
      description:
        string(
          description:
            "A description of what this resource represents.\n\nThis can be used by clients to improve the LLM's understanding of available resources. It can be thought of like a \"hint\" to the model."
        ),
      mimeType: string(description: "The MIME type of this resource, if known."),
      name:
        string(
          description:
            "Intended for programmatic or logical use, but used as a display name in past specs or fallback (if title isn't present)."
        ),
      size:
        integer(
          description:
            "The size of the raw resource content, in bytes (i.e., before base64 encoding or any tokenization), if known.\n\nThis can be used by Hosts to display file sizes and estimate context window usage."
        ),
      title:
        string(
          description:
            "Intended for UI and end-user contexts — optimized to be human-readable and easily understood,\neven by those unfamiliar with domain-specific terminology.\n\nIf not provided, the name should be used for display (except for Tool,\nwhere `annotations.title` should be given precedence over using `name`,\nif present)."
        ),
      uri: uri(description: "The URI of this resource.")
    },
    required: [:name, :uri],
    title: "Resource",
    type: "object"
  }
end

defmodule GenMcp.Entities.ResourceContents do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "The contents of a specific resource or sub-resource.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      mimeType: string(description: "The MIME type of this resource, if known."),
      uri: uri(description: "The URI of this resource.")
    },
    required: [:uri],
    title: "ResourceContents",
    type: "object"
  }
end

defmodule GenMcp.Entities.ResourceLink do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "A resource that the server is capable of reading, included in a prompt or tool call result.\n\nNote: resource links returned by tools are not guaranteed to appear in the results of `resources/list` requests.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      annotations: GenMcp.Entities.Annotations,
      description:
        string(
          description:
            "A description of what this resource represents.\n\nThis can be used by clients to improve the LLM's understanding of available resources. It can be thought of like a \"hint\" to the model."
        ),
      mimeType: string(description: "The MIME type of this resource, if known."),
      name:
        string(
          description:
            "Intended for programmatic or logical use, but used as a display name in past specs or fallback (if title isn't present)."
        ),
      size:
        integer(
          description:
            "The size of the raw resource content, in bytes (i.e., before base64 encoding or any tokenization), if known.\n\nThis can be used by Hosts to display file sizes and estimate context window usage."
        ),
      title:
        string(
          description:
            "Intended for UI and end-user contexts — optimized to be human-readable and easily understood,\neven by those unfamiliar with domain-specific terminology.\n\nIf not provided, the name should be used for display (except for Tool,\nwhere `annotations.title` should be given precedence over using `name`,\nif present)."
        ),
      type: const("resource_link"),
      uri: uri(description: "The URI of this resource.")
    },
    required: [:name, :type, :uri],
    title: "ResourceLink",
    type: "object"
  }
end

defmodule GenMcp.Entities.ResourceListChangedNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "An optional notification from the server to the client, informing it that the list of resources it can read from has changed. This may be issued by servers without any previous subscription from the client.",
    properties: %{
      method: const("notifications/resources/list_changed"),
      params: %{
        additionalProperties: %{},
        properties: %{_meta: GenMcp.Entities.Meta},
        type: "object"
      }
    },
    required: [:method],
    title: "ResourceListChangedNotification",
    type: "object"
  }
end

defmodule GenMcp.Entities.ResourceTemplate do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "A template description for resources available on the server.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      annotations: GenMcp.Entities.Annotations,
      description:
        string(
          description:
            "A description of what this template is for.\n\nThis can be used by clients to improve the LLM's understanding of available resources. It can be thought of like a \"hint\" to the model."
        ),
      mimeType:
        string(
          description:
            "The MIME type for all resources that match this template. This should only be included if all resources matching this template have the same type."
        ),
      name:
        string(
          description:
            "Intended for programmatic or logical use, but used as a display name in past specs or fallback (if title isn't present)."
        ),
      title:
        string(
          description:
            "Intended for UI and end-user contexts — optimized to be human-readable and easily understood,\neven by those unfamiliar with domain-specific terminology.\n\nIf not provided, the name should be used for display (except for Tool,\nwhere `annotations.title` should be given precedence over using `name`,\nif present)."
        ),
      uriTemplate:
        string_of("uri-template",
          description:
            "A URI template (according to RFC 6570) that can be used to construct resource URIs."
        )
    },
    required: [:name, :uriTemplate],
    title: "ResourceTemplate",
    type: "object"
  }
end

defmodule GenMcp.Entities.ResourceTemplateReference do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "A reference to a resource or resource template definition.",
    properties: %{
      type: const("ref/resource"),
      uri: string_of("uri-template", description: "The URI or URI template of the resource.")
    },
    required: [:type, :uri],
    title: "ResourceTemplateReference",
    type: "object"
  }
end

defmodule GenMcp.Entities.ResourceUpdatedNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "A notification from the server to the client, informing it that a resource has changed and may need to be read again. This should only be sent if the client previously sent a resources/subscribe request.",
    properties: %{
      method: const("notifications/resources/updated"),
      params: %{
        properties: %{
          uri:
            uri(
              description:
                "The URI of the resource that has been updated. This might be a sub-resource of the one that the client actually subscribed to."
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
end

defmodule GenMcp.Entities.Result do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    additionalProperties: %{},
    properties: %{_meta: GenMcp.Entities.Meta},
    title: "Result",
    type: "object"
  }
end

defmodule GenMcp.Entities.Role do
  use JSV.Schema

  def json_schema do
    string_enum_to_atom([:assistant, :user])
  end
end

defmodule GenMcp.Entities.Root do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Represents a root directory or file that the server can operate on.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      name:
        string(
          description:
            "An optional name for the root. This can be used to provide a human-readable\nidentifier for the root, which may be useful for display purposes or for\nreferencing the root in other parts of the application."
        ),
      uri:
        uri(
          description:
            "The URI identifying the root. This *must* start with file:// for now.\nThis restriction may be relaxed in future versions of the protocol to allow\nother URI schemes."
        )
    },
    required: [:uri],
    title: "Root",
    type: "object"
  }
end

defmodule GenMcp.Entities.RootsListChangedNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "A notification from the client to the server, informing it that the list of roots has changed.\nThis notification should be sent whenever the client adds, removes, or modifies any root.\nThe server should then request an updated list of roots using the ListRootsRequest.",
    properties: %{
      method: const("notifications/roots/list_changed"),
      params: %{
        additionalProperties: %{},
        properties: %{_meta: GenMcp.Entities.Meta},
        type: "object"
      }
    },
    required: [:method],
    title: "RootsListChangedNotification",
    type: "object"
  }
end

defmodule GenMcp.Entities.SamplingMessage do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Describes a message issued to or received from an LLM API.",
    properties: %{
      content: %{
        anyOf: [
          GenMcp.Entities.TextContent,
          GenMcp.Entities.ImageContent,
          GenMcp.Entities.AudioContent
        ]
      },
      role: GenMcp.Entities.Role
    },
    required: [:content, :role],
    title: "SamplingMessage",
    type: "object"
  }
end

defmodule GenMcp.Entities.ServerCapabilities do
  use JSV.Schema
  JsonDerive.auto()

  def json_schema do
    %{
      description:
        "Capabilities that a server may support. Known capabilities are defined here, in this schema, but this is not a closed set: any server can define its own, additional capabilities.",
      properties: %{
        completions: %{
          additionalProperties: true,
          description: "Present if the server supports argument autocompletion suggestions.",
          properties: %{},
          type: "object"
        },
        experimental: %{
          additionalProperties: %{
            additionalProperties: true,
            properties: %{},
            type: "object"
          },
          description: "Experimental, non-standard capabilities that the server supports.",
          type: "object"
        },
        logging: %{
          additionalProperties: true,
          description: "Present if the server supports sending log messages to the client.",
          properties: %{},
          type: "object"
        },
        prompts: %{
          description: "Present if the server offers any prompt templates.",
          properties: %{
            listChanged:
              boolean(
                description:
                  "Whether this server supports notifications for changes to the prompt list."
              )
          },
          type: "object"
        },
        resources: %{
          description: "Present if the server offers any resources to read.",
          properties: %{
            listChanged:
              boolean(
                description:
                  "Whether this server supports notifications for changes to the resource list."
              ),
            subscribe:
              boolean(
                description: "Whether this server supports subscribing to resource updates."
              )
          },
          type: "object"
        },
        tools: %{
          description: "Present if the server offers any tools to call.",
          properties: %{
            listChanged:
              boolean(
                description:
                  "Whether this server supports notifications for changes to the tool list."
              )
          },
          type: "object"
        }
      },
      title: "ServerCapabilities",
      type: "object"
    }
  end
end

defmodule GenMcp.Entities.ServerNotification do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMcp.Entities.CancelledNotification,
        GenMcp.Entities.ProgressNotification,
        GenMcp.Entities.ResourceListChangedNotification,
        GenMcp.Entities.ResourceUpdatedNotification,
        GenMcp.Entities.PromptListChangedNotification,
        GenMcp.Entities.ToolListChangedNotification,
        GenMcp.Entities.LoggingMessageNotification
      ]
    }
  end
end

defmodule GenMcp.Entities.ServerRequest do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMcp.Entities.PingRequest,
        GenMcp.Entities.CreateMessageRequest,
        GenMcp.Entities.ListRootsRequest,
        GenMcp.Entities.ElicitRequest
      ]
    }
  end
end

defmodule GenMcp.Entities.ServerResult do
  use JSV.Schema

  def json_schema do
    %{
      anyOf: [
        GenMcp.Entities.Result,
        GenMcp.Entities.InitializeResult,
        GenMcp.Entities.ListResourcesResult,
        GenMcp.Entities.ListResourceTemplatesResult,
        GenMcp.Entities.ReadResourceResult,
        GenMcp.Entities.ListPromptsResult,
        GenMcp.Entities.GetPromptResult,
        GenMcp.Entities.ListToolsResult,
        GenMcp.Entities.CallToolResult,
        GenMcp.Entities.CompleteResult
      ]
    }
  end
end

defmodule GenMcp.Entities.SetLevelRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "A request from the client to the server, to enable or adjust logging.",
    properties: %{
      id: GenMcp.Entities.RequestId,
      method: const("logging/setLevel"),
      params: %{
        properties: %{
          _meta: GenMcp.Entities.RequestMeta,
          level: GenMcp.Entities.LoggingLevel
        },
        required: ["level"],
        type: "object"
      }
    },
    required: [:method, :params],
    title: "SetLevelRequest",
    type: "object"
  }
end

defmodule GenMcp.Entities.StringSchema do
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
end

defmodule GenMcp.Entities.SubscribeRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "Sent from the client to request resources/updated notifications from the server whenever a particular resource changes.",
    properties: %{
      id: GenMcp.Entities.RequestId,
      method: const("resources/subscribe"),
      params: %{
        properties: %{
          _meta: GenMcp.Entities.RequestMeta,
          uri:
            uri(
              description:
                "The URI of the resource to subscribe to. The URI can use any protocol; it is up to the server how to interpret it."
            )
        },
        required: ["uri"],
        type: "object"
      }
    },
    required: [:method, :params],
    title: "SubscribeRequest",
    type: "object"
  }
end

defmodule GenMcp.Entities.TextContent do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Text provided to or from an LLM.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      annotations: GenMcp.Entities.Annotations,
      text: string(description: "The text content of the message."),
      type: const("text")
    },
    required: [:text, :type],
    title: "TextContent",
    type: "object"
  }
end

defmodule GenMcp.Entities.TextResourceContents do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    properties: %{
      _meta: GenMcp.Entities.Meta,
      mimeType: string(description: "The MIME type of this resource, if known."),
      text:
        string(
          description:
            "The text of the item. This must only be set if the item can actually be represented as text (not binary data)."
        ),
      uri: uri(description: "The URI of this resource.")
    },
    required: [:text, :uri],
    title: "TextResourceContents",
    type: "object"
  }
end

defmodule GenMcp.Entities.Tool do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description: "Definition for a tool the client can call.",
    properties: %{
      _meta: GenMcp.Entities.Meta,
      annotations: GenMcp.Entities.ToolAnnotations,
      description:
        string(
          description:
            "A human-readable description of the tool.\n\nThis can be used by clients to improve the LLM's understanding of available tools. It can be thought of like a \"hint\" to the model."
        ),
      inputSchema: %{
        description: "A JSON Schema object defining the expected parameters for the tool.",
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
          description:
            "Intended for programmatic or logical use, but used as a display name in past specs or fallback (if title isn't present)."
        ),
      outputSchema: %{
        description:
          "An optional JSON Schema object defining the structure of the tool's output returned in\nthe structuredContent field of a CallToolResult.",
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
          description:
            "Intended for UI and end-user contexts — optimized to be human-readable and easily understood,\neven by those unfamiliar with domain-specific terminology.\n\nIf not provided, the name should be used for display (except for Tool,\nwhere `annotations.title` should be given precedence over using `name`,\nif present)."
        )
    },
    required: [:inputSchema, :name],
    title: "Tool",
    type: "object"
  }
end

defmodule GenMcp.Entities.ToolAnnotations do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "Additional properties describing a Tool to clients.\n\nNOTE: all properties in ToolAnnotations are **hints**.\nThey are not guaranteed to provide a faithful description of\ntool behavior (including descriptive properties like `title`).\n\nClients should never make tool use decisions based on ToolAnnotations\nreceived from untrusted servers.",
    properties: %{
      destructiveHint:
        boolean(
          description:
            "If true, the tool may perform destructive updates to its environment.\nIf false, the tool performs only additive updates.\n\n(This property is meaningful only when `readOnlyHint == false`)\n\nDefault: true"
        ),
      idempotentHint:
        boolean(
          description:
            "If true, calling the tool repeatedly with the same arguments\nwill have no additional effect on the its environment.\n\n(This property is meaningful only when `readOnlyHint == false`)\n\nDefault: false"
        ),
      openWorldHint:
        boolean(
          description:
            "If true, this tool may interact with an \"open world\" of external\nentities. If false, the tool's domain of interaction is closed.\nFor example, the world of a web search tool is open, whereas that\nof a memory tool is not.\n\nDefault: true"
        ),
      readOnlyHint:
        boolean(
          description: "If true, the tool does not modify its environment.\n\nDefault: false"
        ),
      title: string(description: "A human-readable title for the tool.")
    },
    title: "ToolAnnotations",
    type: "object"
  }
end

defmodule GenMcp.Entities.ToolListChangedNotification do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "An optional notification from the server to the client, informing it that the list of tools it offers has changed. This may be issued by servers without any previous subscription from the client.",
    properties: %{
      method: const("notifications/tools/list_changed"),
      params: %{
        additionalProperties: %{},
        properties: %{_meta: GenMcp.Entities.Meta},
        type: "object"
      }
    },
    required: [:method],
    title: "ToolListChangedNotification",
    type: "object"
  }
end

defmodule GenMcp.Entities.UnsubscribeRequest do
  use JSV.Schema
  JsonDerive.auto()

  defschema %{
    description:
      "Sent from the client to request cancellation of resources/updated notifications from the server. This should follow a previous resources/subscribe request.",
    properties: %{
      id: GenMcp.Entities.RequestId,
      method: const("resources/unsubscribe"),
      params: %{
        properties: %{
          _meta: GenMcp.Entities.RequestMeta,
          uri: uri(description: "The URI of the resource to unsubscribe from.")
        },
        required: ["uri"],
        type: "object"
      }
    },
    required: [:method, :params],
    title: "UnsubscribeRequest",
    type: "object"
  }
end
