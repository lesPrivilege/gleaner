# Review verification appendix

This appendix records reproducibility. Read the [composition exploration](control-panel-explorations.md) and [source evidence](design-review-evidence.md) for reader-facing findings.

## Scope and revisions

- Public repository: <https://github.com/lesPrivilege/gleaner>.
- Initially inspected: `d9818013a86e87c0d8efcaa5112550f635fd73ba`.
- Reviewed correction commit: `8ab9b795a2a763805b15071c5e5b3be4da78e44e`.
- Current inspected public main: `79d724d1228a4b748572958dcbdd22aa6b7da142`, fetched 2026-10-17.
- The updated main was first inspected in a separate detached worktree; the dedicated design branch then fast-forwarded without discarding staged drafts.
- Reviewed: public spec/notes/prototype and the current native list, detail, wording/model, registry, capture/staging, admission and relevant fixture-test source.
- No app/extractor was run against personal data. No private session logs or `out/` labeling exports were read or generated. Only new design Markdown is proposed.
- No existing ADR convention was found. These documents are exploratory, not an adopted ADR.

## Rendering and native verification limits

The environment did not expose a callable cloud browser control tool after tool/setup inspection. The tracked-file check found no `support.js`, referenced by all three HTML components. The private hosted artifact was not accessed. No original working UI was captured, and no replacement runtime or reconstruction was substituted.

The current application uses SwiftUI/AppKit/Quartz. Linux source inspection cannot verify its rendering, focus, VoiceOver, native copy semantics or target-app drops. Public library-flow tests were read, not run here; their presence is not a successful cross-application drop. Extractor precision/recall requires human labels and remains unmeasured.

## Reproduce the source comparison

```sh
git clone --no-checkout https://github.com/lesPrivilege/gleaner.git gleaner-review
git -C gleaner-review checkout --detach 79d724d1228a4b748572958dcbdd22aa6b7da142
git -C gleaner-review rev-parse HEAD
git -C gleaner-review diff --stat d9818013a86e87c0d8efcaa5112550f635fd73ba HEAD
git -C gleaner-review ls-tree -r --name-only HEAD
```

## Reproduce the prototype state probes

Run inside the clone using Node.js. The probe evaluates only the public component's embedded logic with a minimal state holder. It does not render HTML or emulate a native drag. Changed hashes are synthetic in-memory mutations of fresh sample objects; no source artifact is changed.

```sh
node <<'JS'
const vm = require('node:vm');
const { execFileSync } = require('node:child_process');
const assert = require('node:assert/strict');
const revisions = [
  ['d9818013a86e87c0d8efcaa5112550f635fd73ba', false],
  ['8ab9b795a2a763805b15071c5e5b3be4da78e44e', true],
  ['79d724d1228a4b748572958dcbdd22aa6b7da142', true]
];
for (const [revision, corrected] of revisions) {
  const source = execFileSync('git', ['show',
    revision + ':docs/design/prototype/project/Main.dc.html'], {encoding:'utf8'});
  const logic = source.match(
    /<script type="text\/x-dc"[^>]*>([\s\S]*?)<\/script>/)[1];
  const context = { DCLogic: class {
    constructor(props) { this.props = props; }
    setState(patch) { Object.assign(this.state, patch); }
  }};
  vm.createContext(context);
  vm.runInContext(logic + '\nthis.Probe = Component;', context);
  const c = new context.Probe({});
  c.state.query = 'captions';
  let view = c.renderVals();
  assert.equal(view.results.length, 1);
  assert.equal(view.ver.n, corrected ? 1 : 2);

  const late = c.artifacts().find(a => a.id === 'a8');
  late.nowSha = 'synthetic-new-hash';
  const plan = c.drag(late, late.deliveries[0]);
  assert.equal(plan.mark, corrected ? 'hollow' : 'solid');
  assert.match(plan.title, corrected ? /first saw/ : /copy of delivery/);

  const reverted = c.artifacts().find(a => a.id === 'a1');
  reverted.nowSha = reverted.deliveries[1].sha;
  assert.match(c.nowStatus(reverted).text,
    corrected ? /Rolled back to delivery 1/ : /Changed since delivery 2/);

  c.state.query = 'zz-no-results';
  assert.equal(c.renderVals().hasSel, false);
  c.state.query = '';
  assert.equal(c.renderVals().results.length, corrected ? 10 : 9);

  c.state.query = 'captions intro';
  view = c.renderVals();
  assert.equal(view.results.length, 1);
  assert.equal(view.ver.n, 2);
  console.log(revision.slice(0, 7),
    corrected ? 'three earlier cases corrected' : 'earlier behavior reproduced',
    '; multi-delivery token scope still needs interpretation');
}
JS
```

All assertions above passed. They distinguish corrected behavior from a remaining cross-delivery match-scope question. They do not establish rendered interaction or production acceptance.

## Document checks and future captures

Check Markdown links/reference citations, pinned source line bounds, whitespace, and that the patch contains only new documentation. Check proposed public content for private links, local account paths, raw chats/logs, credentials and internal review transcripts. This package uses public source and explicitly synthetic examples.

When the original HTML runtime/browser or native macOS app is available, capture the unchanged interface first: normal query, older-only match, combined-token match, selected older delivery, saved-copy caveat, unavailable handoff, empty/partial library and narrow-window states. Inspect every saved screenshot before using it as evidence. A reconstruction would need a separate label.

For native validation, also test enter/back/switch focus, selection under sorting/filtering, truncated-text inspection, save/retry feedback and actual successful drops in each named target. Record whether bytes, filename and copy semantics match the explicit selection. Do not report a drag start as a successful drop.
