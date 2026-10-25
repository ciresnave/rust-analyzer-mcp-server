# Roadmap

Ordered; the PM allocates versions and merges.

1. Setup: lane docs, CI/protection/licence/tag state report. (this PR)
2. Issue #1 "Workspace not initialized": fix LSP handshake (read rust-analyzer stdout, route responses,
   stdout kept clean for MCP), regression test against real rust-analyzer. Outsider already acknowledged
   on the issue 2026-10-25.
3. Current: newest crates.io deps, current MCP protocol version, edition/MSRV, hosted CI
   (fmt, clippy -D warnings, test --locked, doc, deny, audit).
4. Decide with evidence: publish to crates.io (at minimum claim the name).
5. Patent sweep (`C:\Projects\PATENT-SWEEP-PROCESS.md`) before any release.

Added 2026-10-25 (PM):
6. Split `src/main.rs` into modules, no behaviour change (0.1.4).
7. MCP spec 2026-07-28 migration (stateless, per-request version in `_meta`, `server/discover`).
8. tower-lsp is unmaintained (0.20.0 newest): evaluate async-lsp and lsp-server with evidence, then replace.
