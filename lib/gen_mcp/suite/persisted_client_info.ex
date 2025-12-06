defmodule GenMCP.Suite.PersistedClientInfo do
  @moduledoc """
  This module represents data that must be persisted in session storage
  when using a `GenMCP.Suite.SessionController` implementation that persists and
  restore long lived sessions.

  When starting with a restored session, the MCP server will not receive
  any `GenMCP.MCP.InitializeRequest` containing client information. This
  information contains client capabilities such as elicitation or sampling
  support.

  When called to persist a session, the session controller will receive
  this module data as a normalized data structure, and should return the
  same data on restore.
  """

  use JSV.Schema

  alias GenMCP.MCP.ClientCapabilities

  defschema client_capabilities: ClientCapabilities,
            client_initialized:
              boolean(decription: "True when the server received notifications/initialized")

  @type t :: %__MODULE__{
          client_capabilities: ClientCapabilities.t(),
          client_initialized: boolean()
        }

  @opaque normalized :: %{optional(binary) => term}

  defimpl JSV.Normalizer.Normalize do
    def normalize(t) do
      %{client_capabilities: cc, client_initialized: ci} = t
      %{"client_capabilities" => cc, "client_initialized" => ci}
    end
  end
end
