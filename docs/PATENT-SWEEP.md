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

# Addendum (same sweep, version 0.1.4 @ f3cef978292fab2a48633284f1f7bfb86e5ef6f8)
Date: 2026-10-25; Run by: rust-analyzer-mcp-server lane (reading by a Sonnet 5.5 subagent, record reviewed by the lane); Method: AI-assisted search and read; NOT legal advice; NOT a freedom-to-operate opinion.
Claims read in full (every independent claim) with `python C:\Projects\tools\patent-claims.py <number>`, one number at a time, output saved in the scratchpad as c_<number>.txt. Text is machine-converted; Google Patents status is not the official record.
Ideas swept: unchanged, items 1-6 of PATENT-SWEEP.md.

## Part 1: the five previously unread hits (all claims read)
| # | patent | title | assignee | status | independent claims read | overlap (quoted) | our difference (quoted) | verdict |
|---|---|---|---|---|---|---|---|---|
| 8 | US8433687 | Off-line indexing for client-based software development tools | Google | Expired (est. 2031) | 1, 10, 13, 16 | "providing ... a software development environment"; "retrieving information related to the at least part of the identifier"; displaying it. Loose match to idea 1 (code-intelligence lookups). | Every independent claim requires "transmitting ... the source code ... to the remote indexing server for indexing", "receiving an index of the source code created by the remote indexing server" and "storing the index on the computing device". We send nothing to a remote indexer and keep no index; rust-analyzer runs locally. | clear |
| 9 | US8667456 | Cloud-based indexing for integrated development environments | Google | Active (est. 2032) | 1, 12 | "request to access index information ... a code completion request, a usages request ... and a refactoring request"; responses "limited to information responsive to the identified type of indexing request". Loose match to idea 1. | Both independents require a "cloud-based indexing services computing system" fetching "identities of one or more related source code files" from a "remote source-code repository computing system" (file name, path, last-modified date, version, hash) and a "source code index data store". We have no cloud indexer, no remote repository and no index store. | clear |
| 10 | US12455736B1 | Standardizing enterprise software code through LLMs | Morgan Stanley | Active | 1, 14 | LLM receives code from a repository. | Requires "a prompt library" with "pattern recognition prompt sets" and "standardized solution prompt sets" that make the LLM produce "replacement code conforming to a predefined enterprise standard". We run no prompts, call no LLM and generate no code. | clear |
| 11 | US20230351118A1 | Controlling generative language models for AI characters | Theai | Active | 1, 11, 20 | Only "language model" in the general sense. | Claims are a dialog between a user and an "AI character model" using "a context of a dialog" from a client "data stream". Unrelated to code or LSP. | clear |
| 12 | US20070274300A1 | Hover to call | Microsoft / MIT | Abandoned | 1, 11, 16 | "hovering" only by word (we expose LSP hover). | Claims establish "a voice connection" (VoIP) from a hovered telephone number. Unrelated. | clear |

## Part 2: re-read of the 7 earlier hits (later independent claims)
| patent | independents now read | does any verdict change? |
|---|---|---|
| US10846203B2 (Microsoft) | 1, 11, 20 | No. All three recite the same elements: "a collaboration session in which the owner computer system and a participant computer system are both members", file versions "assigned" and "published ... to the participant", and "an operation buffer". We have none. Clear. |
| US20240143296A1 (Intel) | 1, 8, 15 | No. All three end in "compile the one or more code representations ... into one or more computer executable instructions" by a code LLM. We do not. Clear. |
| US20060282545A1 (IBM) | 1, 10 | No change in verdict, with a caveat. Claim 1 is a client proposes / server counter-proposes (highest or lowest supported) / client accepts exchange. MCP's initialize is structurally close (client proposes a version, server answers with the one it supports, client accepts or disconnects), so the difference is narrower than the first record implied, and depends on our server answering "highest/lowest supported" vs echoing. Google lists the application Abandoned (priority 2005, so any patent would be past 20 years in any case). Treated as clear on status alone; confirm status in the official record if it ever matters. |
| US8825885B2 (Microsoft) | 1, 8, 15 | No. All require a "network file server" receiving a "compound request" with related/unrelated file system commands. Clear. |
| US8086565B2 (Microsoft) | 1, 10, 15 | No. All require a "platform independent / file system independent synchronization manager" managing "different file systems of multiple computing systems" with a watcher per file system. We use one local watcher. Clear. |
| US20060069672A1 (Microsoft) | 1, 7, 10, 20 | No. All concern batch indexing of unindexed or out-of-date items in response to a query ("initiating batched indexing"). We do not index; we wait on an external server's status. Clear. |
| CN120105438B (Ocean Univ. of China) | 1 (system), 4 (method) | No. Claim 1 requires "IDE plug-in module" and "Secure Language Server (SLS) module"; claim 4 (the only independent method) requires CodeBERT embedding, HNSW k-NN retrieval over a security knowledge base, and an LLM prompt "P" with retrieved knowledge R. We have no RAG or LLM call. Clear. |

Result: no verdict changes. One caveat added (IBM).

## Part 3: additional queries (WebSearch standard, restricted to patents.google.com; all 2026-10-25)
- "patent 'language server' 'tool call' large language model agent code intelligence claims"
- "patent 'model context protocol' code intelligence server tool LLM agent"
- "patent compiler diagnostics large language model feedback loop code repair language server"
- "patent static analysis results provided to language model as tool, symbol definition references retrieval for code generation"
Outcome: no patent claiming a language-server-to-LLM/MCP bridge, MCP code-intelligence server, or compiler-diagnostics feedback loop surfaced. The MCP and diagnostics queries returned only academic papers (absence is weak evidence given search limits). New near hits read in full:

| # | patent | title | assignee | status | independent claims read | overlap (quoted) | our difference (quoted) | verdict |
|---|---|---|---|---|---|---|---|---|
| 13 | US20250272544A1 | Generating and executing action plans involving software tools via an LLM | Adobe | Pending | 1, 11, 17 | LLM drives "one or more software tools" via API calls (idea 1, tool calling). | Every independent claim requires "traversing a decision tree" of an action space with a "best-first search model", and claims 11/17 add cumulative/future cost scores, "self-consistency", "long-term memory". We contain no planner, no LLM, no search; the client LLM is outside our server. | clear |
| 14 | US12670195B2 | Code retrieval method and apparatus based on LLM | Baidu | Active | 1, 5, 9 | Retrieval of code context for an LLM prompt. | Requires "retrieval vector", "code block vectors", top-N similarity, a "code architecture knowledge graph" index, and "constructing a prompt ... calling the large language model". We use none of these. | clear |
| 15 | US8555250B2 | Static semantic analysis of dynamic languages | Microsoft | Expired (est. 2031) | 1, 17, 18 | Static analysis, symbol table, diagnostics. | Requires parsing "dynamic language source code" into syntax trees, building a symbol table and computing metrics ("parameter count mismatches"). We relay rust-analyzer's results and do no analysis of our own. Also expired per Google. | clear |
| 16 | US12511105B2 | Transpiler to extract and use intermediate representations of a code base | Driver Ai | Active | 1, 2, 21 (21 read to its first ~1,500 characters; remaining text is the same model-internals recital as claims 1-2, not read to the end) | Uses AST/symbol table from a parser and "a static analysis tool". | Requires "classifying ... parts according to content type", "processing templates" with "a chain of prompts", and generating "natural language documentation" with generative language models. We generate no documentation and call no model. | clear |
| 17 | US20250258856A1 | Declarative agent with hierarchical components using LLMs | (not extracted from output; Google Patents page lists it under agent orchestration) | not extracted | not read | Surfaced as an agent-orchestration result only. | n/a | unread |

(US20250258856A1 was fetched into c_US20250258856A1.txt but not read in this session; it stays unread. Other search results, US12111859B2 Enterprise generative AI architecture, US20250231801A1, US20250217174A1, WO2025024326A2, were titles only and are unread.)

## Needs review (to the PM)
None. No hit among the 16 read has an independent claim that our design meets.

## Unread
US20250258856A1, US12111859B2, US20250231801A1, US20250217174A1, WO2025024326A2 (titles only; general LLM agent/orchestration, low apparent relevance; no verdict).

## Limitations
- Same as the original record: AI-assisted; WebSearch is a general engine, not a native Google Patents/USPTO/Espacenet/WIPO claim-language query; no Espacenet/WIPO/USPTO full-text queries; absence of a patent is weak evidence.
- The search engine's patent coverage for the MCP-era (2024-2026) is thin; recent unpublished applications (18-month lag) cannot be found at all.
- Claims are machine-converted; statuses are Google's, not the official record. US12511105B2 claim 21 and CN120105438B (translated) were read as converted.
- Not legal advice.
