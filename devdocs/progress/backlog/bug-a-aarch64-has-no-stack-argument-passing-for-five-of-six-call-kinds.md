---
track: A
prio: 55
type: bug
blocked-by: []
summary: "aarch64 refuses `> 8` arguments at SIX separate sites — constructor, external, variadic external, cdecl indirect, indirect, virtual — while the DIRECT call passes stack args fine. One mechanism (AAPCS64 stack arguments) missing, refused six times. It is the live wall stopping NilPy from building for aarch64 AT ALL: `print(1+1)` dies on the indirect-call arm out of pyeval.pas, so ~53 .npy tests are cross-blind on that target."
status: backlog
owner: frankS
---

# aarch64: no stack-argument passing for five of six call kinds

- **Track A** (aarch64 backend / ABI). Found 2026-08-31 by frankS while
  measuring NilPy object lifetime; not caused by that work — it reproduces on
  `pinned`.
- **frankA has said they will pick this up after
  `bug-a-xtensa-cannot-widen-a-forward-call`.** Filed rather than messaged
  because it is an overhaul, not a fix: see the sibling note below.

## The repro

```sh
printf 'print(1+1)\n' > /tmp/h.npy
./compiler/pascal26 --target=aarch64 /tmp/h.npy /tmp/h_a64
# pascal26:2837: error: target aarch64: indirect call with more than 8 parameters
#   not supported
#   in: ./compiler/builtin/pyeval.pas
```

`print(1+1)` — nothing about the program reaches this. It is `pyeval.pas`, which
every NilPy compilation links.

## The six sites, all in `compiler/ir_codegen_aarch64.inc`

| line | kind |
| --- | --- |
| 2608 | constructor |
| 3056 | external call |
| 3090 | variadic external call |
| 3265 | cdecl indirect call |
| 3309 | indirect call ← the one NilPy hits |
| 3367 | virtual call |

The **direct** call is the only kind that passes arguments on the stack, so the
capability exists in the backend and five callers do not reach it. AAPCS64 is
one rule for all six: x0-x7 then 8-byte stack slots, callee-cleaned.

## Why an overhaul, not a seventh microfix

`bug-a-aarch64-cannot-build-programs-with-an-aggregate-result-past-8-params` is
already in `done/` — the same wall, fixed once, on the arm that happened to be
hit. **That fix had six siblings and none were grepped for**, which is exactly
what `devdocs/dev/normalise-dont-special-case.md` says to check before closing.
Six `Error(...)` calls that differ only in a noun are one missing mechanism
wearing six names. Extract the arg-marshalling loop once and delete all six.

## What it is worth

- **NilPy on aarch64 at all** — today: zero .npy programs compile for that
  target. That is what makes
  `feature-nilpy-object-reclamation`'s item 4 (the aarch64 inline
  `EmitVariantClearA64`/`RetainA64` object arms) untestable: there is no NilPy
  program to test it with.
- Corrects `bug-a-nilpy-on-cross-targets-four-remaining-walls`, whose table
  still names the older `aggregate result with more than 8 params` message.
- Every `> 8`-param Pascal program on aarch64, which nobody has counted.

## Not this ticket

The i386 (`symbol kind not supported yet (load)`), riscv32/xtensa (bare-metal
mmap) and wasm32 (`SYS_openat`) NilPy walls. They live on
`bug-a-nilpy-on-cross-targets-four-remaining-walls`.
