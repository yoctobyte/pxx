---
track: N
prio: 45
type: bug
summary: "pyeval raises `<lambda>() takes 0 positional arguments but 1 were given` for uforth's `value` / `TO` / `create` / `allot` — the PYTHON-bodied word is invoked with the VM argument its lowered lambda does not declare. Blocks the deeper uforth .for corpora."
status: done
owner: claude-N
---

# A PYTHON-bodied Forth word is called with one argument too many

`make test-uforth` is GREEN, so this is past the smoke gate — but uforth's real
programs are not:

```
$ printf '0 value ii\n5 TO ii\nii .\nBYE\n' | ./uforth
ERROR: <lambda>() takes 0 positional arguments but 1 were given
                                          # CPython prints: 5

$ printf 'create SArray 256 allot\n65 SArray c!\nSArray c@ .\nBYE\n' | ./uforth
ERROR: <lambda>() takes 0 positional arguments but 1 were given
                                          # CPython prints: 65
```

Both messages come from pyeval, not from uforth. `testje.for` and
`testjefixed.for` (RC4 in Forth) die the same way — their whole output is one
`ERROR:` line where CPython prints `0 7 11 15 11` / `8A 6A D9 02 6A`.

`7 3 mod .` and the arithmetic words are fine, so this is specific to the words
whose bodies uforth defines through the PYTHON/pyeval path rather than as
compiled natives.

## What to look at

uforth defines these words with a `native=` callable built from a pyeval
closure, and the dispatcher calls `native(vm)` with the VM as its one argument.
The arity the closure REPORTS is 0. Suspects, in the order worth checking:

- `pyclosure_setarity` / `PyClosureArityBad` — the recorded own-arity for a
  closure built from source text, and whether the `vm` parameter is counted.
- `pyboundfn_callvn`'s `NOwn` clamp: a zero-parameter lambda carries a DUMMY own
  parameter the caller never counts (see `NDefBase`'s comment), and this smells
  like the same off-by-one seen from the other side.
- Whether the word is reached through `pyvar_callv1` (which arity-checks) or the
  Callable-field path, since only one of them raises.

Diff against CPython with `tools/pydiff.py` on a reduced `.npy` that builds a
closure through `exec` and calls it with one argument — do not reason from the
message alone, it names `<lambda>` for every closure shape.

## Gate

The two one-liners above matching CPython, `testje.for` and `testjefixed.for`
byte-identical to the CPython run, `make test-uforth` still PASS, plus the
per-fix loop.

## RESOLVED 2026-08-08 — a RECYCLED closure row carried its predecessor's arity

Not an arity-counting bug. The arity was recorded correctly for the closure that
declared one, and then INHERITED by a completely different closure.

`PyClosureAllocRow` keeps freed rows on a free stack and handed them back
untouched. Between them, `PyEvalClosureFree` cleared five of the nine fields and
the builders set four — and the four that fell through the gap are
`BodyPos`, `FlatSrc`, `ReqN`, `TotN`. `pyclosure_src_new` sets all of its own;
`PyMakeClosure` (the nested-`def`-as-a-value builder) sets none of the three
that matter, because the declared contract is that every builder except the
LAMBDA lowering stays lenient (`ReqN = -1`).

So a row released by a lambda handed that lambda's arity to the next nested def
built on it. uforth's `0 VALUE ii` raised `<lambda>() takes 0 positional
arguments but 1 were given` about a `def _w(vm2)` that plainly takes one — and
`<lambda>` in the message is literal, not a hint: `PyRaiseArity` has no name to
print, which is why the text pointed away from the real closure.

Second bug of the same shape closed with it: **`FlatSrc`** would have made a
recycled `pyclosure_src_new` row run a nested def's INDENTED body under the flat
top-level grammar. Not observed in the wild; same root, so it goes now rather
than being found the hard way later.

### Fixed at the one place that hands out rows

`PyClosureAllocRow` now returns a row in a DEFINED state — every field, both on
the fresh path and the recycled one. Split responsibility across a free routine
and N builders is what left four fields unowned; one owner cannot.

### Verified

`test/test_nilpy_lambda_arity.npy` EXTENDED — it already owned this subject
(including the "a nested def must stay LENIENT" case, which passed because it
never recycled a row). The new section churns zero-arg lambdas so their rows are
on the free stack, THEN builds a def through `exec` and calls it through a host.

A/B'd against MY change, not against `pinned`: dropping just the two `ReqN`/
`TotN` resets makes it raise again.

`make test-uforth` still PASS · `tools/gate.sh quick` GREEN · self-host
byte-identical.

uforth's `value` / `TO` / `create` / `allot` now match CPython exactly.

## Beyond this ticket

The RC4 corpora (`testje.for` and its three variants) get further but are still
not green — all four now end in `ERROR: Stack underflow` where CPython prints
the cipher output. Filed as [[bug-nilpy-uforth-rc4-corpus-stack-underflow]].

## Log
- 2026-08-08 — resolved, commit d019ddb9f.
