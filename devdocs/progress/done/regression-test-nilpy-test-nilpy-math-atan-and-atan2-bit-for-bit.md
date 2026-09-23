---
prio: 70
track: T
status: done
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_nilpy_atan226 "$(/tmp/test_nilpy_atan226)" "$(python3 test/test_nilpy_math_atan_and_atan2_bit_`. The job's own `src` (`test/test_nilpy_math_atan_and_atan2_bit_for_bit.npy`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_nilpy_math_atan_and_atan2_bit_for_bit`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_math_atan_and_atan2_bit_for_bit.npy at b2f3e65ef050 in step 2/2, `tools/expect_same.sh test_nilpy_atan226 "$(/tmp/test_nilpy_atan226)" "$(python3 test/test_nilpy_math_atan_and_atan2_bit…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-22T08:33:09Z
- **Test source:** test/test_nilpy_math_atan_and_atan2_bit_for_bit.npy tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh test/test_nilpy_math_atan_and_atan2_bit_for_bit.npy`.
  ```
  tools/expect_same.sh test_nilpy_atan226 "$(/tmp/test_nilpy_atan226)" "$(python3 test/test_nilpy_math_atan_and_atan2_bit_for_bit.npy)"
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_math_atan_and_atan2_bit_for_bit.npy'` at b2f3e65ef0506f652ec578df301554c2a1546187

## Range
> **The named sha `b2f3e65ef050` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b2f3e65ef050`, last good `67ef6a2222b9`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
5 1.3258176636680326
 1.0 -0.25 1.8157749899217608
-1.0 7.0 0.14189705460416394
+1.0 7.0 0.1418970546041639
 1.0 -7.0 2.999695598985629
 1.0 1e-08 1.5707963167948966
 1.0 -1e-08 1.5707963367948967
@@ -156,7 +156,7 @@
 -1.0 -1.0 -2.356194490192345
 -1.0 0.25 -1.3258176636680326
 -1.0 -0.25 -1.8157749899217608
--1.0 7.0 -0.14189705460416394
+-1.0 7.0 -0.1418970546041639
 -1.0 -7.0 -2.999695598985629
 -1.0 1e-08 -1.5707963167948966
 -1.0 -1e-08 -1.5707963367948967
@@ -191,8 +191,8 @@
 3.0 1.0 1.2490457723982544
 3.0 -1.0 1.892546881191539
 3.0 0.25 1.4876550949064553
-3.0 -0.25 1.6539375586833378
-3.0 7.0 0.40489178628508343
+3.0 -0.25 1.653937558683338
+3.0 7.0 0.4048917862850834
 3.0 -7.0 2.7367008673047097
 3.0 1e-08 1.5707963234615634
 3.0 -1e-08 1.57079633012823
@@ -203,8 +203,8 @@
 -3.0 1.0 -1.2490457723982544
 -3.0 -1.0 -1.892546881191539
 -3.0 0.25 -1.4876550949064553
--3.0 -0.25 -1.6539375586833378
--3.0 7.0 -0.40489178628508343
+-3.0 -0.25 -1.653937558683338
+-3.0 7.0 -0.4048917862850834
 -3.0 -7.0 -2.7367008673047097
 -3.0 1e-08 -1.5707963234615634
 -3.0 -1e-08 -1.57079633012823
@@ -239,9 +239,9 @@
 100000000.0 1.0 1.5707963167948966
 100000000.0 -1.0 1.5707963367948967
 100000000.0 0.25 1.5707963242948966
-100000000.0 -0.25 1.5707963292948965
+100000000.0 -0.25 1.5707963292948968
 100000000.0 7.0 1.5707962567948965
-100000000.0 -7.0 1.5707963967948966
+100000000.0 -7.0 1.5707963967948968
 100000000.0 1e-08 1.5707963267948966
 100000000.0 -1e-08 1.5707963267948968
 100000000.0 100000000.0 0.7853981633974483
@@ -251,9 +251,9 @@
 -100000000.0 1.0 -1.5707963167948966
 -100000000.0 -1.0 -1.5707963367948967
 -100000000.0 0.25 -1.5707963242948966
--100000000.0 -0.25 -1.5707963292948965
+-100000000.0 -0.25 -1.5707963292948968
 -100000000.0 7.0 -1.5707962567948965
--100000000.0 -7.0 -1.5707963967948966
+-100000000.0 -7.0 -1.5707963967948968
 -100000000.0 1e-08 -1.5707963267948966
 -100000000.0 -1e-08 -1.5707963267948968
 -100000000.0 100000000.0 -0.7853981633974483

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-09-22 — NOT A COMPILER CHANGE, AND THE CONTROL IS NARROWER THAN IT LOOKS (frankh-c0)

Reproduced on **plexus**, so it is not specific to borg: **40 rows** differ from
the `python3` oracle. Every one is a **last-ULP** difference in the printed form
(`1.0738277219158434` against `...32`), not a wrong answer.

**THE COMPILER IS NOT THE VARIABLE.** Pin **v417** and my working binary
(`faacce0c0a0b`) produce **BYTE-IDENTICAL** output on this fixture — `cmp` clean,
not merely the same diff count, which is an identity check and not an arithmetic
one.

**WHAT THAT CONTROL DOES AND DOES NOT ESTABLISH, because I first wrote it down
wrong.** I recorded it as showing the failure is PRE-EXISTING. It does not. **Pin
v417 was cut TODAY at 16:59** (`e70ec7bfc`), so it is not an old compiler and
"identical to the pin" bounds nothing earlier than this afternoon. What it does
establish, and this is the only claim on it: v417 was built from origin/master
**without** the uncommitted `__file__` work in my tree, so that work **cannot be
the cause**. Whether anything in the compiler moved BEFORE v417 is untested here
and still open.

**SO THE REMAINING SUSPECT IS THE ORACLE, WHICH IS LIVE AND NOT PINNED.** This
fixture has no stored `.expected` — it runs `python3 <the .npy>` at test time and
compares bit for bit, so **the host's CPython is an input to the verdict.** Host
here is **CPython 3.14.4 (main, Aug 20 2026, GCC 15.2.0)**. The fixture was last
touched `0838c1be3` (2026-09-10), whose own subject says math.atan2 *"was never
blocked on a ulp"* — i.e. it was made bit-exact then and was green against
whatever CPython was installed then. **Record the interpreter beside the number:
CLAUDE.md already carries an instance where two math counts that read as a
regression were one measurement against two different CPythons.**

**Re-laning note:** the `track: T` line is the auto-filer's fallback and says so.
On the evidence above this is not Track T's and not a compiler regression; it is
**F-lane** — float formatting/last-ulp — which is low prio by definition and
parks in `devdocs/progress/float/`. I have NOT moved or re-rated it, because the
one thing still unmeasured is whether an older compiler agrees, and that decides
between "the oracle moved" and "we regressed before v417". **That measurement is
one command with any pre-09-22 binary and I did not have one to hand.**

**WHAT IT COSTS TODAY, which is the part that matters more than the ulp:** this
row is a **first-failure wall in `make test-nilpy`**. make stops here, so the
~130 rows after it never run. It blocked verification of an unrelated NilPy
change tonight (698 rows green, then this, then nothing) and will block the next
seat the same way. **If it is going to sit at F priority it should not also be
able to stop the tier** — either give it a tolerance, per CLAUDE.md's own rule
that a byte-exact float diff reddens ~7% of rows for no defect, or move it behind
the rows that can still be verified.

## Resolution (2026-09-23, frank)

**Not a defect — the test asserted a contract the owner has since traded away,
and the TEST is what changed.**

Reproduced at 2702b4abebca: 272 lines, 665 tokens, 657 of them parsed as float,
**20 differing from CPython and every one of the 20 exactly 1 ulp**. The raw
`struct` byte rows and every behaviour row matched. Track T's bisect had already
narrowed the range to `6b8b45af45d9` alone ("perf(B): a fast arm for ArcTan and
ArcTan2 -- the fdlibm kernel, 133x"), which also disposes of the theory that the
unpinned CPython oracle moved: a bisect varies the tree while holding the oracle
fixed.

The owner ruled on the contract directly, 2026-09-22: *"yes, performance. screw
insignificant bits pls. we learned our lesson."* So the fast arm stays.

**What landed:**
- `tools/expect_close.py` — a ULP-tolerant comparator. Soft ONLY on the last
  bits of a value both sides call a finite float of the same sign. nan, inf,
  the sign bit *including on zero*, raw bytes, integers, line count and token
  count are all still exact. The sign-of-zero rule is load-bearing: ±0.0 are
  0 ulp apart under the monotone mapping, so a bare ulp check would have masked
  the signed-zero defect this very file's `DELIBERATELY ABSENT` note watches.
- Tolerance **2**, taken from `test/lib_math_fast_tolerance.pas` ("within 2 ulp
  of glibc, and that is all") rather than invented, and one ulp above the
  measured max so the gate is not born at its own limit.
- `--selftest`, wired as its own Makefile row ahead of the consumer, asserting
  the rejections. Verified against the real population as well: reinstating the
  Dekker-split `nan` (this file's own positive control), a signed-zero flip, and
  a 3-ulp drift each redden; 1 and 2 ulp pass.
- The file is renamed `..._against_cpython.npy`. `bit_for_bit` was the claim
  that just stopped being true, and its header argued that claim at length.

**Population note:** the 20/657 figure is this file at 2702b4abebca under
CPython 3.x on plexus. It is not a claim about the ArcTan kernel generally —
`6b8b45af45d9` measured that separately at max 1 ulp over ~15600 rows against
glibc.

This row halted `make test-nilpy` at 2470 of 6614 recipe lines; 5b's earlier
`make -i` run found it the only failure in 6709 lines, so the territory behind
it was already measured green.
- 2026-09-23 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
