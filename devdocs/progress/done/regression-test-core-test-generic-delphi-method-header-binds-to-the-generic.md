---
prio: 70
track: T
status: done
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh sweep_gendelphi26 "$(/tmp/sweep_gendelphi26)" "$(printf '100\n100\n10\n10\n7\n2\n4')"`. The job's own `src` (`test/test_generic_delphi_method_header_binds_to_the_generic.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_generic_delphi_method_header_binds_to_the_generic.pas at 5acbe362b034 in step 2/2, `tools/expect_same.sh sweep_gendelphi26 "$(/tmp/sweep_gendelphi26)" "$(printf '100\n100\n10\n10\n7\n2\n4')"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `0c5ad13167ab`).
  Untriaged.
- **Found:** 2026-09-09T09:11:36Z
- **Test source:** test/test_generic_delphi_method_header_binds_to_the_generic.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh sweep_gendelphi26 "$(/tmp/sweep_gendelphi26)" "$(printf '100\n100\n10\n10\n7\n2\n4')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_generic_delphi_method_header_binds_to_the_generic.pas'` at 5acbe362b0340998e9b2bf0aff83b52473839874

## Range
> **The named sha `5acbe362b034` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `5acbe362b034`, last good `06e404587e29`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:50: warning: duplicate definition of 'TSvc$Int64.Sel' with the same parameter types; the later body wins, but calls written between the two bind to the earlier one
ok: /tmp/testmgr-scratch-1784719/sweep_gendelphi26  [code=69400B  data=4280B  bss=43532B  procs=144]
expect_same: MISMATCH [sweep_gendelphi26]
--- expected
+++ actual
@@ -1,7 +1,7 @@
 100
 100
-10
-10
+100
+100
 7
 2
 4

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Re-laned to P, root-caused and fixed — frankZ, 2026-09-09

**The lane fallback was right to be a fallback:** this is Track P, not T. The
failing step names `expect_same.sh` and the defect is in
`compiler/pasparser_generic.inc`.

**The watcher's range was correct and its warning was too.** `5acbe362b034`
touches no buildable file; the one buildable commit in the range is
`1c16d4523` (frankH, "a specialized body now materialises where the
specialization is visible"), which introduced `BufferTemplateMethodsAhead`.

### What broke

`BufferTemplateMethodsAhead` is a LOOKAHEAD: at `ParseSpecialization`, when the
template has no buffered methods yet, it scans the whole token stream for
`<TemplateName> . <Method>` headers and copies them into the template arena.
In this test the specialization `TSvc<Int64>` is registered at token 157 — the
Delphi rewrite emits the alias right behind the template declaration — which is
BEFORE the method bodies, so the lookahead runs and takes **both** `TSvc.Sel`
headers: the generic one at line 59 and the **non-generic class's own** at line
49. The pend then streamed both into `TSvc$Int64`, which is the
`duplicate definition of 'TSvc$Int64.Sel'` warning in the log tail above, and
the non-generic body won.

### Why the existing hardening could not catch it

`ParseSubroutine`'s `X.M` branch (`pasparser_proc.inc:1150`) has a **two-part**
predicate, and its own comment describes this exact program:

1. name and arity, then
2. when the header was **not** a rewritten Delphi generic header, ask which
   class actually **DECLARES** this method — `FindUClass` + `FindUMeth` — and
   refuse the template if an ordinary same-named class does.

The lookahead had only part 1. `3801a4d66` (frankS) tightened this site from a
bare name match to name+arity, which is a real improvement and is orthogonal:
`DelphiGenMethImplHdrOfTemplate` answers **True** for an offset that is not in
`GenMethImplSOff` at all, and a plain `class function TSvc.Sel` is precisely
that. `IsDelphiGenMethImplHdr` — the predicate that answers False there — was
left called from nowhere in the tree.

### The shape

The parser reaches the same header later and decides correctly. By then the
arena row exists and the pend has already streamed it, so the correct decision
changes nothing. **A predicate that lives on one side of a lookahead/parse pair
fails by AGREEING** with the other side about every header except the one that
matters — the same shape as the four instances collected in
`debugging-playbook.md`, "A RULE THAT LIVES ON ONE SIDE OF A
DECLARATION/IMPLEMENTATION PAIR FAILS BY AGREEING", with the pair being
lookahead/parse rather than decl/impl.

### The fix

`TemplateOwnsMethodImplHdr(scan, ti)`, added beside the lookahead and wired into
its condition: it is part 2 of the parser's predicate, with the same asymmetry
(a recorded Delphi header skips the test, because the source did write `<T>` and
was never ambiguous).

**No new test.** `test/test_generic_delphi_method_header_binds_to_the_generic`
was written for this defect (`042bcbb32`), is already wired as
`sweep_gendelphi26`, went red, and is green again — a positive control drawn
from the right population, which is why it is the one that caught this.

**Negative controls, all green:** `test_circspec26` (frankH's circular-uses
fixture — the reason the lookahead exists at all), `test_twoscopespec26`,
`test_genselfparam26`, `sweep_gennestid26`, `sweep_clsnestarg26`,
`sweep_inhnestarg26`.
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 54286c1ab.

### What this fix does NOT establish

**The claim is "the one path that reached the lookahead without the parser's
guard now carries it" — not "the two sides agree."** The second is what would
have been written and it is not checkable. `BufferTemplateMethodsAhead` only
runs when `TemplateHasBufferedMethods(ti)` is false, so any header the parser
reaches first never goes through it at all; if a third path exists that reaches
neither predicate, this fix is silent about it.

The discriminating evidence here was not the two wrong values, it was the
`duplicate definition of 'TSvc$Int64.Sel'` warning: **a duplicate row means both
readings materialised**, which is the one symptom a value check cannot see —
whichever body wins, the output can still be right by accident. Anyone
re-verifying should watch for that warning's return, not only for `10`.
