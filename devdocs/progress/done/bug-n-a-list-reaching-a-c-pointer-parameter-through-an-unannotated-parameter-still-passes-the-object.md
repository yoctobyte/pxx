---
slug: bug-n-a-list-reaching-a-c-pointer-parameter-through-an-unannotated-parameter-still-passes-the-object
title: a list reaching a C pointer parameter through an unannotated parameter still passes the object
summary: >
  FIXED 2026-09-13. A list arriving through an UNANNOTATED parameter (a variant)
  now reaches a C `char **` parameter as a real array of pointers, like the
  static spellings already did. The ownership question that kept this open is
  answered by SPLITTING the decision: the OWNER does not have to be chosen at
  run time, only the CONTENT. `PyCoerceCallableArgsIn` hoists a caller-local
  `tmp := pyvar_cptrarray(v)` UNCONDITIONALLY -- a caller-local can be allocated
  without knowing whether it will be used -- and passes `pyvar_cbuf_or(v, tmp)`,
  which falls through to plain `pyvar_cbuf` when tmp is nil. Every non-list shape
  therefore emits exactly what it did before. Residual, named in the code: the
  arm is gated on the argument being AN_IDENT, because `v` is mentioned twice
  and a call in that position would be evaluated twice.
track: N
type: bug
prio: 45
owner: frank-user
status: done
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

## Resolution

Fixed. `pyvar_cptrarray(v)` (pylib) returns the pointer array as a TPyBytes when
`v` holds a tag-7 TPyList and nil otherwise; `pyvar_cbuf_or(v, arr)` returns
`pybytes_cbuf(arr)` when arr is non-nil and `pyvar_cbuf(v)` otherwise. The
frontend arm sits beside the static one in `PyCoerceCallableArgsIn`.

**The ownership answer, stated as the thing that was actually blocking:** the
ticket asked where the array's owner lives when the decision is made at run
time, and read the two as one question. They are not. **Only the CONTENT is
decided at run time; the OWNER can be decided statically**, because allocating a
caller-local temp costs nothing when it goes unused. So the decision did NOT
have to move back to the call site -- the ALLOCATION did, which the call site
can do unconditionally and without knowing the type.

## Verified

- `test/test_nilpy_a_list_reaches_a_c_pointer_parameter_through_a_variant.npy`,
  wired into the Makefile beside its static sibling. The list is forwarded
  through `def forward(path, args)` with `args` unannotated, and the readout is
  `/bin/echo` printing argv[1..].
- Positive control under pin v409: the last row prints
  `D execv returned -- argv was not an array of pointers`; the two rows above it
  are identical on both compilers, so the diff is exactly the one row that is the
  claim.
- Siblings still green: `test_nilpy_a_list_reaches_a_c_pointer_to_pointer_parameter`,
  `test_nilpy_a_bytearray_reaches_a_c_pointer_parameter`.
- `make compiler/pascal26` -> `converged after 1 round(s)`; `tools/gate.sh quick`
  and the full `make test-nilpy`.

## Still unmeasured, and it stays that way

`str` and `array` in this same position -- unmeasured when the static half
landed, unmeasured here. `pyvar_cptrarray` refuses anything that is not a
tag-7 TPyList, so they take exactly the path they took before this fix.

## Log
- 2026-09-13 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 114dfd769.
