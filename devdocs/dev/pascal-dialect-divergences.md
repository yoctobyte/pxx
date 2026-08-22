# Pascal dialect divergences from FPC — deliberate, decided, do not re-file

The sibling of `nilpy-semantics-divergences.md`, for Track P / Track A.

**Read this before filing a "pxx disagrees with FPC" ticket.** Everything on this
page is a divergence the owner has *decided*, with the ticket that decided it.
A differential run rediscovers these every time — that is what
`bug-t-fpc-probe-reports-the-deliberate-shl-deviation-as-new` is about — and each
rediscovery costs a session an hour before it finds the decision.

The rule for adding a row: it belongs here only once a `decide-*` ticket has been
**resolved**. An unexplained disagreement is a bug ticket, not a row here.

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
