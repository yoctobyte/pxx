---
type: bug
track: A
prio: 85
status: done
summary: FIXED. Under -dPXX_SHORTSTRING, a `const` frozen-string parameter was read
  through the PARAMETER's prefix width while the argument carried another, so any
  cross-width argument (a literal, or a string[N] of the other width) lost its
  payload — symmetric, not literal-only. `const` guards aliasing, never layout; the
  by-value copy funnel now also fires on a prefix-width mismatch.
---

# A const shortstring parameter arrives as NUL bytes under the byte-prefix mode

**Silent, and on EVERY target** — unlike the ordering and concat blockers, which
are x86-64 only. `const` is the idiomatic way to pass a string one does not
intend to modify, so this hits ordinary code.

## Repro

```pascal
program cp;
procedure T(const n: string[12]); begin WriteLn('const param=[', n, '] len=', Length(n)); end;
procedure V(n: string[12]);       begin WriteLn('value param=[', n, '] len=', Length(n)); end;
begin T('hello'); V('hello'); end.
```

Measured at `45f6639f5`, compiler sha `a43276f1ce47`, exit 0 everywhere.

| | default | `-dPXX_SHORTSTRING` |
| --- | --- | --- |
| `const` param | `[hello] len=5` | **`[<NUL><NUL><NUL><NUL><NUL>] len=5`** |
| value param | `[hello] len=5` | `[hello] len=5` |

Confirmed identical on x86-64, i386, arm32, aarch64 and riscv32 (`cat -v` shows
`^@^@^@^@^@`; without `cat -v` the field looks like blanks, or like nothing at
all in a terminal).

**The LENGTH is right and the DATA is gone**, which is the same signature as the
array bug before it was fixed: the prefix is found and the payload is not.
By-value works, so the divergence is in how the `const` reference is passed or
dereferenced, not in the layout.

## Guard note

Printed normally, `[<NUL>*5]` renders as an empty-looking field that reads as a
formatting quirk. `cat -v` is what separates "prints nothing" from "prints five
NULs", and the two have different causes. **Any probe comparing printed output
of a string that might be NUL-filled needs `cat -v` or a byte comparison**, not
an eyeball.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

## RESOLVED — `const` guards ALIASING, never LAYOUT

The by-value copy funnel in `IRLowerCallArg` materialises a private temp for a
by-value set or frozen-string argument, and deliberately skips `const`:
*"`const` is the escape hatch: it cannot be written, so the copy would be pure
cost."* That reasoning is about **aliasing**, and it was completely correct
while every frozen kind was 8 bytes wide. It says nothing about **layout**. A
frozen string is read through the *parameter's* prefix width, so once
`-dPXX_SHORTSTRING` made two widths exist, a `const` argument of the other
width is read with its length at one size and its payload at another. Const-ness
stops writes; it does not make the widths agree.

Fixed by widening that funnel's condition: the copy also fires when both sides
are frozen and their **prefix widths differ**. Keying on the width rather than
on the kinds keeps the default mode free — every frozen kind is 8 bytes there,
so the clause is never true.

### THE REPORTED SHAPE IS HALF OF IT — the bug is symmetric

The ticket's repro passes a LITERAL, and that mattered more than it looks: a
literal keeps its 8-byte pool prefix permanently, so it is the cross-width
operand. Passing a *variable* of the parameter's own type does not reproduce at
all, which is why a first attempt to reproduce this came up clean on ten
configurations before the literal was tried. Varying the shape found four rows,
measured on x86-64 under `-dPXX_SHORTSTRING`, with `C(const n: string[12])`:

| argument | before | after |
| --- | --- | --- |
| `s: string[12]` (narrow var) | `[hello]` ok | ok |
| `'hello'` (literal, 8-byte prefix) | `len=5` + **five NULs** | `[hello]` |
| `b: string[300]` (8-byte prefix) | `len=5` + **five NULs** | `[hello]` |
| narrow var into `const string[300]` | **`len=122511465736197`** | `len=5` |

So it is not a literal quirk and not one direction — it is any prefix-width
mismatch across a `const` frozen-string call boundary.

### WHY THE LENGTH SURVIVES, AND WHY THAT MADE IT LOOK LIKE SOMETHING ELSE

In the narrowing direction the length is *correct* while the payload is gone.
That is not two bugs: on a little-endian target `5` is the low byte of the
8-byte length word, so a 1-byte read of an 8-byte prefix returns the right
answer by construction, and the payload pointer then lands in the remaining
seven zero bytes of that word — which is exactly where the NULs come from.
**A `Length()`-only probe passes with this bug fully present**, and five NUL
bytes render as an empty field in a terminal, so the visible symptom is a
plausible formatting quirk sitting next to a correct number.

### THE ROW THAT CAUGHT A WRONG FIX

The first fix keyed the width test on `ASTTk[argAST]`, and closed three of the
four rows. It left the widening row broken, because **a genuinely narrow
variable's AST node carries the legacy `tyString` alias**, whose prefix is 8 —
so `C12(s)` reads as a width *difference* against a 1-byte parameter (copies,
correct) while `CBig(s)` reads as a width *match* against an 8-byte one (skips
the copy, still broken). The comment written alongside that first fix asserted
the alias was harmless because it "misreads as a difference and copies, and a
copy of a const argument is always safe" — true of one direction, false of the
other, and the four-row table is what falsified it. An alias that gives the
right answer half the time is worse than one that is always wrong, because the
half you check confirms it.

`ASTFrozenArgTk` asks the symbol instead, whose `TypeKind` is not aliased, and
falls back to `ASTTk` for literals and expression temps, where `ASTTk` is
correct. This is also the AST-side twin of the `IRFrozenKindOfAddr` resolution
on the IR side — the same question asked at the other end of the pipeline.

### Verified

- FPC 3.2.2 oracle, five rows it can express, exact match in both modes. Note
  FPC does **not** truncate a `const` shortstring param either: a 200-char
  `string[200]` into a `const string[12]` answers `200` under both compilers.
- 7 shapes × 4 mode combinations native, and the wired test on x86-64, aarch64,
  arm32, riscv32 and xtensa × 2 modes — the 32-bit targets included, since this
  is a width class and x86-64 is where width bugs hide.
- Positive control: rebuilt at the pre-fix tree and confirmed the three rows go
  red there (`converged`, not the stamp path; binary sha changed).
- Regression rows `cp1`/`cp1`/`cp3` wired into all 12 expected blocks. Both
  directions are asserted, because a fix for one left the other broken.
- `gate.sh quick` GREEN, FPC seed canary `PASS` (run before commit, so it was
  not the `SKIP` a clean tree produces).

### Not fixed here

`string[300]` into a `const string[12]` answers 255 rather than 300. 255 is the
largest length a 1-byte prefix can represent, i.e. the ceiling of the
parameter's own declared layout, and `string[300]` is a kind FPC cannot express
so there is no oracle to diverge from. Recorded rather than filed.
