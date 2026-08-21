---
track: A
prio: 40
type: bug
blocked-by: []
summary: "AIntToStr(n) returns the EMPTY STRING for any n < 0 — `while n > 0` never enters. It is the compiler's own IntToStr, used in ~40 diagnostics across the Pascal, NilPy and C frontends and the C preprocessor, so a negative value silently drops out of an error message rather than being reported wrong-looking."
status: done
owner: claude-A
---

# AIntToStr returns '' for negative numbers

```pascal
function AIntToStr(n: Integer): AnsiString;
begin
  rev := '';
  if n = 0 then AppendChar(rev, '0')
  else
    while n > 0 do            { <-- n < 0 never enters }
    ...
```

`AIntToStr(0)` = `'0'`. `AIntToStr(-5)` = `''`. No minus sign, no digits, no error.

Found while moving the function out of `aparser.inc` into the new shared
`compiler/util.inc` ([[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]]).
Moved **verbatim**, defect included, so that the move stayed provably mechanical
and the self-host binary stayed byte-identical; fixing it is this ticket.

## Why it has survived

Every current caller passes a count, an index, a parameter number or a version —
quantities that are non-negative in practice. So the failure mode is not a wrong
number, it is a **diagnostic with a hole in it**: `'takes at most  arguments'`
rather than `'takes at most -1 arguments'`. A message missing a number reads as a
formatting slip, not as a value bug, which is precisely why nobody chased it.

That also makes it the cheap kind of latent bug to fix now rather than the day
something starts passing a negative sentinel: several call sites pass
`Procs[mpi].ParamCount - 1`, which is `-1` when `ParamCount` is 0.

## Fix

Handle the sign, then the magnitude. Watch `Low(Integer)`, whose negation
overflows — the usual guard is to build digits from the negative side, or to
special-case it.

Gate: the per-fix loop. Add a test covering `-1`, `0`, `Low(Integer)`, and one
ordinary negative.

---

## Resolution (2026-08-21)

### The fix

Accumulate the digits on the **negative** side, and negate only a positive input
on the way in:

```pascal
  neg := n < 0;
  if not neg then n := -n;
  ...
  while n < 0 do
  begin
    AppendChar(rev, Chr(Ord('0') - (n mod 10)));
    n := n div 10;
  end;
  if neg then AppendChar(rev, '-');
```

The obvious fix — remember the sign, negate, reuse the existing loop — is wrong
for exactly one input, and it is the one the ticket told us to watch:
`Low(Integer)` has no positive representation, so `n := -n` leaves it
**unchanged** and `while n > 0` still never enters. Going the other way there is
no asymmetry at all: `n div 10` truncates toward zero, so the magnitude only ever
shrinks, and the digit is `-(n mod 10)` because Pascal's `mod` takes the sign of
the dividend. The `'-'` is appended LAST because the buffer is built backwards
and reversed at the end, which lands the sign in front.

`Integer` here is 32-bit (measured: `SizeOf(Integer)` = 4, `Low` =
-2147483648), and `Syms[].ConstVal` is `Int64`, so the call site used by the test
truncates on the way in — which is how the test can hand the function exactly
`Low(Integer)`.

### Testing it took a prop, and that is the interesting part

The ticket asked for a test over -1, 0, `Low(Integer)` and an ordinary negative.
There is no call site that can pass a negative — that is the ticket's own
explanation for why the bug survived — so a straightforward test would have had
to re-implement the algorithm and would then test the copy, not the function.

The one diagnostic a user can drive to a negative through supported CLI surface
is the **RTL layout guard** (`pasparser_proc.inc`): it prints the linked
builtinheap's `PXX_RTL_LAYOUT_VERSION` verbatim when it differs from the
compiler's. `-Fu` is searched before the compiler's own RTL directory —
`compiler.pas` appends the default LAST on purpose, so a user override wins — so
`test/aintostr_units/builtinheap.pas` is an impostor unit that declares whichever
number a `-d` define selects. `Error()` halts at the guard, which is the very next
statement after the unit body is parsed, so the stub is never linked and its
emptiness never matters.

Four values, one Makefile loop, each a different way for a sign fix to be wrong:

| value | what it catches |
| --- | --- |
| `-1` | the single-digit boundary |
| `-12345` | ordinary multi-digit |
| `0` | the separate branch — the digit loop cannot emit `'0'`, so a rewrite is most likely to drop this one |
| `-2147483648` | `Low(Integer)` — a negate-first fix **hangs** here while passing the other three |

Plus the same program compiled with **no** `-Fu`, which must build and print
`ok` — so a failure above is the impostor doing its job rather than something
about the carrier program.

**Negative control:** the pinned (pre-fix) compiler on the same input prints

```
... but the builtinheap it is linking implements version .
```

— the hole, exactly as reported. The test fails on a pre-fix binary, so it is not
vacuous.

No cross-target rows: `AIntToStr` runs *in the compiler*, on the host, so the
answer cannot vary by `--target`.

### Gate

`make compiler/pascal26` converged in 1 round; the four diagnostic cases and the
positive control run green; `gate.sh quick` GREEN.

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
