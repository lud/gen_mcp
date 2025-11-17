import Config
import Nvir

dotenv!(dev: ".env")

# TODO(doc) node id must be an alphanumeric string without dashes
config :gen_mcp,
  node_id: env!("GEN_MCP_NODE_ID", :string!, :random)
