---
prio: 25
track: A
summary: "ROUTE B, SPLIT OUT OF [[feature-a-the-threadvar-area-is-3072-bytes-of-bss-in-every-program-that-has-no-threadvar]] WHEN THAT TICKET CLOSED ON ITS SHIPPED HALF. Grow the TLS user area from what the program actually declares instead of reserving a fixed 3,072 B cap, which would retire the text-scan heuristic (route A) entirely and cover every frontend at once. PRICED IN BOTH DIRECTIONS 2026-09-22 AND DEFERRED, NOT BLOCKED -- the parent read as blocked on a missing mechanism and it was missing two numbers. WORTH: 3,072 B to 25 of the 28 host example programs that build (3 already have it from route A), mean 2.86% of bss, range 0.18%-3.32%, and 3.32% is near a ceiling because the smallest uses-bearing Pascal bss measured is ~92 KB. Population 46 of 50 .pas files under examples/, oracle -dPXX_TLS_USER_0 which REFUSES any compilation declaring a threadvar, control the DEFAULT arm; 36 of 46 build at default and 36 of 36 also at _0, matching an expectation recorded before the run -- there are ZERO threadvar declarations in examples/ or lib/. x86-64 ONLY: TryAssignThreadVarStorage refuses FIRST on TargetArch <> TARGET_X86_64 and the area is not reserved off x86-64 either (measured delta zero on i386, arm32, aarch64, riscv32/esp32c3, wasm32), so this is worth NOTHING on ESP and must not be wired to an ESP umbrella. COSTS: three things, one backend. Defer the BSS_TLS_MAIN offset assignment past parsing; patch the two prologue displacements at ir_codegen.inc:2005/2009; stop __pxxTlsBlockSize folding to AN_INT_LIT at pasparser_expr.inc:4451. The parent's blocker section named only the fold and prescribed Patch32 -- WRONG PRECEDENT: Patch32 is a within-pass backpatch, and PatchProcPrologue (symtab.inc:15533) is the only existing case in this compiler of a NUMBER rather than an address emitted as a placeholder and filled in later. Three of the four TlsBlockSize consumers are ALREADY LATE FOR FREE (the clone stub's four reads fire at IR_CLONE lowering) and the block's ADDRESS is already a GlobFix the ELF writer resolves at the end. DEFERRED because the failure mode of getting it wrong is silent gs-relative corruption in the entry prologue every program runs through, for ~3% of bss, against stated goals of a full green pin and working demos. WHAT REVIVES IT, and it is a mechanism rather than a row: a threadvar landing anywhere in lib/rtl -- route A's `uses` term then forces the full area on every program that touches a unit, and this becomes the only way to pay for what is actually declared."
status: rainy-day
owner: unassigned
---

# Size the threadvar area from what the program declares, instead of a fixed cap

- **Type:** feature (codegen / emission size) — Track A, tag O
- **Status:** rainy-day — split out 2026-09-22 by frankb-8e when the parent
  closed on its shipped half. Deferred with a price, not parked for want of a
  mechanism.
- **Parent:** [[feature-a-the-threadvar-area-is-3072-bytes-of-bss-in-every-program-that-has-no-threadvar]]
  (routes A and C shipped; this is what was left)

## What shipped, so this is not confused with it

- **Route C** — `-dPXX_TLS_USER_0/_1K/_2K/_4K/_8K/_16K` sets the size
  explicitly and always wins.
- **Route A** — a Pascal source naming neither `threadvar` nor `uses` gets a
  zero-byte area automatically, and BASIC got the same arm on the same
  precedent. It is a text scan because the token array is empty at the only
  moment the size may be chosen.

Route A's reach is capped by its `uses` term, and that term cannot be dropped:
without it a program whose imported unit declares a `threadvar` would be
REFUSED, and programs that compile today must keep compiling. **This ticket is
the only thing that removes that cap.**

## Why it is deferred rather than blocked

The parent's blocker section named one obstacle and prescribed the wrong
precedent for it, which made the whole route look unapproachable. The real map:

| consumer | site | when | route B? |
| --- | --- | --- | --- |
| the `AN_INT_LIT` fold | `pasparser_expr.inc:4451` | parse time | **early** |
| BSS reservation | `ir_codegen.inc:1992` | before parsing | **early** |
| two prologue displacements | `ir_codegen.inc:2005`, `:2009` | before parsing | **early** |
| clone stub carve, ×4 | `thread_emit.inc:114/120/164/182` | at `IR_CLONE` lowering | **already late** |

The block's ADDRESS is already resolved late — the prologue reaches it through
`mov r9, @glob BSS_TLS_MAIN`, a `GlobFix[]` entry the ELF writer patches at the
end — so what is early is the BSS *offset assignment*, not the reference. And
it is one backend: `threadvar` refuses off x86-64, so every site above is in
the x86-64 path. The fold is the only cross-cutting one, and it is 2 of 25
`__pxx*` builtins that fold to a literal at all; the other 23 already allocate
a node that survives to IR and emit.

**`Patch32` is not the mechanism** — it is a within-pass backpatch of
already-emitted bytes. `PatchProcPrologue` (`symtab.inc:15533`) is the
precedent: `EmitProcPrologue` emits a placeholder `0` for the frame size and
returns its code position, and the real number is written after the body, with
a per-arch encoder.

So the cost is real but bounded, and the reason to defer is the **failure
mode**, not the difficulty: too small a block means gs-relative slots write
past the mapping — silent corruption, in the entry prologue every program runs
through — for a measured ~2.9% of bss.

## What would revive it

Stated as a mechanism so it does not decay when the demo changes:

1. **A `threadvar` landing anywhere in `lib/rtl`.** Today there are none, so
   route A's `uses` term is a conservative approximation that happens to be
   exactly wrong 25 times out of 28. The moment one exists, every program that
   touches a unit pays the full area and this becomes the only way to pay for
   what is declared. Note `lib/rtl/sockets.pas` and `scheduler.pas` both
   hand-build per-thread tables and both would be candidates if `threadvar`
   were not x86-64 only — see their comments, corrected 2026-09-22.
2. **A hosted program whose bss is small enough for 3,072 to be a large
   share.** Nothing under `examples/` is: the floor for anything with a `uses`
   is ~92 KB.
3. **A thread register that can be SET off x86-64**, which would make the area
   exist on other targets and multiply the value by the number of targets.

## Acceptance

Not "bss got smaller". A program declaring N bytes of `threadvar` must reserve
exactly what the slot map plus N needs, a program declaring none must reserve
zero **without any text scan**, and `TLSREFUSE_AREAFULL` must become
unreachable — it exists only because the cap is fixed, and its diagnostic text
says so in its own words. Route A's two arms in `ApplyTlsUserBytesOption` and
their fixtures should be DELETED by this change, not left beside it; if they
survive, the cap did not really go.
