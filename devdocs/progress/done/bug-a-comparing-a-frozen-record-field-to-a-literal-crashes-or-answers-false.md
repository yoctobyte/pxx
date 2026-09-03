---
prio: 60
track: A
type: bug
status: done
summary: FIXED `ba90811d3`. Under -dPXX_SHORTSTRING a record FIELD compared against
  any NON-FIELD operand crashed or answered FALSE (`r.f = r.f` answered TRUE, so
  operand HOMOGENEITY was the discriminator, not the literal). Cause: the field was
  VALUE-LOADED where an address was wanted, plus two compare guards spelled
  `= tyString` where they meant TypeIsFrozenString, plus CmpFusible fusing the
  field-vs-field row into a scalar address compare — correct at -O0 and FALSE at
  -O1+, which is why -O0 hid it. NOTE this summary previously recorded a
  "decompose/compare sequencing mismatch"; that was my own hypothesis and it was
  refuted by gdb — see the retraction below. Re-verified against the FPC oracle.
---

# Comparing a frozen record FIELD to a literal crashes or answers FALSE

```pascal
type TS10 = string[10]; TRec = record f: TS10; end;
var r: TRec;
begin
  r.f := 'hello';
  if r.f = 'hello' then ...   { segfault on x86-64 and riscv32,
                                FALSE on aarch64 and arm32 }
end.
```

Measured 2026-09-02 at `764dc3a30`, compiler `e81a80c4621c`, under
`-dPXX_SHORTSTRING`. Default mode is correct on all four.

## Why this is a FIFTH cause, not a remnant

`764dc3a30` fixed four distinct readers and its own summary says so. In the
**same run** that produces the failures above, `s = 'hello'` and `p^ = 'hello'`
are both green on all four backends — so the comparison arm itself now resolves
the frozen kind for a variable and for a deref, and does not for a FIELD. The
field operand reaches it by a path none of the four fixes covers.

The two failure modes are the same defect at two word sizes: a field operand
whose length is read at the wrong width gives a count in the hundreds of
millions, which the comparison either walks off (segfault) or short-circuits on
a length mismatch (FALSE).

## Where it is asserted

`test/test_shortstring_through_a_pointer.pas`, row `compare field to literal`.
That file is wired DEFAULT-only; this bug is one of the two reasons its
`-dPXX_SHORTSTRING` rows are still not wired.

It is also the current truncation point on x86-64 and riscv32 — a crashing row
costs every row behind it, so this bug is currently hiding the verdict of the
eleven rows that follow it.

[[bug-a-indexing-a-frozen-string-through-a-pointer-deref-reads-the-wrong-byte]]
[[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]]


## MEASURED DIAGNOSIS — three theories refuted, one signature left (frankB, 2026-09-02)

Binary `4ba5c77aacc7`, `converged after 1 round(s)`, at HEAD with `764dc3a30`
and `c8375f3e7` (i386) both ancestors.

**Every shape run as its OWN program.** `40646620c` banked the reason and it bit
again here: a row that ends the process costs every row behind it, so a single
file reported `C` crashing and told me nothing about `D`, `E` or `F`. A crashing
test reports LESS the worse the state is.

| shape | result |
| --- | --- |
| `s = 'hello'` | TRUE |
| `s = s` | TRUE |
| `r.f = s` | **CRASH** |
| `s = r.f` | **CRASH** |
| `r.f = 'hello'` | **CRASH** |
| `'hello' = r.f` | **CRASH** |
| `r.f = r.f` | **TRUE** |
| `a[1] = s`, `array[1..2] of string[10]` | rc=0 |
| any of the above, DEFAULT mode | rc=0 |

**REFUTED (1) — it is not the walker missing an `IR_FIELD` arm.** That is the
theory the shape invites, and `IRFrozenKindOfAddr` genuinely has no `IR_FIELD`
arm, which makes it look confirmed by reading. It is wrong: **`Length(r.f)`
answers 5 and `r.f[1]` answers `h` in the same binary as the crash.** The
field's prefix width already resolves. Reading the walker would have produced a
confident wrong root cause; running it took one program.

**REFUTED (2) — it is not aggregate members.** `a[1] = s` is fine. Only a record
field.

**REFUTED (3) — it is not the literal.** `r.f = s` crashes with no literal
present, and `r.f = r.f` is TRUE with two fields.

**WHAT SURVIVES:** field+field takes one path and works; field+anything-else
mixes two and does not. Symmetric in operand order. So look at how a field
operand's decompose interacts with the OTHER operand's — a clobber or a
sequencing mismatch between two decompose arms — not at what kind the field
resolves to.

**Related but NOT the same defect:** `p^[1]` reads a blank while `s[1]` and
`r.f[1]` read `h` in the same run. That one IS the walker's shape at an index
origin. Two survivors, two causes; merging them is the failure mode this ticket
and its sibling exist to prevent.

Found while reviewing i386 (`c8375f3e7`), from frankA's observation that
resolving the operand kind AT THE DECOMPOSE is what makes i386's comparison
correct. i386 crashes on this row too, so the decompose fix is necessary and not
sufficient.

## RESOLVED `ba90811d3` — and the hypothesis above was WRONG (frankB, 2026-09-02)

**Correcting my own diagnosis in the section above before anyone acts on it.**
It said the surviving signature was *"a record field's decompose being
incompatible with the two-operand compare SEQUENCE"* and pointed at a clobber
between two decompose arms. **That is not what it was**, and the homogeneity
table that suggested it was a true observation with a false explanation
attached.

**FOUR causes, all one sentence: a guard spelled `= tyString` where it meant
`TypeIsFrozenString`.**

1. **The value-load** (`ir.inc`, AN_FIELD rvalue). The arm implementing *"a
   frozen-string value IS its address (no load)"* tested `ASTTk = tyString`. A
   tyShortString field failed it, fell through to `IR_LOAD_MEM`, and **loaded
   eight bytes of the string as its value**. gdb at the fault: `rax =
   $6F6C6C656805` — length byte 5, then `hello`. An AN_IDENT frozen string takes
   the address path above and never reaches this arm, which is precisely why
   `s = 'hello'` was green beside the crash and why the failure looked like it
   was *about* fields.
2. **The compare guards**, x86-64 (`= tyString`) and aarch64/arm32
   (`in [tyAnsiString, tyString, ...]`). Two spellings of one omission. With (1)
   fixed, `r.f = r.g` — two fields, no literal — failed both and fell through to
   the generic scalar compare. A literal operand had been dragging the guard
   true all along.
3. **`CmpFusible`**, the optimiser predicate. After (1) and (2), x86-64 still
   answered FALSE **at -O1/-O2 and correctly at -O0**. It excludes
   float/string/variant from `cmp`+`setcc` fusion and spelled the string half as
   a bare equality, so a tyShortString operand was fused and the two field
   ADDRESSES were compared as integers.

**THE WIDTHS WERE NEVER WRONG.** The emitted code around the fault was already
`lea 0x1(%rax)` for the field against `lea 0x8(%rcx)` for the literal, byte load
against word load. This read as a width bug for a day. `Length(r.f)` = 5 was
telling the truth.

**`-O0` CORRECT WHILE `-O1+` IS WRONG IS THE TRANSFERABLE TELL** — it says the
unwidened predicate is in the OPTIMISER, not in the arm you are reading. By that
point nothing in the compare path looked wrong, because nothing in it was.

**Three theories died before gdb.** Missing `IR_FIELD` walker arm (refuted by
`Length(r.f)`), aggregate members (refuted by `a[1] = s`), the literal (refuted
by `r.f = r.g`). Each was refuted by a one-program measurement and each had
looked confirmed by reading. The fourth attempt stopped theorising and read the
registers at the fault, which took one command.

Verified 17/17 against the FPC 3.2.2 oracle at `a81084690bac` — native × four
mode combinations × -O0/-O2, plus aarch64/arm32/riscv32/xtensa at default and
`-dPXX_SHORTSTRING` — with `r.f = 'nope'` as a must-be-FALSE row so a
stuck-TRUE compare cannot pass. Gate GREEN, FPC canary PASS.

**NOTE ON A CLAIM IN CIRCULATION:** `0dd5858e6` did NOT close this. Re-measured
at exactly the compiler sha it was reported passing at (`a09992a1c33f`, stashed
tree, rebuilt): `r.f = 'hello'` exits 139 there. It closed the pointer-deref
index and nothing else.

## RESOLVED — ba90811d3

Cause: the field was value-loaded; two compare guards plus CmpFusible, which fused the field-vs-field row into a scalar address compare (right at -O0, FALSE at -O1+).

Re-verified at 05f50f9ae with the repro in this ticket, unchanged, against the
FPC 3.2.2 oracle: exact match at default AND -dPXX_SHORTSTRING. Covered going
forward by test/test_frozen_field_and_deref_readers.pas, wired into all 12
expected blocks (4 native modes; x86-64, aarch64, arm32, riscv32, xtensa x 2
modes) — the 32-bit targets included, since this is a width class and x86-64 is
where width bugs hide.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
