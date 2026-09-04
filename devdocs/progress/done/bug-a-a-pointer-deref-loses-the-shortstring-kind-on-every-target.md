---
slug: bug-a-a-pointer-deref-loses-the-shortstring-kind-on-every-target
track: A
prio: 65
type: bug
status: done
blocked-by: []
owner: unassigned
created: 2026-09-04
found-by: frankA (fixing the wasm32 half of the same family)
summary: "`r.NamePtr^` for `NamePtr: ^string[N]` with N <= 255 is read with the EIGHT-byte prefix layout on ALL SEVEN targets, because the deref's IR node is tagged the generic tyString and the pointee's tyShortString is never recovered. FPC says TRUE for every row; pxx answers `cmp FALSE`, `Length` 4342018, an assignment of 16 blanks and a garbage print. Silent and cross-target. Cap 256 (tyString) is correct everywhere, which is why lib/rtl/typinfo.pas -- whose TRttiStr is capped at 256 on purpose -- is NOT affected."
---

# A pointer deref loses the shortstring kind, on every target

Found while fixing
`bug-a-wasm32-a-frozen-string-through-a-pointer-in-a-record-field-compares-as-the-fields-address`,
which is the same family at the OTHER width and was wasm32-only. That one is
fixed. This one was underneath it and is not wasm32's.

## Repro and the oracle

```pascal
program ss;
type S16 = string[16]; P16 = ^S16;
type TEnt = record NamePtr: P16; end;
var n: S16; r: TEnt; t: S16; ln: Integer;
begin
  n := 'AB'; r.NamePtr := @n;
  WriteLn('cmp   ', r.NamePtr^ = 'AB');
  t := r.NamePtr^;            WriteLn('assign [', t, ']');
  ln := Length(r.NamePtr^);   WriteLn('len   ', ln);
  WriteLn('print [', r.NamePtr^, ']');
end.
```

| | cmp | assign | len | print |
| --- | --- | --- | --- | --- |
| FPC 3.2.2 | TRUE | `AB` | 2 | `AB` |
| pxx, every target | **FALSE** | **16 blanks** | **4342018** | **garbage** |

`4342018` is `0x42410 2`-shaped: the length byte and the characters read as one
machine word. The 8-byte prefix is being applied to a 1-byte one.

**Seven targets measured, all identical:** x86-64, wasm32, i386, arm32,
aarch64, riscv32, xtensa. This is not a backend defect.

## The boundary is the FIELD, and cap 255 is the cliff

Six shapes, `a`..`g`, at two widths (the `probe11` form: `q^` through a plain
pointer variable, `r.NamePtr^`, `r.s`, `arr[1]`, `pr^.NamePtr^`, `pr^.s`,
`ents[1].NamePtr^`):

```
string[16]  and string[255]:  a TRUE b FALSE c TRUE d TRUE e FALSE f TRUE g FALSE
string[256]:                  a TRUE b TRUE  c TRUE d TRUE e TRUE  f TRUE g TRUE
```

So it is exactly the three shapes whose pointer comes OUT OF A FIELD, and only
below the tyShortString/tyString boundary. `q^` through a plain pointer
VARIABLE is correct at both widths -- `IRFrozenKindOfAddr` has an arm for
IR_LOAD_SYM that reads the pointer symbol's `PtrElemTk`, and that arm carries a
long comment about exactly this failure mode. There is no equivalent for a
pointer that came from a field, because by then the IR node is an
`IR_LOAD_MEM` over an `IR_FIELD` and the field node records only `tyPointer`.

## Where the information still exists

`AN_DEREF` nodes already carry the answer: `ASTSOffset` is the pointer levels
REMAINING and `ASTSLen` the ultimate base kind (ir.inc's PChar arm reads both,
and its comment says the storage "turned out to already exist"). For
`r.NamePtr^` that is 0 levels over a `tyShortString` base. So the fix is to tag
the lowered `IR_LOAD_MEM` with the real frozen kind instead of the generic
`tyString`, not to add another walker.

Do NOT fix it by widening `IRFrozenKindOfAddr`'s `IR_LOAD_SYM` arm to
`IR_LOAD_MEM`. That arm's own comment records why it was NARROWED to LOAD_SYM:
on a LOAD_SYM `IRA` is a symbol index and on a LOAD_MEM it is a NODE index, so
the old code read `Syms[<node number>]` -- bounds-checked, never an error, and
it answered about an unrelated symbol.

## Why this is prio 65 and not lower

It is silent, it is on every target, and FPC is unambiguous, so it is real code
someone MEANT to write coming out wrong -- not an edge case and not a parity
nicety. `Length` answering 4342018 also means a caller that trusts it walks
four megabytes.

## What it is NOT

`lib/rtl/typinfo.pas` is unaffected and deliberately so: `TRttiStr`'s cap is
256, chosen with a comment saying the cap "is not a length, it is a" layout
selector. Anything that reads RTTI names is on the wide side of the cliff.

## Positive controls for any fix, both directions

- `q^` at BOTH widths must stay TRUE -- it already works through the LOAD_SYM
  arm and a change that re-routes derefs can break it.
- a plain `string[N]` FIELD (`r.s`) and a plain ARRAY ELEMENT (`arr[1]`) must
  stay TRUE at both widths -- they emit no `load_mem` at all and a change that
  makes them do so breaks them.
- the `string[256]` row must stay TRUE on all seven, which is
  `test/test_cross_frozen_ptr_in_field.pas` -- it exists, it is wired, and it
  deliberately does NOT cover this width for the reason above.

## FIXED 2026-09-04 — one question, asked at three sites

`ASTDerefFrozenTk` (compiler/ir.inc, just above `IRLowerAddress`) returns the
narrow kind an `AN_DEREF` node already records, or -1. Three arms ask it:

1. the **value** arm shared by AN_DEREF/AN_INDEX/AN_FIELD — fixes `=`, `:=`
   and concat;
2. the **address** arm of `IRLowerAddress` — fixes `Length(p^)` and
   `Write(p^)`, which address the deref instead of valuing it and so never saw
   the value arm's tag;
3. the **index base** kind in `IRLowerAddress`'s AN_INDEX arm, beside
   `DerefFrozenStrPtrSym` — fixes `p^[1]`, whose origin `lo` is derived from
   the prefix size and stayed at the 8-byte `-7`.

That the same expression needed three is the finding: `=` and `:=` were already
correct in the same program that answered `Length` 4342018, which is what made
one missing kind look like three separate defects.

**The address arm is restricted to NARROW kinds, and that is measured, not
cautious.** Tagging a plain `^string` deref there too made the compiler unable
to lower its own source (`IR_UNSUPPORTED ... AST node kind 39`): the node is an
ADDRESS and consumers key on its `tyPointer` tag. `tyString` is also the width
`IRFrozenKindOfAddr` already defaults to, so there is nothing to repair in that
direction.

`IRFrozenKindOfAddr` was NOT widened to `IR_LOAD_MEM`, as this ticket asked.

## Verification

- FPC oracle, six shapes × six columns (cmp / assign / Length / print / concat
  / `[1]`) at cap 16 and cap 255: **byte-identical output**.
- **Positive control**: the same program on the pre-fix compiler
  (`aaf09343d1cb`) **segfaults**, exit 139, no output — the concat row reads a
  1-byte prefix as an 8-byte length. The control was built from the commit
  under test with `git checkout -- compiler/ir.inc`, rebuilt, and the fix
  rebuilt after restoring (`7ba433bea4e4` before and after, so the restore is
  proven).
- `test/test_cross_frozen_ptr_narrow.pas`, wired into `test-core`: green on
  **all seven targets** (x86-64, wasm32, i386, arm32, aarch64, riscv32,
  xtensa). It prints Length and the indexed character rather than a verdict,
  because a compare-only row passes when both sides are read at the same wrong
  width.
- Both control directions asserted in that file and green: `q^` at both widths,
  a plain `string[N]` field, a plain array element.
- The cap-256 sibling `test/test_cross_frozen_ptr_in_field.pas` re-run on all
  seven: green. Its "still-open" paragraph is corrected in the same commit.
- `make compiler/pascal26` converged after 1 round; `tools/gate.sh quick`
  GREEN with the FPC seed canary running (`PASS`, uncommitted `compiler/**`).

## It also closes the wasm32 sibling, and the attribution was checked

`bug-a-a-typed-pointer-deref-of-a-frozen-string-is-unlowered-on-wasm32`
(p25) recorded `Length(p^)` for `p: ^string[10]` TRAPPING on wasm32 at both
default and `-dPXX_SHORTSTRING`, and answering 122511465736197 natively under
the define. All four cells of its table now read `5` / `5`.

**Measured which change did it rather than assuming**: its own repro on the
pre-fix binary — HEAD, so already carrying the wasm32 frozen-load fix
`9b67b266d` — still traps (`wasm trap: unreachable`, exit 134). So this is the
change that closed it, and `9b67b266d` is not.

The WRITE half that ticket documents and explicitly excludes (`p^ := c` giving
`1 0 ... 88` at offset 8) was ALREADY correct before this change: both the
pre-fix and post-fix compilers give `1 88` on native and wasm32 alike, which is
exactly the "a fix turns both into `1 88`" outcome that ticket predicted. Not
mine to claim.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
