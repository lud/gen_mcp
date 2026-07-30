run X='0':
  GEN_MCP_NODE_ID=AA0{{X}} PORT=500{{X}} iex --name genmcpdev-{{ X }}@127.0.0.1 -S mix run

_mix_deps:
  mix deps.get

gen-entities:
  rm -vf lib/gen_mcp/entities.ex
  elixir tools/gen-rpc-schemas.exs
  mix run tools/check-entities.exs

update-schema: _mix_deps
  mix deps.get
  mix mcp.update_schema
  mix deps.get | rg modelcontextprotocol
  just gen-entities
  git status
  mix test
  just _git_status

format:
  mix format --migrate

_libdev_check:
  mix libdev.check

_git_status:
  git status

sobelow:
  mix sobelow --config

readme:
  mix rdmx.update README.md
  rg rdmx guides -l0 | xargs -0 -n 1 mix rdmx.update

docs: readme
  mix docs

check: _mix_deps format gen-entities readme _libdev_check _git_status