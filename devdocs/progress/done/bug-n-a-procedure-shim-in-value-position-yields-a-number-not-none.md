---
slug: bug-n-a-procedure-shim-in-value-position-yields-a-number-not-none
track: N
type: bug
prio: 45
status: done
owner: rd
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

# Fixed 2026-11-20 (rd): a third way, the one CPython takes

**Wider than the stdlib table.** Measured at origin/master f784b38446, the same
defect applies to ANY Pascal procedure a NilPy program calls in value position:
- a procedure in a Pascal shim unit printed its own argument
  (`print(m.poke(3))` -> `3`);
- a procedure METHOD printed a pointer (`469762080`);
- `v = m.poke(4); v is None` was `False`.

NilPy's own `def`s without a `return` were already correct.

**Neither option above.** Option 2 refuses a call that CPython accepts, since
`print(f())` on a function that returns nothing prints `None`. Option 1 is a
convention every shim author must remember. Instead the shared factor
dispatch (pasparser_expr.inc, after `PyParseFactorCore`) calls
`PyProcCallValueIsNone`:
- A call to a proc that is not `IsFunc` becomes `(call, None)`: an AN_COMMA
  tagged `PY_PROC_NONE_COMMA`.
- `PyBindDiscardedValue`, which both expression-statement arms go through,
  takes the bare call back out. A procedure called as a statement is
  therefore exactly what it was.

**Measured:**
- Five NilPy tests that call Pascal procedures (sys streams, array, itertools,
  wave, delitem) compile to byte-identical binaries before and after.
- The new test-nilpy row procnone26,
  `test_nilpy_a_pascal_procedure_used_as_a_value_is_none.py` (fixture
  `test/nilpy_procnone/`), covers:
  - a free procedure and a method, in value and statement position;
  - procedures inside a list display and inside a conditional;
  - side-effect counts, which prove each call still runs exactly once.

  It fails on the compiler before the fix.

The positive control the ticket asks for is this row: its fixture declares
procedures on purpose.
