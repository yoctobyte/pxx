---
slug: feature-a-the-threadvar-area-is-3072-bytes-of-bss-in-every-program-that-has-no-threadvar
title: "The threadvar area is 3,072 bytes of bss in every program that declares no threadvar — and it is an x86-64-only cost, ZERO on ESP"
type: feature
track: A
prio: 45
status: new
created: 2026-09-18
owner: ""
summary: "`TLS_BLOCK_SIZE = TLS_USER_FIRST_OFF (1152) + TLS_USER_BYTES (3072)`, reserved as BSS_TLS_MAIN + 16 by EmitTlsMainInstall, and 3,072 of it is the source-declared `threadvar` area — held whether or not the program has one. MEASURED by flipping TLS_USER_BYTES to 0 and rebuilding (2026-09-18): x86-64 hosted empty program 38,444 -> 35,372 bss, **-3,072**; i386 34,156 -> 34,156, aarch64 34,204 -> 34,204, riscv32 bare ESP 66,856 -> 66,856, **ZERO on all three**. THAT IS THE HEADLINE AND IT IS THE OPPOSITE OF THE DAY'S OTHER TWO SIZE ITEMS: `EmitTlsMainInstall` returns immediately unless `TargetArch = TARGET_X86_64` (ir_codegen.inc), so this belongs to [[umbrella-a-hosted-program-is-as-small-as-it-can-be]] ONLY and must NOT be wired under the ESP umbrella or ranked on ESP SRAM. After the signal alt stack it is the largest single item in the hosted floor: 3,072 of 38,444 is 8%. THE FAILURE DIRECTION IS SAFE and that is measured too — `TryAssignThreadVarStorage` (pasparser_decl.inc:2800) REFUSES a threadvar that does not fit, with a diagnostic, so under-detection is a compile error and never a wrong binary."
---

# Why it is a fixed cap, in the code's own words

`EmitTlsMainInstall` emits the program's entry prologue at code offset 0 and is
called from `compiler.pas:2330` — **before any frontend parses anything** — so it
reserves the block and bakes the size into emitted immediates before a single
`threadvar` has been seen. `defs.inc` says so and calls growing it out of scope
for the first rung. That is still true; what follows is about getting the 3,072
back for programs that never needed it.

# Two routes, and they are not equal

**A — conservative prescan, safe in every direction, worth less.** Scan the
token array for an identifier `threadvar` before `EmitTlsMainInstall`, the way
`DetectPascalRuntimeNeeds` already scans for `tkUses`/`tkArray`/`tkClass`. Absent
→ the user area is 0. **`uses` must also force the area back on**, because a used
unit's `threadvar` is not in the main source's tokens; that is the same opacity
rule the existing prescan uses. Non-Pascal frontends have no `threadvar` at all
and can always take 0.

So it wins on unit-free programs — which is exactly the hosted umbrella's floor
subject, and nothing else. **Counted 2026-09-18: 11 of 49 Pascal files under
`examples/` have no top-level `uses`, so route A reaches 22% of them.** That is
the honest ceiling on this route; decide against it rather than discovering it.

**B — exact, worth the full 3,072 on every program, and it hinges on ONE fact
nobody has established.** Reserve the area from what parsing actually used
(`TlsUserUsed`) and patch the handful of size immediates afterwards — the
compiler already patches code with `Patch32`, and the clone stub is emitted
lazily (`CloneStubAddr := 0`) so it may not need patching at all.

**IT FOLDS EARLY, AND THAT IS ROUTE B'S ONE REAL BLOCKER — established
2026-09-18 from the mechanism, not from a comment.** `lib/rtl/palthread.pas:280`
reads the block size from `__pxxTlsBlockSize` rather than restating it, and
`pasparser_expr.inc:4451` lowers that name to `AllocNode(AN_INT_LIT)` with
`ASTIVal := TLS_BLOCK_SIZE` **at the use site, while palthread is being parsed**.
Its own comment states the intent — *"Constants, not calls — they fold to an
AN_INT_LIT here, so a `const` in the RTL can be defined from them."*

So if the block size becomes a value that grows when a `threadvar` is seen, that
literal captures whatever it was when palthread was parsed, which can be BEFORE
the growth. Too small a block means gs-relative slots write past the mapping —
the exact silent corruption palthread's own comment warns about, arriving from
inside one compile instead of between two releases.

**Route B therefore needs the builtin to resolve LATE** — a patched immediate
recorded like the other `Patch32` sites, or a relocation — before any of the
reservation work is worth starting. The `const`-definability the comment cites is
currently unused: `palthread.pas:280` is the ONLY consumer in `lib/**` and it
assigns to a local, so nothing today actually depends on the literal form.

`PAL_MIN_STACK` (palthread.pas:85) restates 4224 as part of a stack FLOOR. A
smaller block only makes that floor more generous, so it blocks neither route —
but it is a second copy of a number that has already moved once, and it should be
derived rather than restated whichever route is taken.

# Do not re-measure these

- The 3,072 is per-PROGRAM bss on x86-64, and also per-THREAD stack, since the
  clone stub carves the same block off every child's stack.
- The full block is 4,240 B (1,152 map + 3,072 user + 16 bytes of `struct
  rlimit` scratch past the end). Only the 3,072 is reclaimable; the slot map is
  an ABI other code reads.
- `--emit-obj` and `--shared` already skip the whole thing.
