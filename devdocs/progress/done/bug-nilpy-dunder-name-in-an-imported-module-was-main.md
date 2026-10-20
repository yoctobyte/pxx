---
track: N
prio: 25
type: bug
---

# `__name__` was "__main__" in an imported module; `sys.stdout = None`

Found 2026-10-20: Vloot's backend.py ends with `if __name__ == "__main__":
main(...)`, and importing it ran that block, so every mode of the app first
printed a JSON dump. An imported module now answers its dotted name
(`pkg.sub.mod`; a package's `__init__` the package; a mimic_ shim the module it
stands for).

Same program, console.py: `sys.stdout = None` (written after a BrokenPipeError)
did not compile ("IR_UNSUPPORTED ... kind 8", which named no file). It now
points fd 1 (or 2 for stderr) at /dev/null (pysys_stream_to_none, dup3 in
pypal), so later prints go nowhere, as in CPython. `sys.stdout` still reads as
the stream object afterwards, not None. Other values are still refused.

Test: test_nilpy_dunder_name_and_stdout_none (CPython output).
