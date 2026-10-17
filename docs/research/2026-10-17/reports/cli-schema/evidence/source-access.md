# MCP and academic source-access record

Checked 2026-10-17. This records what was accessible and read, rather than treating search results as full-text evidence. URLs below are original publisher, standards-body, repository or author-hosted sources. Line counts refer to the browser tool's parsed response, not published pagination. No copyrighted full text is redistributed in this package.

## Model Context Protocol (MCP)

| Original source | Access and scope | Supported observation |
|---|---|---|
| [Latest specification](https://modelcontextprotocol.io/specification/latest) | Opened; resolved to the dated 2026-07-28 specification | Current revision on the check date; not an inferred version from search snippets |
| [2026-07-28 resources](https://modelcontextprotocol.io/specification/2026-07-28/server/resources) | Original HTML read; 398 parsed lines; reopened successfully for this record | Required request metadata at line 26; listing and read examples, templates and changed notification/subscription mechanics inspected |
| [2026-07-28 tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools) | Original HTML read; 684 parsed lines; reopened successfully | Required request metadata, deterministic tool-list guidance, result shape and structured output inspected |
| [2026-07-28 basic messages](https://modelcontextprotocol.io/specification/2026-07-28/basic) | Original HTML read; 396 parsed lines | Result discriminator and compatibility rules; new-version messages cannot be assembled by copying old examples without checking changes |
| [2025-11-25 resources](https://modelcontextprotocol.io/specification/2025-11-25/server/resources) | Original HTML read; 411 parsed lines; reopened successfully | Older list/read/template example dialect used in the source atlas; no claim that its template listing has the newer pagination semantics |
| [2025-11-25 tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools) and [transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports) | Original HTML read; 512 and 190 parsed lines | Structured results and local standard-input/output transport guidance for the explicitly selected older version |
| [Swift SDK pinned README](https://github.com/modelcontextprotocol/swift-sdk/blob/a0ae212ebf6eab5f754c3129608bc5557637e605/README.md) | Repository file read; commit resolved from the 0.12.1 release; manifest and license also inspected | README declares 2025-11-25 support. Its “latest” wording differs from the current specification site. This is a documentation/version compatibility question, not a tested SDK failure. |

The generic latest transport URL returned an overview rather than the expected transport page. It is not evidence for 2026 transport behavior. No MCP server/client conformance test was run. Examples in the atlas select 2025-11-25 after initialization; proposed Gleaner examples are API sketches, not verified wire implementations.

## Papers

### Rahm and Bernstein (2001)

[A survey of approaches to automatic schema matching, The VLDB Journal 10, 334–350](https://link.springer.com/article/10.1007/s007780100057). The original publisher page and abstract were accessible and read (179 parsed lines). The abstract supports the survey's scope and its schema/instance, element/structure and linguistic/constraint distinctions. Full text required subscription and was **not read**. The atlas does not rely on unseen results or experimental conclusions. A guessed Microsoft publication URL redirected to a general research page and supplies no evidence.

### Buneman, Khanna and Tan (2001)

[Why and Where: A Characterization of Data Provenance](https://homepages.inf.ed.ac.uk/opb/papers/ICDT2001.pdf), ICDT 2001. This original author-hosted PDF was accessible: 15 pages, 674 parsed lines. The abstract, opening motivation and formal distinction between why a result exists and where a value comes from were inspected. It is a full-paper source, not just an abstract, but the research does not claim to reproduce its proofs. The transfer to Gleaner is an analogy about evidence precision. A previously guessed Penn PDF URL failed and is not cited as read.

### Curino, Moon and Zaniolo (2008)

[Graceful Database Schema Evolution: the PRISM Workbench](https://www.cs.ucla.edu/~zaniolo/papers/prism-vldb2008-cameraready.pdf), Proceedings of the VLDB Endowment 1(1), 761–772. Original author-hosted PDF accessible: 12 pages, 1,103 parsed lines. Abstract, architecture discussion and Schema Modification Operators table were inspected. These support explicit evolution operations, retained histories, query rewriting and migration as the work's scope; they do not establish that Gleaner needs PRISM.

The [canonical VLDB PDF](https://www.vldb.org/pvldb/vol1/1453939.pdf) timed out; the [ACM record](https://dl.acm.org/doi/10.14778/1453856.1453939) returned 403. Neither inaccessible location was used as read full text. The accessible UCLA author copy supplied the paper evidence. No access-control bypass or elevated retry was attempted.

## Limits

The distinction is **accessible full-paper originals**, **accessible original abstract only**, and **failed locations**. There is no claim to have read an inaccessible abstract. Automated GitHub API maintenance snapshots were separately denied by the environment proxy (403); their exact outcomes are recorded in [public-sources.json](public-sources.json). Public documentation and repository pages supplied the cited release/license context.
