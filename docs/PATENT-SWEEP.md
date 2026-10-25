# Patent sweep: rust-analyzer-mcp-server 0.1.4 @ f3cef978292fab2a48633284f1f7bfb86e5ef6f8 (branch lane/split, PR #5)
Date: 2026-10-25; Run by: rust-analyzer-mcp-server lane (search by a Sonnet 5.5 subagent, record reviewed by the lane); Method: AI-assisted search and read; NOT legal advice; NOT a freedom-to-operate opinion.

## Ideas swept (from src/lsp.rs, src/server.rs, src/protocol.rs)
1. A stdio server bridges a language server's code-intelligence requests (diagnostics, hover, definition, references, completion, workspace analysis) to an LLM tool-calling protocol (MCP).
2. Before each query, on-disk file content is synced to the language server: textDocument/didOpen on first use, then didChange with full text and an incremented version.
3. Queries are delayed until the language server reports quiescent via the experimental/serverStatus notification.
4. Diagnostics are re-requested after load completes, because diagnostics published earlier are incomplete.
5. A recursive filesystem watcher drives resynchronization of open documents to the language server.
6. The tool-protocol version is negotiated against the client's requested version at initialize.

## Queries (source, query, date; all 2026-10-25)
- WebSearch (standard, patents.google.com): "patent language server protocol bridge large language model tool calling code intelligence diagnostics hover definition"
- same: "patent language server synchronize file content didOpen didChange before query LLM agent code editing"
- same: "patent delay request until language server indexing complete status notification diagnostics re-request"
- same: "patent file system watcher resynchronize document language server protocol model context protocol"
- same: "patent model context protocol server protocol version negotiation client server"
- WebSearch (standard, open web): "language server" "large language model" tool call compiler diagnostics agent patent application 2025 claims
- WebSearch (standard, open web): patent "language server protocol" "model context protocol" code intelligence tools AI agent
- Claims read with C:\Projects\tools\patent-claims.py (Google Patents).

Search outcome: no patent found claiming an LSP-to-LLM/MCP bridge. Results for ideas 1 and 7 queries were academic papers and open-source projects (lspmcp, mcpls, agent-lsp, lsp-mcp), which are prior art context, not patents. Only the first ~2,300-5,000 characters of each patent's claims were reviewed in this session's output (see Limitations).

## Hits
| # | patent | title | assignee | status | claim(s) read | overlap | our difference | verdict |
|---|---|---|---|---|---|---|---|---|
| 1 | US10846203B2 | Responding to requests by tracking file edits | Microsoft | Active (exp. ~2039, Google est.) | 1 (opening) | Idea 2/3: language service requests answered against tracked file state. | Claim 1 requires "a collaboration session in which the owner computer system and a participant computer system are both members", file versions "assigned" to edits and "published ... to the participant", and an "operation buffer". We have no collaboration session, participant, or edit-ordering buffer. | clear |
| 2 | US20240143296A1 | Combining code LLMs with compilers | Intel | Pending | 1, 8 | Idea 1 (LLM plus compiler tooling) only loosely. | Claim 1: LLM "generate one or more code representations ... and compile the ... representations into ... executable instructions". We do not generate code representations or compile with an LLM; we relay LSP results. | clear |
| 3 | US20060282545A1 | Application or protocol version negotiation | IBM (assignee current) | Abandoned | 1-6 | Idea 6: version negotiation. | Claim 1 requires proposing an alternative as "a highest ... version supported" if the initial is higher, or "a lowest" if lower, with accept step at initiator. We answer once in the initialize result with a supported version; no counter-proposal exchange. Also abandoned. | clear |
| 4 | US8825885B2 | Data communication protocol (SMB) | Microsoft | Expired (Google status) | 1-7 | Idea 6 (negotiation) only in the title-level sense. | Claims are about compound file-system requests at a network file server, unrelated. | clear |
| 5 | US8086565B2 | File system watcher in the presence of different file systems | Microsoft | Active (exp. ~2029) | 1 (opening) | Idea 5: filesystem watcher notifications trigger sync. | Claim 1 requires "a platform independent synchronization manager" managing "multiple file system watchers" for "different file systems of multiple computing systems" and replicating objects between them. We use one watcher on one local tree to resend text to one language server. | clear |
| 6 | US20060069672A1 | Query forced indexing | Microsoft | Expired | 1, 7 (opening) | Idea 3/4: query waits on indexing status. | Claim 1: indexing items "in response to a query" with partial results and "batched indexing". We do not index; we wait for an external server's quiescent flag. | clear |
| 7 | CN120105438B | LLM and retrieval-enhanced security detection | Ocean University of China | Active | 1 (translated opening) | Idea 2: IDE plug-in to language server via LSP with didOpen full text. | Claim 1 requires an "IDE plug-in module" plus a "Secure Language Server (SLS) module" with retrieval-enhanced LLM security analysis. We have no IDE plug-in, SLS, or retrieval-augmented security detection; our LSP use is standard sync. | clear |

Also surfaced but NOT read (unread): US8433687, US8667456 (IDE indexing, background only); US12455736B1 (standardizing enterprise code through LLMs); US20230351118A1; US20070274300A1. Treated as unread, not clear; titles suggest low relevance.

## Needs review (to the PM)
None found among the 7 read hits. Unread items above carry no verdict.

## Limitations
- AI-assisted search; WebSearch is a general engine, not a native Google Patents/USPTO/Espacenet/WIPO query interface, so coverage of claim-language searching is weak. No Espacenet/WIPO/USPTO full-text queries were run.
- Claims were read via a machine-converted tool; output in this session was truncated to the opening claims (independent claim 1 plus a few dependents) for each patent, so later independent claims (e.g. claim 8/15 of the multi-independent patents) were not fully checked.
- Ideas 3 and 4 (quiescent wait; re-request diagnostics) returned no on-point patent; absence is weak evidence given search limits.
- Not legal advice; a lawyer's freedom-to-operate review is separate.
