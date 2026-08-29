---
track: A
prio: 55
type: bug
blocked-by: []
summary: "EmitZeroFrameSlot (compiler/symtab.inc:10074) is the single owner of the zero-init contract and has TWO per-target chains, one per size class. The wide one (> pointer) ends in Error and fails loud — that is what this ticket originally described. The narrow one (<= pointer, which is EVERY managed scalar) ends in an UNGUARDED else that emits x86-64 bytes, so wasm32 falls open there and has been doing so since the managed-string phase. Measured 2026-08-28 with a probe build. Output is byte-identical with the fall-through removed, so Code[] is unread on this target and nothing wrong has been PRODUCED — it is latent, not active. Carries one open design question: the wasm32 backend now zeroes its own managed scalars in its prologue, so there are three mechanisms for one guarantee on this target."
status: new
owner: ""
---

# `EmitZeroFrameSlot` has no wasm32 arm

- **Type:** bug (shared codegen) — **Track A** (`compiler/symtab.inc`).
- **Filed:** 2026-08-28 by the wasm32 lane (branch `wasm`), which cannot fix it
  under its own standing rule: a shared-file change is filed, not made.
- **Blocks:** any wasm32 program whose lowering mints a hidden managed temp.
  Measured: `test/test_dynarray_insert_delete.pas` dies at line 93 with
  `compiler error: EmitZeroFrameSlot: unhandled target`.

## CORRECTION, 2026-08-28 — this ticket described one of two arms, and the other fails OPEN

**What was originally written here was half right, and the wrong half was the
part the priority rested on.** The correction is recorded rather than edited
away, because the reasoning error is the reusable part.

`EmitZeroFrameSlot` has **two** per-target dispatch chains, one per size class,
and they end differently:

| extent | chain ends | wasm32 gets |
| --- | --- | --- |
| `nBytes > TARGET_PTR_SIZE` (records with managed fields, variants, arrays of string) | `Error('... unhandled target')` | a loud, located failure |
| `nBytes <= TARGET_PTR_SIZE` (**every managed scalar** — AnsiString, dyn-array) | an **unguarded `else`** that is the x86-64 arm | `mov qword [rbp+off], 0`, silently |

The original text quoted the terminal `Error`, said "`TARGET_WASM32` reaches
that `else`", and drew a contrast with `HeapMmap` and `PXXSysWrite` as the two
chains in this family that fail OPEN. **wasm32 reaches BOTH**, and the narrow
chain is the one nearly every program hits — so this ticket belongs in the
fail-open family it was written to distinguish itself from.

### How it was found, and why reading did not find it

Compiling `compiler/compiler.pas` for wasm32 (Phase 9's first measurement)
stopped at the loud arm, which is what the ticket predicted. The narrow arm was
found only by *probing* it: a temporary build replacing the x86-64 fall-through
with `Error('PROBE: wasm32 reached the x86-64 fall-through')` fires immediately
on `procedure P; var r: TR;` where `TR = record a: string; end` — a
single-pointer extent.

The reason a read missed it is worth keeping: the routine's first chain has SIX
named target arms and a seventh unnamed one, and an unnamed final arm reads as
"the default" rather than as "x86-64". It IS x86-64 — the bytes are
`mov qword [rbp+off], 0`. **A dispatch chain whose last arm is a real target
rather than an error is a fall-open chain wearing the shape of an
exhaustive one**, and this is the third instance in this family
(`refactor-a-target-dispatch-chains-fail-open` is the general ticket).

### Severity: it fails open, but demonstrably INERTLY

Measured, not assumed. A second probe build made the wasm32 arm emit *nothing*,
and the emitted `.wasm` for three slices (`managed_slice`, `index_slice`,
`wasi_slice`) is **byte-identical** to the real compiler's. `Code[]` is not read
on this target — the wasm backend builds its own module model — so the x86-64
bytes go into a buffer nothing consumes.

So: no wrong answer has ever been produced by it, and prio stays **55**. But the
*reason* is now different, and the difference matters for whoever fixes it. It
is not "this one fails loud". It is "this one fails open into an unread buffer,
and stops being inert the moment anything on this target reads `Code[]` or the
byte-count of what was emitted into it".

## The open question the arm has to answer first

As of `wasm` HEAD the wasm32 backend zeroes its OWN managed locals in its own
prologue — `WasmEmitManagedLocals` in `ir_codegen_wasm32.inc`, added with the
managed-string phase because a function's result slot is shadow-stack memory
and its first publish reads the slot to find the handle it must release. That
pass runs at codegen time over `Procs[CurProc].ScopeBase .. SymCount-1`, so it
already covers hidden temps minted during lowering, and it covers them EARLIER
(prologue) than `EmitZeroFrameSlot` does (at the current emission point).

So the two mechanisms overlap, and the arm should be written knowing which:

- **If the wasm prologue pass is the answer for scalars,** the wasm arm needs
  to handle only what that pass does not — the `> TARGET_PTR_SIZE` extents
  (records with managed fields, variants, static arrays of string), which route
  to `PXXMemZero` and are refused elsewhere on wasm32 today anyway.
- **If `EmitZeroFrameSlot` is the answer,** the wasm arm emits the store and
  `WasmEmitManagedLocals`'s zeroing half should be deleted rather than left as
  a second implementation of one guarantee — which is precisely what this
  routine's header says must not happen.

The second reading is the one that matches the file's stated design. The first
is what the wasm backend actually needs, because it has its own prologue and
never calls `EmitProcEpilog`. **This is a fork, not an oversight** — whoever
takes the ticket should decide it explicitly and record which, rather than
adding an arm beside a pass that already does the job.

## Three mechanisms for one guarantee, on one target

The header of `EmitZeroFrameSlot` states that the zero-init guarantee has ONE
owner. On wasm32 it currently has three:

1. `WasmEmitManagedLocals`, the backend's own prologue pass (scalars);
2. the x86-64 fall-through, emitting into an unread buffer (scalars again);
3. the loud `Error` (wide extents).

`devdocs/dev/root-cause-over-microfix.md` calls two a smell and three a design
flaw. Whoever takes this should count them before adding a fourth: the fix is
plausibly *deleting* an arm rather than adding one, and the decision fork below
is the same fork stated one level down.

## Notes

- The wasm arm itself is small: `$fp + WasmCurFrame + frameOff`, then an
  `i32.store` of zero (or a `PXXMemZero` call for a wide extent). The cost is
  entirely in the question above.
- **Whatever the fix, the narrow chain needs a wasm32 arm or an error, not the
  x86-64 default.** Even if the decision is "the prologue pass owns scalars and
  this routine should do nothing for wasm32", that has to be written as an
  explicit no-op arm with the reason, because an unnamed fall-through is
  indistinguishable from an unconsidered one — which is exactly how this went
  unnoticed through an entire phase of managed-string work.
- `EmitManagedLocalCleanupForTarget` (`ir_codegen.inc:10135`) has the same
  shape and the same missing arm on the release side, and the wasm backend
  likewise does its own. Same fork, same answer; fold it in.
