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

## Scope refinement (2026-07-21) — two consumption shapes

Investigated the call mechanism. `ns["__body__"]()` / `env["push"](x)` go through
`PyMakeDynCall` (pyparser.inc:3077): unbox the variant to its payload as a raw
CODE POINTER, emit `AN_CALL_IND` with `ASTSLen=0` (no Self). That is why a bound
method segfaults — self is never passed. Two ways to fix, very different size:

**(A) General — `env["push"](x)` works as compiled NilPy.** PyMakeDynCall must
RUNTIME-branch on the callee variant's tag: bound-method object → load {code,recv},
call `code(recv, args)` (Self prepended, `ASTSLen=1`); plain func value → today's
no-Self call. The static type of a dict fetch is unknown, so the branch is
unavoidably runtime — an if/else around two CALL_IND shapes in the frontend.
Bigger, and it touches the shared dynamic-call lowering (self-host-critical).

**(B) Narrow — pyeval is the only caller.** uforth NEVER calls `env["push"](x)`
as compiled NilPy; it does `env["push"] = self.push` (CAPTURE) and
`ns["__body__"]()` (trampoline, already a plain fn ptr). The push/pop calls live
INSIDE the exec'd source, run by the pyeval interpreter. So pyeval (Pascal) reads
the bound-method object {code,recv} out of `g` and calls it via a TYPED
proc-pointer cast — it hardcodes push/pop/fpush/fpop's fixed signatures, no
general dispatch. Requirement shrinks to: (1) CAPTURE `self.method` as a
{code,recv} variant; (2) pyeval reads+invokes it; (3) PyMakeDynCall just ERRORS
clearly on a bound-method variant instead of segfaulting. Much smaller, no
runtime tag-branch in shared call lowering — but couples the representation to
pyeval, so build them together.

Recommendation: **(B)**, built alongside pyeval — it avoids the risky shared
dynamic-dispatch change and is exactly what uforth needs. Promote to (A) only if
a corpus genuinely calls a stored bound method directly.

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
