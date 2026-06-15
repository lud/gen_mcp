defmodule GenMCP.Support.UnsupportedRequest do
  @moduledoc false
  # Minimal stand-in for a request type the transport validator accepts but the
  # Suite does not implement. It mirrors the only shape the Suite catch-all reads
  # off a request: `req.__struct__.json_schema().properties.method.const`.

  defstruct [:id, :params]

  def json_schema do
    %{properties: %{method: %{const: "test/unsupported"}}}
  end
end
