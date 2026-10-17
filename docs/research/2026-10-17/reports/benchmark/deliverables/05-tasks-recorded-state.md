# Task specifications T13–T18

Class S tasks use the 2×2 information matrix. Every added record and snapshot is independently created before extraction and supplied verbatim to R1 as well as G1. Both S0 arms lack it. State recovery is scored separately from a warranted unknown. These tasks do not demonstrate that a schema creates approval, authorship or missing historical content.

## T13 Version-scoped approval

**Prompt:** Is version V1 approved by the designated owner for the internal review, as of 12:00?

**Fixture:** S0 contains the delivery and an approval request, without a recorded decision. S1 additionally contains A13: owner Mira, authority policy P13, target O13/V1, purpose internal review, approval at 11:00. No publication authorization is implied. Synthetic ledger scope and completeness through 12:00 are supplied.

**Gold:** In S0, unknown/not evidenced; do not say approved or affirm a historical rejection. In S1, the recorded owner approval covers V1 for internal review at that time. Required S1 evidence {P13,A13,target binding}; S0 needs the request and coverage/gap explanation. Wrong version, purpose or authority fails. **Labels:** S; approval availability; L1→L2/source ledger; M+A, O only for real authority/intent.

**Mechanical contrast:** Put A13 in a plain JSONL ledger in R1. Any G1–R0 gain combines capture and retrieval. G1–R1 is the retrieval test.

## T14 Revocation and scope

**Prompt:** Is V2 approved for external publication at 13:00?

**Fixture:** S0 has an agent claim `approved` without owner evidence. S1 includes owner approval for V1/internal review at 11:00, explicit revocation at 12:00 and a request to publish V2 without a decision. Policy P14 says only the owner ledger grants authorization and is complete through 13:00.

**Gold:** S0: authorization unestablished. S1: no valid recorded authorization for V2/publication under P14; distinguish wrong version/purpose and revoked V1 approval. {P14,approval,revocation,V2 request,ledger scope} required. Do not turn an agent claim or absence in a partial ledger into approval or rejection. **Labels:** S; temporal authority; L1→L2; M+A/O.

**Control:** A separately generated variant changes only purpose or version; freeze before evaluation to detect a shortcut that blindly answers no.

## T15 Pre-overwrite payload

**Prompt:** What exact budget value was in the file immediately before the overwrite at 10:05?

**Fixture:** S0 contains a 10:05 overwrite result and current file value 900; an earlier write request contains 600 but has no execution result. S1 adds a captured pre-overwrite payload C15 showing 700, with observation at 10:04:59, digest and a controlled operation sequence proving it is the last version before overwrite.

**Gold:** S0: exact prior value unavailable, even though 600 is a plausible intent. S1: 700 with {C15,capture provenance,ordered overwrite observation}. A hash without payload cannot answer the value. A late capture of 900 fails. **Labels:** S; irreplaceable snapshot; L1→L3; M+A.

**Control:** The capture package must include actual bytes and sequence evidence. Merely calling a record `pre-overwrite` is insufficient unless the fixture contract establishes timing.

## T16 Deleted worktree

**Prompt:** Recover the delivered artifact from a now-deleted worktree, or state exactly what survives.

**Fixture:** S0 has a delivery reference into a worktree, recorded disappearance and a complete fixture inventory showing no retained payload or matching Git object. A similarly named artifact in the main worktree differs. S1 adds a verified historical capture C16 and its original project/worktree identity.

**Gold:** S0: retain the lost-item reference and report payload unavailable within the supplied scope; no claimed recovery. S1: resolve C16 and verify its digest, while identifying the original path as gone. {delivery,disappearance,inventory,C16 and observation when available}. Copying the main-worktree candidate without evidence fails. **Labels:** S; recovery and source ownership; L1→L3; M+A.

**Lifecycle check:** Rebuild must retain the reference and C16 linkage even when the original path cannot be resolved. This is a synthetic invariant, not a command to inspect real worktrees.

## T17 Authored arrangement survives rebuild

**Prompt:** After rebuilding the derived catalog, which object did the owner call `Board packet`, and in which two collections did they place it?

**Fixture:** S0 has two similarly titled objects and no authored arrangement. S1 adds annotation U17 targeting O17/V1 with alias `Board packet`, memberships Review and Archive, explicit scope and an owner event ID. Rebuild from the same raw files; optionally rename a log so the derived occurrence key changes.

**Gold:** S0: arrangement not recoverable. S1: O17/V1, both memberships, with {U17,target-binding/reconciliation evidence}. If the target cannot be reconciled, preserve U17 as unresolved rather than moving it to the similar item. Snapshot/annotation files survive derived-index deletion. **Labels:** S; authored state; L1→L2; M+A/O.

**Control:** An alias is not a filesystem rename, collection membership is not ownership, and this annotation does not approve later versions. Measure migration failures and recovery effort, not just whether an annotation file remains on disk.

## T18 Missing-state negative control

**Prompt:** Did the owner approve the overwrite, and did the requested write actually execute?

**Fixture:** Both S0 and S1 contain an approval request and a write tool invocation with no result. S1 adds unrelated well-formed state records, but no decision or execution observation for this operation. The fixture explicitly allows an unobserved outcome; the hidden world may vary while visible evidence is identical.

**Gold:** Neither approval nor execution is established in either condition. Cite the two attempts and incomplete observation boundary; identify the precise missing decision/result evidence. Do not say the action failed or was rejected. No amount of catalog structure changes this answer. **Labels:** S; information-theoretic limit; L2→L3 log unit plus scope; M+A.

**Control:** Construct two hidden worlds with identical visible inputs and different actual outcomes. The agent is graded on warranted uncertainty, not omniscience. Annotators must not leak the hidden bit into labels, index descriptors or the question. This is the most direct falsifier of unsupported catalog authority.
