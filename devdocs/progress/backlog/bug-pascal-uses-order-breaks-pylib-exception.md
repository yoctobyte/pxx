---
track: A
prio: 70
type: bug
summary: "REOPENED 2026-08-13: `uses sysutils, pylib` fails to compile again. The 2026-08-01 fix (382b75e54) made the then-existing fields resolve but never fixed the root cause, so the FIRST new field on pylib's Exception (`argsv`, added by 67910b097 feat(N)) re-broke it verbatim. Master is red. Track N is the trigger, not the cause."
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

## REOPENED 2026-08-13 — the 2026-08-01 fix did not hold, and could not

Track T's watcher went RED at `1df75aad5458` on
`test-core#src:test/test_uses_order_pylib_exception_a.pas` — the very
regression test this ticket's Gate asked for. It did its job.

**The original two-line repro at the top of this file fails again**, verbatim,
against a compiler rebuilt at HEAD:

```
$ ./compiler/pascal26 /tmp/uo_orig.pas /tmp/uo_orig26
pascal26:4824: error: "argsv": no such member on this record/class
  near: k    e  >>> argsv  TPyList
```

Same program, same uses order, same mechanism — **a different field**. In August
it was `msg`; now it is `argsv`, at `compiler/builtin/pylib.pas:4824`
(`e.argsv := TPyList.Create`). Reverse the uses clause and it compiles; the
`_b.pas` companion, which names pylib first, still passes.

### So this was a microfix, and the root cause is untouched

`382b75e54` made the *then-existing* fields of pylib's `Exception` resolve. It
did not fix "pylib's own implementation binds `Exception` against sysutils'
class when the CONSUMER names sysutils first". That defect sat dormant for
twelve days purely because nobody added a field — and the moment
`67910b097 feat(N): e.args, and the KeyError repr it unblocked` added one, it
returned unchanged.

**Any new member on pylib's `Exception` re-breaks `uses sysutils, pylib`.** That
is the actual bug, and it is a booby trap for every future N/B change: the lane
that adds the field is not the lane that owns the defect, and the failure
surfaces far from the edit.

### Track N is NOT at fault — do not route it there

The obvious reading is "the `feat(N)` commit turned it red, so N broke it".
It did not. Adding a field to a class your own unit declares is unremarkable
code. `67910b097` is the *trigger*, not the cause, and reverting it would only
re-arm the trap for the next field. This ticket stays **Track A**, where the
name-resolution defect lives.

### Why the Gate passed in August and the bug survived

The Gate asked for "a regression test with both orders". It got one, and the
test is good — it caught this within hours. But a test pinned to the fields that
existed on the day cannot prove the *class* of bug is gone. Whatever fix lands
now should be checked by adding a throwaway field to pylib's `Exception` and
confirming `uses sysutils, pylib` still compiles — that is the property, and it
is the one thing neither the old fix nor the old Gate established.

See `devdocs/dev/root-cause-over-microfix.md`; this is a worked example of
exactly what it warns about, including the part where the microfix looked
complete because the symptom was gone.

## Log
- 2026-08-01 — resolved, commit 382b75e54.
- 2026-08-13 — REOPENED by Track T. Fix did not hold; root cause never
  addressed. Consolidates the auto-filed stub
  [[regression-test-core-test-uses-order-pylib-exception-a]].
