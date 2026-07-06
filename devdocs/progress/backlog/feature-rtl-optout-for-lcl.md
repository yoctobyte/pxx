---
prio: 45  # auto
---

# Opt out of pxx's own RTL/widget layer (for compiling LCL) — without pulling FPC's RTL

- **Type:** feature (RTL layering / compiler flag — Track A/B) — **not now, keep in mind**
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-04 (from the FPC/LCL compile-probe discussion;
  [[fpc-lcl-compile-probe]])

## Context / goal

To compile a real LCL (Lazarus Component Library) against pxx, we must be able to
**opt out of pxx's own RTL/PCL widget stack** (`lib/pcl/controls`, `graphics`,
`forms`, `gtk3`, `stdctrls`, …) so LCL's own units provide those instead —
without a name/type clash against pxx's reimplementation.

**Hard constraint (user, 2026-07-04): we do NOT compile against or rely on FPC's
RTL.** pxx stays self-sufficient and libc-free. So "opt out of our RTL" means
opting out of the *pxx PCL/widget layer*, while pxx still supplies the low-level
runtime (heap, managed strings, syscalls, PAL) that LCL's RTL-level code needs.
This is emphatically NOT "use FPC's system/objpas/fcl".

## Where we already are (the good news)

The RTL is **strictly separated from the builtin surface**, so the boundary
mostly exists:
- `--no-default-rtl` / `NoDefaultRtl` / `{$define PXX_NODEFAULTRTL}` already opts
  out of the default standard-unit surface (textfile + PAL/platform dirs). A
  plain program still compiles — the builtin heap + managed-string helpers
  (`builtinheap`, the `__pxx*` intrinsics) are a separate, always-available layer.
- So "opt out of our RTL, keep the builtin core" is already the shape of the
  flag. This should be "easy peasy" precisely because builtin ≠ RTL.

## What this ticket needs to nail down (later)

1. **Granularity.** `--no-default-rtl` today is coarse (textfile + PAL search
   paths). Compiling LCL wants: keep the builtin core + libc-free PAL, but drop
   pxx's PCL widget units so LCL's `Controls`/`Graphics`/`Forms` resolve to
   LCL's sources (via `-Fu`) with no shadow from `lib/pcl/*`. Decide whether that
   is the same flag, a new `--no-pcl`, or purely a `-Fu` search-order rule
   (LCL dir before `lib/pcl`).
2. **Shadowing order.** `ParseUsesUnit`'s search chain currently prefers pxx's
   `lib/rtl`/`lib/pcl` for those unit names. For LCL, the user's `-Fu` must win
   for the widget units while pxx's low-level RTL still resolves. Confirm/adjust
   the precedence.
3. **What LCL actually still needs from pxx** (the RTL floor LCL builds on:
   `Classes`, `SysUtils`, streams, `TComponent`/`TPersistent` surface — see the
   related library-surface tickets). Those stay pxx's, grown toward FPC's API.

## Acceptance (when picked up)

- A documented switch/`-Fu` recipe compiles a program that `uses` LCL widget
  units from an external LCL checkout, with pxx providing the low-level runtime
  and LCL providing the widgets — zero FPC-RTL dependency, zero libc.
- pxx's own PCL demos still build unchanged (opt-in, default off).

## Note

Low priority — parked deliberately. Filed so the boundary requirement (opt out
of *our* PCL, never depend on FPC's RTL) is not forgotten when LCL work resumes.
Related: [[feature-classes-tlist-notify-hook]] and the "grow `classes` toward
`TComponent`" thread are the RTL-floor pieces LCL needs regardless.
