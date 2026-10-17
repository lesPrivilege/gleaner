# Sources and what they support

This index supports the explorations; it is not an endorsement of copying another product's architecture. Current repository evidence is pinned to `79d724d1228a4b748572958dcbdd22aa6b7da142`. Exact findings and line references are in the [source review](design-review-evidence.md).

## Public repository evidence

| Source | Relevant evidence |
|---|---|
| [SPEC](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/docs/SPEC.md) | Product boundary, observation/availability distinctions, provisional admission and open gates; its derived-project model is distinct from the newer project-first direction |
| [LibraryView](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/LibraryView.swift), [DetailView](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/DetailView.swift), [LibraryModel](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/LibraryModel.swift) | Current information order, selection, preview and action targets; source inspection does not establish rendered/native behavior |
| [Library semantics](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/GleanerCore/Library.swift), [Wording](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/Gleaner/Wording.swift) | Path-based artifact/project projection, search scope, availability, provenance and current labels |
| [Registry](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/GleanerCore/Registry.swift), [Indexer](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/GleanerCore/Indexer.swift), [ContentStore](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/GleanerCore/ContentStore.swift) | Implemented delivery/capture records, provisional admission, saved regular-file copies and verified staging |
| [SessionLog](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/GleanerCore/SessionLog.swift), [MentionExtractor](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/Sources/GleanerCore/MentionExtractor.swift) | Record-specific evidence and extraction; not validated precision/recall |
| [Prototype](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/docs/design/prototype/project/Main.dc.html), [notes](https://github.com/lesPrivilege/gleaner/blob/79d724d1228a4b748572958dcbdd22aa6b7da142/docs/design/library-prototype.md) | Earlier design intent and sample state transitions; the missing runtime prevents treating raw HTML as a rendered product |

## Primary external references

| Source | Transferable principle | Do not import by implication |
|---|---|---|
| [Zotero collections and saved searches](https://www.zotero.org/support/collections_and_tags) | Non-exclusive membership differs from item identity; dynamic criteria differ from a fixed selection | A nested collection hierarchy or reference-management workflow |
| [Obsidian Outline](https://obsidian.md/help/plugins/outline) | Navigate headings that exist in active content | Source editing/reordering or an invented outline for every format |
| [Apple Quick Look](https://support.apple.com/guide/mac-help/preview-a-file-mh14119/mac) | Quick inspection from selection and explicit external opening | Universal format support, Gleaner source editing or proof of target-app drops |
| [Diátaxis](https://diataxis.fr/) | Organize around reader needs rather than file types alone | Its four documentation categories as a mandatory Gleaner taxonomy |
| [Nygard: Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) | Preserve decision context, stated status and supersession history | Authority for Gleaner to approve a source's decision or infer supersession |
| [W3C SKOS Primer](https://www.w3.org/TR/skos-primer/) | Labels, hierarchy and associative relationships have distinct meanings | RDF, a general ontology editor or synonym/identity inference from similar names |
| [W3C Web Annotation](https://www.w3.org/TR/annotation-model/) | Separate note bodies from targets, selectors and resource state | A full annotation-platform implementation |
| [W3C PROV-DM](https://www.w3.org/TR/prov-dm/) | Distinguish attribution, derivation and responsibility, including the basis of derived notes | A provenance graph UI or the assumption that a citation proves truth |
| [Git worktrees](https://git-scm.com/docs/git-worktree), [repository layout](https://git-scm.com/docs/gitrepository-layout) | Repository/worktree relationships can be established independently of parent directories | Logical project identity, or automatic project merging from shared remotes |

These sources support transferable distinctions. Proposed Gleaner arrangements remain task hypotheses, with their assumptions and costs described in the [composition](control-panel-explorations.md) and [editorial](project-knowledge-explorations.md) chapters.

## Deeper references by question

- [Architecture mechanisms](architecture-precedents.md) pins Cass, AgentsView, Obelisk, Vibe Kanban, lcsmas/orchestra and OpenCode; it also compares Git, VS Code, Backstage and MLflow. Source mechanisms are separated from Gleaner inferences.
- [Evidence and lifecycle](evidence-and-lifecycle.md) uses OpenTelemetry for event/observation time, SQLite/Datasette for optional retrieval, BIBFRAME for identity questions, RO-Crate/BagIt for assembly extent and preservation, Memento for archived representations, OCI for platform variants and DCMI for naming roles. These standards do not mandate formats or entities.
- [Native interaction](native-interaction.md) links Apple's platform documentation and pinned Maccy, Itsycal and CotEditor source. Platform behavior, inspected implementation and proposed Gleaner acceptance scenarios remain distinct.
