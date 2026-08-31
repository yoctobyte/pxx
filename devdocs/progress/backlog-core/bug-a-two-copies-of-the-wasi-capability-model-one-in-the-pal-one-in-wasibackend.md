---
slug: bug-a-two-copies-of-the-wasi-capability-model-one-in-the-pal-one-in-wasibackend
title: "Two copies of the WASI capability model: the PAL's and wasibackend's, and the promised de-duplication was never filed"
track: A
prio: 25
type: bug
status: backlog
owner: ""
created: 2026-08-30
found-by: frankwasm (closing feature-a-wasm32-sys-intrinsics-and-ir-syscall-lowering)
summary: "compiler/builtin/wasibackend.pas copied the preopen-resolution and rights logic out of lib/rtl/platform/wasi/platform_backend.pas on purpose, so its landing commit changed no existing file, and said in its own header that the NEXT commit would make the PAL delegate and delete its copy. That commit was never written and no ticket was ever filed. Both copies work, so nothing fails — which is exactly why a capability model is the wrong thing to duplicate: the two drift into one path opening files the other refuses. The unit's self-reporting comment is what caught it."
---

> **Re-priced by the owner, 2026-08-30: WASM IS LOW PRIO FROM NOW ON.** *"it works,
> it tests our IR, we should be able to compile applications.. for now, that's good
> enough."* The anchor is met — `pascal26` runs under wasmtime and emits an ELF
> byte-identical to the native compiler's for the same source. wasm has served its
> real purpose, which was exercising the IR from a second direction. These tickets
> stay OPEN and correct; they simply must not outrank ordinary Track A work. Pick
> them up on request, or when a lane is warm on the files anyway.

> ## UNBLOCKED AND RESCOPED, 2026-08-30 — the answer is a TEST, not a de-duplication.
>
> The owner's standing constraint (*no PAL in the compiler source*) plus the
> measured scope (~150 lines of preopen/rights logic behind seven primitives;
> 696 lines vs the PAL's 1120) settled
> `decide-which-way-the-wasi-capability-model-should-point-once-it-has-one-owner`
> as **keep both copies, guard the drift**. Neither layering option is worth its
> permanent structural price at this size.
>
> **So this ticket's job is now:** (1) a differential test asserting both
> implementations resolve the same path to the same preopen and the same rights,
> refusal cases included — an `ENOTCAPABLE` from one and not the other is the
> whole point; (2) replace `wasibackend.pas`'s header comment, which currently
> says a de-duplication is owed, with a note that the duplication is deliberate
> and what the test is. **Do not merge the two implementations.** If the shared
> surface grows well past these primitives, reopen the decide ticket.
>
> Original filing note, superseded: **Blocked on a Track U decision, filed 2026-08-30 by the coordinator.** The fix
> direction is a layering call: a shared include double-defines when both units
> co-occur, wasibackend cannot use the PAL by design, and what remains points a
> `lib/rtl` unit at `compiler/builtin` — backwards from every other dependency in
> the tree. See
> `decide-which-way-the-wasi-capability-model-should-point-once-it-has-one-owner`.
> The coordinator's recommendation there is a differential test FIRST (it removes
> the silent-drift danger without spending the layering decision), then a shared
> home. Do not start the de-duplication until that decision lands.

# The state

Two independent implementations of the same capability model:

| file | has | since |
| --- | --- | --- |
| `lib/rtl/platform/wasi/platform_backend.pas` | preopen table (~line 254), `WasiFindPreopen` (~line 393), rights masks, `WasiErr` | the WASI PAL |
| `compiler/builtin/wasibackend.pas` | a copy of all of it | `8f6f3e373` |

Nothing is broken today. Both work; `check_wasi.sh` and `check_pal.sh` are
green and so is the wasm-hosted compiler's own file I/O.

# Why it is filed as a bug and not as a cleanup

Because the unit that created it says so, in its own header:

> DUPLICATION, DELIBERATE AND TEMPORARY. […] Two copies of a CAPABILITY MODEL
> is exactly the kind that drifts silently — one path opening files the other
> refuses — so it does not stay: the next commit makes platform_backend
> delegate here and deletes its copy. **If you are reading this comment and
> platform_backend still has its own preopen table, that follow-up did not
> happen and this is now a real defect.**

I am reading that comment and `platform_backend` still has its own preopen
table. By the author's own criterion this is now a defect rather than a debt.

**Nothing else would have caught it.** `grep -rl wasibackend devdocs/progress/`
returns only the BOARD and the decision doc — no ticket was ever filed, both
copies pass every check, and a divergence would first appear as a path that
opens under one caller and returns `ENOTCAPABLE` under the other. This is the
self-reporting comment doing the entire job it was written for, and it is worth
noting as a pattern that worked.

# The constraint that makes it non-obvious, and why it is not just "move it"

The obvious shapes are both closed:

* **A shared include is OUT, measured.** The decision doc records that option
  (c) was implemented far enough to fail: both units can co-occur in one
  program — a raw `sysopen` alongside `uses SysUtils` — so a shared `{$i}`
  defines every symbol twice.
* **`wasibackend uses platform_backend` is OUT by design.** `compiler.pas`
  links no PAL, deliberately; that is the whole reason `wasibackend` exists.

So the only direction left is the one the header names: **`platform_backend`
delegates to `wasibackend`**, guarded by `{$ifdef CPU_WASM32}`. That is
feasible — `compiler/builtin/` is a compiler SEARCH DIRECTORY whose units are
read per-program, so a `uses wasibackend` resolves — but it points a `lib/rtl`
unit at a `compiler/builtin` one, which is backwards from how every other
dependency in the tree runs.

**That direction is the actual open question, and it is a design call rather
than a typing job.** Worth settling before the edit, not during it. If pointing
the PAL at `compiler/builtin/` is unacceptable, the alternative is a third home
both can reach, which reopens the question of what that home may depend on.

# Lane note

`lib/rtl/platform/wasi/**` is normally Track B's. It was assigned to the wasm
lane for this campaign, and the original landing was made under an explicit
owner grant of sole occupancy that is no longer in force (three Track A
sessions now run concurrently). So this needs a coordination check before it is
picked up, not just a claim.

# Gate

`test/wasm/check_all.sh` 33/33 (it is `check_wasi.sh` and `check_pal.sh` that
prove the PAL's behaviour is unchanged by the delegation) plus
`make compiler/pascal26` self-host fixedpoint. The wasm-hosted compiler must
still resolve its unit chain — `--list-libraries` under WASI is the cheapest
end-to-end witness, since it walks a directory through the model in question.
