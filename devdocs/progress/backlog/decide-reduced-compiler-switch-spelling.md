---
track: U
prio: 55
type: decide
blocked-by: []
summary: "How does a reduced build get selected — subtractive (`omit-c`), positive-list (`only-pascal`), or a named-configuration file? And do frontend and target selection compose freely or only in blessed combinations? The user flagged the names in the parent ticket as placeholders. Recommendation: subtractive defines as the mechanism, named configurations as the tested surface."
---

# Reduced-compiler build: how is the reduction spelled?

Fork raised by [[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]],
which flags `only-pascal` / `only-pascal-and-c` / `omit-nilpy` / `only-esp-riscv` as
deliberate placeholders. Filed rather than guessed: this is the user-facing surface of the
feature and it is cheap to decide now, expensive to rename once configurations are documented,
tested and shipped.

## What the measurement says, because it constrains the answer

Omitting a component is guarding the sites that break when its `{$include}` goes away
(measured by omission on 2026-08-19; full table in the parent ticket):

    zig 3 · nilpy 7 · arm32 8 · i386 10 · aarch64 10 · cfront 11 · rust 200 · xtensa 288 · riscv32 518

Two consequences for the spelling:

- **The mechanism is inevitably subtractive.** Each component gets a `{$ifndef PXX_NO_X}`
  around its include and its call sites; the default defines nothing and is byte-identical.
  A *positive* list (`only-pascal`) has to be translated into that same set of negatives
  somewhere, so the question is not which mechanism but **which spelling the user types**.
- **Not every combination is meaningful.** x86-64 has no `ir_codegen_x64.inc` — it lives
  inside the shared `ir_codegen.inc` — so "omit the host target" is not expressible by this
  mechanism at all, and `only-esp-riscv` cannot mean "drop x64 codegen" today.

## Options

1. **Subtractive defines only.** `make PXX_OMIT="c nilpy zig"`. Honest about the mechanism,
   composes freely, no translation layer. Cost: the user's own framing was `only-pascal`, and
   spelling that means listing eight things to omit and keeping the list correct as frontends
   are added — a new frontend silently joins every "reduced" build.
2. **Positive list, translated.** `make PXX_ONLY="pascal esp"`. Matches how the user talks
   about it and is future-proof: a new frontend is absent unless named. Cost: a translation
   table in the Makefile that must know every component, and the awkward case above
   (`only-esp` still ships x64 codegen, so the name overpromises).
3. **Named configurations.** A small set — `full` (default), `pascal-host`, `nilpy-esp` —
   each a fixed define set, with no free composition. Cost: no ad-hoc reduction; every new
   combination is a commit.
4. **Both: subtractive underneath, named configurations as the tested surface.**

## Recommendation

**4.** The mechanism is subtractive because the code is; the *supported* surface is a handful
of named configurations, because that is also the only surface Track T can afford to test —
the parent ticket's own open question about the matrix answers itself here, as every
configuration is a build that can rot silently and the combinatorial set cannot be swept.
Free composition stays available and unsupported: `PXX_OMIT="..."` works, is documented as
best-effort, and gates on nothing.

Named set to start, driven by the two motivations on record:

    full         (default, byte-identical, the only pinned artifact)
    pascal-host  the STRUCTURAL TEST: one frontend, host target, must rebuild the full compiler
    nilpy-esp    the PRODUCT: the user's "python compiler for esp at reduced code size"

## What is NOT being asked here

**What a reduced compiler must still self-host is already ANSWERED** by the user
(2026-08-19), in the parent ticket: a reduced build must be able to build the FULL compiler
from source, which requires the Pascal frontend and the host target. A configuration without
the Pascal frontend is not a self-host candidate and is gated on its own frontend's tests
instead. No decision needed; recorded here so this ticket is not read as reopening it.
