# rust-analyzer-mcp-server

MCP (stdio) server exposing rust-analyzer (LSP) as tools. Single binary crate, `src/main.rs`.
Portfolio rules in `C:\Projects\CLAUDE.md` apply and are not restated here. Maintained by the
`rust-analyzer-mcp-server` lane (CireSnave, 2026-10-25: "We maintain it").

- Primary checkout `C:\Projects\rust-analyzer-mcp-server` stays on `main`; work in worktrees `-wt-<topic>`.
- stdout is the MCP channel: **never print anything to stdout except MCP messages** (logs go to stderr).
- Verify against a real rust-analyzer (`rust-analyzer --version`), not only unit tests: the original
  defect (#1) passed every unit test.
- PM allocates versions, merges, and publishes. Outsider issues: answer within 3 days.
- Plan: `ROADMAP.md`. Session state: `HANDOFF.md`.
