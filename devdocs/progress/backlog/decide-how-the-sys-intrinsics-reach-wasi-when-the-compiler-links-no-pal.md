---
slug: decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal
title: "How should the sysopen/sysread/sysclose intrinsics reach WASI, given compiler.pas links no PAL by design?"
track: U
prio: 70
type: decide
status: backlog
owner: ""
created: 2026-08-29
found-by: frankwasm (sizing the builtins refusal block)
summary: "24 of wasm32's 52 remaining compiler.pas refusals are the sys* intrinsics (tkSysOpen 15, tkSyswrite 6, tkArgStr 3), and they collapse to ONE blocked primitive: opening a file under WASI. That needs preopen resolution, rights computation and errno mapping, which exist once in lib/rtl/platform/wasi/platform_backend.pas -- a unit compiler.pas deliberately does not link, because the compiler bootstraps on intrinsics to avoid an RTL dependency. Three ways out, each with a real cost: duplicate the capability model into builtinheap.pas, link the PAL into the compiler, or factor the WASI helpers into a shared include. The choice spans Track A and Track B files, so it is not the wasm lane's to make."
---

> **Re-priced 40 -> 70 by the coordinator, 2026-08-30, on a re-measurement by frankwasm.**
> When this was filed it was 24 of 52 refusals -- one blocker among several. It is now
> **32 of 32**: the histogram has exactly one shape left (17x -50, 8x -100 `LoadFile`,
> 6x -52, 1x IR op 54 `getdents64`), every one file / directory / environment I/O, every
> one gated by this decision. The two categories that were NOT this ticket have both
> been cleared since -- argv landed as Phase 9j (`b9e1ef22f` **on branch `wasm`**, backend-emitted
> `args_sizes_get`/`args_get`, self-host fixedpoint plus 28 wasm checks) and the float
> intrinsics as Phase 9k (`Frac` -205 / `Int` -206, ten lines, both `f64.trunc`).
>
> **What changed is not the number, it is the shape.** 24-of-52 prices as "a big piece of
> the work"; 32-of-32 prices as "the lane cannot finish the anchor without a human". This
> decision now gates 32 bodies in the compiler itself, i.e. the entire *pascal26 runs
> under wasmtime* milestone. Nothing else in the wasm lane's anchor work is blocked on
> anything but this.
>
> Not raised higher: frankwasm is NOT idle on it -- it continues on non-anchor lane work
> while this sits, so the cost is a stalled milestone, not a stalled agent. 70 puts it
> level with the other ranked Track U items rather than ahead of the fleet.

> **DANGLING SHAS BY DESIGN.** Every commit sha in this ticket lives on branch
> **`wasm`**, not on `origin/master` — the wasm lane works in a standalone
> checkout and pushes to its own branch. `progress.sh check` flags them as
> `SIDE-BRANCH-SHA` and that is correct, not a defect: the measurements were
> taken where the work is. A reader cannot tell a side-branch sha from a dead
> one, hence this note. **Branch permission is not merge permission** — nothing
> on `origin/wasm` is pre-approved for master, so treat these as citations to
> evidence, not as work that has landed for everyone.
> — frankwasm, 2026-08-30

# The number, and what is actually behind it

24 of the 52 remaining refusals when compiling `compiler.pas` for wasm32:
`tkSysOpen` (-50) 15 lines, `tkSyswrite` (-52) 6, `tkArgStr` (-56) 3.

**It is a first-refusal count, so it understates by an unknown amount.**
`tkSysRead` (-51), `tkSysClose` (-53) and `tkSysFchmod` (-54) do not appear at
all -- every body that would reach them stops at `sysopen` first. Landing
`sysopen` promotes them.

Decomposed by what the milestone actually needs:

| group | bodies | needed for a wasm-HOSTED compiler? |
| --- | --- | --- |
| read source / write output | `PxxReadSmallFile`, `PxxEnvLoad`, `WasmSaveModule`, `WasmWriteText`, `WTFlush` | **yes -- Phase 9's milestone is exactly this** |
| ELF output | `writeELF`, `writeELF32`, `writeELF32Rel`, `writeELF32RelIram`, `writeELFRelX64`, `writeELFSharedX64`, `WriteMapFile`, `WriteDisassemblyX64`, `DisWriteStr`, `writeU8/16/32/64` | only to cross-compile to native FROM wasm |
| CLI / diagnostics | `PxxListDir`, `WhereDirExists`, `WhichOnPath`, `PrintWhere`, `PrintLibraries`, `PrintDoctor` | no |

**Five of the twenty-four are on the milestone's critical path, and all five
need the same one primitive.** The block is not 24 pieces of work; it is one
decision plus a small amount of typing.

# Why it is blocked on a decision rather than on effort

`sysopen` under WASI is not a syscall number swap. `path_open` takes a
**preopened directory fd** and a path relative to it, plus an explicitly
computed rights mask -- ask for too much and a strict host refuses, too little
and the fd opens then fails `ENOTCAPABLE` on first use. That logic exists,
correct and tested, in `lib/rtl/platform/wasi/platform_backend.pas`
(`PalBackendOpen`, ~55 lines, plus `WasiFindPreopen`, the rights table and
`WasiErr`).

`compiler.pas` cannot call it. It links no PAL **on purpose** -- it uses the
raw `sysopen`/`syswrite` intrinsics precisely so the compiler has no RTL or
unit dependency to bootstrap. Confirmed: no `PalBackend*` symbol appears in the
wasm build of `compiler.pas`. The compiler only knows the PAL's *search
directories*, for the programs it compiles (and those are currently hardcoded
to `posix/`, which is its own separate problem).

So the primitive is implemented once, in the one place the caller may not
reach, and the caller's inability to reach it is a deliberate design property
rather than an oversight.

# The options

**(a) Duplicate a minimal WASI open into `builtinheap.pas`.**
Self-contained; no unit dependency; matches what `PXXSysWrite` already does
there (`__wasi_fd_write` called directly). But it is **a second implementation
of the capability model** -- preopen resolution and the rights mask -- in a
repo whose own guidance says two mechanisms for one concept is a design flaw
and the second one is the one that stays broken. `fd_write` got away with it
because writing to fd 1 needs no capability; `path_open` does.

**(b) Link the PAL into `compiler.pas` for wasm32 only.**
One implementation, no duplication. But it puts a `lib/` unit inside the
compiler's bootstrap for one target, which is the dependency the intrinsic
design exists to avoid, and it makes the compiler's own build target-shaped.

**(c) Factor the WASI helpers into a shared include both consume.**
`WasiFindPreopen` / rights / `WasiErr` move to something like
`lib/rtl/platform/wasi/wasi_core.inc`, included by both the PAL and
`builtinheap.pas`. One implementation, no unit dependency, and it is the
"normalise, don't special-case" answer. Costs a refactor that touches a Track B
file and a shared RTL file, so it **spans two lanes' gates**.

# Recommendation

**(c)**, and I hold it loosely. It is the only option that leaves one
implementation of the capability model without putting a unit dependency into
the compiler's bootstrap, and the thing being shared is a pure leaf helper
(find a preopen, map an errno) with no state of its own -- close to the
cheapest possible thing to share. (a) is the fastest and I would expect it to
drift the first time a rights bug is fixed on one side only. (b) is the
smallest diff and the largest change in what `compiler.pas` *is*.

If the answer is (a) anyway -- because Phase 9 is a proof of concept and
drift is acceptable for now -- that is a perfectly reasonable call and worth
saying out loud in the ticket, so the duplication is a decision on the record
rather than something a later reader has to reconstruct.

# What does NOT depend on this

`bug-a-three-pxxsys-primitives-return-a-plausible-fd-on-wasm32` -- making
`PXXSysOpenRO`/`PXXSysClose`/`PXXSysLseek` fail CLOSED instead of returning a
plausible fd. That is a correctness fix in the failure direction and should not
wait for this decision.

`tkArgStr` (3 lines) may also be independent: WASI `args_get` /
`args_sizes_get` need no preopen and no rights. Not verified.

## 2026-08-30 (frankwasm) — the `tkArgStr` escape hatch is CLOSED. Measured, nothing applied.

This ticket's "What does NOT depend on this" section offers `tkArgStr` as
possibly independent:

> `tkArgStr` (3 lines) may also be independent: WASI `args_get` /
> `args_sizes_get` need no preopen and no rights. Not verified.

Verified now, and it splits: **the capability half is true, the linkage half is
false, and the linkage half was always the binding constraint.**

**True:** `args_sizes_get` / `args_get` take no descriptor and need no grant, so
they really are reachable while the whole path-opening surface waits on this
decision. An implementation was written against them and compiled.

**False:** "3 lines" assumed the code could live in the WASI PAL. It cannot, for
two independently sufficient reasons, both measured:

1. **`compiler.pas` links no PAL at all** — `uses SysUtils, Math, BaseUnix,
   asmcore_base, asmcore_x64`, and nothing in that chain reaches
   `lib/rtl/platform.pas`, the only unit that says `uses platform_backend`. The
   units that pull the PAL in are the networking and `classes` family. This is
   this ticket's own title, arrived at from a different direction.
2. **Even with the PAL linked, a PAL routine nothing calls is eliminated.** A
   probe with an explicit `uses platform` still reported `no PalBackendArgCount`,
   while `strings` on the same module shows `PalBackendPlatform` /
   `PalBackendHasFiles` present — they survive because `platform.pas` calls
   them. A routine whose only caller is a call the BACKEND synthesises later has
   no Pascal caller when emission-size DCE runs.

**Why this is evidence for the decision rather than just a note on it.** The
route those two close is the PAL route; what remains is for the backend to emit
the import itself (`WasmHostImport('wasi_snapshot_preview1', …)`, the mechanism
the unhandled-exception `fd_write` path already uses). That is a worked
demonstration of a WASI capability being reached **with no PAL linked at all** —
which is close to this ticket's option (b), on the one capability where it can
be tried in isolation because it needs no preopen and no rights. If (b) is
where this lands, argv is the cheapest place to prove it; if (c) is chosen, argv
is the case that shows a shared leaf helper is not always enough, because the
problem here is reachability, not duplication.

**Also worth having on the record for whoever answers this:** the decision is
`prio: 40` while it is the sole blocker on **36 of 36** remaining refusals in
`feature-target-wasm` [p60], whose anchor milestone is `pascal26` running under
wasmtime. Prio propagates down `blocked-by:` edges, but that edge does not
exist — the dependency is stated in PROSE, in `devdocs/dev/wasm/PLAN.md` on a
side branch, which is the least visible place in the repo. Flagged rather than
changed: the edge and the number are the U lane's call, not this lane's.

> **Both halves of that paragraph are now RESOLVED and it is kept only as the
> record of why.** The `blocked-by:` edge exists — added to
> `feature-target-wasm` on 2026-08-30 after the coordinator's correction that
> *the number is U's call; the edge is a fact* — and the prio is 70, not 40.
> The refusal count is 32 of 32, not 36 of 36; the four that were not this
> decision have since landed (Phase 9j argv, Phase 9k `Frac`/`Int`).
> — frankwasm, 2026-08-30

Full measurement and the costing: `devdocs/dev/wasm/PLAN.md`, Phase 9j, on
branch `wasm` (`b564c8f39`). Nothing applied there either.

## The experiment that would settle this, and it is cheap

Added 2026-08-30 so this reads as a question with a named test rather than an
open one. **argv is the one capability that can be tried in isolation**, because
`args_sizes_get` / `args_get` need no preopen and no rights (verified above) —
every other candidate drags the whole capability model in with it and so cannot
distinguish the options.

- **If (b) — the backend emits the imports itself** — argv is the cheapest place
  to prove it: `ParamCount` is one import plus eight bytes of scratch, and a
  working `ParamStr` demonstrates a WASI capability reached with **no PAL
  linked at all**, which is the property (b) is really being asked about.
- **If (c) — a shared leaf helper** — argv is the case that shows a leaf helper
  is not sufficient, and *why*: the problem here is **reachability, not
  duplication**. A helper in a unit nothing calls is eliminated before the
  backend can ask for it, so (c) has to say where the helper lives such that a
  synthesised call can still find it. That is a real constraint on (c)'s design
  and it is not visible from the option list.
- **If (a) — duplicate per side** — argv is where the duplication is smallest,
  so it is the least informative test, which is itself worth knowing.

Whoever answers this can therefore answer it on one small capability first and
let the rest follow, instead of deciding the whole model up front.

**Blocking relationship now recorded in frontmatter.** `feature-target-wasm`
[p60] carries `blocked-by:` this ticket as of today — 36 of its 36 remaining
refusals are this decision. Effective priority propagates down that edge, so
this now ranks from what it unblocks rather than from its filed `prio: 40`.
The filed number is untouched and stays the U lane's to set; the edge is a
measurement.
