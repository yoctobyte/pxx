---
track: N
prio: 50
type: feature
---

# pyeval: a nested `def` passed to a host method, called back later (closure-as-native-word)

- **Track:** N (pyeval is a builtin unit consumed by the NilPy frontend).
  Consumer: [[feature-nilpy-corpus-uforth]]. Sibling of
  [[feature-nilpy-bound-method-value]] / [[feature-lib-pyexec]] host bridge, but
  a distinct case: the callable is a **pyeval-internal `def`**, not a NilPy
  `self.method`.

## Repro (the current uforth STD-load wall)

`STD.UFO` → `VARIABLE.UFO:30` (and CONSTANT/CREATE/array words) run this PYTHON
body under pyeval:

```python
name = vm.next_token_strict()
vm.vars[name] = 0
def _w(vm2):
    vm2.push(name)          # closure over `name`
vm.define_word(name, native=_w)   # pass the def as a VALUE to a host method
```

pyeval aborts: `pyeval: name not defined: _w`. `EnvGet` (pyeval.pas ~1254)
resolves locals → EnvG → type-codes, but **not** `FnFind` — a bare nested-def
name has no value form. So `native=_w` cannot even be evaluated; STD load halts
before any VARIABLE word is defined.

## Two parts (both required for the word to actually work)

1. **Resolve a bare `def` name to a value.** `EnvGet` falls back to `FnFind`;
   returns a callable variant. *Alone* this only stops the load-time abort — the
   value must also be runnable later.
2. **Persist + reverse-bridge the closure.** `vm.define_word(name, native=_w)`
   stores the value in a uforth `Word.native` field (NilPy heap). Much later the
   interpreter runs the word: `word.native(vm2)` — NilPy-compiled, so it goes
   through `PyMakeDynCall` (pyparser.inc:3138), which unboxes the variant payload
   as a raw code pointer and does an `AN_CALL_IND` with `ASTSLen=0` (no self/no
   state). A bare code pointer cannot carry **which** `_w` nor its captured
   `name`. And pyeval's per-`EvalPyStmts` state (Cur/FnN/LclN/EnvG, the token
   buffer, FnBodyPos spans) is **gone** by the time the word runs — a different
   exec reset it.

   So the closure must be **snapshotted** at capture: the def's body (source text
   or a copied token span) + a captured-env record (here just `name`), held in a
   persistent heap object, boxed as a **stateful** callable variant
   ({trampoline-code, closure-obj}). `PyMakeDynCall` needs a runtime tag-branch
   that, for that tag, prepends the closure object as an extra arg (the same
   gap noted for VT_BOUNDMETHOD in [[feature-nilpy-bound-method-value]]). The
   trampoline re-enters pyeval to run the body with the captured env + the passed
   `vm2` arg. pyeval globals must be save/restored around the trampoline
   (a native word may itself call another PYTHON-bodied word → nested
   EvalPyStmts).

## Direction already set

[[decide-nilpy-closure-model]] (resolved): a def used as a VALUE gets a closure
record now; cells are the end state. This ticket is the pyeval-side instance of
that model. Reuse the `{recv, method-ref}` boxing shape from
[[feature-nilpy-bound-method-value]] and the `PyBodyTramp`/`CallUserFn` pattern
already in pyeval.pas (~2464) for the 0-arg `__body__` case — this generalizes it
to N args + captured free vars + persistence.

## Done when

`cd ~/projects/uforth && printf 'VARIABLE Q 42 Q ! Q @ .\nBYE\n' | /tmp/uforth`
prints 42; `100 8192 ! 5 8192 +! 8192 @ .` = 105; `BL .` = 32; STD.UFO loads all
10 files. Gate: self-host byte-identical + pyeval standalone + test-nilpy +
quick, then `make test-uforth`.
