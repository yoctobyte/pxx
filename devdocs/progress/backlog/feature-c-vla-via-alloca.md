---
track: C
prio: 50
type: feature
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
