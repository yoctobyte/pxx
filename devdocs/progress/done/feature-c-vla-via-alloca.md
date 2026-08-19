---
track: C
prio: 50
type: feature
status: done
owner: claude@frank2
---

# C variable-length arrays, lowered through alloca

`int arr[n]` with a runtime `n` is now REFUSED with a named error
([[bug-cfront-vla-stack-corruption]] — it used to be sized at ZERO and sit on
top of the next stack slot, so a loop over it clobbered its own counter and
stopped after two iterations, silently). Refusing is the honest state, not the
finished one: `char buf[len]` is ordinary real-world C.

## The design, worked out while fixing the corruption

The pieces already exist, which is what makes this a bounded feature rather than
a new mechanism:

- `AN_ALLOCA` is implemented and gated (`feature-c-alloca-dynamic-stack`,
  cparser.inc — `alloca(n)` / `__builtin_alloca(n)` lower to it, freed at
  function return).
- A C array name decays to a pointer for indexing, so a VLA can simply BE a
  pointer local: `arr[i]` through a `tyPointer` symbol with `PtrElemTk` set is
  the path every `T *p` local already takes.

So, in the local-declaration array branch (cparser.inc, the `while CurTok.Kind =
tkLBrack` dimension loop):

1. Detect the runtime dimension — `CConstExprSawNonConst` already reports it;
   that flag is what the current refusal reads.
2. Re-parse the bracket contents as an EXPRESSION (save TokPos before the
   constant-evaluator call) to get a dim AST node.
3. Allocate the symbol as `tyPointer` via `CAllocDeclVar`, setting `PtrElemTk` /
   `PtrElemRec` / `SymPtrDepth` from the element type, exactly as the scalar
   pointer branch a few hundred lines below does.
4. Emit `arr := alloca(dim * sizeof(elem))` onto the declaration's statement
   chain (`head`/`tail`), which the array-initializer code in the same branch
   already builds.

## Known limits to decide before starting

- `sizeof(arr)` on a VLA must be `n * sizeof(elem)`; as a pointer local it would
  answer the pointer size. Either special-case the symbol (a flag saying "VLA,
  size expression is node X") or document the divergence.
- Multi-dimensional VLAs (`int a[n][m]`) need the row stride at run time; the
  flat row-major layout the fixed path uses assumes constant dims. Start with
  1-D and refuse the rest with the existing error.
- A VLA in a loop body allocates per iteration and is only freed at function
  return — same as `alloca`, and the same caveat C itself has.

## Gate

`tools/run_c_conformance.sh` with `00207.c` REMOVED from `test/c-conformance/pxx.skip`
(that line names this ticket), plus a `test/` C program writing and reading a
runtime-sized array in a loop and printing the values, diffed against gcc — the
exact shape that used to stop after two iterations.

## Triage 2026-08-19 (Track D re-triage pass, pin v363)

**Genuine feature, still wanted — measured, not read.** The refusal is intact:

```c
int n = 5; int arr[n];
```
```
pascal26:4: error: C: variable-length array (a dimension that is not a
compile-time constant) is not supported — use a fixed bound, malloc or alloca
```

gcc compiles and runs the same file (`30 20`), so this is code the reference
implementation accepts and pxx refuses — squarely **compat** work (ISO C99
surface), and worth carrying that tag. It is deliberately NOT re-typed as a
bug: the refusal is loud and names the workarounds, and this repo's escape rule
promotes a compat finding to a bug only when the divergence is a *silent wrong
value*. The corruption that was silent is already fixed
([[bug-cfront-vla-stack-corruption]]); what remains is the missing feature.

## Resolution (2026-08-19)

Built as designed above; every open question in "Known limits" got an answer
rather than a divergence note.

**`sizeof` on a VLA — a hidden companion local, not a flag.** C evaluates
`sizeof` on a VLA at RUN TIME, so a runtime variable is the honest
representation of it, not a workaround for the lack of one. Each VLA `name`
gets a companion local `$vlasz$name : tyInt64`, assigned `dim * sizeof(elem)`
on the same statement chain, immediately before the `alloca`. `ParseCSizeof`
looks the companion up by name when its operand is a `tyPointer` symbol and
returns it as an identifier node. Without this the pointer symbol answered the
POINTER size — `8` where gcc says `20` — which is a silently wrong value, the
one outcome worse than refusing the feature.

The companion opened a hole in the other direction: an `AN_IDENT`'s `ASTIVal`
is a SYMBOL INDEX, so `int fixed[sizeof(vla)]` would have sized an array with a
symbol number. `CEvalConstPrimary` now checks that `ParseCSizeof` handed back an
`AN_INT_LIT` and errors otherwise ("sizeof of a variable-length array is not a
constant expression — its value is only known at run time"). That refusal has
its own negative test with a `grep -q` on the message, so it asserts the right
wall rather than merely "something failed".

**No `defs.inc` change, so no Track A edit.** `cparser.inc` is included after
the implementation's var section and cannot declare globals, so a "VLA, size
node is X" side table would have had to live in `defs.inc`. The companion
symbol avoids that entirely — precedent: `CWrapStaticInitOnce`'s
`'$staticinit' + MangleSuffix(...)` symbols.

**Refused, loudly:** multi-dimensional VLAs (`int a[n][m]` — the flat row-major
layout assumes constant strides) and a VLA with an initializer (C99 6.7.8p3).

**Targets: x86-64 only, by inheritance.** `IR_ALLOCA` codegen lives only in
`ir_codegen.inc`; `feature-c-alloca-dynamic-stack` scoped it that way
deliberately. The other backends refuse with `target <arch>: IR op not yet
supported: alloca` — loud, named, at compile time. `00207.c` therefore moves
from the base `pxx.skip` into all four `pxx.skip.<arch>` files (aarch64's is
new) rather than out of the skip system altogether.

## What landed

- `compiler/cparser.inc` — rewind-and-reparse the runtime dimension, the
  pointer+`alloca` lowering, the `$vlasz$` companion, `ParseCSizeof` lookup
  (both the parenthesized and the bare `sizeof vla` forms), the
  `CEvalConstPrimary` guard.
- `test/c_vla.c` — seven rows, all byte-identical to gcc on the same source:
  the loop shape that used to stop after two iterations, `sizeof` on a
  `char[n+1]` and an `int[n]`, an expression dimension over a record element
  (stride = `RecSize`), a VLA of pointers, a VLA declared inside a loop body,
  and a fixed-bound control whose `sizeof` must stay constant.
- `test/c_vla_const_fail.c` + a `grep -q` arm — the constant-context refusal.
- `test/c-conformance/pxx.skip` line 8 removed; `00207.c` added to the four
  per-target skip files.

## Gate run

`make compiler/pascal26` (fixedpoint, "converged after 1 round(s)"), the
Makefile's own two assertions run by hand (`gate.sh quick` cannot see
`test-core`), `00207.c` producing exactly its `.expected`, and
`tools/gate.sh quick` GREEN.

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.
