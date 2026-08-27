---
slug: refactor-a-target-properties-have-no-single-answer
title: "Six targets answer \"how wide is a pointer\" in six voices, and there is no helper to ask"
track: A
prio: 80
type: refactor
blocked-by: []
status: urgent
owner: ""
created: 2026-08-27
unblocks: feature-target-wasm
summary: "There is no TargetPtrSize / TargetIs32 anywhere in compiler/ — 36 files ask TargetArch directly, in raw if/else-if chains with an implicit x86-64 fallthrough. Adding a 7th target means every chain that forgot an else silently answers 64-bit; in symtab.inc that is pointer width and record layout, i.e. wrong offsets with no diagnostic. Land the helpers BEFORE the 7th target exists, not after."
---

# The measurement

No such helper exists. Measured 2026-08-27:

```
$ grep -rnE 'function (PtrSize|PointerSize|Is32|IsTarget32|TargetPtrSize)' compiler/*.inc
(no output)
```

Instead, 36 files reference `TargetArch` directly. Density:

| file | `TargetArch` refs |
| --- | --- |
| `ir_codegen.inc` | 83 |
| `symtab.inc` | 47 |
| `cparser.inc` | 31 |
| `elfwriter.inc` | 27 |
| `compiler.pas` | 23 |
| `asmfront.inc` | 22 |
| `ir.inc` | 21 |
| `lexer.inc` | 19 |
| `emit.inc` | 15 |
| 27 more | 1-12 each |

And the shape is a raw chain, e.g. `symtab.inc:8849`:

```pascal
  if TargetArch = TARGET_I386 then ...
  if TargetArch = TARGET_ARM32 then ...
  if TargetArch = TARGET_AARCH64 then ...
  if TargetArch = TARGET_XTENSA then ...
  if TargetArch = TARGET_RISCV32 then ...
```

`lexer.inc:936` is the same idea in `else if` form with no final `else`.

# Why this is a bug generator, not a tidiness complaint

The chains are *complete today* — six targets, all enumerated, nothing broken.
That is exactly what makes them dangerous. They are `if` / `else if` with an
**implicit x86-64 fallthrough**: a target that no arm matches gets the 64-bit
answer, silently, with no diagnostic.

So adding a 7th target does not fail loudly at the chains that forgot it. In
`symtab.inc` the questions being asked are pointer width and record layout, so
the failure is **wrong field offsets in a target that otherwise builds, links
and runs** — the exact "plausible wrong value far from the cause" that
`devdocs/dev/debugging-playbook.md` says is the expensive case here.

This is `devdocs/dev/normalise-dont-special-case.md` applied to the target axis:
one concept ("is this target 32-bit / how wide is a pointer") served by dozens
of mechanisms. Two is a smell; this is 36 files.

# Proposed surface

A single site — `defs.inc` or `util.inc` — with a `case TargetArch of` and a
**mandatory `else Error(...)`**, so that adding a target is loud at exactly one
place instead of silent at thirty:

```pascal
function TargetPtrSize: Integer;    { 8 or 4 }
function TargetIs32: Boolean;
function TargetStackAlign: Integer;
function TargetIsLittleEndian: Boolean;   { if any chain asks this }
```

Then convert the **width/size/layout-related** chains to call them. Explicitly
NOT in scope: chains that genuinely dispatch per-ISA (register names, encoding,
ABI arg registers). Those are real per-target code and should stay a `case`.

The audit is "which of the 36 files ask a *property* question vs an *identity*
question" — the answer is the ticket's actual work.

# Acceptance test (strong, and cheap)

This is a pure refactor, so the bar is byte-identity of output, not a new
behaviour test:

1. Pick a fixed corpus (a handful of `test/` programs).
2. Compile each for all six targets with the **pinned** compiler; keep the
   binaries.
3. Apply the refactor, `make compiler/pascal26` (must converge byte-identical).
4. Recompile the same corpus for all six targets. **Every output binary must be
   byte-for-byte identical to step 2.**

Any diff is a chain that was answering something other than what the helper
answers — which is the finding, not a nuisance.

# Why urgent

It is the prerequisite for `feature-target-wasm` (a 7th target, wasm32 — 32-bit
pointers, which is precisely the property these chains get silently wrong), and
that work is blocked on it.

But the urgency is not the wasm schedule. It is that doing this **before** the
7th target exists is a refactor with a byte-identical acceptance test, and doing
it **after** is remediation of a bug class already spread through a new backend.
The cost difference is the whole ticket.

## Log
- 2026-08-27 — filed from the wasm-target scoping session. Findings and the
  full target-side accounting: `devdocs/dev/wasm-target-findings.md`.
