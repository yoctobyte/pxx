---
track: A+C
prio: 55
type: bug
blocked-by: []
status: done
owner: frankA
created: 2026-09-01
found-by: frankA (while fixing bug-a-c-a-shared-library-never-runs-its-initialisation; frankC found the shared-library half)
summary: "FIXED for x86-64, both frontends. A pxx --emit-obj object never ran its file-scope initialisers in a foreign program, because they rode pxx's own entry stub and a gcc program has none. Fixed via .init_array/.fini_array in writeELFRelX64General plus the init thunk from the .so fix: C measured shared_c_from_data() NULL -> pxx-c-data and shared_c_envcount() -1 -> 73; Pascal measured flag=0/msg= -> flag=4242/msg=pxx-pascal-init, both under `gcc host.c lib.o`. The Pascal arm needed a decision first because a program body is not obviously an initialiser -- resolved as A (it is, and --shared already treated it that way) in decide-a-should-a-pascal-program-compiled-to-an-object-run-its-main-body-when-a-foreign-program-loads-it. i386/xtensa/riscv32 still do not, tracked as bug-a-an-i386-emit-obj-object-still-never-runs-its-initialisers."
---

# An --emit-obj object linked into a non-pxx program runs no initialisers

Split out of
[[bug-a-c-a-shared-library-never-runs-its-initialisation]], whose two shared
library halves are fixed (`7d1aed2b5`, `9b6ca0475`). This is the case that
ticket's reasoning excluded by a premise that holds everywhere except the
feature's purpose.

## Measured

```
$ pascal26 -Fulib/crtl --emit-obj test/test_shared_lib.c lib.o
$ gcc host.c lib.o -o host && ./host
obj from_data=(null) tag=pxx-c-shared
```

`shared_c_from_data` returns a file-scope `static const char *` initialised to
a string literal. The identical source compiled as a pxx **program** prints
`pxx-c-data` and matches the gcc oracle, and as a **.so** it now does too.

## Why the object case is different from the .so case

The C frontend emits `CompilePendingGlobalInits` at the start of `main`
(`cparser.inc`), so a translation unit with no `main` emits them nowhere. For
`--shared` that was fixed by emitting them into a DT_INIT thunk. **An object
has no dynamic section**, so there is nothing to point at: the standard
mechanism is a `.init_array` section holding a pointer to the initialiser
function, which the linker concatenates across objects and the host C runtime
runs before `main`.

So the work is:

- emit the initialisers into a real FUNCTION rather than inline (the .so thunk
  emits them inline, which an object cannot do — there is no entry to fall into)
- emit a `.init_array` section in the relocatable writer, with an
  `R_X86_64_64` relocation against that function
- decide whether the .so should ALSO move to `.init_array` for consistency, or
  keep DT_INIT. Both are correct; DT_INIT is what shipped.

## Scope note, and the reason this is not filed as "the same bug"

The `environ` half does **not** apply here: an object linked into a gcc program
gets glibc's `environ`, not ours, and `__pxx_run_initializers` is not wanted.
Only the file-scope initialisers are missing. Filing them together would
overstate what is broken.

## Not measured

Whether a pxx object linked into a **pxx** program is affected — the parent
ticket says it is not, because that program's entry stub runs the initialisers,
and nothing here contradicts it. Worth one run before the fix, since the fix
must not run them twice.

---

## C half resolved 2026-09-01 (frankA)

`41b08f2bf` — .init_array/.fini_array in `writeELFRelX64General`, appended after
.shstrtab's INDEX so no existing section index moves, with the init thunk from
the .so fix under a widened condition. One thunk, two carriers: glibc calls a
DT_INIT and an .init_array entry alike, with (argc, argv, envp).
`SharedInitOff`/`SharedFiniOff` became `InitThunkOff`/`FiniThunkOff`.

`c1bb99ec2` — corrects two things in the above. An object with nothing to
initialise now gets no thunk and no .init_array (decided by emitting the body
and reading CodeLen, not by a predicate that would need updating when a fourth
source of pre-main work arrives). And the byte-identity claim in `41b08f2bf` was
verified against a PASCAL object, which the Pascal frontend never gives a thunk
— a population that could not contain the phenomenon, so it agreed without
being able to disagree. Every C object had in fact been growing both sections.

**Two mechanisms, not one, same as the .so half:** `from_data()` needed the
initialisers to run at all; `environ` needed the environment, and the object
does not reach glibc's environ — it carries private storage nothing filled. I
had reasoned a gcc link would bind it to glibc's own and the measurement said
-1, which is the direction that ships half a fix.

**On `CNeedsEnvironInit`, which the parent ticket warns against widening:** that
warning is about widening it to BAIL under `EmitSharedMode`, which would delete
a dead-code tell while keeping a wrong value. This widened it the other way, to
be true where it was falsely false. The parent's premise for exempting
`--emit-obj` — "that object is linked into a program whose entry stub does run
them" — is the thing this ticket refutes.

## Pascal arm: measured, attempted, reverted

    pinit.pas --emit-obj, gcc host    flag=0  msg=          (want 4242 / pxx-pascal-init)
    with the C-style widening         flag=4242 msg=pxx-pascal-init, host exit 0
    same run, test-emit-obj           expected `45 pxx-emit-obj`, got `done99 pxx-emit-obj`

The third line is not a stale expectation. `test/test_emit_obj.pas` reads `g`
deliberately so that a foreign caller sees 45 rather than 45+9, and its comment
states that this is the property being pinned and that the value says which
world we are in. The tripwire was written before this work and it fired on the
first run. Retuning it would be taking the decision quietly, so the change is
reverted and the fork is filed.

**Why Pascal cannot borrow the C answer:** a C translation unit has file-scope
initialisers and no main body, so "run the initialisers" is unambiguous. A
Pascal program emits `CompilePendingGlobalInits`, then the unit init sections,
then the program body — contiguous, no `ret` between them, all at offset 0. The
first two should run in a foreign host; the third is a different question. They
share a code offset by accident of emission order, not by design.

---

## Pascal arm resolved 2026-09-01 — decided A, landed

The decision came back A: an object runs the program body, because `--shared`
already did and the two library-shaped outputs had no reason to disagree about
the same source. Full argument in the decision ticket; the short version is that
the comment I had read as pinning a design was written in `41045d7b4` describing
behaviour that existed only because the mechanism did not, and `library foo;`
does not parse, so `program` is the only spelling a user has.

    pinit.pas --emit-obj, gcc host   flag=0 msg=  ->  flag=4242 msg=pxx-pascal-init

**The target gate is the part to not lose.** `EmitSharedThunkPrologue` emits raw
x86-64 pushes; `--shared` is x86-64-only so its call site never needed a guard,
but `--emit-obj` also accepts i386, xtensa and riscv32. My first attempt widened
the Pascal terminal ungated and would have spliced x86-64 bytes into those
objects. It passed unnoticed because `make` stops at the first mismatched row
and never reached the i386 one — the x86-64 expectation failed first and masked
it. Anyone widening the gate must widen the emitter first.

`test/test_emit_obj.pas`'s tripwire comment is rewritten rather than deleted: it
now pins the opposite property and says why it changed, because a tripwire
retired quietly is worse than none.

## Log
- 2026-09-01 — resolved, commit 0148feacf.
