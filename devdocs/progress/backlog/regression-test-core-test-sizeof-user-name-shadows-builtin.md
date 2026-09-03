---
prio: 75
track: P
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_sizeof_shadow26 "$(/tmp/test_sizeof_shadow26)" "$(printf 'a 12\nb 10\nc TRUE\nd 1\ne 1\nf 8\ng`. The job's own `src` (`test/test_sizeof_user_name_shadows_builtin.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_sizeof_user_name_shadows_builtin.pas at 5ad048c2d9ae in step 2/2, `tools/expect_same.sh test_sizeof_shadow26 "$(/tmp/test_sizeof_shadow26)" "$(printf 'a 12\nb 10\nc TRUE\nd 1\ne 1\nf 8\n…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-02T16:09:42Z
- **Test source:** test/test_sizeof_user_name_shadows_builtin.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_sizeof_shadow26 "$(/tmp/test_sizeof_shadow26)" "$(printf 'a 12\nb 10\nc TRUE\nd 1\ne 1\nf 8\ng 4 8 2\nh 4 8 8\ni TRUE x 5')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_sizeof_user_name_shadows_builtin.pas'` at 5ad048c2d9ae35a65937eee29c7e4e1e498b2846

## Range
> **The named sha `5ad048c2d9ae` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `5ad048c2d9ae`, last good `08f7de0715a8`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2929954/test_sizeof_shadow26  [code=114456B  data=5800B  bss=43568B  procs=248]
expect_same: MISMATCH [test_sizeof_shadow26]
--- expected
+++ actual
@@ -7,3 +7,8 @@
 g 4 8 2
 h 4 8 8
 i TRUE x 5
+j 12
+k 6
+l 12 12
+m 10
+n 2 1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## DIAGNOSED 2026-09-03 (frankuser, coordinator) — NOT A DEFECT, A STALE ASSERTION

Re-laned T -> P. The Track-T fallback banner above is correct that it named no
owner; the owner is the commit that added the rows.

`2ba37ba91` (*"a user RECORD, class, array or enum now beats a builtin type name
in a type position"*) added five printed rows — `j k l m n` — to
`test/test_sizeof_user_name_shadows_builtin.pas:97-108` and left the Makefile's
INLINE expected string at rows `a..i` (`Makefile:12669`). The program prints more
than the assertion knows about, so `expect_same` reports MISMATCH on the extra
lines. Nothing compiled wrong.

**Every added row matches the source's own comment**, which is the check that
settles it — `j 12` (the record, not the builtin 8), `k 6`, `l 12 12`, `m 10`,
`n 2 1` (WideChar 2 and ByteBool 1, chosen by that commit's author *"because no
fallback in this area produces 2 or 1"*). The compiler is answering exactly what
the test was written to demand.

**The fix is one line: extend the `printf` at `Makefile:12669` with
`\nj 12\nk 6\nl 12 12\nm 10\nn 2 1`.** Do not touch the `.pas` and do not
touch `compiler/**`.

### Why this is worth more than a one-line fix

The file's own comment eight lines below the last new row says **"ASSERT, do not
only PRINT"**, and explains that rows `a..i` are bare `WriteLn`s judged against
FPC by hand, which *"is fine for a row a human reads once; it is not fine for a"*
regression test. The commit that wrote that sentence then added five rows that
are printed and not asserted. It is not hypocrisy — it is the shape of the
trap: **the assertion for this job does not live in the file you are editing.**
It lives in a `printf` inside a 12000-line Makefile, so extending the test looks
complete from inside the test.

**And the failure mode is inverted from the usual one.** Adding an unasserted
row normally makes a test WEAKER and silent. Here `expect_same` compares whole
transcripts, so an unasserted row makes the job RED — the new rows were asserted
by accident, in the negative direction, against a value nobody wrote down.

### The cost, which is the actual finding

`native` has returned **RED at every sha since 2026-09-02T16:09Z** — roughly 18
hours and a dozen tstate commits — for this and nothing else. A tier that is red
for a stale string is a tier whose verdict carries no information: every reader
since has had to open the report to learn that RED meant "the same non-defect
again". STILL-RED rows are listed separately from NEW-RED precisely so this is
survivable, and it is; the cost is that the top-line word stopped discriminating.
**A red left standing because it is understood is indistinguishable, at a glance,
from one nobody has looked at.**
