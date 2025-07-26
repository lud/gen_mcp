run X='0':
    iex --name genmcpdev-{{ X }}@127.0.0.1 -S mix run

gen-entities:
  rm -vf lib/gen_mcp/entities.ex
  elixir tools/gen-rpc-schemas.exs
  mix run tools/check-entities.exs