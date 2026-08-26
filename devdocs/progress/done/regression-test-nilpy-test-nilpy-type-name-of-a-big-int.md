---
prio: 70
track: N
status: done
owner: frank1-N-reds
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/dev has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_type_name_of_a_big_int.npy red at 44193e547f6d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-25T20:32:52Z
- **Test source:** test/test_nilpy_type_name_of_a_big_int.npy test/test_nilpy_type_name_of_a_big_int.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_type_name_of_a_big_int.npy'` at 44193e547f6d4ca77453770378b710d8af82f5df

## Range
bad `44193e547f6d`, last good `d2cb6721e175`, 23 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2553870/test_nilpy_typebig26  [code=2317884B  data=55230B  bss=43340B  procs=1988]
--- test/test_nilpy_type_name_of_a_big_int.expected	2026-08-13 07:02:31.902669004 +0200
+++ -	2026-08-25 22:03:53.631275002 +0200
@@ -4,5 +4,5 @@
 int float str bool
 list dict tuple NoneType
 K type
-function
+method
 1180591620717411303424 1180591620717411303424 1180591620717411303424 1180591620717411303424 1180591620717411303424

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## CORRECTION — the range above is WRONG, and too narrow (Track T, 2026-08-25)

**Do not bisect the 23-commit range this ticket was filed with.** The job named
here does not run in the `native` tier, and the parent it was diffed against
(`d2cb6721e175`) was a native run. It last actually executed in the full tier at
`aa9f0989a4c0` on 2026-08-24 — so the honest range is **179 commits**
(`aa9f0989a4c0..44193e547f6d`), not 23, and the last-good sha is
`aa9f0989a4c0`, not `d2cb6721e175`.

This matters more than the arithmetic suggests. A bisect over a range that does
not contain the culprit does not fail and does not report "not found" — it
narrows, confidently, onto an innocent commit, and a core-job red is a revert
candidate by this repo's own rule. The 23-commit window is precisely the set of
commits that CANNOT have caused this, since the job was already in this state
before the window opened.

Cause: `twatch` computed the blame range from "since this host last tested
anything" rather than "since this job last ran". Fixed in `c68e6492e` —
the range is now decided per job from `job_tier` and widened only when the
parent's run provably did not contain it. Tickets filed from later runs carry
the corrected range; this one is annotated rather than rewritten, because the
filed text is the record of what the watcher actually claimed.

---

## RESOLVED — same commit as the uforth red (Track N, frank1-N-reds, 2026-08-26)

Reproduced at HEAD: exactly one line differs, `type(f).__name__` on a plain
module-level def, `function` expected and `method` produced. Nothing about big
ints is involved — the big-int lines all pass; this test simply happened to
carry the control line that caught it.

### Range

Same story as `regression-test-uforth-core`, and the same culprit:
**`293d70509` "fix(N): a bare def name in value position is boxed like every
other callable"**, which `git merge-base --is-ancestor 293d70509 d2cb6721e175`
says is an ANCESTOR of the filed last-good sha. The 23-commit window excluded
it; the honest 179-commit range contains it. Reverting that commit's
`compiler/pyparser.inc` hunk and rebuilding made this test green (and the uforth
core word set too — one commit, two reds).

The watcher's own bisect over the filed range had already converged on
`ab584382edcd`, a commit that changes 250 `prio:` frontmatter lines and no code.

### Root cause

Not a defect in `293d70509` — the commit is correct. It routes a bare def name
in value position through `PyMakeFuncValueFor`, so a plain def now travels as a
`{code, recv}` pair with a NIL receiver, variant tag 8. Its own message records
the intent: *"pyvartag(g) answered 12 in an argument position and 8 after an
assignment ... Both now answer 8."*

But tag 8 is BOTH shapes. `pybound_new(code, recv)` is a bound method when recv
is an instance and a plain def when recv is nil — "a plain def is the same pair
with a nil receiver" (`PyMakeFuncValue`'s own comment). `PyVarTypeName(t)`
answers from the TAG ALONE, so it said 'method' for both the moment plain defs
started arriving there.

`PyCallableStr` had already met this exact question for `<function at 0x...>`
vs `<bound method at 0x...>` and answered it correctly in `4eb11a20b`: *"What
makes something a bound method is being bound to something, so the receiver is
the answer and the tag is not."* The type-NAME table is that fix's unfixed
sibling arm — the shape `devdocs/dev/normalise-dont-special-case.md` describes.

### Fix

`compiler/builtin/pylib.pas`: new `PyVarTypeNameOf(const v: Variant)` — the
type name of a VALUE. It defers to `PyVarTypeName(tag)` for everything and
refines the one tag that needs the receiver. Every caller that holds the value
uses it (`pytype_name_v`, `pydynattr_get_v`, `pydynattr_no_method`, and
pyeval's four "object is not subscriptable" TypeErrors); the tag-only
`PyVarTypeName` stays for `PyTypeError`, which is handed a bare tag and cannot
have a plain def in hand without having lost the value first.

### Verification

- `test/test_nilpy_type_name_of_a_big_int` matches its `.expected` byte for byte.
- New test `test/test_nilpy_type_name_function_vs_method.npy` asserts BOTH
  halves — a plain def, an alias, a def in a list and a dict, and a lambda are
  all `function`; a bound method stays `method` — all diffed against CPython.
- `make compiler/pascal26` fixedpoint, `tools/gate.sh quick`.

### Filed, not fixed

`bug-n-a-staticmethod-read-through-an-instance-binds-a-receiver` (prio 25): a
`@staticmethod` reached through an INSTANCE binds the instance as a receiver, so
`type(k.stat).__name__` says 'method' where CPython says 'function'. Every VALUE
is correct; the divergence is in the attribute read, is pre-existing, and is a
different mechanism, so it is a ticket rather than scope creep. The new test
carries the case as a comment naming that ticket instead of as an assertion.
- 2026-08-26 — resolved, commit c2c0e79e0.
