---
track: N
prio: 75
type: bug
---

# A def stored in a NAME and then called SEGFAULTS

```python
def f(ch: str) -> str:
    return "hi " + ch

def g(cb) -> str:
    return cb("x")

print(g(f))     # ok — "hi x"
x = f
print(g(x))     # SIGSEGV
```

CPython prints `hi x` twice. The difference is only whether the function value
passes through a NAME. It reproduces with `x` as a module global or as a local,
and the same shape crashes when the callee is a METHOD:

```python
class D:
    def m(self, cb) -> str:
        return cb("x")
D().m(f)        # SIGSEGV
```

## Cause

`x = f` goes through `PyMakeFuncValue` (pyparser.inc ~5397), which boxes the
function as `pybound_new(@f, nil)` — a **VT_BOUNDMETHOD** (tag 8) variant whose
payload is a pointer to a `{Code, Recv}` pair OBJECT, not a code address.

`cb("x")` goes through `PyMakeDynCall` (pyparser.inc ~5184), whose callee
address is `pyvar_callee_addr(v)` = `PPyVarRec(@v)^.Payload` — for tag 8 that is
the **pair object**, which is then jumped to. `pyvar_callee_addr`'s nil check
does not fire (the payload is a valid pointer), so there is no diagnostic.

`g(f)` works because the argument position boxes the raw proc address rather
than a bound pair, so the payload really is the code.

## Fix sketch

Two levels:

- **Cheap, covers the plain-def case:** in `pyvar_callee_addr` (pylib.pas),
  when `VType = 8`, read the pair: `Recv = nil` -> return `Code`. `Recv <> nil`
  cannot be served by this path at all (the receiver has nowhere to go), so
  raise the same TypeError rather than returning a pointer that will be jumped
  to.
- **Complete:** wrap the dynamic call the way `PyWrapClosureDynCall` /
  `PyWrapClosureFieldCall` already wrap theirs — `pycallback_is(v) ?
  <AN_CALL_IND on pybound_code(v), receiver prepended when pybound_recv(v) <>
  nil, sig PyDynCallSig(n+1)> : <existing path>`. That is what makes a BOUND
  METHOD held in a variable callable, which the closed-world façade paths get
  today only through `pycallback_call0/1` (which discard the result).

## Why it matters

songformatter's `analyze_key(chords, chord_to_notes=notes_of, ...)` forwards a
module-level def through a parameter into every detector's `analyze`, so the
whole key-analysis entry point segfaults. Found while verifying
[[bug-nilpy-slice-of-variant-local-returned-is-unusable]]; sibling of
[[bug-nilpy-callable-in-local-var-call-does-nothing]] (that one is the LAMBDA
half and fails silently; this one is the def half and crashes).

## Repro / gate

The snippet at the top, plus the method form. Then, in a `cp -r` of
`~/songformatter`:

```python
from key_analysis import analyze_key
NOTES = {"C": ["C", "E", "G"], "F": ["F", "A", "C"], "G": ["G", "B", "D"],
         "Am": ["A", "C", "E"], "Dm": ["D", "F", "A"], "Em": ["E", "G", "B"]}
def notes_of(ch: str) -> list[str]:
    return NOTES.get(ch, [])
res = analyze_key(["C", "F", "G", "C", "Am", "F", "G", "C"], chord_to_notes=notes_of)
print(res.final.winner.label)   # CPython: C
```
