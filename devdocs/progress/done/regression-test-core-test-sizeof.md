---
prio: 70
track: P
status: done
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_sizeof.pas red at 35dbb5a998e7 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-31T03:32:08Z
- **Test source:** test/test_sizeof.pas tools/expect_same.sh +1

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_sizeof.pas'` at 35dbb5a998e7651529f3411d26dfddaf6d7d8a4a

## Range
> **The named sha `35dbb5a998e7` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `35dbb5a998e7`, last good `904244e001b2`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1033624/test_sizeof26  [code=110360B  data=4952B  bss=42480B  procs=242]
expect_same: MISMATCH [test_sizeof26]
--- expected
+++ actual
@@ -18,7 +18,7 @@
 4
 8
 8
-10
+8
 16
 2
 4

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## TRIAGE 2026-08-31, host `seven` — NOT A REGRESSION. A stale expectation.

**Do not bisect this and do not revert anything.** The range is right, the
commit in it is correct, and the defect is in the test's recorded expectation.

`ce4d9004c` ("fix(P): SizeOf and declarations share ONE builtin type table")
resolved `done/bug-p-sizeof-extended-disagrees-with-the-storage-extended-gets`
[P p65]. It changed `SizeOf(Extended)` from **10 to 8 deliberately**, and its own
message says so: *"`SizeOf(Extended)` answered 10 against storage of 8."*
`Makefile:11428` still expects `10`. Nothing updated it.

This is track-t.md's fourth bisect case, the one the watcher explicitly cannot
decide: *a correct commit that is not a fault — a feature retired a recorded
divergence and its expectation was left behind.*

### Measured, not read

Compiler rebuilt at HEAD `8284f7376` (sha256 `ee45a08cbc7f`, self-host
fixedpoint converged), running the test's own invocation:

```
actual   1 1 2 2 4 4 4 4 8 8 8 8 8 8 8 1 1 4 8 8  8 16 2 4 1 8 8
expected 1 1 2 2 4 4 4 4 8 8 8 8 8 8 8 1 1 4 8 8 10 16 2 4 1 8 8
                                                  ^ position 21 = SizeOf(Extended)
```

**Exactly one of twenty-seven values differs**, which is itself the evidence that
this is a single retired expectation and not a table-merge that went wide.

### Why 8 is the right answer here, checked against storage rather than against FPC

```
pxx      SizeOf(Extended)=8    SizeOf(record x,y: Extended)=16
fpc 3.2.2 SizeOf(Extended)=10  SizeOf(record x,y: Extended)=32
```

pxx really does store an `Extended` in 8 bytes — two of them occupy 16 — so
`SizeOf` is now *internally consistent*, which is the property the parent ticket
was about. The old `10` was agreeing with FPC while misdescribing our own
layout, and a `SizeOf` that disagrees with the storage it describes is the worse
of the two errors.

### The fix

`Makefile:11428`, one character, in the `expect_same.sh test_sizeof26`
expectation: `...\n8\n8\n10\n16\n...` → `...\n8\n8\n8\n16\n...`

Left to Track P rather than done here: T owns the tool, never the bug, and this
is a P test expectation retired by a P commit. It is a one-character change with
the measurement above behind it.

### A separate finding this surfaced, which is NOT this ticket

**pxx's `Extended` is 8 bytes; FPC's is 10 (and pads to 16 in a record).** That
divergence is real, reachable by any compiling program that takes `SizeOf` or
lays out a record, and it is **not recorded in
`devdocs/dev/pascal-dialect-divergences.md`** — I checked. Under the compat
ceiling it is not a bug to chase (we are not emulating FPC's every behaviour),
but "not a bug" and "not written down" are different things, and this one is
invisible: code asking for extended precision silently gets a Double. Worth a
line in the divergences doc; Track P's call, not filed as a bug.

*Triaged by the Track T agent on `seven` under the provenance rule — my box's
watcher auto-filed the stub, so the triage is mine; the fix is the lane's.*
- 2026-08-31 — resolved, commit PENDING-COMMIT.

## Resolved — frank-rust, 2026-08-31

**Not a bug: a stale expectation.** Row 21 is `SizeOf(Extended)`, and the change
from 10 to 8 is the *intended* resolution of
[[bug-p-sizeof-extended-disagrees-with-the-storage-extended-gets]] (now `done/`):
a variable declared `Extended` has always occupied 8, because `Extended` aliases
`Double` on every target (`feature-extended-alias-or-reject`), and only the
SizeOf table said 10. The inline `expect_same.sh` expectation in the Makefile was
the last place the old answer survived.

Fixed in `582e4de09` along with a real regression from the same commit — see
below, because the two travelled together and only one of them was signalled.

**The part worth keeping.** `ce4d9004c` made SizeOf and the declaration path
share one builtin type table. That produced **two** changes in behaviour:

1. `SizeOf(Extended)` 10 → 8 — intended, and it tripped this red.
2. A builtin name began **shadowing the user's own** types and variables —
   `SizeOf(Currency)` on a user record 12 → 8, a `Boolean` named `longbool`
   1 → 4, a ten-byte array named `tdatetime` 10 → 8, all against FPC 3.2.2.

**Only the first had a test.** The second is the wrong-answer one — wrong sizes
reaching `GetMem` and `Move` with no diagnostic — and nothing in the suite
declared a user type whose name collides with a builtin, so nothing could see
it. This red was the *intended* half of the change announcing itself while the
unintended half travelled silently beside it.

Guarded now by `test/test_sizeof_user_name_shadows_builtin.pas`.
