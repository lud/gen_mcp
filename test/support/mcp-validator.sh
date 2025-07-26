root_dir=$(pwd)
report_dir=$root_dir/_build/mcp-validator-reports
mkdir -p $report_dir
cd deps/mcp_validator
uv run python -m mcp_testing.scripts.http_compliance_test \
  --output-dir $report_dir \
  --server-url http://localhost:5002