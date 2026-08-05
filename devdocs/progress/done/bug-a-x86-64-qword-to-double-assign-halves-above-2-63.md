---
summary: "x86-64 only: assigning a QWord above 2^63 to a Double yields ~half the value (QWord max -> 9223372036854775809). The Int() intrinsic path is correct; the ASSIGNMENT conversion is not"
type: bug
track: A
prio: 55
owner: claude-A
---

# x86-64: `d := q` for a QWord above 2^63 produces half the value

- **Type:** bug — Track A (x86-64 backend, int→float assignment conversion)
- **Status:** done
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

## Resolution (2026-08-05) — RE-TRIAGED: the conversion is correct; the WRITER is not

The ticket blames the assignment conversion `d := q`. Measured, that conversion
is **right**, and the ticket's own repro was reading the result through a broken
formatter.

```pascal
q := 18446744073709551615;
d := q;
writeln('sci   : ', d);       { pxx  1.8446744073709552E+019   FPC  1.8446744073709552E+019 }
writeln('fixed : ', d:0:1);   { pxx  9223372036854775809.0     FPC  18446744073709552000.0  }
e := 18446744073709551616.0;
writeln(Ord(d = e));          { 1 — the double is exactly the literal }
```

The scientific spelling of the SAME double matches FPC exactly, and `d = e`
against the literal `18446744073709551616.0` is TRUE. So the QWord→Double
conversion produces the correct bits; `EmitCvtSi2SdOrU64` already carries the
round-to-odd halve/convert/double fixup and the store path at
`ir_codegen.inc` calls it with the value node's type (`tyUInt64`, confirmed in
the IR dump). Nothing to fix there.

`9223372036854775809` is 2^63+1 — the **Int64 saturation value**, and it comes
from the fixed-decimals WRITER, not the conversion. Same number the aarch64
comparison produced for `writeln(1e20:0:2)` earlier today.

**This is a duplicate of `bug-a-x86-64-writeln-fixed-saturates-at-int64`**,
filed earlier today from the other direction. Closing as such; that ticket has
been enriched with this second repro.

### Why the original diagnosis was reasonable and still wrong

The ticket reasoned from "the `Int()` intrinsic path got the halve/convert/double
sequence and is now correct, so the assignment site must be the one still
missing it". That inference was sound — there really are three sites in that
family — but the assignment site had already been fixed (or never lacked it),
and the surviving `≈2^63` in the output came from a different layer entirely.
The lesson is the one in the debugging playbook: the printed value went through
TWO conversions, and only one of them was under suspicion. Comparing the same
double through a second spelling (`writeln(d)` vs `writeln(d:0:1)`) separated
them in one run.

### Its structural point still stands

The closing note argues the int→float ladder should be one
`EmitIntToFloat(dstReg, srcTk)` per backend rather than once per site. x86-64
already has exactly that (`EmitCvtSi2SdOrU64`) and it is why this site was
fine. The observation is right; it is simply already done on this target.

## Log
- 2026-08-05 — resolved, commit PENDING-COMMIT.
