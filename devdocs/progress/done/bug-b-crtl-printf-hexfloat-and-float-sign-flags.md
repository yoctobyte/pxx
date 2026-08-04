---
summary: "printf %a SEGFAULTED every 32-bit target (it fell to the unknown-conversion path and did not consume the double); +/space were ignored on all float conversions; NAN was negative; strtod could not parse hex floats at all"
type: bug
track: B
prio: 65
---

# `printf("%a")` crashed on every 32-bit target, and three things around it

- **Type:** bug — Track B (`lib/crtl`), tag `compat`
- **Status:** done
- **Opened:** 2026-08-05

## The crash, which is the part that matters

`%a` was not implemented, so it fell to printf's unknown-conversion path. That
path prints the spec verbatim **and does not consume the argument**. On x86-64
this was invisible: doubles arrive in their own register save area, so a
following `%d`/`%s` still read the right slots. On **i386, arm32 and riscv32**,
where varargs walk the stack, the unconsumed double shifted everything after it:

    printf("[%a] %s\n", 0.5, "tail");     ->  SIGSEGV on a garbage pointer

So this was a crash, not a missing format. Implemented properly, with the rules
read off a gcc build rather than from the standard's prose — several are not
what you would guess:

- the exponent is binary, always signed, never zero-padded (`p+0`)
- zero is `0x0p+0`, not `0x0p-1023`
- a subnormal keeps a `0` leading digit and exponent `-1022`, **not**
  renormalised: `0x0.0000000000001p-1022`
- with no precision, trailing zero nibbles vanish entirely: `0x1p+0`
- with a precision, rounding carries **into** the leading digit and stays there:
  `%.0a` of 0.1 is `0x2p-4`, not `0x1p-3`

## Three more, found alongside

- **`+` and ` ` were ignored on every float conversion.** `%+f` printed
  `1.500000` where every other libc prints `+1.500000`; same for `%e`, `%g`.
  They worked for `%d`, which is why it read as correct.
- **`NAN` was `(0.0 / 0.0)`**, which on x86 produces a NaN with the **sign bit
  set**, so `printf("%f", NAN)` gave `-nan`. Now an explicit `0x7ff8…` bit
  pattern, so it does not depend on what the hardware returns for an invalid
  operation.
- **`strtod` could not parse hex floats at all** — it stopped at the `x`,
  returned 0 and left `"x1.8p+1"`. `atof` and `scanf`'s `%f`/`%a` go through it,
  so they were wrong the same way. Without this the library could **print** a
  double exactly and not **read it back**, which is the one thing the format
  exists for.

Hex parsing accumulates in binary rather than scaling doubles — hex digits are
exact powers of two, so the only rounding is the final one, with a sticky bit
ORed into bit 0 so the conversion's round-to-nearest-even lands where glibc
does. All 23 edge cases match gcc, including both 53-bit ties, `0x` with no
digits (which is the decimal `0` with `"x"` left over) and an incomplete `p`.

### One self-inflicted trap worth recording

The first scaling helper stepped the exponent in chunks of `2^1023` via the
decimal literal `8.98846567431158e307`. That made the result depend on the
literal being correctly rounded, and it was off by enough to flush
`0x1p-1074` — the smallest subnormal — to **zero**. It now uses only `2.0` and
`0.5`, which are exact, and reaches `2^-1074` precisely. (The literal issue is
its own known ticket: bug-a-float-literal-lexer-is-not-correctly-rounded.)

## Also fixed here: one definition instead of two

`read`, `write`, `close`, `lseek`, `pread` and `pwrite` were implemented in
`src/stdio.c` — reachable only by including `<stdio.h>`, while `<unistd.h>`
*declares* them. A program including just `<unistd.h>` got a glibc import.
They now live in `src/unistd.c`, and `src/stdio.c` includes `<unistd.h>` so the
stdio-only path still reaches them. (An earlier pass in this session had added
duplicates in `unistd.c`; the compiler silently accepted two definitions of
`write`, which is worth someone's attention on its own.)

The declaration probe now reports **353 of 361 implemented**, up from 343.

## Filed, not fixed

- **bug-c-int64-to-double-cast-truncates-on-32bit (URGENT)** — found because a
  correct `strtod` gave the wrong answer for `0x1.fffffffffffffp+1023` on i386
  and arm32. A C cast from a 64-bit integer to `double`/`float` truncates to the
  low 32 bits and sign-extends: `(double)9007199254740991` is `-1`. Pascal is
  correct on the same targets, so the 32-bit backends have a working path and
  the C cast is not using it.
- `strtod("0x1p-1074")` returns 0 on **riscv32** — soft-float flush-to-zero in
  the subnormal range. Noted, not chased: float rounding/representation work is
  explicitly not where the user wants time spent.

## Test

`test/cprintf_hexfloat.c`, diffed against a gcc build — no recorded
expectations. Covers the formatting rules, the flags, `NAN`'s sign, hex parsing
including every edge above, a **print-then-parse round trip** for seven values,
and — the actual regression guard — the mixed-argument lines that used to
segfault off x86-64. Identical to gcc on x86-64, i386, arm32, aarch64 and
riscv32, except the two rows named above, which are kept correct rather than
weakened to what the broken targets produce.

## Gate

`tools/gate.sh lib` GREEN; c-conformance 219 pass / 0 fail on x86-64 and i386.
