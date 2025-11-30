defmodule GenMCP.Test.Extensions.Pizzaz do
  @behaviour GenMCP.Suite.Extension

  alias __MODULE__

  def widgets do
    [
      %{
        id: "pizza-map",
        title: "Show Pizza Map",
        template_uri: "ui://widget/pizza-map.html",
        invoking: "Hand-tossing a map",
        invoked: "Served a fresh map",
        file: "pizzaz.html",
        response_text: "Rendered a pizza map!"
      },
      %{
        id: "pizza-carousel",
        title: "Show Pizza Carousel",
        template_uri: "ui://widget/pizza-carousel.html",
        invoking: "Carousel some spots",
        invoked: "Served a fresh carousel",
        file: "pizzaz-carousel.html",
        response_text: "Rendered a pizza carousel!"
      },
      %{
        id: "pizza-albums",
        title: "Show Pizza Album",
        template_uri: "ui://widget/pizza-albums.html",
        invoking: "Hand-tossing an album",
        invoked: "Served a fresh album",
        file: "pizzaz-albums.html",
        response_text: "Rendered a pizza album!"
      },
      %{
        id: "pizza-list",
        title: "Show Pizza List",
        template_uri: "ui://widget/pizza-list.html",
        invoking: "Hand-tossing a list",
        invoked: "Served a fresh list",
        file: "pizzaz-list.html",
        response_text: "Rendered a pizza list!"
      },
      %{
        id: "pizza-shop",
        title: "Open Pizzaz Shop",
        template_uri: "ui://widget/pizza-shop.html",
        invoking: "Opening the shop",
        invoked: "Shop opened",
        file: "pizzaz-shop.html",
        response_text: "Rendered the Pizzaz shop!"
      }
    ]
  end

  @impl true
  def tools(_channel, _arg) do
    Enum.map(widgets(), fn widget ->
      {GenMCP.Test.Extensions.Pizzaz.Tool, widget}
    end)
  end

  @impl true
  def resources(_channel, _arg) do
    [GenMCP.Test.Extensions.Pizzaz.ResourceRepo]
  end

  @impl true
  def prompts(_channel, _arg) do
    []
  end

  defmodule Tool do
    use GenMCP.Suite.Tool

    alias GenMCP.MCP

    @impl true
    def info(:name, widget) do
      widget.id
    end

    def info(:description, widget) do
      widget.title
    end

    def info(:title, widget) do
      widget.title
    end

    def info(:_meta, widget) do
      %{
        "openai/outputTemplate" => widget.template_uri,
        "openai/toolInvocation/invoking" => widget.invoking,
        "openai/toolInvocation/invoked" => widget.invoked,
        "openai/widgetAccessible" => true,
        "openai/resultCanProduceWidget" => true
      }
    end

    def info(:annotations, _widget) do
      %{
        destructiveHint: false,
        openWorldHint: false,
        readOnlyHint: true
      }
    end

    def info(_, _) do
      nil
    end

    @impl true
    def input_schema(_widget) do
      %{
        type: :object,
        properties: %{
          pizzaTopping: %{
            type: :string,
            description: "Topping to mention when rendering the widget."
          }
        },
        required: [:pizzaTopping],
        additionalProperties: false
      }
    end

    @impl true
    def call(req, channel, widget) do
      args = req.params.arguments

      result =
        MCP.call_tool_result([
          {:text, widget.response_text}
        ])

      result = %{
        result
        | structuredContent: %{
            pizzaTopping: args["pizzaTopping"]
          },
          _meta: %{
            "openai/toolInvocation/invoking" => widget.invoking,
            "openai/toolInvocation/invoked" => widget.invoked
          }
      }

      {:result, result, channel}
    end
  end

  defmodule ResourceRepo do
    @behaviour GenMCP.Suite.ResourceRepo

    alias GenMCP.MCP

    @impl true
    def prefix(_arg) do
      "ui://widget/"
    end

    @impl true
    def list(_cursor, _channel, _arg) do
      resources =
        Enum.map(Pizzaz.widgets(), fn widget ->
          %{
            uri: widget.template_uri,
            name: widget.title,
            description: "#{widget.title} widget markup",
            mimeType: "text/html+skybridge",
            _meta: %{
              "openai/outputTemplate" => widget.template_uri,
              "openai/toolInvocation/invoking" => widget.invoking,
              "openai/toolInvocation/invoked" => widget.invoked,
              "openai/widgetAccessible" => true,
              "openai/resultCanProduceWidget" => true
            }
          }
        end)

      {resources, nil}
    end

    @impl true
    def read(uri, _channel, _arg) do
      case Enum.find(Pizzaz.widgets(), &(&1.template_uri == uri)) do
        nil ->
          {:error, :not_found}

        widget ->
          result =
            MCP.read_resource_result(
              uri: widget.template_uri,
              mime_type: "text/html+skybridge",
              text:
                File.read!(Path.join([Path.dirname(__ENV__.file), "pizzaz/assets", widget.file])),
              _meta: %{
                "openai/outputTemplate" => widget.template_uri,
                "openai/toolInvocation/invoking" => widget.invoking,
                "openai/toolInvocation/invoked" => widget.invoked,
                "openai/widgetAccessible" => true,
                "openai/resultCanProduceWidget" => true
              }
            )

          {:ok, result}
      end
    end
  end
end
