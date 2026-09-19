---
prio: 70
track: N
status: done
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 10 is `tools/expect_same.sh lib_mimic_xmlreader.1 "$(/tmp/lib_mimic_xmlreader | grep -c '=ok')" "25"`. The job's own `src` (`test/lib_mimic_xml_sax_xmlreader.npy`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `lib_mimic_xml_sax_xmlreader`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **The NAMED SHA cannot be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged, and it was not bisected. **That is a statement about ONE commit, not about the range**: this job still reads live `lib/**`, `test/**` and the Makefile, so a commit BELOW the named sha can have caused it. Read the Range section before concluding anything — it says how many commits here the job can actually observe, and it is the section that will tell you when the answer is genuinely the box.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/lib_mimic_xml_sax_xmlreader.npy at 2b2ec3fee1c5 in step 2/10, `tools/expect_same.sh lib_mimic_xmlreader.1 "$(/tmp/lib_mimic_xmlreader | grep -c '=ok')" "25"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-17T18:11:48Z
- **Test source:** test/lib_mimic_xml_sax_xmlreader.npy tools/expect_same.sh
- **Failing step:** line 2 of 10 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh lib_mimic_xmlreader.1 "$(/tmp/lib_mimic_xmlreader | grep -c '=ok')" "25"
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/lib_mimic_xml_sax_xmlreader.npy'` at 2b2ec3fee1c5c5f34462f649a12fa17b66eec278

## Range
bad `2b2ec3fee1c5`, last good `9b8475d4e99e`, **1 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
note: xml_sax_xmlreader -> mimic_xml_sax_xmlreader (shim, subset)
ok: /tmp/testmgr-scratch-758032/lib_mimic_xmlreader  [code=1380120B  data=94012B  bss=70100B  procs=2228]
expect_same: MISMATCH [lib_mimic_xmlreader.1]
--- expected
+++ actual
@@ -1 +1 @@
-25
+24

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-09-19 (frankH) — bisected to the v410 -> v411 pin: a compiler/builtin regression

The watcher cannot narrow this: its one observable commit is the v411 pin
(`8d9d69bdc`). Differential, each pinned binary with its own frozen builtin
extracted from git, over identical live `lib/` and the row's exact command:

| pinned binary | result |
| --- | --- |
| v410 `c599e8546121` | 25/25 |
| v411 `bc884808fda5` | 24/25, `name_by_qname=FAIL got "('http://www.w3.org/1999/xlink', 'href')"` |

HEAD's compiler also answers 24. So the cause is in the compiler or builtin
build inputs between `764ee2ed2` (v410) and `9b8475d4e` (v411's source), in
the NilPy lane. The symptom is a tuple arriving as its repr STRING. It is also
the sole new red that stopped auto-pin in the first five verdicts after v411:
see bug-t-armed-autopin-has-refused-62-consecutive-times-... .


## DIAGNOSED AND FIXED 2026-09-19 (frankS, Track N) — an override's result was coerced to the BASE method's type

**The failing row, in full.** `name_by_qname=FAIL got "('http://www.w3.org/1999/xlink', 'href')" want ('http://www.w3.org/1999/xlink', 'href')`. The `got` is the tuple's **repr string**; the `want` is the tuple. 24 of 25, and the other 24 pass because they compare strings and ints.

**Mechanism.** `PyRegisterClassMembers` (pyparser.inc) makes an override adopt its base method's signature, which is right — the inherited method occupies a VMT slot with the base's types and the base's own body calls through it. It already widened BOTH sides to variant when the two disagree about a SCALAR result. Everything else fell through to `mRet := Procs[ovPi].RetType`.

`AttributesNSImpl(AttributesImpl)`. The base's `getNameByQName` returns a plain `name` — tk=23, `tyAnsiString`. The override returns a `(uri, localname)` dict key — tk=22, `tyVariant`, because a tuple is a `TPyList` reached through a variant. `PyIsScalarRetKind` includes variant and excludes AnsiString, so the widening test failed and the base's AnsiString was adopted: the tuple was rendered as its repr.

**The mirror direction SEGFAULTS**, and it is the same line: a str override of a tuple-literal base puts a string in the tuple's slot.

**Why no reduction found it for a while.** Two reductions reproduced nothing — a module-level dict loop over tuple keys, and a bare parameter reached from mixed-type call sites — because both fixed the axis that decides the outcome: INHERITANCE. The minimal case is a subclass overriding a method whose base returns a different kind, and it is twenty lines. Working down from the real failing artifact found it; working up from a guess did not.

**A tuple has TWO spellings here** and only one of them was in the first fix: `tyVariant` when it arrives through a variant-valued expression (the shim's loop variable) and `tyClass`+rec when it is a literal `return ("u","h")`. Grepping for the construct finds one; the other is a different handler.

**Fix.** `PyOverrideRetJoinsToVariant` replaces the bare scalar test. Variant is the join for any non-covariant disagreement; class-vs-class stays with the base, which is covariance and a separate question.

**This is the configparser `optionxform` case with the opposite correct answer**, which is the whole difficulty: both overrides infer variant, one really returns a str and one really returns a tuple, and nothing in the return kind separates them. The join has to be the type that is right for both. `test_nilpy_configparser` and `test_nilpy_subclass_unit_base` are the controls and both passed before and after.

## INERT UNTIL THE NEXT PIN — this does NOT clear the red on its own

The job's own recipe is `$(PXX_STABLE) -Fulib/rtl test/lib_mimic_xml_sax_xmlreader.npy` (Makefile:37321). It builds with the PINNED compiler, so a fix in `compiler/**` cannot change what it does. **Measured, with this fix in the tree: the pinned binary still gives 24.**

So this closes the DEFECT and does not by itself clear the auto-pin blocker. What clears the row is a pin carrying this commit.

## Evidence

The eight-row matrix, pxx against CPython, after the fix — every row SAME:

| base returns | override returns | result |
| --- | --- | --- |
| str | tuple | `tuple ('u', 'h')` |
| tuple | str | `str 'q'` (was a SEGFAULT) |
| tuple | tuple | `tuple ('a', 'b')` |
| str | str | `str 'q'` |
| int | tuple | `tuple ('u', 'h')` |
| str | list | `list [1, 2]` |
| int | float | `float 1.5` |
| float | int | `int 1` |

The last two are the pre-existing scalar rows, unchanged — they are in the
table as the control that the widening that already worked still works.

**The class half needed more than two controls.** Taking `tyClass` out of the
refusal changes override typing for every NilPy class, not just this shim, so
it was measured against the whole NilPy tier rather than against the fixture
that motivated it: `PXX_ALLOW_FULL_SUITE=1 make test-nilpy`, **495 rows
asserted, 0 `expect_same: MISMATCH`, 0 make errors**. A class base whose
override infers variant (`return self.d["k"]`) still resolves field access
through the widened result on both base and subclass, and matches CPython.

Class-vs-class is untouched and still adopts the base: that is covariance and a
separate question, and the common shape (`return Node(...)` in both) infers the
same kind on both sides so it never reaches the join at all.
- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
