---
track: N
prio: 50
type: bug
summary: "pyeval's host-method bridge accepts only ALL-variant or ALL-pointer-sized parameter lists, so a method mixing them — `define_word(name: str, native: Callable, immediate: bool)`, where Callable is a variant and the rest are registers — is refused outright: \"unsupported param shape\". This is what blocks uforth now."
status: done
owner: claude-N
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

## RESOLVED 2026-08-08 — one register family, not two, plus a latent result bug

### The fix: a variant argument IS a register argument

`compiler/builtin/pyeval.pas`. The two families were never really two: what pxx
passes for `const a: Variant` is the ADDRESS of the 16-byte slot — one
pointer-sized value in an integer register, exactly like an int, a class
reference or an AnsiString's data pointer. So `TK_VARIANT` joins the accepted
kinds and a variant argument is marshalled as `@slot`; nothing else about the
call changes. The third family the ticket warned against is not needed, and the
"pointer family" comment naming uforth's `define_word` as its driver — stale
since `Callable` parameters became variants — is now accurate again.

Two details that are not decoration:

- **The marshalling buffer is a raw `TPyRec`, NOT a `Variant`.** `args` owns the
  value for the whole call; a managed `Variant` local would release it a second
  time on the way out. (Tried it the managed way first — it is not what uforth's
  remaining crash turned out to be, but it is a real double-release and the raw
  buffer is the correct shape for a borrow.)
- **An OMITTED variant parameter is a real None (VT_EMPTY), not the zero every
  other kind defaults to.** Zero would be a NULL address and the callee
  dereferences it unconditionally. `define_word("B")` — omitting both `native`
  and `forth_body` — is the everyday case.

### And a latent bug found in the same block

The register family had ONE thunk, returning `Int64`. A method returning an
**AnsiString** therefore had its string handle boxed by `pyvar_of_int` and came
back to the caller as an INTEGER, silently. A **Variant** return, which travels
through the hidden destination, could not have worked either. Both now have
their own thunk set (`TPSFn0..5`, `TPVFn0..5`), chosen by RESULT kind — the
arguments no longer influence the choice, since they are all one register wide
by the time the call is made.

The refusal diagnostic now prints the arity and every parameter's kind. The bare
"unsupported param shape" cost a bisect to turn into a sentence.

### Verified

`test/test_nilpy_pyeval_host_mixed_params.npy` (new — no existing pyeval test
covers host param shapes; the two that exist are the `**` grammar and the
missing-`vm`-key case). Covers a variant argument supplied, a variant argument
OMITTED, a class argument omitted, an AnsiString result, a class result, and the
callable that travelled through the bridge being stored and then CALLED.

It discriminates — `stable_linux_amd64/default/pinned` dies with
`Unhandled exception: TypeError: expected a number, got <unknown>`.

`make compiler/pascal26` byte-identical · `tools/gate.sh quick` GREEN.

### NOT re-pinned, deliberately

`compiler/builtin/pyeval.pas` is frozen into `stable_linux_amd64/default/builtin/`
by `make pin`, so the PINNED binary keeps the old copy until someone pins. That
matches how pyeval fixes have landed before (3 of the last 4 did not move the
frozen copy) and the self-host fixedpoint is unaffected — the compiler does not
`use` pyeval, only NilPy programs do, which is the same reason pylib changes do
not trip the A != B gate step. Pinning is a deliberate brake; this fix will ride
the next `make stabilize` + `make pin`.

## uforth: past the refusal, now a WRITE AFTER FREE

`make test-uforth` still red, in a third place. The bridge no longer refuses
anything; uforth now loads far enough to compile `IO.UFO` and dies dispatching an
IMMEDIATE word, with `-dPXX_HEAP_DEBUG` reporting WRITE AFTER FREE and the
recycled block coming back as a list's element storage.

**Measured NOT to be this fix**: with the bridge instrumented to print every
variant it marshals, the write-after-free is reported on line 1 of the output,
*before the first mixed host call happens*, and the freed address matches none
of the objects that later pass through it. Filed as
[[bug-nilpy-write-after-free-on-a-callable-held-in-a-dataclass-field]];
[[bug-nilpy-uforth-compiles-but-segfaults-at-runtime]] now blocks on that.

## Log
- 2026-08-08 — resolved, commit PENDING-COMMIT.
