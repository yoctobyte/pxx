---
track: N
prio: 55
type: bug
---

# Every escaping closure leaks its bound-fn object — 320k closures cost 125 MB

```python
def mk():
    L = [1, 2, 3]
    def b():
        return len(L)
    return b

for i in range(n):        # spelled as a while loop in NilPy
    f = mk()
    f()
```

RSS grows linearly with the number of closures created and is never reclaimed.

## Measured — RSS slope, 20k vs 320k iterations

| program | 20 000 | 320 000 | per closure |
| --- | --- | --- | --- |
| closure capturing an **int** | 4 352 KB | 65 408 KB | ~200 B |
| closure capturing a **list** | 8 192 KB | 125 312 KB | ~390 B |
| the same body with NO closure (control) | 264 KB | 264 KB | flat |

The control is flat, so ordinary list/dict/object churn reclaims correctly —
this is specific to the closure object.

## Two contributors, and one of them is new

1. **`pyboundfn_new` GetMems a `TBoundFnObj` and nothing ever frees it.**
   Pre-existing — the int-capture row above uses no other allocation. The
   design note says so out loud, next to `pyboundfn_bind_var`'s heap slot:
   "leaked with it; markers are few". That assumption held while the only
   things reaching this path were uforth's MARKER/DOES> words.

2. **`pyboundfn_bind_obj` retains a class capture and never releases it** — the
   extra ~190 B in the list row. Added by
   [[bug-nilpy-escaping-closure-captures-unbound-unless-arity-is-one]], and
   deliberately so: without the retain the enclosing scope frees the object on
   return and the closure reads freed memory (it answered `len(L) == 0`).
   Retaining was the right call for correctness; it inherits the same missing
   destructor.

The honest framing is that fixing the closure ABI made this leak *reachable*.
Before, an escaping closure produced garbage, so nobody wrote loops that make
them. Now they work, so people will — and "markers are few" stops being true.

## Shape of a fix

The bound-fn object needs a lifetime. Options, roughly in order of effort:

- **Refcount it like any other managed object.** It is already a magic-tagged
  heap object that the variant machinery recognises (`pyboundfn_is`,
  `pycallable_obj_is`); giving it the ordinary retain/release path would also
  release each `Bound[]` entry that `pyboundfn_bind_obj` retained and each heap
  slot `pyboundfn_bind_var` allocated. This is the real fix.
- **Free the bound values with the object** once it has any destructor at all —
  the bind functions already know which slots are owning (`_bind_obj` retained,
  `_bind_var` allocated, plain `_bind` owns nothing), so the object could carry
  a small per-slot kind array.

Both need care: a closure's lifetime is genuinely dynamic (stored in a dict,
returned again, captured by another closure), so a naive "free at scope exit"
would reintroduce the dangling read that `_bind_obj` exists to prevent.

## Gate

`make test-nilpy` + self-host byte-identical, plus the RSS-slope table above:
the closure rows must go flat, and the control must stay flat. Measure with
`/usr/bin/time -f %M` at 20k and 320k — a single run proves nothing, the SLOPE
is the evidence. `test/test_nilpy_escaping_closure.npy` must stay
byte-identical to CPython (that is the test that the retain is still doing its
job).
