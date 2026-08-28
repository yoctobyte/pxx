# Pascal dialect divergences from FPC — deliberate, decided, do not re-file

The sibling of `nilpy-semantics-divergences.md`, for Track P / Track A.

**Read this before filing a "pxx disagrees with FPC" ticket.** Everything on this
page is a divergence the owner has *decided*, with the ticket that decided it.
A differential run rediscovers these every time — that is what
`bug-t-fpc-probe-reports-the-deliberate-shl-deviation-as-new` is about — and each
rediscovery costs a session an hour before it finds the decision.

The rule for adding a row: it belongs here only once a `decide-*` ticket has been
**resolved**. An unexplained disagreement is a bug ticket, not a row here.

**WHY these exist at all** — worth knowing before you read a row as a compatibility
failure. Owner, 2026-08-27: *"us being 'lax' is not intended to be incompatible.
it is more because of the odd design goal of pxx where we intend to be
cross-language."* Pascal is what the compiler and the RTL are written in, so it
must be expressive enough to serve **every other frontend's runtime**. A
restriction that is harmless in a Pascal-only world can be exactly what stops the
RTL expressing another language's semantics. So the question a divergence answers
is *"does this restriction serve a cross-language substrate, or is it an accident
of Pascal's own history?"* — not *"does FPC do it?"* Full reasoning:
`frontend-compat-philosophy.md`.

Note also what the divergences are **not**: FPC-compatible code still compiles.
These widen what is accepted; they do not reject anything FPC accepts.

---

## Shift width: `shl` / `shr` on a declared 32-bit operand

Decided in `devdocs/progress/decided/decide-shift-operator-promotion-width.md`
(2026-08-10), implemented 2026-08-11. **Default dialect: shifts happen at NATIVE
width, fold and runtime alike, with no truncation.** `--strict-fpc` reproduces
FPC exactly, asymmetry and all.

Measured against fpc 3.2.2, x86-64, `-O1` (re-measured 2026-08-21; rows 2, 3 and
9 were NOT in the decision's own table and are the ones a differential trips
over first, because they need no unary minus and no 40-bit count):

| # | expression | FPC | pxx default | pxx `--strict-fpc` |
| --- | --- | --- | --- | --- |
| 1 | `-a shr 1` (a: Integer = 8) | 9223372036854775804 | same | same |
| 2 | `a shr 1` (a: Integer = -8) | 2147483644 | **9223372036854775804** | 2147483644 |
| 3 | `a shr 4` (a: Integer = -8) | 268435455 | **1152921504606846975** | 268435455 |
| 4 | `c shr 1` (c: Cardinal) | 2147483644 | same | same |
| 5 | `q shr 1` (q: Int64 = -8) | 9223372036854775804 | same | same |
| 6 | `(-8) shr 1` (const) | 9223372036854775804 | same | same |
| 7 | `a shl b` (8 shl 40, both vars) | 2048 | **8796093022208** | 2048 |
| 8 | `1 shl 40` (const) | 1099511627776 | same | same |
| 9 | `a shl 31` (a: Integer = 1) | -2147483648 | **2147483648** | -2147483648 |

Row 1 vs row 2 is the trap that makes this look like a bug: FPC's own answer
*changes* depending on whether the operand is `-a` or a variable holding a
negative value, because in FPC the unary minus is what promotes, not the shift.
The decision's table recorded only row 1, so the plain-variable rows read as
undocumented regressions.

Rows 7 and 9 are FPC masking the shift count to 5 bits at 32-bit width — a wart
its own constant folder contradicts (row 8), which is exactly why the default
dialect does not copy it.

`--strict-fpc` was verified on 2026-08-21 to reproduce **all nine rows** exactly.
So the escape hatch works: code that needs FPC's arithmetic has it, and the
default keeps the property that widening never loses information.

**Not a divergence, and still a bug if you see it:** anything where pxx *loses*
information a declared type carries, or where the two disagree at Int64 or at
Cardinal width (rows 4 and 5 agree today and must keep agreeing).

---

## Assertions: on by default here, off by default in FPC

`Assert(False)` raises `EAssertionFailed` in pxx and is a no-op in FPC unless
`-Sa`. With `-Sa` the two agree line for line, so this is purely a default.

**Status: NOT yet decided** — `decide-assertion-default-vs-fpc` is open. Listed
here so a differential run recognises the shape, not because it is settled.

## `Abs` / `Sqr` of a 32-bit Integer: native width, same as shifts

Measured 2026-08-22 (`fpc -Mobjfpc -O1` 3.2.2 vs pxx `80bbe2f38`). Same rule as
the shift section above, reached independently: **pxx evaluates at native width
and does not truncate to the operand's declared type.**

| expression (`i: Integer`) | FPC | pxx default | pxx `--strict-fpc` |
| --- | --- | --- | --- |
| `Abs(i)`, `i = Low(Integer)` | -2147483648 | **2147483648** | 2147483648 |
| `Sqr(i)`, `i = Low(Integer)` | 0 | **4611686018427387904** | 4611686018427387904 |
| `Sqr(i)`, `i = 65536` | 0 | **4294967296** | 4294967296 |
| `i * i`, `i = 65536` | 4294967296 | same | same |
| `-i`, `i = Low(Integer)` | 2147483648 | same | same |
| `Abs(sm)`, `sm = Low(SmallInt)` | 32768 | same | same |
| `Abs(q)`, `q = Low(Int64)` | -9223372036854775808 | same | same |

Read the table as a whole and FPC's own rule is visibly inconsistent, which is
why the default stays ours:

- `i * i` **widens** to Int64, so 65536*65536 is 4294967296 — but `Sqr(i)`,
  which means the same thing, keeps Integer and answers **0**. Nobody writes
  `Sqr(65536)` intending zero.
- `-i` widens (that is the same unary-minus promotion the shift ticket's
  row 1 turns on), but `Abs(i)` does not — so `-Low(Integer)` and
  `Abs(Low(Integer))` differ in sign in FPC and agree in pxx.
- The narrower and wider types are not affected either way: `Abs(SmallInt)`
  promotes to Integer in both, `Abs(Int64)` wraps in both. Only the exactly
  32-bit case diverges, which is the same shape as rows 2/3/9 of the shift
  table.

So this is the shift decision's rule applied to two more operators, and here it
is also the arithmetically correct answer rather than merely the convenient one.
Not a bug — do not "fix" it toward FPC in the default dialect.

**`--strict-fpc` does NOT yet cover these two.** That gap mirrors the one
`bug-a-strict-fpc-does-not-reproduce-fpc-shift-widths` closed for shifts, and is
filed as `compat-pascal-strict-fpc-abs-and-sqr-widths`. Until it lands, a port
of FPC bit-twiddling can pin shift width with the flag but not `Abs`/`Sqr`.

## `High`/`Low` of a SHORTSTRING expression

`sh: string[10]`, `s: AnsiString`, measured against fpc 3.2.2:

| operand | fpc `-Mobjfpc` | fpc `-Mdelphi` | pxx |
| --- | --- | --- | --- |
| `'abc'` | 0 .. 2 | 0 .. 2 | same |
| `('ab')` | 0 .. 1 | 0 .. 1 | same |
| `sh` | 0 .. 10 | 0 .. 10 | same |
| `s` | 1 .. 3 | 1 .. 3 | same |
| `'ab' + s` | 1 .. 5 | 1 .. 5 | same |
| `s + 'x'` | 1 .. 4 | 1 .. 4 | same |
| **`sh + 'x'`** | **0 .. 255** | 0 .. 255 | **1 .. 3** |
| **`'ab' + 'cd'`** | **0 .. 255** | **1 .. 4** | 1 .. 4 |

Only the last two rows differ, and both are the same fact: in FPC a
concatenation whose operands are all short/frozen strings is itself a
SHORTSTRING expression, so its bounds are the DEFAULT CAPACITY — 0 .. 255 —
rather than anything to do with the value. pxx has no shortstring-expression
type: `SizeOf(sh)` is 8 here and 11 in FPC, so the whole capacity model differs,
and matching those two cells means changing the string model rather than the
intrinsic.

Two reasons the default stays ours:

- FPC is not self-consistent about it. `'ab' + 'cd'` is 0 .. 255 in objfpc mode
  and 1 .. 4 in Delphi mode — and 1 .. 4 is pxx's answer, so pxx already agrees
  with one of FPC's own two answers.
- 0 .. 255 is not a usable bound for the value: `for i := Low(sh + 'x') to
  High(sh + 'x')` walks 254 characters that are not there. No correct program
  depends on it.

Recorded while closing the `High`/`Low` operand row of
`bug-p-every-compile-time-intrinsic-hand-rolls-its-own-operand-parser`;
`test/test_high_low_operand_shapes.pas` pins every row that DOES agree and says
in its header which two do not.

## A generic's own type-parameter name, reused as a member/param/local name

**pxx accepts; FPC rejects.** Recorded 2026-08-27 while fixing
`bug-p-a-nested-type-may-name-a-field-after-an-enclosing-type-parameter`.

Inside `generic TG<T> = class ... end`, the type parameter `T` is in the class's
scope, so FPC 3.2.2 treats a field, parameter, local or method also named `T` as
a redeclaration:

| shape | FPC 3.2.2 | pxx |
| --- | --- | --- |
| `generic TG<T> = class private t: T; ... end` | `Duplicate identifier "T"` | compiles |
| `procedure TG.S(const t: T)` | `Duplicate identifier "T"` | compiles |
| `procedure TG.S(...); var t: T;` | `Duplicate identifier "T"` | compiles |
| `generic TG<T> = class procedure T(...); end` | `overloaded identifier "T" isn't a function` | compiles |
| **`public type TRec = record t: T; end`** | **accepted** | **accepted** (this one was the bug) |

The last row is the one that matters and is NOT a divergence: a nested type is
its own scope, so `record t: T` is legal in both, and it is
`TDictionary<K,V>.TPair`'s exact shape. pxx used to reject it, which is what the
fix addressed.

The first four rows fall out of that fix rather than being chosen: the
substitution pass now recognises name positions, so it stops corrupting them,
and there is no scope model at that layer to tell "nested type's scope" from
"the class's own scope" and refuse only the latter. That is the
**not-a-defect** direction of the compat table in CLAUDE.md — we accept a form
FPC rejects — and the alternative was not "reject like FPC" but the previous
behaviour, which SILENTLY MISCOMPILED all five rows.

No correct FPC program can observe the difference: every program in rows 1-4 is
one FPC refuses to build, so nothing portable depends on pxx refusing it too.
Worth a diagnostic some day if a scope model appears at that layer; not worth
inventing one for this.

## `SysUtils.Error(TRuntimeError)` raises where FPC halts

*Recorded 2026-08-28, with
[[feature-sysutils-delphi-exception-api-gaps-found-by-rtl-generics]].*

FPC's `Error(reRangeError)` produces an **uncatchable** runtime error 201 and
terminates. Ours raises a catchable exception mapped to the nearest SysUtils
class (`ERangeError` here), so a surrounding `try..except` sees it.

**Deliberate, on two grounds.** It is inside the "error handling stays ours"
ruling — a strict flag governs how source is compiled, not how a program dies.
And it matches our own runtime, which is the consistency that matters more than
parity here: pxx already surfaces a division by zero as a catchable
`EDivByZero` and a malformed `StrToInt` as `EConvertError`, so a halting
`Error` would be the odd one out in its own RTL.

**The cost, stated so it is not rediscovered as a surprise:** a catchable
`Error` can be swallowed. Every call site that motivated this — 7 in
`generics.defaults.pas` — is the `else` arm of a `case` over a type kind, i.e.
"this cannot happen"; if one ever does happen inside a `try..except`, FPC would
stop the program and we would continue. If that bites, the fix is to halt, and
this entry is the record that the choice was made knowingly rather than by
default.

**The symptom to look for**, since an entry you must already suspect to go read
is not findable: *if a vendored consumer appears to CONTINUE PAST AN IMPOSSIBLE
STATE — an `else` arm that says "cannot happen" is reached and the program keeps
running, or a `try..except` reports an error it has no business seeing — suspect
a swallowed `Error`.* Under FPC the program would have stopped there. Grep the
consumer for `Error(re` and check whether any caller wraps it in a handler.

Verified against FPC 3.2.2: `test/lib_sysutils_delphi_exceptions.pas` runs
identically under both for its first 18 rows and diverges at exactly this point.

## `VarType` of an integer LITERAL is `varInteger`, where FPC says `varShortInt`

`lib/rtl/variants.pas` now speaks FPC's public `varXxx` numbering (the internal
`VT_*` tags stay private — the same facade seam as `decide-rtti-kind-numbering`).
Measured against fpc 3.2.2, **11 of the 12 rows agree exactly**. One does not:

```pascal
var v: Variant; i: Integer;
v := 1;         { pxx: varInteger (3)   FPC: varShortInt (16) }
i := 1; v := i; { pxx: varInteger (3)   FPC: varInteger  (3)  — agree }
```

**FPC narrows an integer LITERAL to the smallest type that holds it**, so the
variant's reported type depends on the literal's magnitude: `v := 1` is
`varShortInt`, and a larger literal would report something else again. pxx has
one integer tag and does not narrow, so it reports `varInteger` throughout.

**Deliberate, and the cheap side of the trade.** Matching FPC here means
narrowing integer literals at the assignment — a language change with
consequences far beyond `VarType`, to buy parity on a value that changes with
the *literal* rather than with the program's meaning. The line that real code
writes, `v := someInteger`, agrees with FPC exactly; it is the bare-literal form
that differs, and it differs in the direction of being more predictable.

**The symptom to look for:** *code that switches on `VarType` and has a separate
`varShortInt` / `varByte` / `varSmallint` arm will take its `varInteger` arm
instead under pxx.* That is only a bug if the arms disagree about more than
width. FPC-portable code that wants "is this an integer at all" should use
`VarIsNumeric`, or test against the set, not a single sized code.

**Not a divergence, despite looking like one:** a `Char` and a one-character
string both report `varString` (256). FPC has no char variant at all — `v := c`
with `c: Char` reports 256 there too — so this is parity. pxx reaches it by
folding its private `VT_CHAR` tag onto `varString` at the seam, which is also
what stopped `VarType(v) = varString` from being false for `'x'`.

Verified against FPC 3.2.2: `test/lib_variants_vartype_codes.pas` asserts every
row above, and marks the divergent one in place next to the row that agrees.
