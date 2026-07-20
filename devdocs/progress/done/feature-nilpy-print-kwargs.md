---
track: N
prio: 55
type: feature
---

# NilPy: keyword arguments on the `print` builtin (`file=`, `flush=`, `sep=`, `end=`)

Hangs off [[feature-nilpy-corpus-uforth]]. This is uforth's wall as of
2026-07-20, at uforth.py:308, immediately after
[[feature-nilpy-bytes-and-slices]] landed both its halves:

```python
print(line, file=sys.stderr, flush=True)
```

## Why this is not already covered

Keyword arguments for `def`s and methods LANDED (see the uforth milestone-1
notes): `ASTIVal=paramIdx+1` on `AN_ARG` plus a post-loop reorder. `print` is
not a def — it is a builtin lowered by the frontend, so it never goes through
that path and has no parameter list to match names against.

## Census in uforth.py

| form | sites |
| --- | --- |
| `print(x, file=sys.stderr, ...)` | the trace/error paths |
| `print(..., end="")` | output words (Forth's `EMIT` / `TYPE` must not add newlines) |
| `flush=True` | paired with the `file=` uses |

`end=""` matters most for OUTPUT CORRECTNESS: a Forth interpreter that appends
a newline per `EMIT` produces the wrong transcript, and the suite is diffed
against CPython byte for byte.

## Shape

Recognise the four names on the `print` builtin only, with everything else an
error rather than a silent drop:

- `sep=` / `end=` — change the separator and terminator (default `" "` / `"\n"`).
- `file=sys.stderr` — route to stderr. `sys.stdout` is the default; anything
  else should be rejected until real file objects exist.
- `flush=` — accept and IGNORE is defensible here (output is unbuffered per
  line already), but say so in the code rather than dropping it silently.

Suggest doing this as an intrinsic argument shape, the same trade
`to_bytes`/`from_bytes` took, rather than generalising keyword arguments to all
builtins.

## Gate

`make test-nilpy` green with a `.npy` case diffed against CPython (must cover
`end=""` and stderr routing separately, since stderr does not show in a stdout
diff) + `--tier quick` + self-host byte-identical + `make fpc-check` clean
relative to HEAD.

## Log
- 2026-07-20 — resolved, commit HEAD.
