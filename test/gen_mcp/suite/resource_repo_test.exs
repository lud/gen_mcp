defmodule GenMCP.Suite.ResourceRepoTest do
  alias GenMCP.MCP
  alias GenMCP.Mux.Channel
  alias GenMCP.Suite.ResourceRepo
  alias GenMCP.Support.ResourceRepoMock
  alias GenMCP.Support.ResourceRepoMockTpl
  alias GenMCP.Support.ResourceRepoMockTplNoSkip
  import GenMCP.Test.Helpers
  import Mox
  use ExUnit.Case, async: true

  setup :verify_on_exit!

  @moduletag :resource_repo

  describe "expand/1" do
    test "expands module to descriptor with empty arg list" do
      stub(ResourceRepoMock, :prefix, fn [] -> "file:///" end)

      descriptor = ResourceRepo.expand(ResourceRepoMock)

      assert %{
               mod: ResourceRepoMock,
               arg: [],
               prefix: "file:///",
               template: nil
             } = descriptor
    end

    test "expands {module, arg} tuple to descriptor" do
      stub(ResourceRepoMock, :prefix, fn :custom_arg -> "file:///" end)

      descriptor = ResourceRepo.expand({ResourceRepoMock, :custom_arg})

      assert %{
               mod: ResourceRepoMock,
               arg: :custom_arg,
               prefix: "file:///",
               template: nil
             } = descriptor
    end

    test "expands module with template to descriptor including template" do
      ResourceRepoMockTpl
      |> stub(:prefix, fn :arg -> "file:///" end)
      |> stub(:template, fn :arg ->
        %{
          uriTemplate: "file:///{path}",
          name: "FileTemplate",
          description: "A file resource"
        }
      end)

      descriptor = ResourceRepo.expand({ResourceRepoMockTpl, :arg})

      assert %{
               mod: ResourceRepoMockTpl,
               arg: :arg,
               prefix: "file:///",
               template: template
             } = descriptor

      assert %{
               uriTemplate: %Texture.UriTemplate{},
               name: "FileTemplate",
               description: "A file resource"
             } = template
    end

    test "raises ArgumentError when prefix is not a string" do
      stub(ResourceRepoMock, :prefix, fn _ -> :not_a_string end)

      assert_raise ArgumentError,
                   ~r/resource repo .* must return a string prefix, got: :not_a_string/,
                   fn ->
                     ResourceRepo.expand(ResourceRepoMock)
                   end
    end

    test "raises ArgumentError when template is missing required keys" do
      ResourceRepoMockTpl
      |> stub(:prefix, fn _ -> "file:///" end)
      |> stub(:template, fn _ -> %{uriTemplate: "file:///{path}"} end)

      assert_raise ArgumentError,
                   ~r/resource repo .* must return a map with :uriTemplate and :name keys/,
                   fn ->
                     ResourceRepo.expand(ResourceRepoMockTpl)
                   end
    end

    test "raises ArgumentError when uriTemplate is not a string" do
      ResourceRepoMockTpl
      |> stub(:prefix, fn _ -> "file:///" end)
      |> stub(:template, fn _ -> %{uriTemplate: :not_a_string, name: "Test"} end)

      assert_raise ArgumentError,
                   ~r/resource repo .* must return a map with :uriTemplate and :name keys/,
                   fn ->
                     ResourceRepo.expand(ResourceRepoMockTpl)
                   end
    end

    test "passes through valid descriptor maps" do
      descriptor = %{
        mod: ResourceRepoMock,
        arg: :some_arg,
        prefix: "file:///",
        template: nil
      }

      assert ^descriptor = ResourceRepo.expand(descriptor)
    end

    test "parses complex URI templates with multiple variables" do
      ResourceRepoMockTpl
      |> stub(:prefix, fn _ -> "http://api.example.com/" end)
      |> stub(:template, fn _ ->
        %{
          uriTemplate: "http://api.example.com/{version}/users/{userId}",
          name: "UserAPI"
        }
      end)

      descriptor = ResourceRepo.expand(ResourceRepoMockTpl)

      assert %{template: %{uriTemplate: %Texture.UriTemplate{}}} = descriptor
    end
  end

  describe "list_resources/3" do
    test "returns list of resources and nil cursor" do
      resources = [
        %{uri: "file:///file1.txt", name: "File 1"},
        %{uri: "file:///file2.txt", name: "File 2"}
      ]

      ResourceRepoMock
      |> stub(:prefix, fn _ -> "file:///" end)
      |> expect(:list, fn nil, channel, :arg ->
        assert %Channel{} = channel
        {resources, nil}
      end)

      repo = ResourceRepo.expand({ResourceRepoMock, :arg})
      channel = build_channel()

      {list, cursor} = ResourceRepo.list_resources(repo, nil, channel)

      assert ^resources = list
      assert is_nil(cursor)
    end

    test "returns list of resources and pagination cursor" do
      page1 = [%{uri: "file:///file1.txt", name: "File 1"}]

      ResourceRepoMock
      |> stub(:prefix, fn _ -> "file:///" end)
      |> expect(:list, fn nil, _channel, :arg ->
        {page1, "next-cursor"}
      end)

      repo = ResourceRepo.expand({ResourceRepoMock, :arg})
      channel = build_channel()

      {list, cursor} = ResourceRepo.list_resources(repo, nil, channel)

      assert ^page1 = list
      assert "next-cursor" = cursor
    end

    test "passes cursor to list callback for pagination" do
      ResourceRepoMock
      |> stub(:prefix, fn _ -> "file:///" end)
      |> expect(:list, fn "page-2", _channel, :arg ->
        {[%{uri: "file:///file3.txt", name: "File 3"}], nil}
      end)

      repo = ResourceRepo.expand({ResourceRepoMock, :arg})
      channel = build_channel()

      {list, cursor} = ResourceRepo.list_resources(repo, "page-2", channel)

      assert [%{name: "File 3"}] = list
      assert is_nil(cursor)
    end

    test "passes channel with assigns to list callback" do
      ResourceRepoMock
      |> stub(:prefix, fn _ -> "file:///" end)
      |> expect(:list, fn nil, channel, :arg ->
        assert %{user_id: 123, role: :admin} = channel.assigns
        {[], nil}
      end)

      repo = ResourceRepo.expand({ResourceRepoMock, :arg})
      channel = build_channel(%{user_id: 123, role: :admin})

      ResourceRepo.list_resources(repo, nil, channel)
    end

    test "exits with bad_return_value when list callback returns invalid format" do
      ResourceRepoMock
      |> stub(:prefix, fn _ -> "file:///" end)
      |> expect(:list, fn nil, _channel, :arg ->
        # Invalid: should return {list, cursor}
        :invalid_return
      end)

      repo = ResourceRepo.expand({ResourceRepoMock, :arg})
      channel = build_channel()

      assert catch_exit(ResourceRepo.list_resources(repo, nil, channel)) ==
               {:bad_return_value, :invalid_return}
    end
  end

  describe "read_resource/3 for direct resources" do
    test "returns resource result from callback module" do
      result = %MCP.ReadResourceResult{
        contents: [
          %MCP.TextResourceContents{
            uri: "file:///readme.txt",
            text: "# Welcome"
          }
        ]
      }

      ResourceRepoMock
      |> stub(:prefix, fn _ -> "file:///" end)
      |> expect(:read, fn "file:///readme.txt", channel, :arg ->
        assert %Channel{} = channel
        {:ok, result}
      end)

      repo = ResourceRepo.expand({ResourceRepoMock, :arg})
      channel = build_channel()

      assert {:ok, ^result} = ResourceRepo.read_resource(repo, "file:///readme.txt", channel)
    end

    test "returns {:error, {:resource_not_found, uri}} from {:error, :not_found}" do
      ResourceRepoMock
      |> stub(:prefix, fn _ -> "file:///" end)
      |> expect(:read, fn "file:///missing.txt", _channel, :arg ->
        {:error, :not_found}
      end)

      repo = ResourceRepo.expand({ResourceRepoMock, :arg})
      channel = build_channel()

      assert {:error, {:resource_not_found, "file:///missing.txt"}} =
               ResourceRepo.read_resource(repo, "file:///missing.txt", channel)
    end

    test "returns custom error message as-is" do
      ResourceRepoMock
      |> stub(:prefix, fn _ -> "file:///" end)
      |> expect(:read, fn "file:///invalid.txt", _channel, :arg ->
        {:error, "Invalid file format"}
      end)

      repo = ResourceRepo.expand({ResourceRepoMock, :arg})
      channel = build_channel()

      assert {:error, "Invalid file format"} =
               ResourceRepo.read_resource(repo, "file:///invalid.txt", channel)
    end

    test "passes channel with assigns to read callback" do
      result = %MCP.ReadResourceResult{contents: []}

      ResourceRepoMock
      |> stub(:prefix, fn _ -> "file:///" end)
      |> expect(:read, fn "file:///test.txt", channel, :arg ->
        assert %{user_id: 456, permissions: [:read]} = channel.assigns
        {:ok, result}
      end)

      repo = ResourceRepo.expand({ResourceRepoMock, :arg})
      channel = build_channel(%{user_id: 456, permissions: [:read]})

      assert {:ok, ^result} = ResourceRepo.read_resource(repo, "file:///test.txt", channel)
    end

    test "exits with bad_return_value when read callback returns invalid format" do
      ResourceRepoMock
      |> stub(:prefix, fn _ -> "file:///" end)
      |> expect(:read, fn "file:///test.txt", _channel, :arg ->
        # Invalid: should return {:ok, result} or {:error, _}
        :invalid_return
      end)

      repo = ResourceRepo.expand({ResourceRepoMock, :arg})
      channel = build_channel()

      assert catch_exit(ResourceRepo.read_resource(repo, "file:///test.txt", channel)) ==
               {:bad_return_value, :invalid_return}
    end
  end

  describe "read_resource/3 for template-based resources" do
    test "reads template resource using default URI template matching" do
      # Given the module does not export parse_uri/2

      result = %MCP.ReadResourceResult{
        contents: [
          %MCP.TextResourceContents{
            uri: "file:///config/app.json",
            text: ~s({"port": 3000})
          }
        ]
      }

      ResourceRepoMockTpl
      |> stub(:prefix, fn _ -> "file:///" end)
      |> stub(:template, fn _ ->
        %{uriTemplate: "file://{/path*}", name: "FileTemplate"}
      end)
      |> expect(:read, fn params, _channel, :arg ->
        assert %{"path" => ["config", "app.json"]} = params
        {:ok, result}
      end)

      repo = ResourceRepo.expand({ResourceRepoMockTpl, :arg})
      channel = build_channel()

      assert {:ok, ^result} =
               ResourceRepo.read_resource(repo, "file:///config/app.json", channel)
    end

    test "returns error when URI does not match template pattern" do
      # Default error message with default template uri matcher

      ResourceRepoMockTpl
      |> stub(:prefix, fn _ -> "file:///" end)
      |> stub(:template, fn _ ->
        %{uriTemplate: "file:///prefix{/path*}", name: "FileTemplate"}
      end)

      repo = ResourceRepo.expand({ResourceRepoMockTpl, :arg})
      channel = build_channel()

      assert {:error, "expected uri matching template" <> _} =
               ResourceRepo.read_resource(repo, "file:///wrongprefix/test.txt", channel)
    end

    test "calls parse_uri callback when provided" do
      result = %MCP.ReadResourceResult{
        contents: [
          %MCP.TextResourceContents{uri: "file:///test.txt", text: "content"}
        ]
      }

      ResourceRepoMockTplNoSkip
      |> stub(:prefix, fn _ -> "file:///" end)
      |> stub(:template, fn _ ->
        %{uriTemplate: "file:///{path}", name: "FileTemplate"}
      end)

      # The returned value can be anything
      |> expect(:parse_uri, fn :arg, "file:///test.txt" ->
        {:ok, :some_returned_value}
      end)
      |> expect(:read, fn :some_returned_value, _channel, :arg ->
        {:ok, result}
      end)

      repo = ResourceRepo.expand({ResourceRepoMockTplNoSkip, :arg})
      channel = build_channel()

      assert {:ok, ^result} = ResourceRepo.read_resource(repo, "file:///test.txt", channel)
    end

    test "returns error when parse_uri fails" do
      ResourceRepoMockTplNoSkip
      |> stub(:prefix, fn _ -> "file:///" end)
      |> stub(:template, fn _ ->
        %{uriTemplate: "file:///{path}", name: "FileTemplate"}
      end)
      |> expect(:parse_uri, fn :arg, "file:///invalid" ->
        {:error, "Invalid URI format"}
      end)

      repo = ResourceRepo.expand({ResourceRepoMockTplNoSkip, :arg})
      channel = build_channel()

      assert {:error, "Invalid URI format"} =
               ResourceRepo.read_resource(repo, "file:///invalid", channel)
    end

    test "returns error :resource_not_found when template resource read returns error :not_found" do
      ResourceRepoMockTpl
      |> stub(:prefix, fn _ -> "file:///" end)
      |> stub(:template, fn _ ->
        %{uriTemplate: "file:///{path}", name: "FileTemplate"}
      end)
      |> expect(:read, fn _params, _channel, :arg ->
        {:error, :not_found}
      end)

      repo = ResourceRepo.expand({ResourceRepoMockTpl, :arg})
      channel = build_channel()

      assert {:error, {:resource_not_found, "file:///missing.txt"}} =
               ResourceRepo.read_resource(repo, "file:///missing.txt", channel)
    end

    test "passes channel with assigns to read callback for template resource" do
      result = %MCP.ReadResourceResult{contents: []}

      ResourceRepoMockTpl
      |> stub(:prefix, fn _ -> "file:///" end)
      |> stub(:template, fn _ ->
        %{uriTemplate: "file:///{path}", name: "FileTemplate"}
      end)
      |> expect(:read, fn _params, channel, :arg ->
        assert %{tenant_id: "tenant-123"} = channel.assigns
        {:ok, result}
      end)

      repo = ResourceRepo.expand({ResourceRepoMockTpl, :arg})
      channel = build_channel(%{tenant_id: "tenant-123"})

      assert {:ok, ^result} = ResourceRepo.read_resource(repo, "file:///data.txt", channel)
    end

    test "exits with bad_return_value when parse_uri returns invalid format" do
      ResourceRepoMockTplNoSkip
      |> stub(:prefix, fn _ -> "file:///" end)
      |> stub(:template, fn _ ->
        %{uriTemplate: "file:///{path}", name: "FileTemplate"}
      end)
      |> expect(:parse_uri, fn :arg, _ ->
        # Invalid: should return {:ok, _} or {:error, _}
        :invalid_return
      end)

      repo = ResourceRepo.expand({ResourceRepoMockTplNoSkip, :arg})
      channel = build_channel()

      assert catch_exit(ResourceRepo.read_resource(repo, "file:///test.txt", channel)) ==
               {:bad_return_value, :invalid_return}
    end
  end

  describe "integration scenarios" do
    test "handles empty resource list" do
      ResourceRepoMock
      |> stub(:prefix, fn _ -> "file:///" end)
      |> expect(:list, fn nil, _channel, :arg ->
        {[], nil}
      end)

      repo = ResourceRepo.expand({ResourceRepoMock, :arg})
      channel = build_channel()

      assert {[], nil} = ResourceRepo.list_resources(repo, nil, channel)
    end

    test "handles resource with optional fields" do
      # behaviour mod keeps the return value as-is

      resource = %{
        uri: "file:///document.pdf",
        name: "Document",
        description: "Important document",
        mimeType: "application/pdf",
        size: 1024
      }

      ResourceRepoMock
      |> stub(:prefix, fn _ -> "file:///" end)
      |> expect(:list, fn nil, _channel, :arg ->
        {[resource], nil}
      end)

      repo = ResourceRepo.expand({ResourceRepoMock, :arg})
      channel = build_channel()

      assert {[^resource], _cursor} = ResourceRepo.list_resources(repo, nil, channel)
    end
  end
end
