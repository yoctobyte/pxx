---
track: A
prio: 50
type: refactor
blocked-by: []
summary: "Three frontends have each independently grown a private piece of target machinery: the Pascal driver emits the signal runtime, the C frontend writes the _start stub as raw machine code, and Zig calls Rust's REmitParamRegSpill for raw x86-64 register spill. Two is a smell and three is a design flaw: there is no layer between the frontends and the backends, so each frontend built its own. Found by three unrelated omission probes, not by reading."
status: done
owner: claude-A
---

# The missing layer between the frontends and the backends

## The class, not the instances

| frontend | private target machinery | how it surfaced |
| --- | --- | --- |
| Pascal | the per-arch **signal runtime** — only the Pascal driver emits it at all | `EmitSignalRuntimeForTarget` refactor; [[bug-a-only-the-pascal-driver-emits-the-signal-runtime]] |
| C | the program **`_start` entry stub**, written as raw `rv32_sw` / `rv32_lw` / `EncodeRISCVJalr` in `cparser.inc:8960-9015`, with parallel arms at 8292 / 8416 / 8518 | `-dPXX_NO_RISCV32`; [[refactor-a-backend-machine-code-lives-in-six-shared-files]] |
| Zig | **`REmitParamRegSpill`** — raw x86-64 REX-byte register spill, borrowed from `rparser.inc` | `-dPXX_NO_RUST`; [[refactor-a-seven-frontends-borrow-rust-parser-helpers]] |

Each was filed as its own finding. Filing them separately was right and is also how
the class stayed invisible: three tickets, three lanes, three plausible local fixes.

This repo's own [[root-cause-over-microfix]] sets the threshold explicitly — *count
how many mechanisms serve the one concept; two is a smell, three is a design flaw.*
Three frontends, three separate implementations of "get this program started and its
registers placed on this target." None of that is a language concern. All of it is
target machinery that ended up in a frontend because **there is nowhere else for it
to go**: below `parser.inc` there is the IR and then the backends, and no layer that
owns per-target program setup independent of the source language.

So this is not three frontends misbehaving. It is one absence, observed three times.

## The corollary finding: `rparser.inc`'s `R` prefix hides three different layers

Detailed in [[refactor-a-seven-frontends-borrow-rust-parser-helpers]]; repeated here
because it is the same absence seen from the side:

- `RMakeIdent` / `RSeqAppend` / `RBinOp` — AST constructors. **Correctly shared**
  ([[the-substrate-is-ast-and-ir-not-the-parser]]: the AST *is* the substrate). Wrong
  file and wrong prefix only.
- `RWiden` — numeric widening, i.e. **one language's semantics**, which that same doc
  says must NOT be shared because "a shared parser helper couples two specs and is
  wrong in both." Zig calls it in three places **despite having no implicit numeric
  widening at all**.
- `REmitParamRegSpill` — raw x86-64, the third row of the table above.

One prefix, three layers, three different right answers. Nobody asked which layer a
function belonged to, because `R` reads as "Rust's" and that answered a question that
was never the one being asked.

## What to build

A layer that owns per-target, language-independent program machinery: entry stub,
signal runtime, parameter placement, whatever else the sweep turns up. The dispatcher
shape already exists and works — `EmitIoLockStubsForTarget` and its sibling
`EmitSignalRuntimeForTarget` are exactly this, for two functions. The job is to
recognise that as the layer and move the rest into it, then delete the per-frontend
copies. Doing so also makes `PXX_NO_RUST` stand alone (today it requires `PXX_NO_ZIG`
plus six probe defines) and removes A's need to edit `cparser.inc`, which is Track C's
file-lane, at all.

Sweep first: the three above were each found by a *different* probe, so there is no
reason to think three is the total.

## Why this ticket exists at all — the instrument, not the feature

Every instance above was found by an omission define failing to compile, and **none**
of them by reading the code. That is worth saying plainly, because it changes what the
reduced-compiler work is for:

> **The omission defines are worth more as a measuring instrument than as a shipping
> feature.**

A frontend or backend that is always compiled in cannot be observed to be entangled;
the entanglement is free until something tries to remove it. `-dPXX_NO_ADA` is the
whole argument in one line — it was the only thing in the project's history that ever
noticed the compiler's own `IntToStr` was living inside a 460-line Ada skeleton
([[bug-a-aintostr-returns-empty-for-negative-numbers]]). Nobody would have found that
by reading `aparser.inc`, because nobody has a reason to read `aparser.inc`.

The size win is real but modest and lopsided (nine frontends: −4.4 %; three host
backends: −20.7 %). The structural findings have already produced five tickets. Rank
the feature accordingly.

## Progress — the layer exists now, three pieces moved into it (2026-08-21)

Found the fourth and fifth instances of the class first, both in the NilPy
driver, both by the same probe: `--target=arm32` on a two-line `.npy`.

| # | private target machinery | frontend | status |
| --- | --- | --- | --- |
| 4 | the program **entry stub** and its **jump patch** — six arch arms in the Pascal driver, an x86-64 open-code in every other | NilPy (+ 8 more) | **moved** → `EmitProgramEntryForTarget` / `PatchProgramEntryJump` |
| 5 | **parameter spill** — ~570 lines of arch arms in the Pascal driver, `PyEmitParamSpills` in NilPy, `REmitParamRegSpill` in Rust/Zig | NilPy | **moved** → `EmitParamSpillsForTarget` |
| 5b | prologue **slot zero-init** (NilPy's Variant locals) | NilPy | **moved** → `EmitZeroLocalSlotForTarget` |

So the count is not three, it is at least five, and the sweep the ticket asked
for is what turned up 4 and 5. `EmitMmapArena` was a sixth in a weaker form: it
*Errored* for xtensa and riscv32 and silently emitted x86-64 for the other
three. It now has real i386/arm32/aarch64 arms.

All four new entry points live in `ir_codegen.inc` beside
`EmitIoLockStubsForTarget` and `EmitSignalRuntimeForTarget`, forwarded from
`frontend_forwards.inc` — the ticket's "recognise the dispatcher shape as the
layer" in literal form.

### Evidence the extraction is behaviour-preserving

25 Pascal tests × 5 targets = **120 binaries, all byte-identical** before and
after the param-spill lift (built from a stashed tree and `cmp`'d; the only
files that differed were `.map` files, which embed the output path). The
Pascal driver's local `parr` / `pbyref` / `ptypes` arrays were replaced by the
`Procs[procIdx].Params[]` fields the driver mirrors them into, and the byte
comparison is what proves that substitution is exact.

### Evidence it was worth doing

NilPy on arm32, 52 runnable `.npy` tests matching the native oracle:

```
session start   0 / 52     (nothing compiled at all)
entry stub      9 / 52
zero_sym       10 / 52     (34 BUILDFAILs cleared; then SIGILL)
param spill    36 / 52     broke=0, fixed=27
```

The jump from 10 to 36 is one deletion: NilPy's private x86-64 param spill. A
3-byte `mov rax, rdi` shifted every following ARM instruction two bytes out of
alignment, so every NilPy function taking a parameter SIGILLed with no output.
NilPy also picked up the `tySingle` narrow its copy never had.

Self-host fixedpoint + `tools/gate.sh quick` GREEN; native x86-64 `.npy` output
unchanged (the one differing line is an ASLR address in a pre-existing FAIL).

### Still open on this ticket

- ~~Row 3 (Rust/Zig `REmitParamRegSpill`)~~ — **done, same day.** Both frontends
  call `EmitParamSpillsForTarget`; `REmitParamRegSpill` is deleted. Verified by
  running all 14 Rust and Zig tests before and after: **output identical, line
  for line** (`test_rust_else_if` keeps its pre-existing rc=20). They now also
  get 1- and 2-byte params, the tySingle narrow, the >6-param all-stack path,
  and every cross target's arm for free. Zig borrowing Rust's raw x86-64 was
  the instance that named this ticket; that borrow no longer exists.
- **Row 2 (C `_start` stub)** — `cparser.inc` has its own per-target case and is
  Track C's file-lane; `EmitProgramEntryForTarget` does not yet cover its
  argc/argv + initializer/finalizer shape.
- The eight simple frontend drivers (`fparser`, `bparser`, `aparser`, `gparser`,
  `lparser`, `wparser`, `eparser`) still open-code an x86-64 entry stub; each has
  a slightly different tail, and all are x86-64-only today.

## Resolution (2026-08-21)

The layer exists and every row of the opening table is either moved into it or
handed to the lane that owns the file.

`ir_codegen.inc` now holds, as one group next to the two dispatchers that
started this:

| entry point | what it owns |
| --- | --- |
| `EmitIoLockStubsForTarget` | `--threadsafe` I/O lock stubs (pre-existing) |
| `EmitSignalRuntimeForTarget` | per-arch signal runtime (pre-existing choice) |
| **`EmitProgramRuntimeStubsForTarget`** | **THE finish-the-runtime step** — the two above, called once by every driver |
| **`EnsureSignalBss`** | the `BSS_SIG_*` storage, beside its only reader |
| **`EmitDefaultSignalInstallForTarget`** | SIGINT/SIGTERM install at program start |
| **`EmitProgramEntryForTarget`** | the entry stub (+ optional mmap heap arena) |
| **`PatchProgramEntryJump`** | its jump fixup — the half that was missed first |
| **`EmitParamSpillsForTarget`** | parameter placement, all six arch arms |
| **`EmitZeroLocalSlotForTarget`** | prologue slot zero-init |

Row by row:

| # | machinery | status |
| --- | --- | --- |
| 1 | Pascal's signal runtime | **done** — `bug-a-only-the-pascal-driver-emits-the-signal-runtime`, resolved with the shared finalisation step |
| 2 | C's `_start` stub | **handed to Track C** — `bug-c-driver-misses-the-shared-runtime-finalisation-step`. `cparser.inc` is C's file-lane; the ticket carries both the one-line call and the entry-stub question |
| 3 | Zig borrowing Rust's `REmitParamRegSpill` | **done** — deleted; both call the shared spill |
| 4 | the entry stub + its jump patch | **done** |
| 5 | NilPy's `PyEmitParamSpills` | **done** — deleted |
| 5b | NilPy's Variant-local nil-init | **done** |
| 6 | `EmitMmapArena` refusing two targets and lying to three | **done** — real i386/arm32/aarch64 arms |

The ticket's own instruction — *"sweep first: the three above were each found by
a different probe, so there is no reason to think three is the total"* — paid
for itself immediately. Three became six, and the three new ones came from one
probe: `--target=arm32` on a two-line `.npy`.

### What the layer bought, measured

NilPy on arm32, `.npy` tests matching the native oracle, over 52 runnable tests:

```
before   0 / 52     nothing compiled
after   36 / 52     broke=0 at every step
```

And Pascal's own output never moved: 25 tests × 5 targets = 120 binaries
byte-identical across both lifts.

### Left open, deliberately

The eight simple frontend drivers (`fparser`, `bparser`, `aparser`, `gparser`,
`lparser`, `wparser`, `eparser`) still open-code an x86-64 entry stub. Each has
a different tail — some emit no jump, some `call main` with their own exit
sequence — and all are x86-64-only today, so converting them is churn without a
gate. `EmitProgramEntryForTarget` is what they should call when one of them
grows a cross target. Filed as a note here rather than a ticket because there is
no defect to observe until that happens.

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
