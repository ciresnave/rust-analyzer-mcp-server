# Changelog

## 0.1.12 - 2026-11-22 (allocated by pm-assist)

- Fixes: a failure inside a known tool is now an MCP tool-execution error (`isError` result the model can read), not a JSON-RPC protocol error; an unknown tool is still a protocol error. Tests added.
- Docs: README gains a `cargo install rust-analyzer-mcp-server` section (0.1.11 or later).

## 0.1.11 - 2026-11-21

- Fixes: `analyze_workspace` deadlock; `get_diagnostics` resync no longer loses diagnostics; no empty result before the 5s grace. Test `test_real_rust_analyzer_tools` (real rust-analyzer). Allocated by pm-assist.

## 0.1.10 - 2026-11-20

- Adds the documented `RUST_ANALYZER_PATH` override for the rust-analyzer binary; README no longer claims `RUST_LOG` (it was never read by the code).

## 0.1.9 - 2026-11-16

- dependencies: bytes 1.10.1 -> 1.12.1 (dependabot #6).
