---
summary: "x86-64 only: assigning a QWord above 2^63 to a Double yields ~half the value (QWord max -> 9223372036854775809). The Int() intrinsic path is correct; the ASSIGNMENT conversion is not"
type: bug
track: A
prio: 55
---

# x86-64: `d := q` for a QWord above 2^63 produces half the value

- **Type:** bug — Track A (x86-64 backend, int→float assignment conversion)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** Track A+C, cross-checking the Pascal side while fixing
  `bug-c-int64-to-double-cast-truncates-on-32bit`. **Pre-existing** — reproduced
  identically on `stable_linux_amd64/default/pinned`, so it is not a regression
  from that fix.

## Symptom

```pascal
var q: QWord; d: Double;
begin q := 18446744073709551615; d := q; writeln(d:0:1); end.
```

| | |
| --- | --- |
| FPC | `18446744073709552000.0` |
| pxx x86-64 | **`9223372036854775809.0`** |
| pxx i386 / arm32 / riscv32 | `18446744073709551616.0` (correct value — see note) |
| pxx aarch64 | see `bug-a-aarch64-large-double-decimal-formatting` |

The 32-bit targets' `...551616.0` and FPC's `...552000.0` are the SAME double
printed to different precision — a formatting difference, deliberately not
chased. x86-64's answer is a different NUMBER (≈2^63), and that is the bug.

## Why x86-64 specifically

`cvtsi2sd` is signed and x86-64 has no unsigned-64→double instruction, so the
unsigned case needs the halve/convert/double sequence. The **`Int()` intrinsic**
path (`specialId = 206` in `ir_codegen.inc`) got exactly that sequence in
`bug-c-int64-to-double-cast-truncates-on-32bit` and is now correct. The
**assignment** conversion `d := q` is a *different site* and still emits a bare
signed convert. Same fix, different place — see the 206 branch for the sequence
to copy.

## Repro

```
printf 'var q: QWord; d: Double;\nbegin q := 18446744073709551615; d := q; writeln(d:0:1); end.\n' > /tmp/q.pas
./compiler/pascal26 /tmp/q.pas /tmp/q_p && /tmp/q_p     # 9223372036854775809.0
```

## Note for whoever takes it

This is the third site in the same family (`Int()` intrinsic, C `(double)` cast,
Pascal assignment), which is the argument for the structural ticket
`feature-a-unify-32bit-call-argument-marshalling` makes about call marshalling:
the int→float conversion ladder is likewise written out once per *site* instead
of once. Consider a shared `EmitIntToFloat(dstReg, srcTk)` per backend — i386 and
arm32 already have one (`EmitIntToXmm386`, `EmitIntToD0Arm32Tk`) and the bug in
both cases was a site that did not call it.
