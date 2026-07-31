---
track: A
prio: 45
type: bug
---

# `uses sysutils, pylib` fails to compile; `uses pylib, sysutils` is fine

Pre-existing (reproduces on `stable_linux_amd64/default/pinned`). A two-line
program is enough:

```pascal
program t;
uses sysutils, pylib;      { swap the two and it compiles }
begin
  WriteLn(1);
end.
```

```
error: undefined variable (msg)
  near:  AnsiString   begin msg >>>  m
```

The failure is inside **pylib's own** `Exception.Create`, where `msg := m` no
longer resolves `msg` to the class's field. pylib declares an `Exception` class
and so does sysutils; with sysutils compiled first, pylib's constructor body
binds against the wrong class and its field vanishes. Which unit is named first
should not change whether a library compiles.

Related, and probably the same root: [[bug-nilpy-rtl-exception-surface-shadowed]]
— pylib's Exception shadows sysutils', so `Exception.CreateFmt` is missing from
NilPy. One of the two classes has to win properly, or they have to be one class
(the "ONE Exception class" work in `873a693e` did that for the NilPy side).

## Where it bites

`lib/pcl/mimic_reportlab_pdfgen.pas` needs both (pylib for Python-shaped keyword
arguments, sysutils for `raise Exception.Create`) and carries a comment pinning
the order. Any library in the same position has to know this folklore.

## Gate

`make test` + a regression test with both orders, and the pylib/sysutils
Exception surfaces both reachable.

## Log
- 2026-08-01 — resolved, commit 382b75e54.
