---
track: N
prio: 30
type: bug
blocked-by: []
commit: PENDING-COMMIT
summary: "A nested def's default was bound where the def was taken as a VALUE, not at the `def` statement, so reassigning the name in between changed it. The def-time value already existed in a hidden global — and a SECOND bug meant that global's symbol index was the trial parse's rolled-back one, so `r = h()` answered None where `return h()` was right."
status: done
---

# A nested def's default is evaluated at value time

```python
def make():
    seed = 5
    def h(v=seed):
        return v
    seed = 99
    return h

print(make()())          # CPython 5     pxx 99
```

Silent. Found 2026-08-15 alongside
[[bug-nilpy-a-nested-defs-default-parameter-ignores-the-callers-value]] — a
third defect in the same lowering, and the probe written for this one found a
fourth (below).

## Two mechanisms for one concept, disagreeing

`PyEvalParamDefault` evaluates every NON-CONSTANT default into a hidden
`$pdef.<def>.<param>` global **at the `def` statement** — the point Python
specifies, and what makes the shared-mutable-default idiom accumulate. The
direct-call path has read that global all along (`ir.inc`, the omitted-argument
fill).

`PyNestedDefClosureValue` — the path a def taken AS A VALUE goes down — instead
RE-PARSED the default expression at the point of the value, and its comment
claimed that was "the scope where the def statement stands — Python's
default-at-def-time rule". Right about the scope, wrong about the time: `return
h` can stand many statements after the `def`. It now binds a read of the global,
so both paths get their answer from the one evaluation.
`devdocs/dev/normalise-dont-special-case.md`.

uforth's `DOES>`/`DEFER`, which the re-parse was written for, is unaffected —
the store is IN the enclosing body, so a fresh enclosing invocation still
evaluates fresh defaults. A CONSTANT default has no global and still re-parses;
a literal cannot observe the difference.

## The fourth bug, found by this one's probe

```python
def make4():
    s = 7
    def h(v=s):
        return v
    r = h()          # CPython 7
    return r         # pxx None -- while `return h()` directly was correct
```

`$pdef.make4.h.v` is allocated by the enclosing body's local-typing TRIAL parse
and ROLLED BACK with the rest of that trial's scope. The real parse allocates it
afresh at whatever index is free NOW — one higher, if the body meanwhile
declared a local like `r`. `PyQueueNestedDef` only carried the signature onto
the Proc when it REGISTERED it, which the trial had already done, so
`ProcParamDefaultSym` kept the trial's index and the call read the symbol that
inherited it. With no `r` there was no index to lose, which is why the same def
answered correctly through `return h()` — the difference was the caller's own
locals, not the def.

Re-recorded on every real pass now, beside the by-ref capture re-apply two lines
up, which exists for exactly the same reason. Recycled index, plausible wrong
value — the neighbour of `project_tsymbol_field_landmine`.

## Gate

`test/test_nilpy_nested_def_default_at_def_time.npy` (+`.expected`, in the
Makefile), byte-identical to CPython: the reassignment between def and return;
the value taken twice from one enclosing call; a FRESH enclosing invocation
re-evaluating (the DOES> shape); direct calls before and after the
reassignment; the result assigned to a local; a local declared after the def
(the index shift); a caller-supplied override; a constant and a captured default
together; the mutable-container accumulator; and a default reading the enclosing
def's PARAMETER. `gate.sh quick` GREEN.

## Log
- 2026-08-15 — resolved, commit c582d219c.
