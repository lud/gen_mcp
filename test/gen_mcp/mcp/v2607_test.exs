defmodule GenMCP.MCP.V2607Test do
  use ExUnit.Case, async: true

  alias GenMCP.MCP.V2607, as: MCP
  alias GenMCP.MCP.V2607.Info
  alias GenMCP.MCP.V2607.ModMap
  alias GenMCP.MCP.V2607.TextContent

  require ModMap

  ModMap.require_all()

  describe "Info.subscription_notification_methods/0" do
    test "returns the listen-stream notification methods that require subscriptionId" do
      assert [
               "notifications/prompts/list_changed",
               "notifications/resources/list_changed",
               "notifications/resources/updated",
               "notifications/subscriptions/acknowledged",
               "notifications/tools/list_changed"
             ] == Info.subscription_notification_methods()
    end

    test "recognizes subscription-stream methods and excludes unrelated notifications" do
      assert true ==
               Info.subscription_notification_method?("notifications/subscriptions/acknowledged")

      assert true == Info.subscription_notification_method?("notifications/tools/list_changed")
      assert false == Info.subscription_notification_method?("notifications/cancelled")
      assert false == Info.subscription_notification_method?("notifications/progress")
      assert false == Info.subscription_notification_method?("foo")
    end
  end

  describe "discover_result/1" do
    test "creates discover result with required server_info and default capabilities" do
      server_info = %MCP.Implementation{
        name: "TestServer",
        version: "1.0.0"
      }

      result = MCP.discover_result(name: "TestServer", version: "1.0.0")

      assert %MCP.DiscoverResult{
               resultType: "complete",
               capabilities: %MCP.ServerCapabilities{
                 tools: nil,
                 resources: nil,
                 prompts: nil
               },
               serverInfo: ^server_info,
               supportedVersions: ["2026-07-28"]
             } = result
    end

    test "creates discover result with custom capabilities" do
      capabilities = %MCP.ServerCapabilities{
        tools: %{},
        resources: %{}
      }

      result =
        MCP.discover_result(
          name: "TestServer",
          version: "1.0.0",
          capabilities: capabilities
        )

      assert %MCP.DiscoverResult{
               resultType: "complete",
               capabilities: ^capabilities,
               serverInfo: %MCP.Implementation{name: "TestServer", version: "1.0.0"},
               supportedVersions: ["2026-07-28"]
             } = result
    end

    test "raises when server name is missing" do
      assert_raise KeyError, ~r/option :name is required/, fn ->
        MCP.discover_result(version: "1.0.0")
      end
    end
  end

  describe "capabilities/1" do
    test "unset keys remain nil" do
      result = MCP.capabilities([])

      assert %MCP.ServerCapabilities{
               tools: nil,
               resources: nil,
               prompts: nil
             } = result
    end

    test "cast capabilities to map when true" do
      result = MCP.capabilities(tools: true, resources: true, prompts: true)

      assert %MCP.ServerCapabilities{
               tools: %{},
               resources: %{},
               prompts: %{}
             } = result
    end

    test "keep capabilities to nil when false or nil" do
      result = MCP.capabilities(tools: false, resources: nil, prompts: false)

      assert %MCP.ServerCapabilities{
               tools: nil,
               resources: nil,
               prompts: nil
             } = result
    end

    test "creates capabilities with custom maps" do
      tools = %{listChanged: true}
      resources = %{subscribe: true, listChanged: false}
      prompts = %{some: :custom, map: :values}

      result = MCP.capabilities(tools: tools, resources: resources, prompts: prompts)

      assert %MCP.ServerCapabilities{
               tools: ^tools,
               resources: ^resources,
               prompts: ^prompts
             } = result
    end

    test "a ServerCapabilities struct is returned as-is" do
      caps = %MCP.ServerCapabilities{tools: %{}, resources: %{listChanged: true}}

      assert ^caps = MCP.capabilities(caps)
    end
  end

  describe "server_info/1" do
    test "creates server info with required name and version" do
      result = MCP.server_info(name: "MyServer", version: "2.0.0")

      assert %MCP.Implementation{
               name: "MyServer",
               version: "2.0.0",
               title: nil
             } = result
    end

    test "creates server info with optional title" do
      result =
        MCP.server_info(
          name: "MyServer",
          version: "2.0.0",
          title: "My Awesome Server"
        )

      assert %MCP.Implementation{
               name: "MyServer",
               version: "2.0.0",
               title: "My Awesome Server"
             } = result
    end

    test "raises when name is missing" do
      assert_raise KeyError, ~r/option :name is required/, fn ->
        MCP.server_info(version: "1.0.0")
      end
    end

    test "raises when version is missing" do
      assert_raise KeyError, ~r/option :version is required/, fn ->
        MCP.server_info(name: "MyServer")
      end
    end
  end

  describe "list_tools_result/1" do
    test "creates result with empty list" do
      result = MCP.list_tools_result([])

      assert %MCP.ListToolsResult{
               tools: [],
               nextCursor: nil
             } = result
    end

    test "creates result with MCP.Tool structs" do
      tool1 = %MCP.Tool{
        name: "tool1",
        description: "First tool",
        inputSchema: %{"type" => "object"}
      }

      tool2 = %MCP.Tool{
        name: "tool2",
        description: "Second tool",
        inputSchema: %{"type" => "object"}
      }

      result = MCP.list_tools_result([tool1, tool2])

      assert %MCP.ListToolsResult{
               tools: [^tool1, ^tool2],
               nextCursor: nil
             } = result
    end

    test "creates result with mixed tool types" do
      tool_struct = %MCP.Tool{
        name: "tool1",
        description: "First tool",
        inputSchema: %{"type" => "object"}
      }

      # This test would need a mock tool module to work properly
      result = MCP.list_tools_result([tool_struct])

      assert %MCP.ListToolsResult{
               tools: [^tool_struct],
               nextCursor: nil
             } = result
    end
  end

  describe "call_tool_result/1" do
    test "creates result with single text content" do
      result = MCP.call_tool_result(text: "Hello, world!")

      assert %MCP.CallToolResult{
               content: [%MCP.TextContent{text: "Hello, world!"}],
               structuredContent: nil,
               isError: nil
             } = result
    end

    test "creates result with multiple text contents" do
      result =
        MCP.call_tool_result(
          text: "First message",
          text: "Second message"
        )

      assert %MCP.CallToolResult{
               content: [
                 %MCP.TextContent{text: "First message"},
                 %MCP.TextContent{text: "Second message"}
               ],
               structuredContent: nil,
               isError: nil
             } = result
    end

    test "creates result with media contents" do
      result =
        MCP.call_tool_result(
          image: {"image/png", "some-base-64"},
          audio: {"audio/wav", "some-base-64"}
        )

      assert %MCP.CallToolResult{
               content: [
                 %MCP.ImageContent{mimeType: "image/png", data: "some-base-64"},
                 %MCP.AudioContent{mimeType: "audio/wav", data: "some-base-64"}
               ],
               structuredContent: nil,
               isError: nil
             } = result
    end

    test "creates result with embedded resources" do
      result =
        MCP.call_tool_result(
          resource: %{text: "some text", uri: "some-uri"},
          resource: %{blob: "some blob", uri: "some-uri"}
        )

      assert %MCP.CallToolResult{
               content: [
                 %MCP.EmbeddedResource{
                   resource: %{text: "some text", uri: "some-uri"}
                 },
                 %MCP.EmbeddedResource{
                   resource: %{blob: "some blob", uri: "some-uri"}
                 }
               ],
               structuredContent: nil,
               isError: nil
             } = result
    end

    test "creates result with resource links" do
      result =
        MCP.call_tool_result(
          link: %{name: "some name", uri: "some-uri"},
          link: %{name: "some name", uri: "some-uri", custom: "foo"}
        )

      assert %MCP.CallToolResult{
               content: [
                 %MCP.ResourceLink{
                   name: "some name",
                   uri: "some-uri"
                 },
                 %MCP.ResourceLink{
                   name: "some name",
                   uri: "some-uri"
                 }
               ],
               structuredContent: nil,
               isError: nil
             } = result
    end

    test "creates result with existing structs" do
      # When structs are used, the helpers will do make any additional casting,
      # invalid structs will go through
      #
      # it's possible to mix keyword lists and structs
      result =
        MCP.call_tool_result(
          :lists.flatten([
            [
              %MCP.TextContent{text: 123, annotations: 123},
              %MCP.AudioContent{data: 123, mimeType: 123, annotations: 123},
              %MCP.ImageContent{data: 123, mimeType: 123, annotations: 123}
            ],
            [text: "using shortcut"],
            [
              %MCP.EmbeddedResource{resource: 123, annotations: 123},
              %MCP.ResourceLink{name: 123, uri: 123, annotations: 123}
            ]
          ])
        )

      assert %MCP.CallToolResult{
               resultType: "complete",
               content: [
                 %MCP.TextContent{text: 123, annotations: 123},
                 %MCP.AudioContent{data: 123, mimeType: 123, annotations: 123},
                 %MCP.ImageContent{data: 123, mimeType: 123, annotations: 123},
                 %MCP.TextContent{text: "using shortcut"},
                 %MCP.EmbeddedResource{resource: 123, annotations: 123},
                 %MCP.ResourceLink{name: 123, uri: 123, annotations: 123}
               ],
               structuredContent: nil,
               isError: nil
             } == result
    end

    test "other maps are returned as structured content" do
      # structured content is also returned as text

      result =
        MCP.call_tool_result([
          {:text, "foo"},
          %{foo: :bar}
        ])

      assert %MCP.CallToolResult{
               resultType: "complete",
               content: [
                 %TextContent{text: "foo"},
                 %TextContent{text: ~s({"foo":"bar"})}
               ],
               structuredContent: %{foo: :bar},
               isError: nil
             } == result
    end

    test ":data shortcut sets structured content and mirrors it as text" do
      result =
        MCP.call_tool_result(
          text: "summary",
          data: %{rows: 3}
        )

      assert %MCP.CallToolResult{
               resultType: "complete",
               content: [
                 %TextContent{text: "summary"},
                 %TextContent{text: ~s({"rows":3})}
               ],
               structuredContent: %{rows: 3},
               isError: nil
             } == result
    end

    test ":_data shortcut sets structured content without text mirror" do
      result =
        MCP.call_tool_result(
          text: "summary",
          _data: %{rows: 3}
        )

      assert %MCP.CallToolResult{
               resultType: "complete",
               content: [
                 %TextContent{text: "summary"}
               ],
               structuredContent: %{rows: 3},
               isError: nil
             } == result
    end

    test ":_data shortcut alone produces only structured content" do
      result = MCP.call_tool_result(_data: %{ok: true})

      assert %MCP.CallToolResult{
               resultType: "complete",
               content: [],
               structuredContent: %{ok: true},
               isError: nil
             } == result
    end

    test "cannot return structured content twice" do
      assert_raise ArgumentError, ~r/cannot return multiple structured content/, fn ->
        MCP.call_tool_result([
          %{foo: :bar},
          %{foo: :other}
        ])
      end
    end

    test "cannot mix :data and :_data" do
      assert_raise ArgumentError, ~r/cannot return multiple structured content/, fn ->
        MCP.call_tool_result(data: %{foo: :bar}, _data: %{foo: :other})
      end
    end

    test "cannot mix :data with a naked map" do
      assert_raise ArgumentError, ~r/cannot return multiple structured content/, fn ->
        MCP.call_tool_result([{:data, %{foo: :bar}}, %{foo: :other}])
      end
    end

    test "creates result with error flag set to true" do
      result =
        MCP.call_tool_result(
          text: "Error occurred",
          error: true
        )

      assert %MCP.CallToolResult{
               content: [%MCP.TextContent{text: "Error occurred"}],
               structuredContent: nil,
               isError: true
             } = result
    end

    test "creates error result with text content" do
      result = MCP.call_tool_result(error: "something bad")

      assert %MCP.CallToolResult{
               content: [%MCP.TextContent{text: "something bad"}],
               structuredContent: nil,
               isError: true
             } = result
    end

    test "supports error: false" do
      result =
        MCP.call_tool_result(
          text: "Success",
          error: false
        )

      assert %MCP.CallToolResult{
               content: [%MCP.TextContent{text: "Success"}],
               structuredContent: nil,
               isError: nil
             } = result
    end

    test "supports error: nil" do
      result =
        MCP.call_tool_result(error: nil)

      assert %MCP.CallToolResult{
               content: [],
               structuredContent: nil,
               isError: nil
             } = result
    end

    test "preserves error flag as true even with false in list" do
      result =
        MCP.call_tool_result(
          text: "Message",
          error: true,
          error: false
        )

      assert %MCP.CallToolResult{
               isError: true
             } = result
    end

    test "creates result with empty content list" do
      result = MCP.call_tool_result([])

      assert %MCP.CallToolResult{
               content: [],
               structuredContent: nil,
               isError: nil
             } = result
    end

    test "other shortcuts" do
      assert_raise ArgumentError, ~r/unsupported content block definition/, fn ->
        MCP.call_tool_result(foo: "bar")
      end
    end
  end

  describe "list_resources_result/2" do
    test "creates result with empty resources and no cursor" do
      result = MCP.list_resources_result([], nil)

      assert %MCP.ListResourcesResult{
               resources: [],
               nextCursor: nil
             } = result
    end

    test "creates result with resources and no cursor" do
      # For now anything that is passed in the helper gets wrapped as-is
      result = MCP.list_resources_result([:foo], nil)

      assert %MCP.ListResourcesResult{
               resources: [:foo],
               nextCursor: nil
             } = result
    end

    test "creates result with resources and cursor" do
      # For now anything that is passed in the helper gets wrapped as-is
      result = MCP.list_resources_result([:foo], "next-page-token")

      assert %MCP.ListResourcesResult{
               resources: [:foo],
               nextCursor: "next-page-token"
             } = result
    end

    test "creates result with multiple resources" do
      # For now anything that is passed in the helper gets wrapped as-is
      result = MCP.list_resources_result([:resource1, :resource2], "cursor-123")

      assert %MCP.ListResourcesResult{
               resources: [:resource1, :resource2],
               nextCursor: "cursor-123"
             } = result
    end
  end

  describe "list_resource_templates_result/1" do
    test "creates result with empty templates" do
      result = MCP.list_resource_templates_result([])

      assert %MCP.ListResourceTemplatesResult{
               resourceTemplates: []
             } = result
    end

    test "creates result with single template" do
      # resource templates are returned as is for now

      result = MCP.list_resource_templates_result([:foo])

      assert %MCP.ListResourceTemplatesResult{
               resourceTemplates: [:foo]
             } = result
    end
  end

  describe "read_resource_result/1" do
    # The helper function returns a single result, using all the options to
    # define the content

    test "creates text resource result" do
      result = MCP.read_resource_result(uri: "file:///readme.txt", text: "# Welcome")

      assert %MCP.ReadResourceResult{
               contents: [
                 %MCP.TextResourceContents{
                   uri: "file:///readme.txt",
                   text: "# Welcome",
                   mimeType: nil
                 }
               ]
             } = result
    end

    test "creates text resource result with mime type" do
      result =
        MCP.read_resource_result(
          uri: "file:///index.html",
          text: "<p>Hello</p>",
          mime_type: "text/html"
        )

      assert %MCP.ReadResourceResult{
               contents: [
                 %MCP.TextResourceContents{
                   uri: "file:///index.html",
                   text: "<p>Hello</p>",
                   mimeType: "text/html"
                 }
               ]
             } = result
    end

    test "creates blob resource result" do
      blob_data = "some-base-64"

      result =
        MCP.read_resource_result(
          uri: "file:///image.png",
          blob: blob_data
        )

      assert %MCP.ReadResourceResult{
               contents: [
                 %MCP.BlobResourceContents{
                   uri: "file:///image.png",
                   blob: ^blob_data,
                   mimeType: nil
                 }
               ]
             } = result
    end

    test "creates blob resource result with mime type" do
      blob_data = "some-base-64"

      result =
        MCP.read_resource_result(
          uri: "file:///doc.pdf",
          blob: blob_data,
          mime_type: "application/pdf"
        )

      assert %MCP.ReadResourceResult{
               contents: [
                 %MCP.BlobResourceContents{
                   uri: "file:///doc.pdf",
                   blob: ^blob_data,
                   mimeType: "application/pdf"
                 }
               ]
             } = result
    end

    # Giving structs/maps instead of options to the helper will return multiple
    # content elements
    test "multiple contents from structs" do
      result =
        MCP.read_resource_result(
          contents: [
            MCP.resource_contents(
              blob: "some-base-64",
              uri: "file:///doc.pdf",
              mime_type: "application/pdf"
            ),
            MCP.resource_contents(
              text: "some html",
              uri: "file:///doc.html",
              mime_type: "text/html"
            ),
            %{custom: :foo}
          ]
        )

      assert %MCP.ReadResourceResult{
               contents: [
                 %MCP.BlobResourceContents{
                   uri: "file:///doc.pdf",
                   blob: "some-base-64",
                   mimeType: "application/pdf"
                 },
                 %MCP.TextResourceContents{
                   text: "some html",
                   uri: "file:///doc.html",
                   mimeType: "text/html"
                 },
                 %{custom: :foo}
               ]
             } = result
    end

    test "raises when uri is missing" do
      assert_raise KeyError, ~r/option :uri is required/, fn ->
        MCP.read_resource_result(text: "content")
      end
    end

    test "raises when neither text nor blob is provided" do
      assert_raise ArgumentError, ~r/requires either :text or :blob option/, fn ->
        MCP.read_resource_result(uri: "file:///test.txt")
      end
    end

    # --- edge cases for the flat `:contents` API (spec 005) -----------------

    test ":contents takes precedence over :uri/:text/:blob, which are ignored" do
      result =
        MCP.read_resource_result(
          uri: "file:///ignored.txt",
          text: "ignored",
          contents: [MCP.resource_contents(uri: "file:///real.txt", text: "real")]
        )

      assert %MCP.ReadResourceResult{
               contents: [%MCP.TextResourceContents{uri: "file:///real.txt", text: "real"}]
             } = result
    end

    test "an empty :contents list passes through as empty contents" do
      # `contents` has no `minItems` in the schema, so the builder permits an
      # empty list. Whether a server *should* return zero contents is a usage
      # question, not a builder concern.
      assert %MCP.ReadResourceResult{contents: []} = MCP.read_resource_result(contents: [])
    end

    test ":_meta is preserved per content when built via the :contents form" do
      # Per-content `_meta` is attached via `resource_contents/1`; it is distinct
      # from the top-level `:_meta`, which feeds the result object (below).
      result =
        MCP.read_resource_result(
          contents: [MCP.resource_contents(uri: "file:///a.txt", text: "x", _meta: %{trace: 1})]
        )

      assert %MCP.ReadResourceResult{
               contents: [%MCP.TextResourceContents{_meta: %{trace: 1}}]
             } = result
    end

    test "top-level :_meta feeds the ReadResourceResult, not the content" do
      # On the single-content flat path, `:_meta` is split off as a wrapper opt
      # and set on the result object; the built content keeps `_meta: nil`.
      result = MCP.read_resource_result(uri: "file:///a.txt", text: "x", _meta: %{trace: 1})

      assert %MCP.ReadResourceResult{
               _meta: %{trace: 1},
               contents: [%MCP.TextResourceContents{_meta: nil}]
             } = result
    end

    test "top-level :_meta is set on the result even when :contents is given" do
      result =
        MCP.read_resource_result(
          _meta: %{trace: 2},
          contents: [MCP.resource_contents(uri: "file:///a.txt", text: "x")]
        )

      assert %MCP.ReadResourceResult{
               _meta: %{trace: 2},
               contents: [%MCP.TextResourceContents{_meta: nil}]
             } = result
    end

    test "a keyword list given to :contents is rejected, not passed through verbatim" do
      # `contents: [uri: ..., text: ...]` is a keyword list, not a list of
      # content structs; today it silently becomes `contents: [{:uri, _}, ...]`.
      assert_raise ArgumentError, ~r/:contents/, fn ->
        MCP.read_resource_result(contents: [uri: "file:///a", text: "x"])
      end
    end
  end

  describe "list_prompts_result/2" do
    test "creates result with empty prompts and no cursor" do
      result = MCP.list_prompts_result([], nil)

      assert %MCP.ListPromptsResult{
               prompts: [],
               nextCursor: nil
             } = result
    end

    test "creates result with prompts and no cursor" do
      # For now returns the list as-is
      result = MCP.list_prompts_result([:foo], nil)

      assert %MCP.ListPromptsResult{
               prompts: [:foo],
               nextCursor: nil
             } = result
    end

    test "creates result with prompts and cursor" do
      # For now returns the list as-is
      result = MCP.list_prompts_result([:foo], "next-cursor-abc")

      assert %MCP.ListPromptsResult{
               prompts: [:foo],
               nextCursor: "next-cursor-abc"
             } = result
    end

    test "creates result with multiple prompts" do
      # For now returns the list as-is
      result = MCP.list_prompts_result([:prompt1, :prompt2], "cursor-xyz")

      assert %MCP.ListPromptsResult{
               prompts: [:prompt1, :prompt2],
               nextCursor: "cursor-xyz"
             } = result
    end
  end

  describe "get_prompt_result/1" do
    test "simple text and assistant text" do
      result =
        MCP.get_prompt_result(
          text: "hello user",
          assistant: "hello assistant",
          description: "some descr"
        )

      assert %MCP.GetPromptResult{
               description: "some descr",
               messages: [
                 %MCP.PromptMessage{
                   role: "user",
                   content: %MCP.TextContent{
                     text: "hello user"
                   }
                 },
                 %MCP.PromptMessage{
                   role: "assistant",
                   content: %MCP.TextContent{
                     text: "hello assistant"
                   }
                 }
               ]
             } = result
    end

    test "image content" do
      result =
        MCP.get_prompt_result(
          image: {"image/png", "base64data"},
          description: "image prompt"
        )

      assert %MCP.GetPromptResult{
               description: "image prompt",
               messages: [
                 %MCP.PromptMessage{
                   role: "user",
                   content: %MCP.ImageContent{
                     mimeType: "image/png",
                     data: "base64data"
                   }
                 }
               ]
             } = result
    end

    test "audio content" do
      result =
        MCP.get_prompt_result(audio: {"audio/mp3", "audiodata"})

      assert %MCP.GetPromptResult{
               messages: [
                 %MCP.PromptMessage{
                   role: "user",
                   content: %MCP.AudioContent{
                     mimeType: "audio/mp3",
                     data: "audiodata"
                   }
                 }
               ]
             } = result
    end

    test "embedded resource" do
      result =
        MCP.get_prompt_result(resource: %{text: "resource text", uri: "file:///resource.txt"})

      assert %MCP.GetPromptResult{
               messages: [
                 %MCP.PromptMessage{
                   role: "user",
                   content: %MCP.EmbeddedResource{
                     resource: %{text: "resource text", uri: "file:///resource.txt"}
                   }
                 }
               ]
             } = result
    end

    test "assistant text with media content" do
      # To use the "assistant" role with other content than text, the full
      # prompt message should be given
      result =
        MCP.get_prompt_result([
          {:text, "user message"},
          %MCP.PromptMessage{
            role: "assistant",
            content: MCP.content_block({:audio, {"mp3", "some-base-64"}})
          }
        ])

      assert %MCP.GetPromptResult{
               messages: [
                 %MCP.PromptMessage{role: "user"},
                 %MCP.PromptMessage{role: "assistant"}
               ]
             } = result
    end

    test "mixed user and assistant messages" do
      result =
        MCP.get_prompt_result(
          text: "user 1",
          assistant: "assistant 1",
          text: "user 2",
          assistant: "assistant 2"
        )

      assert %MCP.GetPromptResult{
               messages: [
                 %MCP.PromptMessage{role: "user", content: %MCP.TextContent{text: "user 1"}},
                 %MCP.PromptMessage{
                   role: "assistant",
                   content: %MCP.TextContent{text: "assistant 1"}
                 },
                 %MCP.PromptMessage{role: "user", content: %MCP.TextContent{text: "user 2"}},
                 %MCP.PromptMessage{
                   role: "assistant",
                   content: %MCP.TextContent{text: "assistant 2"}
                 }
               ]
             } = result
    end

    test "with only description" do
      result = MCP.get_prompt_result(description: "just description")

      assert %MCP.GetPromptResult{
               description: "just description",
               messages: []
             } = result
    end

    test "direct MCP.PromptMessage structs are supported" do
      prompt_message = %MCP.PromptMessage{
        role: "user",
        content: %MCP.TextContent{text: "direct message"}
      }

      result = MCP.get_prompt_result([prompt_message])

      assert %MCP.GetPromptResult{
               messages: [^prompt_message]
             } = result
    end

    test "%MCP.ResourceLink{} is not supported" do
      assert_raise ArgumentError, ~r/unsupported content block definition/, fn ->
        MCP.get_prompt_result([
          %MCP.ResourceLink{name: "link", uri: "file:///link"}
        ])
      end
    end

    test ":link option is not supported" do
      assert_raise ArgumentError, ~r/unsupported ResourceLink/, fn ->
        MCP.get_prompt_result(link: %{name: "link", uri: "file:///link"})
      end
    end

    test ":error option is not supported" do
      assert_raise ArgumentError, ~r/unsupported content block definition/, fn ->
        MCP.get_prompt_result(error: "some error")
      end
    end

    test "map is supported given a :role and :content keys" do
      result =
        MCP.get_prompt_result([
          %{role: "user", content: %MCP.TextContent{text: "from map"}},
          %{role: "assistant", content: %MCP.TextContent{text: "assistant from map"}}
        ])

      assert %MCP.GetPromptResult{
               messages: [
                 %{
                   role: "user",
                   content: %MCP.TextContent{text: "from map"}
                 },
                 %{
                   role: "assistant",
                   content: %MCP.TextContent{text: "assistant from map"}
                 }
               ]
             } = result
    end

    test "other map is not supported" do
      assert_raise ArgumentError, fn ->
        MCP.get_prompt_result([%{foo: "bar"}])
      end
    end
  end

  describe "cache hints (spec 005)" do
    # The list/read builders accept optional flat `cache_scope:` and `ttl_ms:`
    # opts (no nesting). Omitted, they default to the no-cache hint (private / 0)
    # that preserves pre-005 behaviour. Passing only one of the two fills the
    # other with that same no-cache default. `server/discover` is a capability
    # snapshot, not user content, so it keeps the no-cache default and takes no
    # cache opts.

    test "list_tools_result defaults to no-cache" do
      assert %MCP.ListToolsResult{cacheScope: :private, ttlMs: 0} =
               MCP.list_tools_result([])
    end

    test "list_tools_result honors an explicit cache hint" do
      assert %MCP.ListToolsResult{cacheScope: :public, ttlMs: 60_000} =
               MCP.list_tools_result([], cache_scope: :public, ttl_ms: 60_000)
    end

    test "list_resources_result defaults to no-cache" do
      assert %MCP.ListResourcesResult{cacheScope: :private, ttlMs: 0} =
               MCP.list_resources_result([], nil)
    end

    test "list_resources_result honors an explicit cache hint" do
      assert %MCP.ListResourcesResult{cacheScope: :public, ttlMs: 60_000} =
               MCP.list_resources_result([], nil, cache_scope: :public, ttl_ms: 60_000)
    end

    test "list_resource_templates_result defaults to no-cache" do
      assert %MCP.ListResourceTemplatesResult{cacheScope: :private, ttlMs: 0} =
               MCP.list_resource_templates_result([])
    end

    test "list_resource_templates_result honors an explicit cache hint" do
      assert %MCP.ListResourceTemplatesResult{cacheScope: :public, ttlMs: 60_000} =
               MCP.list_resource_templates_result([], cache_scope: :public, ttl_ms: 60_000)
    end

    test "read_resource_result (keyword form) defaults to no-cache" do
      assert %MCP.ReadResourceResult{cacheScope: :private, ttlMs: 0} =
               MCP.read_resource_result(uri: "file:///a.txt", text: "x")
    end

    test "read_resource_result (keyword form) honors an explicit cache hint" do
      assert %MCP.ReadResourceResult{cacheScope: :public, ttlMs: 60_000} =
               MCP.read_resource_result(
                 uri: "file:///a.txt",
                 text: "x",
                 cache_scope: :public,
                 ttl_ms: 60_000
               )
    end

    test "read_resource_result (contents form) honors an explicit cache hint" do
      contents = [MCP.resource_contents(uri: "file:///a.txt", text: "x")]

      assert %MCP.ReadResourceResult{cacheScope: :public, ttlMs: 60_000} =
               MCP.read_resource_result(contents: contents, cache_scope: :public, ttl_ms: 60_000)
    end

    test "list_prompts_result defaults to no-cache" do
      assert %MCP.ListPromptsResult{cacheScope: :private, ttlMs: 0} =
               MCP.list_prompts_result([], nil)
    end

    test "list_prompts_result honors an explicit cache hint" do
      assert %MCP.ListPromptsResult{cacheScope: :public, ttlMs: 60_000} =
               MCP.list_prompts_result([], nil, cache_scope: :public, ttl_ms: 60_000)
    end

    test "passing only one of the two opts fills the other with the no-cache default" do
      assert %MCP.ListToolsResult{cacheScope: :public, ttlMs: 0} =
               MCP.list_tools_result([], cache_scope: :public)

      assert %MCP.ListToolsResult{cacheScope: :private, ttlMs: 30_000} =
               MCP.list_tools_result([], ttl_ms: 30_000)
    end
  end

  describe "structs generate valid json" do
    test "discover request" do
      # Given a struct. Under the 2026 stateless core there is no `initialize`
      # handshake: the client info, capabilities and protocol version travel in
      # the request `_meta` instead. `server/discover` is the canonical
      # client->server request.
      data = %MCP.DiscoverRequest{
        id: 123,
        params: %MCP.RequestParams{
          _meta: %MCP.RequestMetaObject{
            "io.modelcontextprotocol/clientCapabilities": %MCP.ClientCapabilities{},
            "io.modelcontextprotocol/clientInfo": %MCP.Implementation{
              name: "clientname",
              version: "clientversion"
            },
            "io.modelcontextprotocol/protocolVersion": "2026-07-28"
          }
        }
      }

      # It should be JSON-encodable
      json = JSON.encode!(data)

      # When decoded
      raw = JSON.decode!(json)

      # Raw map should have RPC request fields
      assert %{"jsonrpc" => "2.0", "method" => "server/discover"} = raw

      # It should produce a valid discover request
      assert {:ok, :request, new_data} = GenMCP.Validator.validate_request(raw)

      assert %MCP.DiscoverRequest{
               id: 123,
               params: %MCP.RequestParams{
                 _meta: %MCP.RequestMetaObject{
                   "io.modelcontextprotocol/clientCapabilities": %MCP.ClientCapabilities{},
                   "io.modelcontextprotocol/clientInfo": %MCP.Implementation{
                     name: "clientname",
                     version: "clientversion"
                   },
                   "io.modelcontextprotocol/protocolVersion": "2026-07-28"
                 }
               }
             } = new_data
    end
  end
end
