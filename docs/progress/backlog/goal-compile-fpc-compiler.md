# 🗼 Lighthouse — compile the FPC compiler (`pp.pas`) with PXX

- **Type:** goal (lighthouse / end-goal — NOT a sprint ticket)
- **Status:** backlog
- **Opened:** 2026-06-18
- **Nature:** a fixed point on the horizon to steer by, not a task to schedule.
  Attempting it will avalanche into many concrete tickets; those are the work,
  this is the bearing. Do not "start" this ticket — it resolves when the corpus
  ladder below reaches the top.

## The goal

PXX compiles the Free Pascal Compiler's own source (`compiler/pp.pas` and its
unit graph) and the produced `fpc'` works. The point is **conformance**: the
FPC compiler source is the largest, most edge-case-dense real Object Pascal
corpus available, so compiling it correctly proves dialect conformance at
industrial scale — not on toy tests. The motive is better software built on
50 years of borrowed Pascal language design; this is how we prove we inherited
it correctly.

## Acceptance = the differential oracle (not "it runs")

The bar is not "pp.pas compiles." It is:

1. PXX compiles FPC source → `fpc'`.
2. `fpc'` compiles a real corpus, and its **output matches upstream FPC's output
   byte-for-byte**.

A match is a brutal, end-to-end correctness signal. "Compiles and runs" is a
weaker waypoint; the differential match is the proof.

## Evidence — what the FPC compiler source ACTUALLY uses

Empirical grep over `/home/rene/src/fpc-source/compiler` (FPC 3.2.2, 861
`.pas/.pp/.inc` files), 2026-06-18. Distinguishes features the compiler
**implements** from features its **own source uses** — they are very different.

| Feature | Real usage in compiler source | A gate to compile pp.pas? |
| --- | --- | --- |
| Generics (`generic T = …`) | **0 declarations** (112 file hits = comments + the compiler's own handling of generics) | ❌ no |
| Interfaces (`= interface`) | 2 files | ❌ negligible |
| Operator overload | 4 files | ❌ negligible |
| Variants (as a type) | ~0 (hits = comments / case-variant *records*) | ❌ no |
| inline `asm` bodies | 4 files | minor (codegen emits via nodes, not `asm{}`) |
| `{$mode objfpc}` | uniform / consistent | ✅ dialect breadth |
| `bestreal` / `extended` | **35 files** | ✅ **the one real language gate** |
| classes / objects / virtual | pervasive | ✅ already have |

**Conclusion:** the FPC compiler source is *linguistically conservative* — same
discipline PXX used to bootstrap itself. The big ecosystem features (generics,
interfaces, operators, variants) are NOT needed to compile the compiler. They
gate the *ecosystem* corpus (Lazarus / packages), a separate and larger climb.

### Principle — implements-vs-uses

A compiler implements a huge feature set; its source uses a small subset. Choose
corpus rungs by what each *uses*. The compiler-source rung needs far less than
the ecosystem rung — do not price it as if it needed the whole dialect.

## Two mountains (keep them separate)

1. **Language conformance** — compile the Pascal. Turns out conservative (table
   above): full classes (have), `{$mode objfpc}` breadth, **extended-precision
   constant folding** (35 files), heavy conditional compilation, likely
   nested-procedure frame capture. Achievable.
2. **Build-system / toolchain compat** — acting as a drop-in `fpc`: same CLI
   flags, the undocumented version-locked **`.ppu`** precompiled-unit binary
   format, `ppas`, fpcmake. Brutal (the `.ppu` format especially) — **and
   AVOIDABLE.**

### Avoid mountain 2: whole-program compile

For the conformance proof, point PXX at `compiler/pp.pas` and **compile
whole-program from source** — PXX follows `uses` and compiles every unit in one
shot. No `.ppu`, no make, no `fpc`-CLI emulation. The makefile/aliasing
complexity is only needed for a *drop-in `fpc` replacement* — a different, much
later, maybe-never goal. Do NOT let it block the proof.

## The one real language gate — extended precision

FPC uses `bestreal` (= `extended` 80-bit on x86; = `double` off-x86) for
constant folding so folded constants carry max target precision.

- For **"compiles and runs"** — irrelevant; double folding works.
- For the **differential bar** — it matters: if `fpc'` folds float constants at
  double but upstream folds at 80-bit, emitted float constants differ in low
  bits → diff fails on float-constant-heavy code.

**Honesty note:** do the proof on **x86-64 first**, where `extended` is real.
Off-x86 a PXX-built FPC inherits the *same* reduced precision FPC itself has
there (FPC drops `extended`→`double` off-x86) — conformance-preserving, not a
PXX defect; document as inherited.

## The corpus ladder (the climb that resolves this lighthouse)

Each rung exposes the next missing feature → a concrete ticket → fix → corpus
grows. Metric = kLOC of real FPC compiling+matching, not a binary done.

```
Lazarus helloworld (DONE) → Synapse (in progress) → mid-size FPC libs
  → FPC RTL units → compiler/pp.pas (whole-program)  ← the differential summit
```

- Ecosystem rungs (libs/RTL/Lazarus) trip the big gates: generics, interfaces,
  operator overload, managed records. Those become their own tickets when hit.
- The compiler rung trips only the conservative gates above.
- Both climbs share the dialect-completeness work already on the roadmap
  (feature-mimic-fpc, feature-fpc-vs-pxx-feature-boundary, byte-identical
  self-host).

## Known unknown

A prior manual attempt halted on a first blocker (not recorded). When the climb
resumes, re-run `pp.pas` whole-program through PXX and capture the first error
as the first concrete sub-ticket.

## Log
- 2026-06-18 — opened as a lighthouse (end-goal), grounded in an empirical grep
  of FPC 3.2.2 compiler source (not speculation). Findings: compiler source is
  linguistically conservative — generics/interfaces/operators/variants NOT used;
  real gates = classes (have) + objfpc-mode breadth + extended-precision
  constant folding (35 files) + conditional compilation + nested-proc frames.
  Acceptance reframed to the differential oracle (`fpc'` output == upstream).
  Two mountains separated: language conformance (achievable) vs build-system/
  .ppu compat (avoidable via whole-program compile of pp.pas). x86-first for the
  extended gate; off-x86 precision is inherited from FPC, not a PXX defect.
