---
track: A
prio: 55
type: feature
blocked-by: []
summary: "Build-time selection of frontends and targets, so `only-pascal` + `only-esp-riscv` yields a small Pascal-for-ESP compiler instead of the megalith. The umbrella build stays the default. Filed with a measurement: C is nearly separable already (16 references in shared files), NilPy is NOT (1281) — so this doubles as a falsifiable test of the frontend-separation design, and NilPy already fails it."
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

## Log
- 2026-08-19 — filed with the coupling measurement above.
