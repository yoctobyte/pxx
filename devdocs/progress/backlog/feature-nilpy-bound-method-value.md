---
track: N
prio: 65
type: feature
---

# NilPy: a BOUND METHOD as a value (`self.push` carries self)

Follow-on to [[feature-nilpy-function-values]] (done — a FREE `def` as a value
works). A **bound** method used as a value drops its receiver and crashes.

## Repro (SIGSEGV)

```python
class VM:
    def push(self, v: int) -> None: ...

vm = VM()
env = {}
env["push"] = vm.push      # capture the BOUND method as a value
env["push"](5)             # SIGSEGV — self is gone
```

A free function in a dict works (`d["f"] = make; d["f"]()` ✓); only a bound
method breaks. Capturing `vm.push` stores the method's code pointer and DROPS
`self`; the dynamic call (`PyMakeDynCall`, `ASTSLen=0`) then calls
`code()` with no receiver → the body reads `self.*` off garbage.

## Why it matters — the exec() unblocker

This is the FOUNDATION under [[feature-lib-pyexec]]. uforth's exec() builds an
env of bound methods:

```python
env = {"vm": self, "push": self.push, "pop": self.pop, "fpush": ..., "fpop": ...}
exec("def __body__():\n    b=pop(); a=pop(); push(b+a)", env, ns)
r = ns["__body__"]()
```

The `pyeval` interpreter (a builtin unit) is compiled with NO knowledge of
uforth's `VM` class, so it CANNOT statically call `vm.push` — it must invoke the
env's `push`/`pop` callables. And `self` is lost at the STORE (`env["push"] =
self.push`), which is uforth's own code and unmodifiable. So a self-carrying
callable value is unavoidable: pyeval cannot run a single PYTHON-bodied stdlib
word (`/`, `2/`, most of CORE) until this lands. Sequencing decided with the
user: bound methods FIRST, then pyeval.

## Scope refinement (2026-07-21) — folds into the reflection bridge

Investigated the call mechanism and the consumer. `ns["__body__"]()` /
`env["push"](x)` go through `PyMakeDynCall` (pyparser.inc:3077): unbox the variant
to its payload as a raw CODE POINTER, `AN_CALL_IND` with `ASTSLen=0` (no Self) —
which is why a bound method segfaults, self is never passed.

An early idea was a narrow "pyeval hardcodes push/pop signatures" path. **That is
WRONG** — the exec'd bodies do not just call push/pop; they touch ~25 distinct
`vm` MEMBERS, fields AND methods with args (`vm.memory`, `vm.here`,
`vm.define_word(...)`, `vm.run_forth_word(...)`, …; full census in
[[feature-rtti-field-reflection]]). No fixed callable set covers that, so the
interpreter needs GENERAL reflection over the host object, not hardcoded
signatures.

So this ticket folds into the [[feature-lib-pyexec]] host bridge rather than
standing alone: capturing `self.method` as a value becomes `{recv, method-ref}`,
and it is invoked through the SAME machinery the tree-walker uses for every
`vm.method(...)` — method reflection (invoke-by-name, VMT-8, already ships) plus
the generic native-call trampoline. i.e. a bound-method value is just
"method-by-name with the receiver already bound." Build it with pyeval, not
before it.

The one piece that must still work standalone: `env["push"] = self.push` must
STORE a usable value (currently the capture drops self). Make capture produce the
`{recv, method-ref}` object; and make `PyMakeDynCall` at least ERROR clearly on a
bound-method variant instead of segfaulting, until/unless a corpus needs the
general compiled `env["push"](x)` path (then add the runtime tag-branch).

## Design

Represent a bound method as a small heap object, boxed as a variant:

```
TPyBoundMethod = class     { or a 16-byte record in pylib }
  Code: Pointer;           { the method's proc entry }
  Recv: Pointer;           { self }
end;
```

- **Capture** (`obj.method` with no following `(`): in the NilPy postfix path,
  when `.name` resolves to a METHOD (not a field) and is not immediately called,
  build `pybound_new(code, recv)` -> a VT_OBJECT variant. Non-virtual methods
  take the proc address directly; a VIRTUAL method reads the slot off recv's VMT
  at capture time (bind-now, Python semantics). Start with non-virtual (uforth's
  push/pop are non-virtual); error clearly on virtual until needed.
- **Call** (`PyMakeDynCall`): when the callee variant holds a TPyBoundMethod,
  emit an indirect call passing `Recv` as arg 0 (Self) then the user args —
  `ASTSLen := 1` (has-Self) and prepend the receiver. A plain function value
  keeps `ASTSLen := 0`. Distinguish by the variant's object type at runtime, or
  by two dyn-call shapes chosen from the static type when known.
- **Runtime helper** in pylib (or the new pyeval unit if it grows there):
  `pybound_new`, and a `pybound_invoke` the Pascal-side interpreter can call.

## Gate

- Repro above prints `pushed 5` (no segfault); `env["push"](x)` mutates the
  right receiver.
- test-nilpy GREEN + self-host byte-identical.

## Then

[[feature-lib-pyexec]] — `pyeval.pas` / `EvalPyStmts` tree-walker over the tiny
pop/push/arith/ternary subset, single-slot trampoline for the `def __body__` +
immediate-call shape, reusing pylib's variant ops.
