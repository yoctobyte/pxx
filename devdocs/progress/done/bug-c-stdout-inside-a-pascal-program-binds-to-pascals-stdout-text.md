---
summary: "C: `stdout` in C compiled into a Pascal program was textfile.pas's `StdOut: Text`; `fp = stdout` segfaulted, and test-nilpy failed after e17b4497b4"
type: bug
prio: 70
---

# C: `stdout` inside a Pascal program binds to Pascal's StdOut Text

- **Type:** bug (C frontend, a silent miscompile that e17b4497b4 turned into
  a compile error). Found 2026-11-28: test-nilpy failed on master at
  test_nilpy_dotted_package_import, in pdfgen.c's `fp = stdout`.
- **Status:** done

## Symptom

C code reached through `uses 'x.c'` in a Pascal program, or through a NilPy
shim:

```c
FILE *fp; fp = stdout; fprintf(fp, "x\n");
```

Before e17b4497b4 this segfaulted at the fprintf. Since then it fails to
compile: "an assignment between a struct and a scalar needs a scalar
operand". `fprintf(stdout, …)` written directly worked. `stdin` was
unaffected, because Pascal has no `StdIn`.

## Cause

FindSym folds case, as Pascal needs. When C's `extern FILE *stdout` was
declared, the global-declaration path found textfile.pas's `StdOut: Text`
and merged into it, so C's `stdout` became that record. Pascal predefined
constants (`StdErr` = fd 2) already had this exception; Pascal variables
did not.

## Fix

- The C global-declaration path (plain globals and function-pointer tables)
  no longer merges into a row that matches only case-insensitively.
- CFindSymFromModule prefers a row spelled exactly like the C name.

Test c_in_pascal_stdout_is_c_stdout (row c_cso26), at x86-64 and i386: a C
helper picks stdout or stderr through a variable, writes through it, and
compares the pointers with the real ones.
