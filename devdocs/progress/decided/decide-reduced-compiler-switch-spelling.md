---
track: U
prio: 55
type: decide
blocked-by: []
status: decided
owner: user
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

## ANSWER (user, 2026-08-21)

> *"we only need 'omit' — and the makefile can have some sane prefabs"*

**One mechanism: `PXX_OMIT`. No positive-list translation layer. The Makefile
carries a few prefab targets that expand to an omit list.**

So of the four options: **1 as the mechanism**, with prefabs playing the role
option 4 wanted named configurations to play — but as ordinary Makefile targets
spelling out an omit list, not a second surface with its own semantics.

    make PXX_OMIT="c nilpy zig"     # free composition, best-effort, gates on nothing
    make nilpy-esp                  # a prefab: expands to the omit list above it

The positive list (option 2) is rejected: it buys "a new frontend is absent
unless named" at the price of a translation table that must know every
component, and a name that overpromises (`only-esp` still ships x64 codegen,
because x86-64 has no `ir_codegen_x64.inc` — it lives inside the shared
`ir_codegen.inc`). A prefab is a list someone maintains in one visible place,
which is the same guarantee without the layer.

## State of the mechanism when this was answered

Already **13 components deep** and proven — the guards exist and are in use:

    PXX_NO_ARM32  PXX_NO_AARCH64  PXX_NO_I386  PXX_NO_CFRONT  PXX_NO_ZIG
    PXX_NO_RUST   PXX_NO_ADA      PXX_NO_LOLCODE  PXX_NO_FORTRAN
    PXX_NO_ERLANG PXX_NO_BASIC    PXX_NO_ALGOL    PXX_NO_WHITESPACE

What is missing is only the user-facing surface: **the Makefile has no
`PXX_OMIT` and no prefab targets**. That is the whole of this ticket's
implementation.

Note the seven obscure ones (ADA, LOLCODE, FORTRAN, ERLANG, BASIC, ALGOL,
WHITESPACE). Nobody composing a minimal build by hand will remember to omit
them, which is exactly the job the prefabs do — a prefab that forgets one
silently ships it, so a prefab's omit list is the thing to review when a
component is added.

## Which prefabs are affordable, measured

The guards that exist are the **cheap** ones. `xtensa` (288 sites) and
`riscv32` (518) have none, which inverts the difficulty of the two
configurations this ticket proposed:

- **`nilpy-esp` (the product) is nearly reachable today.** It *keeps* xtensa and
  riscv32, and everything it drops — cfront, rust, zig, aarch64, arm32, i386 —
  is already guarded. Only dropping the Pascal frontend is new work.
- **`pascal-host` (the structural test) is the expensive one.** It must drop
  xtensa and riscv32: those 806 unguarded sites.

So ship `nilpy-esp` first. Name `pascal-host` if wanted, but as not-yet-buildable
rather than a promise backed by guards nobody has written.

## Related, decided the same day

[[decide-tobject-root-methods-dispatch-model]] added `--compact-classes`, which
the ESP target turns on by default. That is a *codegen* flag, not a build-time
omission, so it does not belong in `PXX_OMIT` — but an ESP-facing prefab is the
natural place to document that the two travel together.
