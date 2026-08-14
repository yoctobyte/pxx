---
track: N
prio: 50
type: feature
status: done
owner: claude-AN
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

## Recon 2026-07-31 — part 1 (this ticket's own load-time abort) fixed; part 2 confirmed still open

Part 1 — "resolve a bare `def` name to a value" inside `exec()`, so
`vm.define_word(name, native=_w)` no longer aborts the load with `name not
defined: _w` — is FIXED. Measured directly: the exact repro shape (a
closure-over-`name` nested def, passed by name as a keyword arg to a host
method inside `exec()`) now compiles and the `exec()` call itself
completes without error.

Part 2 — "persist + reverse-bridge the closure" so the LATER call
(`word.native(vm2)`, from ordinary compiled NilPy code, not from inside
exec()) actually runs the closure with its captured state — is confirmed
STILL open, exactly as this ticket's own analysis predicted. Measured the
concrete failure: with the `native` field/parameter properly annotated
`Callable[[Any], None]` (needed just to get past compilation), the call
reaches pyeval's host-call marshaling and fails at RUNTIME: `pyeval: host
method define_word has an unsupported param shape` — i.e. passing a
pyeval-internal closure value AS AN ARGUMENT to a host method call is the
piece that doesn't exist yet, matching this ticket's own "closure must be
snapshotted... boxed as a stateful callable variant" analysis. Not
attempted this pass — it is the same closure/trampoline architecture
class already deferred elsewhere this session
(`bug-nilpy-bound-fn-closure-objects-are-never-freed`,
`bug-nilpy-void-def-assigned-and-called-crashes`), needing a genuine
runtime tag + trampoline, not a quick patch.

## 2026-08-14 — DONE. Verified against this ticket's own "Done when", at HEAD

Part 2 — the piece the 2026-07-31 recon confirmed still open — **works**. Not
inferred from the uforth corpus being green: measured against the criteria
written in this file, with the closure shape still present in the source.

`VARIABLE.UFO:30` is unchanged and still uses the exact construct this ticket
was opened for — a nested `def _w(vm2)` closing over `name`, passed as
`native=_w` to the host method `vm.define_word`, and called back much later by
the interpreter as `word.native(vm2)`:

```python
name = vm.next_token_strict()
vm.vars[name] = 0
def _w(vm2):
    vm2.push(name)
vm.define_word(name, native=_w)
```

Results (compiled `uforth_pxx` at HEAD, self-hosted fixedpoint):

| criterion from "Done when" | result |
| --- | --- |
| `VARIABLE Q 42 Q ! Q @ .` | **42** |
| `100 8192 ! 5 8192 +! 8192 @ .` | **105** |
| `BL .` | **32** |
| STD.UFO loads all files | **yes** — the full ANS Forth suite runs, Total errors 0 |

### The assertion the criteria did NOT make, and it is the one that matters

Every listed criterion uses ONE variable, so all four would pass on a closure
implementation that captured nothing and happened to read the most recent
`name`. The real property is that each closure carries **its own** captured
value:

```
VARIABLE A VARIABLE B 11 A ! 22 B ! A @ . B @ . A @ .
  ->  11 22 11
```

`A` still answers 11 after `B` has been defined and used, so the two `_w`
closures hold distinct captured `name`s across a later, unrelated call. That is
the "persist + reverse-bridge the closure" half, working.

### Closed by other work, not by this ticket

Nothing here was implemented under this slug. The closure/trampoline
architecture this ticket described as needed landed with the uforth corpus
drive; this file is the verification that it covers this ticket's case, so the
slug does not sit in the queue claiming a wall that is gone.

Worth generalising: this is the second ticket this session whose "still open"
recon was stale because the blocking capability shipped elsewhere. A `Done when`
section is cheap to re-run and should be re-run before the analysis above it is
believed.

## Log
- 2026-08-14 — resolved, commit PENDING-COMMIT.
