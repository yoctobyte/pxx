---
slug: bug-n-a-builtin-function-is-not-a-first-class-value
track: N
prio: 45
type: bug
blocked-by: []
status: backlog
found: 2026-09-11
found-by: frankuser
owner: unassigned
summary: "`call_it(print, x)` gives `error: undefined variable (print)` while `call_it(own_fn, x)` works -- a USER function is a value and a BUILTIN is not. Ordinary Python: a builtin passed as a callback. Three sites in lekkerzeilen's entry-point closure, all `announce=None if quiet else print`, which is what walls the demo at app.py:561. The conditional is not involved; a bare argument reproduces it."
---

# A builtin function is not a first-class value

`print` — and, by the same mechanism, presumably every other builtin — cannot be
passed, stored or returned. Referencing one anywhere but a call position is
reported as an undefined variable.

## Repro

```python
def call_it(f, text):
    f(text)

def own(text):
    print("own:", text)

call_it(own, "a user function as a value works")   # fine
call_it(print, "print as a value")                 # pascal26:8: error: undefined variable (print)
```

CPython prints both lines. Measured at `120eeb39f`, binary `7cf02ff177ca`.

**The discriminating half is the first call.** A user-defined function already
works as a value, so the function-value machinery exists and this is specifically
about how builtins are bound: they are recognised at a CALL site rather than
being bound to a name the expression parser can reach. That is also why the
diagnostic says *undefined variable* — from the name resolver's point of view
there is genuinely nothing called `print`.

## Why it is worth more than its size suggests

A builtin as a callback is a plain Python idiom — `announce=print`,
`key=len`, `sorted(xs, key=abs)`, `map(str, xs)`. lekkerzeilen uses the first of
those three times, identically, to make a loader's progress reporting silenceable:

    self.session = session.load(announce=None if quiet else print)

Nothing exotic, and the workaround is a two-line module-level wrapper — which is
what the corpus now carries, with a comment pointing here. That workaround is in
the DEMO's source, not in pxx, and it is recorded rather than silent: the
lekkerzeilen seam is allowed to change (standing owner rule) but a gap papered
over without a ticket is how a gap survives.

**Scope is unmeasured and the quantifier is the part to check**: I verified
`print` only. Whether `len`, `str`, `abs`, `sorted` behave the same way is a
one-line sweep nobody has run, and "presumably every builtin" above is an
inference, not a measurement. Run the sweep before ranking this on population.

## Where to look

The name resolver's builtin handling, reached from the expression parser's
identifier arm rather than its call arm — `pyparser.inc`. A builtin that is
recognised while parsing a CALL needs a value binding too, so that a bare
reference yields something callable instead of failing resolution.
