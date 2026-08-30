---
track: A
prio: 60
type: feature
status: done
owner: frankwasm
summary: "The last 36 unlowered bodies in compiler.pas on wasm32: 35 sys builtins (writeELF*, writeU8/16/32/64, LoadFile) plus IR_SYSCALL (value op 54), which is the same question wearing a different hat. Blocked on the Track U decision, not on any missing mechanism. Filed so the ranker can SEE that a U item is holding a p60 lane — the edge did not exist, so prio propagation had nothing to work with and the decision sat at 40."
---

# wasm32: the sys intrinsics and `IR_SYSCALL`, the last 36 bodies

**3698 of 3734 bodies in `compiler.pas` lower on wasm32.** The 36 that do not
are:

- **35 sys builtins** — `writeELF*`, `writeU8/16/32/64`, `LoadFile`
- **`IR_SYSCALL`** (value op 54) — the same question in different clothing

Every one is **blocked on
`decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal`**, not
on a missing mechanism. There is no implementation work that can begin before the
decision, and no way to guess a direction that would not have to be redone.

*(Denominator note: 3662 → 3734 across the last merge, so this count is not
comparable to phase 9g's without saying so.)*

## Why this ticket exists at all

It is the **edge**, not the work.

The decision was sitting at **p40**. The only ticket declaring it as a blocker
was already in `done/`, so the ranker saw a U item that blocked nothing live —
and prio propagation, which is the mechanism that is supposed to raise a blocker
to the priority of what it unblocks, **had nothing to propagate along.** The lane
it actually holds is `feature-target-wasm` at **p60**.

The edge was not put on the umbrella deliberately: the umbrella is not blocked,
only its last 36 bodies are, and marking a mostly-live ticket `blocked-by` would
misreport the lane. So the blocked slice gets its own ticket and carries the edge.

> **A blocker with no live dependents is indistinguishable from a blocker nobody
> needs.** The board ranks what it can see, and work that exists only on a branch
> — or only in a lane's own head — contributes no priority to the thing holding
> it up. This is the same rule as *a ticket that is not on master does not
> exist*, one level out: **an unfiled dependency does not merely hide the work,
> it silently under-ranks the decision.**

## When the decision lands

Re-file as ordinary Track A work, or resolve this and let the wasm lane pick it
up directly — a U item that turns out to be plain work once decided belongs in
the owning lane, not in U.


# DELIVERED BY THE DECISION'S OWN IMPLEMENTATION — verified 2026-08-30, no new code

This ticket was the **edge, not the work** (see above), and the work landed with
the decision that unblocked it: `8f6f3e373`, now on master via the wasm merge.
The decision resolved as a FOURTH option none of the three here proposed — a
separate builtin unit, `compiler/builtin/wasibackend.pas` (29 KB), injected
on demand for wasm32 rather than ambiently.

So this closes on verification rather than on a diff. Measured at
`631a13d0d8d0` (self-host fixedpoint, `converged after 1 round(s)`):

## The refusal count is ZERO

```
$ pascal26 --target=wasm32 -Fulib/rtl/platform/wasi compiler/compiler.pas
wasm32: 3888 of 3888 bodies lowered — op coverage is complete for this program.
```

The only remaining indented lines are three `IInterface` declaration-only stubs
(`QueryInterface`, `_AddRef`, `_Release`) — methods DECLARED without an
implementation, which is not a coverage gap and is not target-specific.

**36 → 0.** The trajectory the decision recorded was 32 → 10 at `8f6f3e373`
(the `-50`/`-52` family gone, nine `LoadFile` and one `sysgetdents64` left);
those last ten have since landed too.

## The named bodies are really emitted, not stubbed

Every routine this ticket listed is present in the module with a real body:

`writeELF`, `writeELF32`, `writeELF32Rel`, `writeELF32RelIram`,
`writeELFRelX64`, `writeELFSharedX64`, `writeU8`, `writeU16`, `writeU32`,
`writeU64`, `PxxReadSmallFile`, `WasmSaveModule`, `PxxListDir`.

`LoadFile` lowers to `PXXWasiLoadFile` — a distinct callee chosen by target,
because builtinheap's `PXXStrLoadFile` is written over `PXXSysOpenRO`/`Lseek`/
`Read`/`Close`, whose `{$if}` chain has no wasm arm.

## RUN, not just emitted — `--list-libraries` under WASI

The strongest single check available, because it is the one CLI path that walks
a DIRECTORY: `PxxListDir` → `sysgetdents64` → WASI `fd_readdir`. That is the
`IR SYSCALL`-shaped item this ticket named (op 54), and the decision explicitly
did **not** gate it, so it was the one piece that could plausibly still be open.

```
$ node test/wasm/wasihost.js pxx.wasm <sandbox> --list-libraries
libraries pxx can find from this binary
RTL (Pascal runtime + stdlib) — 110 units in lib/rtl/
  aesgcm  ansirender  ansiterm  ast  asyncnet ...
exit 0
```

Identical to the native build's output for the same tree, all 110 units, modulo
the path prefix — CWD-relative under WASI versus absolute natively, which is
`--where`'s documented behaviour for a bare `argv[0]` and not a divergence.

`--version` and `--where` also exit 0, and the compiler resolves its full
23-probe unit chain and finds `compiler/builtin/builtinheap.pas`.

## Gate

`make compiler/pascal26` — self-host fixedpoint, `converged after 1 round(s)`.
`test/wasm/check_all.sh` — **33/33 green**, including `check_sysio` (the file the
wasm build wrote matches the native one byte for byte), `check_wasi`,
`check_pal` and `check_loadfile`.

## The follow-up the decision named, which was NEVER FILED

`compiler/builtin/wasibackend.pas` copied the preopen/rights core from
`lib/rtl/platform/wasi/platform_backend.pas` deliberately, so that its commit
changed no existing file's behaviour — and said so, with a self-reporting
sentence at the head of the unit:

> *"the next commit makes platform_backend delegate here and deletes its copy.
> If you are reading this comment and platform_backend still has its own
> preopen table, that follow-up did not happen and this is now a real defect."*

It did not happen. `platform_backend.pas` still has its own preopen table
(line 254) and its own `WasiFindPreopen` (line 393), and no ticket anywhere in
`devdocs/progress/` mentions `wasibackend`. The comment did exactly the job it
was written for; nothing else would have caught it, because both copies work.

Filed now as
`bug-a-two-copies-of-the-wasi-capability-model-one-in-the-pal-one-in-wasibackend`.
It is NOT a remainder of this ticket — this ticket asked for the intrinsics to
lower, and they do — but it is the debt that lowering them incurred, and leaving
it unfiled is how it would have been lost.

## Log
- 2026-08-30 — resolved, commit 7943a0762.
