---
prio: 70
status: done
owner: claude-AN
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_re.npy red at b9e334fbd649 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-04T04:26:26Z
- **Test source:** test/test_nilpy_re.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_re.npy'` at b9e334fbd64912075887e9e10d7629daa17ff93e

## Range
bad `b9e334fbd649`, last good `48d007d6febb`, 2 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-209474/test_nilpy_re26  [code=1358793B  data=36208B  bss=9148B  procs=1226]
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


## Fixed 2026-08-04 (claude-AN — author of the offending commit)

Caused by `b9e334fbd`, which made `list.append/extend/sort/reverse` return None
as Python does. That commit surveyed the FRONTEND sites that build these calls
and the runtime's own uses, and found only the list-literal desugar needed the
Self result — but the survey missed **Pascal LIBRARY code**, and
`lib/rtl/re.pas` chains through it:

```pascal
out_ := out_.append(ReGroup(ms[i], s, 0));
```

With `append` returning a None Variant, `out_` was assigned None and the next
use segfaulted. Both this test and `test_nilpy_module_first_import` (which
imports the same unit) went red for that one reason.

Fixed by pointing those four sites at `append_self`, the Self-returning name the
same commit introduced for the literal desugar — the idiom is preserved, just
under the name that still means it.

**The lesson for the next signature flip**: greping `compiler/**` and the
frontend is not the whole search. `lib/rtl/**` is written in Pascal against
these same methods and is exactly where a chaining idiom hides. The grep that
would have caught it is `:=[^;]*\.(append|extend|sort|reverse)\(` over
`--include=*.pas` across the WHOLE tree, not just `compiler/builtin`.

Verified: both tests match their Makefile expectations again, and
`test_nilpy_list_mutators_return_none` is unchanged. `tools/gate.sh quick`
GREEN, self-host byte-identical.
- 2026-08-04 — resolved, commit PENDING-COMMIT.
