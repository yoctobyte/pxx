---
track: A
prio: 55
type: feature
blocked-by: []
summary: "Build-time selection of frontends and targets, so `only-pascal` + `only-esp-riscv` yields a small Pascal-for-ESP compiler instead of the megalith. The umbrella build stays the default. Filed with a measurement: C is nearly separable already (16 references in shared files), NilPy is NOT (1281) — so this doubles as a falsifiable test of the frontend-separation design, and NilPy already fails it."
status: working
owner: frank3
---

# Build a reduced compiler by selecting frontends and targets

**Filed 2026-08-19 at the user's request.** The idea: pxx is now a big beast, but someone
who wants *only* a Pascal compiler should be able to build one. Frontend selection
(`only-pascal`, `only-pascal-and-c`, `omit-nilpy`) and target selection (`only-esp-riscv`)
compose, so `only-pascal` + `only-esp-riscv` produces a much smaller compiler. **The umbrella
megalith stays the default**; this is opt-in reduction, not a split.

The payoff the user named: *"we get the 'python compiler for esp at reduced code size' almost
for free."* Names above are deliberately verbose placeholders — **the switch spelling is
still open**, see below.

## THE ACCEPTANCE TEST, from the user 2026-08-19 — and it settles the open question below

**A reduced compiler — one frontend, one platform — must be able to build the FULL compiler
from our source.**

That is the whole test, and it is far stronger than "the reduced build passes its own tests".
It works because `compiler.pas` and every `*.inc` it pulls in — `cparser.inc`,
`pyparser.inc`, all five backends — are **Pascal text**. A Pascal-frontend-only compiler can
therefore consume the entire megalith source and emit the megalith binary:

    reduced (pascal frontend, host target)  --builds-->  full compiler
    full compiler                           --self-->    byte-identical fixedpoint

**Two properties fall out of one run.** If a stripped compiler rebuilds the unstripped one,
then the frontends and targets really are optional at build time — nothing outside them
depended on their presence — **and** the Pascal frontend is complete enough to compile the
whole project. A failure anywhere in that chain is a structural finding, which is the point:
the user's stated reason is *"to make sure we have a proper structure"*, explicitly **not** to
generate more work for Track T.

### This answers "what must a reduced compiler still self-host?"

Resolved, and more cleanly than the question was posed:

- **The Pascal frontend is what makes a build a bootstrap candidate**, because the compiler is
  written in Pascal. Any configuration including it can rebuild the full compiler.
- **A configuration WITHOUT it — a C-only or NilPy-only build — is not a self-host candidate
  at all, and that is fine rather than a problem.** It is a consumer artifact, gated on its
  own frontend's tests. The fixedpoint gate does not apply.

### One precision the phrase "single frontend and platform" needs

**The target must be the HOST platform for this test to mean anything.** A Pascal-only build
restricted to `esp-riscv` can only emit esp-riscv binaries — it would produce an esp-riscv
"full compiler" that does not run here. True, and useless as a check. **The structural test is
Pascal frontend + host target → full compiler → fixedpoint.** Reductions to a cross target are
the *product*, not the test.

## Why this is worth doing beyond the binary size

**It is a falsifiable test of a design claim we make constantly.**
`devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md` says share the AST and IR,
duplicate the lexer/parser per language. If that has actually been honoured, omitting a
frontend is deleting some `{$include}` lines. **Where it is NOT trivial, that is a
measurement of coupling we currently have no other way to take** — and it points at real
design debt rather than at this ticket being hard.

## MEASURED BEFORE FILING — the premise holds for C and fails for NilPy

Reference counts of frontend-specific identifiers inside the SHARED files:

| shared file | NilPy refs | C refs |
| --- | --- | --- |
| `parser.inc` | **909** | 6 |
| `ir.inc` | 165 | — |
| `defs.inc` | 96 | 4 |
| `symtab.inc` | 85 | 3 |
| `ir_codegen.inc` | 26 | — |
| `lexer.inc` | **0** | 3 |
| **total** | **~1281** | **16** |

**Read this honestly: these are counts of REFERENCES, not of edit sites.** Many of the 909
will cluster into a handful of regions, and the number that actually need a guard is unknown
until someone looks. It is an order-of-magnitude signal, not a work estimate — treat it the
way this repo treats every "population where a problem is possible" figure.

**What it does establish:**

- **`omit-c` is close to the user's "trivial".** 16 references across four files, and the C
  frontend is genuinely its own `clexer.inc` / `cparser.inc` / `cpreproc.inc` (15,594 lines).
  R and Z, being greenfield, should be at least as clean.
- **`omit-nilpy` is NOT.** `pyparser.inc` is 35,682 lines and carved out — but **909 NilPy
  references live in the shared `parser.inc`**, plus 165 in `ir.inc`.
- **`lexer.inc` has ZERO NilPy references**, which is the useful contrast: the *lexer* was
  genuinely carved out to `pylexer.inc`, and the *parser* was not.

### This corrects a claim in CLAUDE.md

CLAUDE.md describes Track N as having "its own carved-out files" and contrasts it with Track
P, whose frontend "still lives inside the SHARED `lexer.inc`/`parser.inc`". **Measured, that
is half right.** N's lexer is carved out; N's parser is not — `parser.inc` carries 909 NilPy
references, more than P's own coupling is usually described as costing. This is very likely
why NilPy work keeps colliding with the A/P slot.

**That finding is worth more than this ticket** and should be checked before anyone plans
frontend work on the strength of the current wording.

## Shape of the work

- **Precedent exists:** `compiler.pas` already guards includes conditionally
  (`{$ifdef PXX_NEED_FORWARDS}{$include forwards.inc}{$endif}`), so the mechanism is in use,
  not new.
- **Targets look genuinely separable:** five backend files —
  `ir_codegen386` / `_aarch64` / `_arm32` / `_riscv32` / `_xtensa` — plus the shared
  `ir_codegen.inc`. Verify before assuming; a shared dispatch table keyed on target is the
  likely bear.
- **Suggested order, cheapest-proof-first:** targets, then `omit-c`, then R/Z, and **NilPy
  last** — by which point the 909 will have been characterised rather than guessed at.

## Open questions (do NOT guess — file `decide-*` or ask)

- **Switch spelling and composition.** `only-pascal` vs `omit-c` vs a positive list; how
  frontend and target selection compose. The user flagged the names as placeholders.
- **What a reduced compiler must still self-host.** A Pascal-only build compiling
  `compiler.pas` is coherent; a **C-only** build cannot self-host at all, since the compiler
  is written in Pascal. So the self-host gate is meaningful for some configurations and
  meaningless for others, and the gate must know which. **This is the sharpest bear on the
  road and it is a design question, not an implementation one.**
- **How the matrix is tested.** Every configuration is a build that can rot silently. Track T
  will need an opinion, and testing all combinations is not affordable — a small set of named
  configurations probably is.

## Gate

Track A's: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick` for the umbrella
build, which must stay byte-identical — **a reduction feature that perturbs the default build
has failed.** Each named reduced configuration additionally needs to build and pass its own
frontend's tests.

**Plus the structural test above**, which is the one that earns the ticket: a Pascal-only,
host-target build produces the full compiler, and that binary reaches its own byte-identical
fixedpoint.

**And measure the second payoff rather than asserting it.** The other motivation is a smaller
and *therefore faster* compiler — "we only do Python, on ESP". Smaller text is a good reason to
expect better instruction-cache behaviour and shorter dispatch, but **faster is a claim about
wall-clock, not about bytes**. Report the size delta AND a compile-time measurement on a fixed
workload. If size drops and time does not, that is worth knowing and does not invalidate the
feature — code size is a legitimate goal on its own for an embedded toolchain.

## Log
- 2026-08-19 — filed with the coupling measurement above.

---

## MEASURED BY OMISSION (frank3, 2026-08-19) — the suggested order is inverted

The filing measurement counted **references to frontend-specific identifiers** and said so
honestly ("an order-of-magnitude signal, not a work estimate"). It is worth replacing,
because the reference count and the thing it stands in for disagree by two orders of
magnitude in one direction and one in the other.

**Method — the compiler is the oracle, not a grep.** Comment out a component's `{$include}`
lines in `compiler.pas`, compile with FPC (`-Se999`, so it reports everything instead of
stopping at 50), count what breaks. A scratch copy of `compiler/` plus `lib/asmcore`
compiles clean in **4 seconds**, so the whole matrix is a couple of minutes. Nothing here is
inferred.

| omit | errors | files | where the coupling is |
| --- | --- | --- | --- |
| **zig** | **3** | 1 | compiler.pas |
| **nilpy** | **7** | 3 | compiler.pas:6, parser.inc:1, rtti_emit.inc:1 |
| **arm32** | **8** | 3 | asmfront.inc:6, ir_codegen.inc:1 |
| **i386** | **10** | 4 | asmfront.inc:6, ir_codegen_arm32.inc:2 |
| **aarch64** | **10** | 3 | asmfront.inc:6, ir_codegen.inc:3 |
| **cfront** | **11** | 2 | compiler.pas:10, parser.inc:1 |
| rust | 200 | 7 | zparser.inc:123, gparser.inc:23, eparser.inc:23, fparser.inc:19 |
| **xtensa** | **288** | 5 | symtab.inc:179, parser.inc:62, exception_emit.inc:45 |
| **riscv32** | **518** | 7 | symtab.inc:222, cparser.inc:123, exception_emit.inc:91, parser.inc:74 |

(Errors, not edit sites: one guard can silence several, and a few are cascades. Read it as an
upper bound with a reliable ORDER.)

### What this changes

**1. NilPy is the CHEAPEST frontend to omit — 7 errors, fewer than C's 11.** The ticket puts
it last, on the strength of 1281 references of which 909 are in `parser.inc`. Both figures are
real; they just do not measure separability. Those 909 are NilPy-aware *behaviour* inside the
shared parser (`if isNilPy then ...`), which stays compiled and inert when `pyparser.inc` is
gone. The compile-time surface is seven names:

    PyLexAppend  PyDfltPendFor  PyDcEqProc  PyDcReprProc  PyExpandFStrings
    PyLexAll  ParsePyProgram

**So the design claim in `the-substrate-is-ast-and-ir-not-the-parser.md` HOLDS for N**, and
the correction the ticket makes to CLAUDE.md ("N's parser is not carved out") is itself half
right: N's parser *file* is carved out cleanly — what is not carved out is the shared parser's
knowledge of N, which is a different property and does not block reduction.

**2. Targets are the bear, not the cheap first step.** `riscv32` (518) and `xtensa` (288) are
20-70x the cost of any frontend. The cause is not dispatch — it is that shared code **emits
instructions inline**: `symtab.inc`, `exception_emit.inc` and `parser.inc` reference
`reg_t0` (81), `reg_sp` (62), `rv32_sw` (49), `rv32_lw` (38) and friends directly, and
`cparser.inc` carries 123 of them. x86-64 has no `ir_codegen_x64.inc` at all — it lives
inside the shared `ir_codegen.inc`, so **the default target is not omittable by this
mechanism** and would need a different one.

**3. The flagship configuration dodges the expensive work entirely.** The user's stated
payoff is *"a python compiler for esp at reduced code size"* = keep NilPy, keep xtensa and
riscv32, drop the rest. The costly omissions are exactly the two targets that configuration
KEEPS. `only-nilpy + only-esp` needs: omit cfront (11), rust (200 — see below), zig (3),
i386 (10), arm32 (8), aarch64 (10). **Do the cheap six and the headline configuration exists.**

**4. R and Z share helpers, which is a genuine finding against the design rule.** Omitting
`rparser.inc` breaks `zparser.inc` in 123 places, plus `gparser`/`eparser`/`fparser` — the
greenfield frontends call each other's support functions, which is the exact thing
`the-substrate-is-ast-and-ir-not-the-parser.md` says not to do ("duplicate the parser, the
lexer and their support functions per language"). Worth its own ticket; it makes R and Z
individually unomittable while costing nothing today.

**5. One misplacement, cheap to fix.** 6 of `cfront`'s 11 errors are `AddPasUnitDir` /
`AddPasIncDir` — generic search-path functions that happen to live in `cpreproc.inc`. Moving
them to a shared file drops `omit-c` from 11 to ~4. Not coupling; filing.

### Revised order of attack

1. **`omit-zig`, `omit-nilpy`, `omit-cfront`** (3, 7, 11) — cheapest, and they prove the
   mechanism end to end. Move `AddPasUnitDir` out of `cpreproc.inc` first.
2. **`omit-i386` / `omit-arm32` / `omit-aarch64`** (8-10 each, nearly all in `asmfront.inc`).
   After 1 and 2, `only-nilpy + only-esp` is reachable.
3. **`omit-rust`** — blocked on untangling R/Z's shared helpers; file separately.
4. **`omit-riscv32` / `omit-xtensa`** last, and only if wanted: 800 errors between them,
   caused by inline instruction emission in shared files. This is the real design debt the
   ticket hoped to surface, and the flagship configuration does not need it.

### Escalated, not guessed

Both open questions are filed to Track U rather than settled here:
[[decide-reduced-compiler-switch-spelling]] and
[[decide-what-a-reduced-compiler-must-still-self-host]].

### The acceptance test and the measurement above INTERACT — read them together

The structural test is **Pascal frontend + host target**. Against the omission table that is
not the cheap corner of the matrix, and it is worth knowing before picking a first
configuration:

- **Frontend side: cheap.** Pascal-only means omitting cfront (11), nilpy (7), zig (3) and
  rust (200, blocked on R/Z's shared helpers) — plus the small frontends (`b`, `l`, `f`, `g`,
  `e`, `w`, `a`), unmeasured but each a few hundred lines.
- **Target side: this is where the bear lives.** "One platform" = host = x86-64, so it means
  omitting **riscv32 (518) and xtensa (288)** — the two most entangled components in the
  tree. The structural test therefore *requires* the expensive omissions, while the product
  configuration (`only-nilpy + only-esp`) *keeps* them. The cheap path does not reach the
  test.

**So split the two rather than blocking one on the other:**

1. **Frontend reduction first, all targets kept.** `pascal-only`, host build, still emitting
   every target. That is ~220 errors' worth of guards (200 of them rust's tangle) and it
   already proves most of the acceptance test's claim: a compiler with ONE frontend rebuilds
   the megalith, so nothing outside the frontends depended on their presence. **Cheapest run
   at the real property.**
2. **Target reduction second**, which is where `riscv32`/`xtensa`'s 800 inline-emission
   references have to be untangled, and which completes "one frontend, one platform".
3. The **product** (`only-nilpy + only-esp`) needs neither of those two omissions and is
   reachable from step 1's mechanism alone.

Stating it because "one frontend, one platform" reads as a single step and is two, with the
expensive half not on the path to the user's stated payoff.

### The speed claim carries a measurement obligation

The second motivation is a smaller *"and hence faster"* compiler. Smaller text is a fair
reason to EXPECT better i-cache behaviour and shorter dispatch, but **faster is a wall-clock
claim and bytes are not**. Whoever lands a configuration reports both: the size delta and a
compile-time measurement on a fixed workload, on the same pin (see
[[measure-before-and-after-on-the-same-pin]]'s hazard — a mid-session pin bump steals the
credit). **If size drops and time does not, say so** — code size is a legitimate goal on its
own for an embedded toolchain, and an unmeasured speed claim is exactly the kind that gets
quoted back at us.

---

## CORRECTION TO MY OWN MEASUREMENT — and the mechanism, landed for Zig and C

**The omission counts above were TRUNCATED, and the NilPy conclusion drawn from them was
wrong.** FPC stops at the first fatal ("There were 7 errors compiling module, stopping"), so
each run reported only the first layer and hid every later one — forward-declaration
resolution in particular. I read a truncated list as a complete one and concluded NilPy was
the cheapest frontend to omit. It is the most expensive.

**This is the same failure the previous ticket in this lane was about**: a mechanism reporting
on something adjacent to what was asked. `grep` counted references, which is not
separability, so I replaced it with the compiler — and then read the compiler's *first
layer* as its whole answer. The fix each round was to guard what it named, recompile, and see
what appeared underneath; four rounds, ~4 seconds each.

**True compile-time surface, distinct names:**

| omit | distinct names | verdict |
| --- | --- | --- |
| **zig** | **0** | clean the moment the includes are guarded |
| **cfront** | **9** | `CLexAppend` `CLexAll` `ParseCProgram` `CPreprocess` `AddDefaultCIncludeDirs` `ParseCUnit` `RegisterCMacroConsts` `CNodeDecaysToPointer` `FindCTypedef` |
| **nilpy** | **183** | 177 forward declarations in `parser.inc` + 6 helper calls |

A forward declaration in `parser.inc` means the shared parser CALLS that body, so those 177
are real coupling, not bookkeeping. **The ticket's original 909-reference figure was
directionally right about NilPy after all, and my first correction of it was wrong.** The
useful part of my revision survives: the 909 are not 909 edit sites, they are 183 names —
one order of magnitude down, not two.

**The target numbers (riscv32 518, xtensa 288) are from the same truncated runs and are
therefore LOWER bounds.** They stay last in the order for the same reason as before.

### What landed

`PXX_NO_ZIG` and `PXX_NO_CFRONT`, both building clean, plus the mechanism the rest will use:

    default                          3,376,496 bytes   (FPC seed build)
    -dPXX_NO_ZIG                     3,336,832
    -dPXX_NO_CFRONT                  3,153,568
    -dPXX_NO_ZIG -dPXX_NO_CFRONT     3,112,496        -7.8%

**`compiler/frontend_stubs.inc`** holds one stub per shared-code entry point of an omitted
frontend, rather than a guard at each of its ~40 call sites: one place that records the fact
beats forty that re-derive it, and a guard forgotten at one site is a compile error in a
configuration nobody builds that day. **Every stub raises rather than returning a plausible
value** — each is unreachable by construction (its call site sits behind `if isNilPy` or the
C dispatch arm, and a compiler without the frontend refuses that source at dispatch), so a
stub that quietly returned 0 would convert "this build has no C frontend" into a wrong answer
far away.

`AddPasUnitDir` / `AddPasIncDir` moved out of `cpreproc.inc` into `lexer.inc`
([[refactor-a-search-path-helpers-live-in-the-c-preprocessor]], now done as part of this —
it was a blocker, not a cleanup: `-Fu` cannot be guarded out, it must work in a C-less build).

The default build is untouched: self-host fixedpoint converges and `gate.sh quick` is GREEN.

**`PXX_NO_NILPY` was deliberately NOT landed.** A half-implemented define that fails to
compile is a trap for whoever tries it next, so the partial guards were reverted rather than
shipped. Its 183 names are the next step and are mechanical but not trivial — each needs a
correct signature and a decision about what an unreachable body should do.
