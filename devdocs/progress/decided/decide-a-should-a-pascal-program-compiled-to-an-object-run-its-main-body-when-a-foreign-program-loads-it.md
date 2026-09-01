---
slug: decide-a-should-a-pascal-program-compiled-to-an-object-run-its-main-body-when-a-foreign-program-loads-it
title: "Should a Pascal program compiled with --emit-obj run its main body when a foreign program loads it?"
track: U
prio: 55
type: decide
status: decided
blocked-by: []
owner: frankA
summary: "DECIDED: A -- an object runs the program body, same as --shared already did. Settled by archaeology rather than by preference, after the owner said the question as filed was not answerable without knowledge they do not have. THE FORK WAS NOT REAL: --shared has run unit init AND the program body since the shared-library fix (the test-shared row says so in its own name), so the two library-shaped outputs disagreed about the same source construct and only one of them had a reason. The test_emit_obj.pas comment I treated as pinning a design was written in 41045d7b4, the commit that INTRODUCED the object writer, describing behaviour that existed only because nothing ran an object's initialisers yet -- and its own wording guards against initialisation SILENTLY starting, which licenses a considered change. `library foo;` does not parse (feature-p-a-pascal-library-unit-does-not-parse), so `program` is the ONLY way a user can currently express this. Landed with the comment rewritten; i386/xtensa/riscv32 remain as bug-a-an-i386-emit-obj-object-still-never-runs-its-initialisers."
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

---

## Decision: A, and the fork was not a fork

The owner read this and said they could not answer it, reframing it as: *can a
program mimic a (shared) library — and the ticket seems to suggest we can.* That
reframing is what dissolved it. **We already do.** Three pieces of evidence, none
of which needs a preference:

1. **`--shared` already runs a Pascal program's body as library
   initialisation.** The Makefile row is named `DT_INIT runs unit init + program
   body in order`. Shipped and asserted. So "a program mimics a library" is
   settled pxx behaviour for one carrier, and `--emit-obj` disagreeing with it
   about the same source construct is an inconsistency, not a design.

2. **The comment I treated as authoritative was describing a defect.** It was
   written in `41045d7b4`, the commit that introduced this object writer, when
   nothing ran an object's initialisers because the mechanism did not exist. It
   records a state. And its own wording is a tripwire against drift, not a
   prohibition: *"the test would still pass if initialisation SILENTLY started
   running"*. It fired, the change was noticed and argued, which is what it was
   built to force. A tripwire retired quietly would have been the failure; one
   retired loudly is it working.

3. **`library foo;` does not parse.** So `program` plus `--shared`/`--emit-obj`
   is the only way a user can express "this is a library" at all. Option C
   (refuse) would forbid the only available spelling.

Option B — run the inits but not the body — dies on evidence 1: it would make
`--emit-obj` disagree with `--shared` deliberately, and it leaves the
`Flag := 4242`-in-the-body shape (which is where Pascal programmers put exactly
this) still wrong. I recommended B in the original filing. I was wrong, and I was
wrong because I read a comment as intent without checking when it was written.

## The process note, which is the part worth keeping

**This should never have been a decision ticket.** My own rule is that the worst
question is one a measurement would have answered — and this one was answered by
`git log -S` on the comment plus one `grep` of the Makefile row name. I filed a
fork because a comment asserted an intent, and I did not apply "comment vs code:
if they disagree, one is wrong and you do not know which" to the comment that was
telling me to stop. The tripwire was well built and it worked exactly as
designed; what it could not do is tell me how old it was.

Cost: one filed decision, one owner interruption, one revert of a working fix.
The owner's "I cannot answer this" was the correct response to a badly-framed
question, and the reframing did more work than the ticket did.

## What landed

Pascal terminal takes the thunk under `EmitSharedMode or (EmitObjMode and
TargetArch = TARGET_X86_64)`. The target gate is load-bearing:
`EmitSharedThunkPrologue` emits raw x86-64 pushes and `--emit-obj` also accepts
i386, xtensa and riscv32 — my first attempt was ungated and would have spliced
x86-64 bytes into those objects. It went unnoticed because `make` stopped at the
first mismatched row and never reached the i386 one.

    pinit.pas --emit-obj, gcc host   flag=0 msg=  ->  flag=4242 msg=pxx-pascal-init
    test-emit-obj x86-64 rows        45 pxx-emit-obj -> done99 pxx-emit-obj (body ran)
    test-emit-obj i386 row           45 pxx-emit-obj, unchanged and now documented

`test/test_emit_obj.pas`'s comment is rewritten in the same commit, as this
ticket required of option A.
