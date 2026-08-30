---
track: C
prio: 45
type: bug
status: done
blocked-by: []
owner: frankC
summary: "`(double)someFloat` was an AN_PTR_CAST retag: the node claimed tyDouble while the value was still four single bytes. Harmless on x86-64/aarch64 (their value model already carries a single as double bits in a register), wrong on arm32/riscv32/i386 through exactly ONE consumer -- a variadic argument, the only one that trusts the tag without converting on the way past. Renamed from bug-c-a-float-parameter-and-return-are-wrong-in-pure-c-on-three-targets, which named the wrong mechanism."
---

# A `(double)` cast of a `float` was a retag, not a conversion

**Renamed.** This was filed as *"a float parameter and return are wrong in pure C
on three targets"* off a single failing row. Both halves of that title are false:
the parameter is fine, the return is fine. frankA caught it first from its own
control, and varying the shape confirmed it.

## The eight-shape matrix that found it

Compiler `8a42f93ffe74`, all against gcc. A `float` value reaching a `double`:

| # | shape | x86-64 / aarch64 | arm32 / riscv32 / i386 |
| --- | --- | --- | --- |
| 1 | `double a = (double)r;` then print | ok | ok |
| 2 | `double b = r;` then print | ok | ok |
| 3 | `as_int((double)r)` — prototyped param | ok | ok |
| 4 | `as_int(r)` — prototyped, implicit | ok | ok |
| 5 | `printf("%.2f", (double)r)` | ok | **0.00** |
| 6 | `printf("%.2f", r)` — implicit | ok | ok |
| 7 | `printf("%.2f", (double)r * 2.0)` | ok | ok |
| 8 | `printf("%.2f", id_d((double)r))` | ok | ok |

**One shape out of eight.** Everything else converts on the way past — a store,
a prototyped parameter's conversion, an arithmetic operand — so the lie never
surfaces. A variadic argument is the one consumer that trusts the node's tag.

Row 6 is the one that names the mechanism: the **implicit** form was always
right, because default argument promotion sees a `tySingle` node and widens it.
**The explicit cast HID the single from that promotion** — two paths to "this
argument is a double", one of which lies.

## Root cause

`ParseCUnary`'s cast path routes float→float through `AN_PTR_CAST` with
`ASTIVal := -1`, the "numeric / pointer reinterpret-retag", then stamps
`ASTTk[node] := Ord(castTk)`. No value is produced; only the label changes.

It survived because of the value model. x86-64 and aarch64 carry a single as
double bits in a register, so relabelling it is genuinely free. On arm32,
riscv32 and i386 a single occupies four raw bytes in its slot, and the variadic
push then sends four bytes where the callee reads eight.

The narrowing direction was already correct — `(float)someDouble` round-trips
through an anonymous `tySingle` temp, added by
[[bug-c-cast-to-float-in-value-position-does-not-round-to-single]]. **Only the
widening mirror was missing**, which is the shape
`devdocs/dev/normalise-dont-special-case.md` warns about: fix one arm of a
double case, grep for its sibling.

## Fix

The mirror, in `compiler/cparser.inc`: `(double)someSingle` at `castDepth = 0`
round-trips through an anonymous `tyDouble` temp, so the assignment store
performs the real widening on every backend. The variadic path then receives a
genuine double and needs to know nothing about casts — **stop it lying rather
than teach every consumer to distrust the tag.**

## Verified

- The eight-shape matrix: **green on all five targets**, matching gcc.
- Narrowing intact and now composing with the widening: `(double)(float)16777217`
  is `16777216`, the doubled chain `(double)(float)(double)(float)d` likewise,
  `(double)0.1f` prints `0.100000001`, all byte-identical to gcc on all five.
- `test/c_abi_pure_c_control.c` goes from red on arm32/riscv32/i386 to **PASS on
  all five**, so its cross rows are now ASSERTED by `make test-c-abi-cross`
  rather than skipped — it becomes a real cross-target regression gate for
  [[bug-a-the-shared-cdecl-spill-arm-cannot-yet-do-the-job-it-would-be-given]].
- `tools/gate.sh quick` GREEN; self-host fixedpoint `12fdd5612512`.

## What this cost, and the cheap lesson

The control I wrote for the calling-convention ticket ran every value through
variadic `printf`, so its float rows were reading THIS defect rather than the
convention. frankA's control routed through a prototyped helper and did not see
it. **Neither control was lying — they exercised different conversions, and only
one reached the broken shape.** Two controls disagreeing is what located the
mechanism; one control agreeing with itself would have buried it.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
