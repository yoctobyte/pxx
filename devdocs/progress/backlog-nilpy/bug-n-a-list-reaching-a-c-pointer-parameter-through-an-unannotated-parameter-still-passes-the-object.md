---
slug: bug-n-a-list-reaching-a-c-pointer-parameter-through-an-unannotated-parameter-still-passes-the-object
title: a list reaching a C pointer parameter through an unannotated parameter still passes the object
summary: >
  The VARIANT half of the list-to-C-pointer marshalling fix. A list whose static
  type IS TPyList (a literal at the call site, a local, or an ANNOTATED
  parameter) now becomes a real array of pointers; a list arriving through an
  UNANNOTATED parameter still passes the object pointer, so the callee reads the
  VMT word as its first `char *`. Measured 2026-09-13: the same execv program
  prints `C three words` for all three static spellings and execv RETURNS for the
  unannotated one. `def f(args: list)` is therefore a WORKING ONE-TOKEN
  WORKAROUND, which was not recorded anywhere. The open question is ownership,
  not detection -- the run-time route is `pyvar_cbuf`, which returns a Pointer
  and can own nothing, so deciding at run time to build an array puts the
  array's owner inside a function that has none.
track: N
type: bug
prio: 45
owner: unassigned
status: open
---

## Why this is a ticket and not a line in `done/`

The fix that landed (`dca30fbae`,
[[bug-n-a-list-bound-to-a-c-pointer-to-pointer-parameter-passes-the-object-pointer]])
closed the static spelling and left this half open ON PURPOSE, recorded under
"Still open, deliberately" in the resolved ticket's body. That is a live
question filed where `ready` and `next` never scan -- `done/` is not ranked --
so it was invisible to the queue while reading as handled. Filed here so it can
be ranked; the history stays in the resolved ticket.

## Measured 2026-09-13 (frankS), at 9393ab277, live

One program, four spellings of the same call, `/bin/echo` as the readout (it
prints argv[1..], so a wrong pointer shows up as a wrong line and a wrong
terminator walks off the end). `D execv returned` means execv FAILED, i.e. argv
was not an array of pointers:

    execv("/bin/echo", [b"/bin/echo", b"C", b"three", b"words", None])
                                                 ->  C three words      ok
    argv = [...]; execv("/bin/echo", argv)       ->  C three words      ok
    def go(args: list): execv("/bin/echo", args) ->  C three words      ok
    def go(args):       execv("/bin/echo", args) ->  D execv returned   BROKEN

## The boundary is the STATIC TYPE, and an annotation crosses it

The third row is the one the resolved ticket does not mention and it changes how
this should be ranked. `PyCoerceCallableArgsIn` hoists
`tmp := pylist_cptrarray(lst)` when the argument is statically TPyList, and an
annotated parameter IS statically TPyList. So:

**`def f(args: list)` is a working workaround costing one token.** Anyone hitting
this on real code -- lekkerzeilen is the live case, every C API taking an array
of strings lands here -- can move today without waiting for this ticket. That
was worth knowing and was not written down.

It also means the compiler is not missing the ability to BUILD the array; it is
missing the ability to decide to at run time.

## The open question is ownership

Unchanged from the resolved ticket, and it is the whole ticket:

`pylist_cptrarray` builds the array into a TPyBytes and the CALLER owns it,
which is what makes the static path safe. The variant route is `pyvar_cbuf`,
which returns a bare `Pointer` and can own nothing -- so deciding at run time to
build an array puts the array's owner inside a function that has none. A scratch
pool is wrong the moment two are live in one call. Options not yet costed:

- give the variant route the same caller-owned hidden temp the static one has,
  which means the DECISION has to move back to the call site even though the
  TYPE is only known at run time;
- have `pyvar_cbuf`'s caller own a slot per argument;
- refuse loudly instead of passing the object, which is strictly better than
  today (a wrong pointer into a C API is the silent-wrong-value shape) and is
  not the fix.

## Still unmeasured

`str` and `array` in this same position -- flagged as never measured when the
static half landed, and still not measured here. Do not assume they behave like
`list`.

## Ownership

Unowned as of 2026-09-13. frankuser (who fixed the static half) explicitly
declined it; frankS (who filed this) is on the bare-builtin-as-a-value group and
is not taking it. Free to take.
