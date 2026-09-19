---
track: A
prio: 60
type: bug
status: done
found: 2026-09-19
found-by: frankB
owner: frankB
summary: "FIXED 2026-09-19. `printf(\"%llu\", 18446744073709551615ULL)` printed one character -- `/`, which is '0' minus one, a digit loop running negative -- on wasm32 and matched gcc on the other six targets. Cause: `WasmBinopWidth` derived signedness as `TypeSigned(a) or TypeSigned(b)`, signed if EITHER operand is signed, which is viral: __crtl_utoa's `v % (unsigned long)base` lowers the cast as a mask against a tyInt64 constant, so a provably non-negative zero-extension reported itself signed and the modulo chose `rem_s`. `wasm2wat` over a hosted module contains no `i64.div_u` or `i64.rem_u` anywhere. THE FIRST REPAIR BROKE THE MIRROR AND THE PROBE CAUGHT IT: a width-based rule letting an unsigned operand win outright fixed %llu and turned `n / (long long)q` -- an explicit cast TO signed -- unsigned, measured as wasm32=124 against 116 everywhere else; `and` instead of `or` passes both and is wrong for a third shape, since a narrow unsigned promotes to signed `int` in C. The fix asks the IR: a non-compare's own recorded `IRTk` decides at the operation's width. Compares are excluded EXPLICITLY -- their recorded type is tyBoolean, which is not signed, so the same fix without that exclusion turns every signed `<` into `lt_u`. Guard: tools/c_int_signedness_every_target.sh, thirteen shapes on all seven targets against gcc, mask PRINTED not returned. Fixed and guarded in commit 9270c1b41."
---

# wasm32 picks signed division for an unsigned 64-bit value

Found 2026-09-19 (frankB) while closing
[[bug-c-hosted-c-on-wasm32-needs-environ-and-va-arg-so-stdio-programs-still-refuse]]
— the first hosted C program that could actually print on wasm32 printed its
integers wrong, and only above 2^63.

## Measured

`compiler/pascal26` at `c6c87fa69d8c`, `test/c_wasm32_hosted_stdio.c` diffed
whole against the gcc oracle:

| value | gcc / six targets | wasm32 before |
| --- | --- | --- |
| `%llu` of 2^64−1 | `18446744073709551615` | `/` |
| `%llu` of 2^63−1 | `9223372036854775807` | correct |
| `%d`, `%u`, `%x`, floats | match | match |

**The row below 2^63 was correct the whole time**, which is the reason nothing
caught this earlier: a wrong SIGNED answer on non-negative data equals the
right answer until the top bit is set. There is no wasm32 C test corpus row
that prints an integer above 2^63.

## Cause

`WasmBinopWidth` in `compiler/ir_codegen_wasm32.inc` decided one `sgn` for the
whole operation:

```pascal
sgn := TypeSigned(tkA) or TypeSigned(tkB);
```

`__crtl_utoa` divides by its base:

```c
d = v % (unsigned long)base;   v = v / (unsigned long)base;
```

The cast lowers to a mask against a `tyInt64` constant, so `tkB` is signed.
`v` is `unsigned long long`. Signed-if-either then selects `i64.rem_s` for a
zero-extended value whose top bit is set — the remainder comes out negative,
`'0' + d` walks below `'0'`, and the loop emits one character and stops.

`wasm2wat` over a hosted module: **zero occurrences of `i64.div_u` or
`i64.rem_u`**, which is the shape of the bug rather than a symptom of it — the
unsigned opcodes were unreachable by construction, not merely unused.

## The repair that was wrong, and why it is worth keeping in the record

First attempt: at the operation's width, an UNSIGNED operand wins.

```pascal
if (not TypeSigned(tkA)) and (TypeSlotSize(tkA) = wantSz) then sgn := False;
```

`%llu` went correct. `test/c_integer_signedness.c` row 8 —
`n / (long long)q`, an explicit cast TO signed — went **unsigned**: measured
wasm32 = 124, six targets = 116. The cast node still carries the source
expression's unsigned type, so the operand check reads the wrong thing.

`and` in place of `or` passes both of those and is wrong for a third: a narrow
unsigned (`unsigned char`, `unsigned short`) promotes to signed `int` in C, so
`-7 / (int)w` must be signed and `and` makes it unsigned — four billion.

**No rule over the operands can be right**, because the frontend has already
applied C's conversions and recorded the answer. Re-deriving one is a second
opinion that can only disagree.

## The fix

Let the node's own recorded type decide, at the operation's width:

```pascal
tkN := IntToTypeKind(IRTk[node]);
if (not WasmIsCompare(WasmBinopOp(node)))
   and (TypeIsOrdinal(tkN) or TypeIsPointerSized(tkN))
   and (TypeSlotSize(tkN) = wantSz) then
  sgn := TypeSigned(tkN);
```

**The compare exclusion is load-bearing and is not defensive coding.** A
compare's recorded `IRTk` is `tyBoolean`; `TypeSigned(tyBoolean)` is False, so
the same fix without that clause turns every signed `<`, `<=`, `>`, `>=` into
its unsigned opcode. That was caught by row 256 of the subject, which exists
for exactly this and asserts a comparison of two signed values, not a division.

## Guard

`tools/c_int_signedness_every_target.sh` — thirteen shapes over x86_64, i386,
arm32, riscv32, aarch64, xtensa and wasm32, gcc as the oracle, the whole
printed line diffed so no expected value is written down twice. No
admitted-refusal branch: every target builds plain integer arithmetic plus one
`printf` today, so a target that stops is a regression.

The subject **prints** its failure mask rather than returning it. The first
draft returned `bad ? 100000 + bad : 42`, and `100000 + 138` is 42 mod 256 —
rows 2, 8 and 128 failing together would have exited with the all-pass answer.

## The rule under it

**Where a frontend has already applied a language's conversion rules and
recorded the result type, ask the IR. Re-deriving the same property from the
operands is a second opinion that can only disagree** — it is right wherever
it agrees and silently wrong wherever it does not, and the disagreement shows
up on the values nobody tests. Banked in `devdocs/dev/debugging-playbook.md`
("ASK THE IR WHAT THE FRONTEND RECORDED"). **Not promoted to CLAUDE.md**: one
subsystem. The promotion test is a second independent one, and frankB and
frankuser agreed on 2026-09-19 to hold it in the playbook until that arrives
rather than argue it up on how good it reads.
