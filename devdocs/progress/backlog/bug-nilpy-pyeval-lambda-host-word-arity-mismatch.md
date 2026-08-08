---
track: N
prio: 45
type: bug
summary: "pyeval raises `<lambda>() takes 0 positional arguments but 1 were given` for uforth's `value` / `TO` / `create` / `allot` — the PYTHON-bodied word is invoked with the VM argument its lowered lambda does not declare. Blocks the deeper uforth .for corpora."
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
