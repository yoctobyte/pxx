---
slug: feature-n-a-runtime-dispatched-method-call-is-capped-at-four-arguments
track: N
prio: 40
type: feature
blocked-by: []
status: done
found: 2026-09-11
found-by: frankuser
owner: frankH
summary: "DONE in 95e7eb26e -- the cap is gone, and the fix was the ARRAY-PASSING shape this ticket named as the thing to consider first: pydyn_methl takes a TPyList and has no ceiling, with pydyn_meth0..4 kept as DIRECT rungs so the small arities keep their timing and do not acquire a hoisted list (a hoisted container temp escapes a ternary branch -- filed separately). MAX_DYN_ARGS is now 64 and is the list path's own runaway guard, not a marshalling limit. This ticket's own reproducer -- seven arguments, no receiver annotation -- answers 28 against CPython's 28. The refusal this ticket said must survive did survive: a callable ATTRIBUTE dispatched at run time still stops at 4 and now REFUSES by name where it used to call pyvar_callv4 with a truncated list. The sibling road -- a callable VALUE, pyvar_callv0..4 -- was still capped and is bug-n-a-star-unpack-through-a-callable-value-stops-at-four-arguments."
---

# A runtime-dispatched method call takes at most four arguments

## The fact

`compiler/pyparser.inc:17436` — `const MAX_DYN_ARGS = 4`. Where no class in the
compilation unit declares the method name, the receiver is dispatched at run
time, and the fifth argument is an error:

```
error: Nil Python: .ReadPixels() is dispatched at run time (no class here
declares it), and that path takes at most 4 arguments — annotate the receiver
with its class to pass more
```

The cap lives in the runtime marshalling, not the parser:
`PyDynMethN(recv, name, kwspec, n, a0, a1, a2, a3)` in
`compiler/builtin/pyeval.pas:5305` has **four fixed Variant slots**, with
`pydyn_meth0..4` and `pydyn_methkw1..4` as thin wrappers over it.

## Why it is a gap against the language and not an edge case

A seven-argument method on a receiver whose class the compiler cannot see is
ordinary Python. It is what every table-driven or plugin-shaped binding looks
like, and OpenGL is the canonical case: `glReadPixels` takes seven arguments and
several others take more. So this is not a construct only a mistake produces,
which is the test CLAUDE.md sets for `rejected/`.

## What is RIGHT about the current behaviour, and must survive a fix

It **refuses**; it does not truncate. The compiler comment at the site says why,
and it is correct: *"dropping arguments silently is how a call returns a
plausible wrong value."* Any fix that raises the cap must keep the refusal at
the new ceiling rather than widening the silent-drop window.

## The prescribed remedy works — verified, not relayed

The diagnostic tells the author to annotate the receiver. That is a prescription,
so it was run rather than quoted:

```python
class GL:
    def ReadPixels(self, a, b, c, d, e, f, g):
        return a + b + c + d + e + f + g

def pick():
    return GL()

gl: GL = pick()
print(gl.ReadPixels(1, 2, 3, 4, 5, 6, 7))      # 28, matching CPython
```

Compiles and answers 28; CPython answers 28. So an author who can name the class
is never blocked, and **declaring the method on the class the receiver already
has is the same remedy** — which is what the lekkerzeilen case actually needs
(see below).

## How it was found, and why it did not rank higher

lekkerzeilen's entry-point closure walls at `capture.py:45`,
`gl.ReadPixels(0, 0, width, height, gl.RGB, gl.UNSIGNED_BYTE, buffer)` — seven
arguments. But `gl` there is `_backend.gl`, and in the native backend
`lekkerzeilen/platform/_pxx.py` that is a real `class gl:` declaring **five**
names, none of them `ReadPixels`. So the dynamic path is taken because the STUB
is a stub, and writing the backend out properly removes the wall without
touching this cap. That is why this is filed at 40 and not as a demo blocker.

It was invisible to the census because it sits one line BEHIND a `ctypes` wall —
a first-failure instrument cannot see it, which is the bias CLAUDE.md's umbrella
section describes.

## The cost, which is the reason this is a ticket and not a fix

Raising the cap means widening `PyDynMethN`'s signature and adding wrappers:
mechanical, but `pyeval.pas` is a **builtin**, so the change is inert until the
next `make pin` and mints a cliff between the compiler and `lib/rtl`. Worth
doing alongside other builtin work rather than on its own. A variadic or
array-passing shape would avoid growing the wrapper family per ceiling, and is
the thing to consider before hard-coding a larger N.

## Lineage — this is the ceiling a shipped feature left, not a regression

`feature-n-open-world-method-dispatch-on-a-dynamically-typed-receiver` (done,
`6ff12ded7`, frankZ) is what made this dispatch exist at all: before it, a method
call on a dynamically-typed receiver whose name no declared class carried was
REFUSED outright, and that ticket replaced the refusal with `pydyn_meth0..4`. The
`0..4` in those names is this cap. So nothing regressed — the feature shipped with
a ceiling, and the ceiling is only visible to a program that passes five.

Worth noting for whoever raises it: that ticket's own recorded finding is that its
cost estimate was wrong because it assumed a mechanism did not exist. The
mechanism here does exist and is named above; the cost is the wrapper family and
the pin cliff, not new machinery.


## RESOLVED 2026-09-13 in `95e7eb26e` — by the array-passing shape, not a wider ladder

This ticket's last section said it: *"A variadic or array-passing shape would
avoid growing the wrapper family per ceiling, and is the thing to consider before
hard-coding a larger N."* That is what was built.

`PyDynMethN` became a thin wrapper over **`PyDynMethL(recv, name, kwspec, args:
TPyList)`**, and `pydyn_methl` is the public entry point past the rungs. There is
no per-arity family to grow: `MAX_DYN_ARGS = 64` is a runaway guard on the
frontend's own argument buffer, not a marshalling width.

**The rungs stayed, deliberately, and that is the one thing a reader should not
"clean up".** `pydyn_meth0..4` remain DIRECT calls for arities 0..4 because the
list path needs a hoisted `TPyList` temp, and a hoist lands at the enclosing
STATEMENT — so inside a ternary it is built whichever branch runs. That is a
measured hazard with its own ticket
(`bug-n-a-hoisted-argument-escapes-a-ternary-s-untaken-branch`), and it is why
this is two paths rather than one.

**The refusal this ticket said must survive, survived and got stronger.** The
callable-ATTRIBUTE arm inside `PyDynMethL` used to fall through to
`pyvar_callv4` with a truncated argument list past four — an unreachable arm at
the time, and a silent-drop the moment the cap moved. It now raises, naming the
mechanism.

Verified with this ticket's own reproducer, unannotated:

```python
gl = pick()
print(gl.ReadPixels(1, 2, 3, 4, 5, 6, 7))     # 28; CPython 28
```

**What is NOT fixed by this, and has its own ticket.** The METHOD road is one of
two. A callable **VALUE** — `f = some_def` then `f(*five_things)` — travels
`pyvar_callv0..4` / `pybound_callv0..4` / `PyBoundPairCallKwBody`, which were
still a four-deep ladder, and lekkerzeilen died on exactly that at run time
(`lines.py:782`, `_quad(out, *quad)`). See
`bug-n-a-star-unpack-through-a-callable-value-stops-at-four-arguments`, which also
records why THAT road cannot take the list shape and what the non-ladder answer
would be.

## Log
- 2026-09-13 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 2b7068dd7.
