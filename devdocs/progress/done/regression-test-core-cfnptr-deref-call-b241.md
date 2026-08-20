---
prio: 70
track: C
owner: frank1-ACP
status: done
---

> **Track guessed as C** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/cfnptr_deref_call_b241.c red at b645e1b2aff7 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-20T11:17:51Z
- **Test source:** test/cfnptr_deref_call_b241.c

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/cfnptr_deref_call_b241.c'` at b645e1b2aff7d0fc6f63267e833a4410c5a49fa8

## Range
bad `b645e1b2aff7`, last good `23730e49d446`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-651873/cfnptr_deref_call_b24126  [code=90980B  data=504B  bss=4832B  procs=382]
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triage + fix — 2026-08-20, same day

Not a C-frontend bug: collateral from `9afcd676a`
([[bug-p-typed-const-array-with-a-negative-low-bound-writes-to-its-base]]), the
middle of the three commits in the watcher's range.

That fix replaced the `-1` / `-2` sentinels in `PendingInitElem` /
`LocalInitElem` with `PI_ELEM_NONE` / `PI_ELEM_ADDRG`, because a *negative array
index* is a legitimate value there and `-1` had been doing double duty as "no
index". Ten write sites in `parser.inc` and seven in `cparser.inc` moved to the
named constants — and **one did not**: `cparser.inc:7708`, the
`if not wasArr then … := -1` arm of the C array/struct initializer walker.

The readers had already moved. So a C initializer for a NON-array target kept
writing `-1`, and the global-init flush now read that as a real element index
and emitted `sym[-1] := value` — a store one slot below the symbol. For these
three tests the symbol is a function pointer and the slot below it is live, so
the call went through a corrupted target: SIGSEGV in b241, wrong exit in the
other two.

One line, `PI_ELEM_NONE`, and all three go green (exit 42, matching gcc).

**Second time today** a fix's sibling-grep missed a site with no shared text to
grep for: the field-array low bound missed `ParseRecordVariantPart` for the same
reason (it never had the N-D code the grep keyed on). The generalisation worth
keeping: when a change redefines what a VALUE means, grep the readers *and* the
writers by array name, not by the pattern the fix happened to touch.

## Gate

`make compiler/pascal26` fixedpoint + `tools/gate.sh quick`; all three tests
verified against gcc.
- 2026-08-20 — resolved, commit 3db1ad71c.
