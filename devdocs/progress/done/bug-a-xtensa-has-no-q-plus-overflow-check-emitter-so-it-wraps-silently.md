---
slug: bug-a-xtensa-has-no-q-plus-overflow-check-emitter-so-it-wraps-silently
track: A+S
prio: 30
type: bug
blocked-by: []
status: done
found: 2026-09-01
found-by: frankA
owner: frankA
summary: "FIXED 2026-09-01, and the ticket's own diagnosis was wrong in a useful way. The check does NOT belong in a binop emitter: Pascal widens Q-tagged arithmetic to Int64 in the frontend, so `Integer + Integer` is a 64-bit binop that cannot overflow and the wrap happens at the NARROWING STORE. Proved with a canary Error() in a 32-bit checked-add arm that no {$Q+} program ever reached. Implemented at IR_STORE_SYM; xtensa now traps RE 215 on Integer/Byte/ShortInt/Word overflow and on 32-bit mul, matching riscv32 exactly. Test test_qplus_narrowing_store.pas, 5 trap shapes + a must-not-trap control, six targets. ORIGINAL: xtensa is the ONE backend with no {$Q+} overflow-check emitter: it is the only target absent from the `FindProc('PXXOverflow')` grep. So `{$Q+}` compiles clean there and SILENTLY WRAPS -- 2147483647+1 stores -2147483648 where the other five raise Runtime error 215. Quieter than the arm32/riscv32 bug it was found beside, which at least failed loudly at compile time. Same shape as the still-open xtensa div-by-zero gap; they are one job."
---

# xtensa has no `{$Q+}` overflow-check emitter, so it wraps silently

Found 2026-09-01 while fixing
[[bug-a-q-plus-overflow-checking-has-no-runtime-helper-on-arm32-and-riscv32]],
which is a different defect with the same trigger. That one was a switch LEAK
and is fixed. This one is a MISSING FEATURE and is not.

## The fact

```pascal
program qC; {$Q+}
var a, b, c: Integer;
begin a := 2147483647; b := 1; WriteLn('before'); c := a + b; WriteLn('after c=', c); end.
```

| target | result |
| --- | --- |
| x86-64, i386, aarch64, arm32, riscv32 | `Runtime error 215 (arithmetic overflow)` |
| **xtensa** | `after c=-2147483648` — **no trap** |

## Why it is the quiet one

The arm32/riscv32 defect it was found beside **failed to compile**. This one
compiles clean and produces a wrong value, which is the failure mode CLAUDE.md
names as the expensive kind. Anyone checking "does `{$Q+}` work on my target"
by whether it builds gets a yes.

## The cause is not subtle — it is simply absent

```
$ grep -rn "'PXXOverflow'" compiler/*.inc
ir_codegen_arm32.inc  ir_codegen_riscv32.inc  ir_codegen386.inc (x2)
ir_codegen.inc (x2)   ir_codegen_aarch64.inc
```

Six sites, five backends, **no xtensa**. There is no `EmitOvfCheckXtensa`, so
`IRIVal[node] = 1` (the `{$Q+}` marker on the binop) has nothing to dispatch to
and is dropped.

## This is the same job as the div-by-zero gap

[[bug-a-the-div-by-zero-check-is-still-missing-on-xtensa]] is the identical
shape — the last target without a pre-divide zero check, left out for the same
reasons — and its write-up already lists the four things that make xtensa a
genuinely different job rather than a sixth copy of the edit: it cannot be RUN
under the bare profile, its branches carry only an 8-bit displacement, the
windowed ABI rotates the register window on a call, and there are two shapes
depending on `XtensaSoftDivide`. All four apply here. **Take them together.**

The trap call itself is the easy half: `PXXOverflow` takes no arguments and
never returns, and hosted xtensa CAN be run (`qemu-xtensa`, `--platform=posix`),
which is how the table above was measured — so unlike the div-zero ticket's
bare-profile problem, this one has a working oracle today.


---

## Fixed 2026-09-01 — and this ticket pointed at the wrong place

I filed this yesterday saying xtensa "is the only target absent from the
`FindProc('PXXOverflow')` grep, so there is no `EmitOvfCheckXtensa` to dispatch
to". The grep was right and the conclusion did not follow.

**Pascal widens Q-tagged arithmetic to Int64 in the frontend.** The IR for
`a + b` with two Integers is identical on xtensa and riscv32:

```
2: binop a=0 b=1 c=70 ival=1 tk=13        tk=13 is tyInt64
```

So the add is a 64-bit operation that cannot overflow, and the wrap happens when
that value is stored into a 4-byte slot. **The check belongs at the narrowing
store**, which is where x86-64 (`EmitOvfCheckNarrowX64`), riscv32 and arm32 all
put it. Their binop-level `{$Q+}` arms exist for genuinely 32-bit ops and are
not what makes `Integer` arithmetic trap.

### The canary, because "I think this arm is unreachable" is not a measurement

I had already written checked add/sub arms into the xtensa **binop** emitter and
they did nothing. Rather than reason about why, I planted
`Error('CANARY: ... IS reachable')` inside one and recompiled every `{$Q+}`
program to hand:

```
q6: not reached   q7: not reached   qC: not reached   qA: not reached
qplus: not reached   test_qplus_survives_ambient_units: not reached
```

Unreachable for every program that could exercise it. Those arms were **removed
rather than shipped** — untestable code that looks like a fix is worse than the
gap, because the next person greps, finds a checked-add arm, and concludes the
target is covered. The comment left in the binop emitter says so explicitly.

### What landed

`EmitOvfTrapXtensa(condR, s, t)` — caller states the SKIP condition, so each
site can build its own predicate (xtensa has no flags and no `slt`). Then the
narrowing check in `IR_STORE_SYM`: re-extend the value to the destination width,
compare with the full a2:a3 pair, trap on any difference. Same branch-patch and
register-lifetime discipline as the div-zero check landed an hour earlier.

### Verified

`test/test_qplus_narrowing_store.pas` — shape by argument count, six targets.

| shape | before (12907805ca46) | after (070b0d10db75) |
| --- | --- | --- |
| Integer add | `-2147483648` | RE 215 |
| Integer sub | `2147483647` | RE 215 |
| Byte | `144` | RE 215 |
| ShortInt | `-56` | RE 215 |
| Word | `54464` | RE 215 |
| **control** | `ok k=8 b=6` | `ok k=8 b=6` |

All five discriminate. **The control is load-bearing**: a check that traps
unconditionally passes the first five rows and fails only this one.

32-bit `*` overflow is covered too, for free — it narrows through the same
store, so the mul-high reconstruction this ticket worried about was never
needed.

### Residual, and it is NOT xtensa-specific

A **64-bit × 64-bit product that overflows Int64** still wraps silently on
xtensa AND riscv32 (x86-64 catches it). Pre-existing, shared, and now filed
separately as
[[bug-a-64-bit-multiply-overflow-is-unchecked-under-q-plus-on-riscv32-and-xtensa]].
xtensa is at parity with its closest sibling, which was the bar.

## Log
- 2026-09-01 — resolved, commit PENDING-COMMIT.
