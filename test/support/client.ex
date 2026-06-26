defmodule GenMCP.Test.Client do
  @moduledoc false

  import ExUnit.Assertions

  alias GenMCP.MCP.V2607.ModMap

  require ModMap

  ModMap.require_all()

  # Outgoing messages from `post_message/3` are validated against the V2607
  # (2026-07-28) schemas, so the test client only speaks what a conforming
  # client can send. `notifications/initialized` is deliberately absent: it
  # does not exist in the 2026 schemas (transitional clients send it and the
  # transport accepts-and-ignores it) — post it with `post_invalid_message/3`.
  [
    # Requests

    GenMCP.MCP.V2607.ListResourcesRequest,
    GenMCP.MCP.V2607.ListResourceTemplatesRequest,
    GenMCP.MCP.V2607.ReadResourceRequest,
    GenMCP.MCP.V2607.SubscriptionsListenRequest,
    GenMCP.MCP.V2607.ListPromptsRequest,
    GenMCP.MCP.V2607.GetPromptRequest,
    GenMCP.MCP.V2607.ListToolsRequest,
    GenMCP.MCP.V2607.DiscoverRequest,
    GenMCP.MCP.V2607.CallToolRequest,

    # Notifications

    GenMCP.MCP.V2607.CancelledNotification,
    GenMCP.MCP.V2607.ProgressNotification
  ]
  |> Enum.map(fn mod ->
    method = mod.json_schema().properties.method.const
    {method, JSV.build!(mod, atoms: true)}
  end)
  |> Enum.each(fn {method, root} ->
    def jsv_root(unquote(method)) do
      unquote(Macro.escape(root))
    end
  end)

  defp validate_request(%{"method" => method} = data) do
    JSV.validate!(data, jsv_root(method))
    :ok
  end

  def new(opts \\ []) do
    opts = Keyword.put_new_lazy(opts, :base_url, &GenMCP.TestWeb.Endpoint.url/0)

    Req.new(opts)
  end

  @doc """
  Builds a valid request `_meta` map (a `RequestMetaObject`) with the three
  required `io.modelcontextprotocol/*` fields defaulted:

    * `protocolVersion` — `GenMCP.protocol_version/0` (matches the header set by
      the test `client/1`, so header and body agree by default);
    * `clientInfo` — a minimal `Implementation` (`name` + `version`);
    * `clientCapabilities` — `%{}`.

  Pass `overrides` (a map) to add or replace keys.

      request_meta()
      request_meta(%{progressToken: "tok"})
      request_meta(%{"io.modelcontextprotocol/protocolVersion" => "1999-01-01"})
  """
  def request_meta(overrides \\ %{}) do
    Map.merge(
      %{
        "io.modelcontextprotocol/protocolVersion" => GenMCP.protocol_version(),
        "io.modelcontextprotocol/clientInfo" => %{"name" => "test-client", "version" => "1.0.0"},
        "io.modelcontextprotocol/clientCapabilities" => %{}
      },
      Map.new(overrides)
    )
  end

  def post_message(client, data, req_opts \\ []) do
    post(client, data, req_opts, _validate_req? = true)
  end

  def post_invalid_message(client, data, req_opts \\ []) do
    post(client, data, req_opts, _validate_req? = false)
  end

  defp post(client, data, req_opts, validate_req?) do
    {mirror_headers?, req_opts} = Keyword.pop(req_opts, :mirror_headers, true)

    raw = data |> ensure_request_meta() |> JSON.encode!() |> JSON.decode!()

    if validate_req? do
      assert :ok = validate_request(raw)
    end

    req_opts =
      if mirror_headers? do
        [headers: routing_headers(raw)] ++ req_opts
      else
        req_opts
      end

    Req.post!(client, [json: raw, receive_timeout: to_timeout(minute: 1)] ++ req_opts)
  end

  # A conforming client mirrors the routing headers from the body on every POST
  # (draft transport spec, Request Metadata): `Mcp-Method` always, `Mcp-Name`
  # for tools/call, resources/read and prompts/get. Pass `mirror_headers: false`
  # to post without them (negative tests for the -32001 validation).
  defp routing_headers(%{"method" => method} = raw) do
    name_headers =
      case raw do
        %{"method" => "tools/call", "params" => %{"name" => name}} -> [{"mcp-name", name}]
        %{"method" => "resources/read", "params" => %{"uri" => uri}} -> [{"mcp-name", uri}]
        %{"method" => "prompts/get", "params" => %{"name" => name}} -> [{"mcp-name", name}]
        _ -> []
      end

    [{"mcp-method", method} | name_headers]
  end

  defp routing_headers(_raw) do
    []
  end

  # A request (one with an `id`) must carry a valid `_meta` (`RequestMetaObject`)
  # or the server's `Validator.validate_request` (draft schema) rejects it before
  # dispatch. Default a valid `_meta` into `params` when the request does not set
  # its own; tests needing a custom or deliberately-invalid `_meta` set it
  # explicitly (see `request_meta/1`). Notifications (no `id`) carry a `MetaObject`
  # which has no required fields, so they are left untouched.
  defp ensure_request_meta(%{params: params} = data) when is_map(params) do
    if request?(data) and not has_meta?(params) do
      %{data | params: Map.put(params, :_meta, request_meta())}
    else
      data
    end
  end

  defp ensure_request_meta(data) do
    data
  end

  defp request?(data) do
    Map.has_key?(data, :id) or Map.has_key?(data, "id")
  end

  defp has_meta?(params) do
    Map.has_key?(params, :_meta) or Map.has_key?(params, "_meta")
  end

  def expect_status(resp, status) when is_integer(status) do
    if status != resp.status do
      flunk("""
      Expected status #{status} but got #{resp.status}

      Response body:
      #{inspect_or_print(resp.body)}
      """)
    end

    resp
  end

  defp inspect_or_print(str) when is_binary(str) do
    str
  end

  defp inspect_or_print(other) do
    inspect(other, pretty: true, limit: :infinity)
  end

  @doc """
  Asserts that the response carries no `mcp-session-id` header. The 2026-07-28
  transport is stateless and must never mint or echo a session id.
  """
  def refute_session_header(resp) do
    assert :error = Map.fetch(resp.headers, "mcp-session-id")
    resp
  end

  def body(%{body: body}) do
    body
  end

  def read_chunk(resp) do
    # Selectively receive only this response's async messages (all shaped
    # `{ref, _}`; see Req.Finch.parse_message/2). A non-selective receive would
    # swallow unrelated messages delivered to the same process (e.g. a test
    # signal sent from a server callback) and feed them to parse_message, which
    # returns `:unknown` for anything that isn't `{ref, _}`. Leaving them in the
    # mailbox lets the caller `assert_receive` them after the stream is read.
    ref = resp.body.ref

    message =
      receive do
        {^ref, _} = msg -> msg
      end

    Req.parse_message(resp, message)
  end

  def stream_chunks(resp) do
    Stream.unfold(resp, fn resp ->
      case read_chunk(resp) do
        {:ok, [:done]} -> nil
        {:ok, [data: data]} -> {data, resp}
      end
    end)
  end

  def parse_stream(stream) do
    Stream.map(stream, fn item ->
      _ = assert ["event: " <> event, "data: " <> data, "", ""] = String.split(item, "\n")

      %{event: event, data: JSV.Codec.decode!(data)}
    end)
  end
end
