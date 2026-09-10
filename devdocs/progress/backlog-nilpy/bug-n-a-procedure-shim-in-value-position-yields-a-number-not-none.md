---
slug: bug-n-a-procedure-shim-in-value-position-yields-a-number-not-none
track: N
type: bug
prio: 45
status: backlog
owner: ""
created: 2026-09-10
found-by: frankB
tags: [nilpy, stdlib, silent-wrong-value, none]
blocked-by: []
summary: "A dotted stdlib call whose pylib shim is a PROCEDURE prints a number when used as a value: `print(sys.stdout.flush())` printed `1` where CPython prints `None`. The AN_CALL node is built the same way for a procedure as for a function, so the value read is whatever sits in the result slot — a plausible wrong number rather than a refusal. Found while adding sys.stdout.flush and fixed FOR THAT ENTRY by returning pynone; the mechanism is unchanged and `pysys_exit` is the other procedure in the table. Either every shim returns a value, or PyParseStdlibCall must refuse a procedure entry in value position."
---

# Measured 2026-09-10, compiler `4d3d006cf973`

With `pystdout_flush` declared `procedure`:

```python
import sys
print(sys.stdout.flush())
```

```
CPython: None
pxx:     1
```

`1` is not a value the program can explain — it is the result slot, read as an
Integer. No error, no warning.

# What was done about it, and what was not

`pystdout_flush` / `pystderr_flush` became `function ...: Variant` returning
`pynone`, so those two rows now answer `None` exactly as CPython does, and
`test/test_nilpy_the_sys_streams.npy` asserts it. **That fixes the entry, not
the mechanism.**

`PyStdlibCallProc`'s other procedure is `pysys_exit`, which nobody writes in
value position because it does not return — so the table has exactly one
observable instance today and it is closed. The next procedure entry someone
adds reopens it, silently, and the tell is a number nobody wrote.

# The two ways to close it

1. **Every shim returns a value.** Cheap, local, and the rule is invisible: the
   next author has nothing telling them a procedure is unsafe here.
2. **`PyParseStdlibCall` refuses a procedure in value position.** Needs the
   parser to know whether the resolved proc is a function, which `Procs[]`
   already records. A compile error naming the call is strictly better than a
   number.

Option 2 is the one that cannot be forgotten, and it is a guard rather than a
convention.

# Positive control

Declare any table shim as a `procedure`, print its call, and assert the program
does NOT compile (option 2) or prints `None` (option 1). A control that only
checks a working entry cannot fail — the defect is in what the mechanism
permits, not in what any current entry does.
