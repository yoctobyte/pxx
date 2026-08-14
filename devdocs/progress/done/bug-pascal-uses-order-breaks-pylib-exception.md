---
track: A
prio: 70
type: bug
summary: "The name `Exception` is DELIBERATELY shared between pylib and sysutils (ClassNameIsDeliberatelyShared), which is what makes `except Exception:` catch either runtime — so this is a design tradeoff with a measured cost, not simply an unfixed bug. Under `uses sysutils, pylib` pylib cannot add any member sysutils lacks. Superseded by decide-pylib-exception-vs-sysutils-exception; do not fix this until that is answered."
status: done
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


## 2026-08-14 — CORRECTED, and superseded by a Track U decision

Two things in my 2026-08-13 reopen above need fixing, and the second matters.

**Master is no longer red.** `feat(N) e.args` was reverted the same night;
plexus is GREEN across native, full, slow and opt at `618371ac365d` with zero
open regressions. The summary's "master is red" was true when written and is not
now.

**And "the 08-01 fix was a microfix, root cause untouched" is too simple.**
Track N measured what I did not: `ClassNameIsDeliberatelyShared('exception')`
exempts the name from `FindUClass`'s own-unit preference **on purpose**, and
that exemption is what makes a bare `except Exception:` catch a raise from
either runtime. Removing it was tried — pylib then sees its own class correctly
and the unification breaks, so `_b` fails at run time. The exemption is
load-bearing exactly as designed.

So this is not a fix someone neglected to finish. It is a **deliberate tradeoff
whose cost was invisible until the first member was added that sysutils lacks**,
and the honest statement of the defect is: *pylib can never extend Exception
beyond sysutils' surface.* My reopen was right that the class of bug survived,
and wrong about why.

**Do not act on this ticket.** The fork belongs to
[[decide-pylib-exception-vs-sysutils-exception]] (Track U, p55) — who owns
`Exception`, and how pylib extends it. Whatever is decided there determines
whether this ticket becomes an A-lane resolution change (its option 4), a B-lane
RTL change (option 1), or is closed as working-as-designed (option 3). Prio
stays 70 so it does not drift out of sight while that is open.

## RESOLVED 2026-08-14 — by construction, not by a fix here

`uses sysutils, pylib` compiles, and so does the reverse, because there is no
longer a name to fight over: pylib's Python root is `PyException`
([[decide-pylib-exception-vs-sysutils-exception]] option 5, commit 6ed45773f).
`Exception` means sysutils' class in a Pascal program, full stop, and pylib's
own constructor bodies resolve `msg` against their own class in every uses
order.

`test_uses_order_pylib_exception_a` and `_b` now print **identical** output —
`_b`'s recorded expectation was `[%5d]`, which was the order-dependence this
ticket describes, written down as if it were correct. Both are `[    3]` now
(sysutils' padded `CreateFmt`), and that equality is what the pair asserts.

`ClassNameIsDeliberatelyShared`, the mechanism this ticket is about, is deleted.
The "design tradeoff with a measured cost" in the summary above is no longer a
tradeoff anyone has to make.
- 2026-08-14 — resolved, commit 84dcd2326.
