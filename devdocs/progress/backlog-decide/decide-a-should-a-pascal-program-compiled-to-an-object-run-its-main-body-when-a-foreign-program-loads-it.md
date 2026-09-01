---
slug: decide-a-should-a-pascal-program-compiled-to-an-object-run-its-main-body-when-a-foreign-program-loads-it
title: "Should a Pascal program compiled with --emit-obj run its main body when a foreign program loads it?"
track: U
prio: 55
type: decide
status: new
blocked-by: []
owner: user
summary: "The C half of bug-a-c-an-emit-obj-object-linked-into-a-non-pxx-program-never-runs-its-initialisers is fixed (41b08f2bf, c1bb99ec2) because a C translation unit has file-scope initialisers and no main body -- the two are not confusable. Pascal has both, at the same code offset, and they need opposite answers. MEASURED broken: a Pascal object's globals read 0 from a gcc host (flag=0, msg empty, want 4242/pxx-pascal-init). MEASURED that the obvious fix flips a DELIBERATELY PINNED property: test/test_emit_obj.pas reads `g` specifically so emit_obj_addup(9) is 45 and not 45+9, with a comment saying that is the property being pinned and that the VALUE says which world we are in -- the tripwire fired, expected 45, got done99. Three options below; my recommendation is B."
---

# Should a Pascal --emit-obj object run its main body?

## Why this is not a bug I can just fix

For C the question does not arise. A translation unit has file-scope
initialisers and no `main`, so "run the initialisers, do not run a main body" is
one unambiguous thing, and that is what landed.

A Pascal `program` emits, at code offset 0 and in this order:

1. `CompilePendingGlobalInits` — typed consts and global initialisers
2. the unit initialization sections, `EmitCallProc(InitProcs[i])`
3. the program BODY (`ParseBlock`, from `DbgMainBodyStart`)

They are contiguous with no `ret` between them, so "call offset 0" runs all
three. 1 and 2 are the Pascal analogue of the C fix and clearly SHOULD run in a
foreign host. 3 is the program, and running it at `dlopen`/startup time in
someone else's process is a different proposition — `test_emit_obj.pas`'s body
prints to stdout, which it duly did.

## The measurement, both directions

Broken today — `pinit.pas`, `--emit-obj`, linked into a gcc host:

    flag=0  msg=            (want flag=4242  msg=pxx-pascal-init)

With the C-style widening applied (`EmitSharedMode or EmitObjMode` in
`pasparser_prog.inc`), that becomes `flag=4242 msg=pxx-pascal-init` and the host
exits 0 — the fix works. And in the same run `test-emit-obj` went red:

    expected 45 pxx-emit-obj
    actual   done99 pxx-emit-obj

That is not a broken test. `test/test_emit_obj.pas` says, in a comment written
before any of this: *"`g` is DELIBERATELY read here. A foreign program that
links this object does NOT run the Pascal main body, so g is 0 at every call
from C and emit_obj_addup(9) is 45, not 45+9. That is the property being pinned:
the test would still pass if initialisation silently started running, but the
VALUE says which world we are in."* Someone anticipated this exact change and
left a tripwire. It fired. I reverted rather than retune the expectation,
because retuning it is the decision, taken quietly.

## Options

**A — run everything, body included.** One rule for `--shared` and `--emit-obj`,
and `--shared` already does this. Fixes the measured defect completely.
Cost: flips the pinned property; an object can print, block or exit during a
host's startup. `PXXExitProcess` in the old terminal would have terminated the
host outright — that part is avoidable (the shared thunk emits `ret`), but
"arbitrary Pascal runs while the host initialises" is not.

**B — run 1 and 2, not the body (RECOMMENDED).** Matches what the C fix
actually means by "initialisers", and preserves the pinned property. An object
gets its typed consts and unit init; a `program`'s body stays the program's.
Cost: `pinit.pas`-shaped code is still wrong, because a program body is where
Pascal programmers put `Flag := 4242` — so this fixes the defect for units and
typed consts and NOT for the shape I reduced. Needs a `ret` (or a separate
thunk) at `DbgMainBodyStart`, which is recorded already.

**C — refuse `--emit-obj` on a `program` with a non-empty body**, and direct
users at a `unit`. Honest and cheap, and turns a wrong value into a diagnostic.
Cost: it is a new refusal on something that works today, and
`feature-p-a-pascal-library-unit-does-not-parse` is open, so the alternative it
names does not exist yet.

## Recommendation

**B**, and file the `pinit.pas` shape as its own ticket under C rather than
letting it argue for A. "Initialiser" and "main body" are two concepts that
share a code offset by accident of emission order; the fix is to separate them,
not to pick which one wins. A is the tempting answer because `--shared` already
does it — but a `.so` is a thing you load ON PURPOSE for its side effects, and
an object linked into a program is not.

If A is chosen, `test/test_emit_obj.pas`'s comment must be rewritten in the same
commit, because it currently documents the opposite as intended design.

## State

C half landed and green (`41b08f2bf`, `c1bb99ec2`). Pascal half measured,
attempted, reverted; the attempt is a 1.5KB patch and is trivially
reconstructible from the two lines named above. `bug-a-c-an-emit-obj-object-...`
stays open for the Pascal arm and points here.
