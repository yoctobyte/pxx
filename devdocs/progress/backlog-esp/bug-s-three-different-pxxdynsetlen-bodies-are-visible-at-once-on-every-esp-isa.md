---
prio: 50
track: S
type: bug
status: backlog
found: 2026-09-21
found-by: frankB
owner: ""
blocked-by: []
summary: "compiler/builtin/builtinheap.pas defines PXXDynSetLen with the SAME signature three times (:533, :2271, :5238) and on the ESP-class ISAs at least two are visible at once, so the compiler itself warns `duplicate definition ... the later body wins, but calls written between the two bind to the earlier one`. The three bodies are NOT copies of each other -- 235, 34 and 59 lines, pairwise different -- so which one a call reaches is decided by the call's LEXICAL POSITION in the builtin, and moving a call site across a definition silently changes which allocator path it takes. Measured 2026-09-21 at HEAD and under pin v413: fires on --target=xtensa and --target=riscv32, WITH and WITHOUT --esp-profile=bare; does NOT fire on arm32, i386 or hosted x86-64, so the trigger is the ISA and not the profile. Long-standing, not a regression -- all three copies date to June 2026 (eb849b3ab, bb234753f, e3b886646) -- and unfiled until now. NO WRONG BEHAVIOUR IS OBSERVED YET: the bare qemu boot rows still diff UART clean against the x86-64 oracle, so this is a live latent hazard on the release target rather than a present miscompile. It would spring the moment a call to PXXDynSetLen is added, moved, or inlined across one of the three definitions. WARNING TO WHOEVER TAKES IT: static analysis of the {$ifdef} nesting in this file is booby-trapped -- lines 13-14 are COMMENT PROSE quoting `{$ifdef CPU_XTENSA}{$define PXX_ESP}` to describe a past bug, and a directive scanner that does not skip comments counts them and produces a confident contradictory answer (three attempts did, here). Ask the compiler which bodies it bound, do not read the conditionals."
---

# Three different `PXXDynSetLen` bodies are visible at once on every ESP ISA

## Measured

At HEAD (`compiler/pascal26 = 1a31826169bc`) and identically under pin v413
(`f94c2a7e2396`), compiling `test/test_esp_bare.pas`:

| target | `duplicate definition of 'PXXDynSetLen'` |
| --- | --- |
| `--target=xtensa --esp-profile=bare` | 1 |
| `--target=riscv32 --esp-profile=bare` | 1 |
| `--target=xtensa` | 1 |
| `--target=riscv32` | 1 |
| `--target=arm32` | 0 |
| `--target=i386` | 0 |
| hosted x86-64 (no `--target`) | 0 |

The trigger is the **ISA**, not the profile. The compiler's own text names the
hazard:

> duplicate definition of 'PXXDynSetLen' with the same parameter types; the
> later body wins, but calls written between the two bind to the earlier one

## Why this is not a harmless duplicate

The three bodies are pairwise **different**, not copies:

| definition | size |
| --- | --- |
| `builtinheap.pas:533` | 235 lines |
| `builtinheap.pas:2271` | 34 lines |
| `builtinheap.pas:5238` | 59 lines |

So "the later body wins" is not a tie-break between identical texts — it selects
between three different implementations of dynamic-array `SetLength`, and a call
site's **lexical position inside the builtin** decides which it gets.

## What is NOT established

- **Which two of the three are simultaneously active**, and under exactly which
  define combination. See the warning below.
- **Whether any call site currently sits between two definitions.** If none
  does, today's images are correct by luck of layout, which is precisely what
  makes this latent rather than academic.
- No wrong behaviour is observed: the bare qemu boot rows still diff UART clean
  against the x86-64 oracle on both chips.

## Do not read the conditionals — ask the compiler

`builtinheap.pas` lines 13-14 are **comment prose** quoting
`{$ifdef CPU_XTENSA}{$define PXX_ESP}` in order to describe a past bug. A
directive scanner that does not skip comments treats those as real and reports a
nesting stack that never unwinds, yielding impossible conditions such as
`ifdef PXX_ESP AND ifndef PXX_ESP` at one line. Three separate static attempts
produced three contradictory answers here before the approach was abandoned.

The reliable instruments are the ones used above: vary one flag at a time and
count the warning, and ask `git log -S` when each copy appeared.

## What would retire this

Either one definition per ISA with the others removed or renamed, or — if all
three are genuinely wanted — a build-time refusal when two same-signature
bodies are visible at once, so the binding can never be decided by layout.
