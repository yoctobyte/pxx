---
slug: feature-n-a-runtime-dispatched-method-call-is-capped-at-four-arguments
track: N
prio: 40
type: feature
blocked-by: []
status: backlog
found: 2026-09-11
found-by: frankuser
owner: unassigned
summary: "MAX_DYN_ARGS = 4 (pyparser.inc:17436): when no class in the unit declares a method name, the call dispatches at run time and a FIFTH argument is refused. Ordinary Python, not an edge case -- found on lekkerzeilen's `gl.ReadPixels(0,0,w,h,fmt,type,buf)`, 7 arguments. Refusing beats truncating and the diagnostic's prescribed remedy WORKS (verified), so this is a gap rather than a blocker. Raising it widens PyDynMethN's four fixed Variant slots, which is a BUILTIN change and mints a pin cliff."
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
