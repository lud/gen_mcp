run X='0':
  GEN_MCP_NODE_ID=AA0{{X}} PORT=500{{X}} iex --name genmcpdev-{{ X }}@127.0.0.1 -S mix run

deps:
  mix deps.get

gen-entities:
  rm -vf lib/gen_mcp/entities.ex
  elixir tools/gen-rpc-schemas.exs
  mix run tools/check-entities.exs

_mix_format:
  mix format

_mix_check:
  mix check

_git_status:
  git status

sobelow:
  mix sobelow --config

docs:
  mix rdmx.update README.md
  rg rdmx guides -l0 | xargs -0 -n 1 mix rdmx.update
  mix docs

check: deps gen-entities _mix_format _mix_check docs _git_status