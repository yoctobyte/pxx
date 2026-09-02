---
prio: 60
track: A
type: bug
status: backlog
summary: "A record FIELD compared against ANY NON-FIELD OPERAND crashes or answers FALSE under -dPXX_SHORTSTRING -- the summary previously said `to a literal` and that scope is measurably wrong. Isolated at `4ba5c77aacc7`, each shape in its OWN program so no crash hides a later row: `r.f = s` CRASH, `s = r.f` CRASH, `r.f = 'hello'` CRASH, `'hello' = r.f` CRASH -- and **`r.f = r.f` answers TRUE**. So a literal is not the discriminator; HOMOGENEITY of operand shape is. IT IS NOT A KIND-RESOLUTION BUG, and this is the useful half: `Length(r.f)` answers 5 and `r.f[1]` answers `h` in the same binary, so the field's PREFIX WIDTH already resolves correctly and the walker is not missing an IR_FIELD arm. That was the attractive theory and it is refuted -- do not spend the session on it. NOR IS IT AGGREGATE MEMBERS GENERALLY: `a[1] = s` for `array[1..2] of string[10]` answers rc=0, so an array element is fine and only a RECORD FIELD is not. Default mode is rc=0 throughout, so this is flag-mode-only. The surviving signature is a record field's decompose being incompatible with the two-operand compare SEQUENCE rather than with its own width -- field+field takes one path and works, field+anything-else mixes two and does not. Symmetric in operand order, which argues against a one-sided evaluation-order slip. Sits beside `bug-a-indexing-a-frozen-string-through-a-pointer-deref-reads-the-wrong-byte` as the second of the two readers that SURVIVED the four-cause fix `764dc3a30`; the two have DIFFERENT causes and must not be merged."
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
