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
