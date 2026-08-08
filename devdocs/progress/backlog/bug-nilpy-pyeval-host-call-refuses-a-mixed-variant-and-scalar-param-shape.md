---
track: N
prio: 50
type: bug
summary: "pyeval's host-method bridge accepts only ALL-variant or ALL-pointer-sized parameter lists, so a method mixing them — `define_word(name: str, native: Callable, immediate: bool)`, where Callable is a variant and the rest are registers — is refused outright: \"unsupported param shape\". This is what blocks uforth now."
---

# pyeval refuses a host method whose params mix variants and scalars

```
pyeval: host method define_word has an unsupported param shape
```

`compiler/builtin/pyeval.pas` (~line 690) recognises exactly two shapes when a
PYTHON-bodied block calls back into a compiled host method:

- **all-variant** — every parameter `TK_VARIANT`, each passed by address;
- **pointer-family** — every parameter one of int / bool / char / int64 /
  pointer / class / AnsiString, each coerced into an integer register.

Anything else prints the message above and fails the call. uforth's

```python
def define_word(self, name: str,
                native: Optional[Callable[["VM"], None]] = None,
                forth_body=None, immediate: bool = False, wid=None) -> Word:
```

is neither: `name` is an AnsiString and `immediate` a Boolean (register family),
while `native` is a **variant** — which is what a `Callable[...]` PARAMETER has
lowered to since
[[bug-nilpy-bound-method-cannot-pass-through-a-callable-parameter]], because a
bare pointer has no room for a bound method's {code, receiver} pair.

The comment in pyeval still names this very method as the pointer-family's
driver ("uforth's `define_word(name: str, native: Callable, forth_body,
immediate: bool) -> Word` is the driver"). That comment is **stale**: it predates
the Callable-parameter change, and the shape it describes no longer exists.

## Attribution — pre-existing, only newly REACHED

Not caused by 2026-08-08's Callable-FIELD unification. That change made a
`Callable` FIELD a variant; the PARAMETER arm of `PyAnnTypeAt` is behaviourally
unchanged by it (a parameter answered `tyVariant` before and answers `tyVariant`
after — the diff only removed the guard that made a FIELD differ). uforth simply
never executed this far before: it crashed in `pyboundfn_callvn`, and then
STD.UFO's colon definitions failed, ahead of the first PYTHON-bodied word that
calls back into the host.

## Shape of the fix

The two families are one special case too many. Decide per ARGUMENT rather than
per SIGNATURE: walk the parameter kinds and place each one the way its own kind
requires — a variant by address, a register kind in a register — which subsumes
both existing families instead of adding a third. The omitted-trailing-parameter
defaults the pointer family already fills (None -> nil, False -> 0) need the
variant equivalent (`pynone`), the same substitution `ir.inc`'s
`ProcParamDefaultIsNone` branch makes.

While there: the diagnostic should print the offending kinds and the parameter
index. "unsupported param shape" alone cost a bisect to turn into the sentence
above.

## Note: this is a BUILTIN

`compiler/builtin/pyeval.pas` is compiled INTO the compiler, so a change here
needs `make stabilize` + `make pin` before the gate's self-host fixedpoint sees
it — prove it landed via the sh-A/sh-B map diff, not by assuming.

## Gate

A `.npy` with a PYTHON-bodied block calling a host method whose parameters mix a
variant with scalars, in both argument orders and with trailing parameters
omitted, oracle-diffed with `tools/pydiff.py`; plus `make test-uforth` getting
past STD.UFO; plus the per-fix loop and the stabilize/pin above.
