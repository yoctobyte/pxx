---
track: A+S
prio: 45
type: bug
blocked-by: []
summary: "__pxxCpuHasHwRandom / __pxxHwRandom64 are excluded from the builtin-unit pull by an `and (not TargetIsEspClass)` guard in pasparser_prog.inc, so naming either on any ESP target is `error: undefined variable`. lib/rtl/random.pas calls them unconditionally -- by design, since its mandate is no per-arch branching -- so the random library is UNCOMPILABLE on xtensa and riscv32, the primary ESP targets. Blocks feature-random-library."
---

# The HW-entropy intrinsics are unreachable on every ESP target

- **Type:** bug (compiler core; ESP campaign) — **Track A** file ownership,
  **S** tag.
- **Filed:** 2026-08-30 by frankB, re-verifying
  [[feature-random-library]]'s blockers at HEAD on the coordinator's request.
- Measured against pin **v395** (`stable_linux_amd64/default/pinned`).

## Repro — five lines, no library involved

```pascal
program hw;
var b: Boolean;
begin
  b := __pxxCpuHasHwRandom;
  if b then b := False;
end.
```

| target | result |
| --- | --- |
| x86-64 (native) | builds |
| aarch64 | builds |
| arm32 | builds |
| i386 | builds |
| `--target=xtensa --platform=esp --esp-profile=bare` | **`error: undefined variable (__pxxCpuHasHwRandom)`** |
| `--target=riscv32 --platform=esp --esp-profile=bare` | **`error: undefined variable (__pxxCpuHasHwRandom)`** |

## Cause — one guard, and it is measured, not inferred

`compiler/pasparser_prog.inc:1056` decides whether a program pulls the builtin
unit by scanning its tokens for names that need it:

```pascal
if (Tokens[i].Kind = tkIdent) and
   (CaseEqual(GetTokenStr(i), '__pxxcpuhashwrandom') or
    CaseEqual(GetTokenStr(i), '__pxxhwrandom64')) and (not TargetIsEspClass) then
  needsBuiltin := True;
```

On an ESP-class target the arm never fires, the builtin unit is not pulled, and
the name resolves to nothing. The comment directly above it states the mandate
this breaks:

> *"lib/rtl/random.pas is required to call them with no per-arch anything of its
> own — that mandate is the whole reason they are compiler-side."*

`random.pas` honours that mandate exactly — `HWEntropyAvailable` is a bare
`__pxxCpuHasHwRandom` with no `{$ifdef}` — and its own comment says
*"__pxxCpuHasHwRandom answers truthfully on x86-64 and False everywhere else,
which routes those targets to tier 2 on its own."* **On ESP it does not answer
False; it fails to exist**, and the program does not build at all.

`(not TargetIsEspClass)` appears on 22 arms of this function, so it is the
file's established pattern rather than a slip on this one line — which is why
this is filed for Track A to decide rather than guessed at from Track B.

## Consequence

`lib/rtl/random.pas` is **uncompilable on xtensa and riscv32**. Measured with a
driver program that only does `v := Random64`:

| target | result |
| --- | --- |
| native / aarch64 / arm32 / i386 | builds |
| xtensa + esp + bare | **`random.pas:321: undefined variable (__pxxCpuHasHwRandom)`** |
| riscv32 + esp + bare | same |
| riscv32 hosted | `atomics need machine-mode CSR access (mstatus)` — the separate, known limitation |

xtensa is the **primary** ESP target (the owner's S2/S3 hardware), so this is
not a corner.

### Control — the ESP failures above are NOT this bug

Run first, because without it the measurement is worthless. An **empty**
program, no `uses random`:

| target | result |
| --- | --- |
| `--target=xtensa --platform=esp` (no `--esp-profile=bare`) | fails: `external (dynamic) symbols are not supported ... (first one: calloc)` |
| `--target=xtensa --platform=esp --esp-profile=bare` | **builds** |
| `--target=riscv32 --platform=esp --esp-profile=bare` | **builds** |
| `--target=riscv32` hosted | **builds** |

So the `calloc` error on the non-bare ESP profile belongs to **any** program on
that profile and has nothing to do with `random`; and hosted riscv32 builds an
empty program fine, which is what makes its `random` atomics failure real. Only
the `bare` rows isolate this ticket's defect.

## Relationship to the two tickets that closed

Both of [[feature-random-library]]'s recorded blockers are in `done/`, and
**both fixes hold** — this is not a regression of either:

- [[bug-a-xtensa-refuses-to-lower-an-unreachable-syscall]] — the
  `unsupported node in IR codegen: syscall` error is **gone**. Confirmed by its
  absence at HEAD; xtensa now stops later, on a different symbol.
- [[feature-a-rdrand-cpuid-compiler-builtins]] — the intrinsics exist and work
  on all four non-ESP targets.

What happened is that **a new wall stood behind the old one.** That ticket's
summary put "the ESP RNG register" in its stated scope; the x86-64 half landed
and the ESP half did not, and the guard makes the gap present as an undefined
symbol rather than as a missing feature. A ticket moving to `done/` does not
mean the thing it was blocking now builds — which is the same lesson
`feature-random-library` already carries in its own words: *"a ranked queue says
a ticket is UNBLOCKED, not that it has WORK LEFT IN IT."*

## Options, for whoever takes it

1. **Provide the intrinsics on ESP.** `__pxxCpuHasHwRandom` returns True and
   `__pxxHwRandom64` reads the ESP RNG register — the tier-1 support the
   parent ticket named. Most work, most value: it is the only tier-1 entropy
   these targets could have.
2. **Drop the guard on this arm only**, so the builtin unit is pulled and the
   existing "False everywhere else" body answers False on ESP. `random` then
   compiles and routes to tier 2, exactly as its comment predicts. Cheapest,
   and it makes the library's stated design true. Needs someone who knows why
   the other 21 guards are there — if the builtin unit cannot be pulled on ESP
   at all, this option does not exist and (3) is the fallback.
3. **A stub that answers False**, reachable on ESP without the full builtin
   unit, if (2) is impossible for unit-size or startup reasons.

Not chosen here: this is a Track A judgement about the builtin unit on ESP, and
Track B has no standing to pick. **Not worked around in `random.pas`** — an
`{$ifdef}` there is precisely the compiler-appeasement workaround the platonic
-code rule forbids, and it would silently delete the mandate the intrinsics
exist to serve.

## Gate

`make test` + self-host byte-identical, plus a cross build of a program using
`lib/rtl/random.pas` for xtensa and riscv32 under `--esp-profile=bare`. The
five-line repro above is the regression test.
