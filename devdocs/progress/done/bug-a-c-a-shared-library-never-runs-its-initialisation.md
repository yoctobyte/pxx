---
track: A+C
prio: 55
type: bug
status: done
found: 2026-09-01
found-by: frankC
owner: frankA
summary: "NO pxx shared library runs its initialisation, so every piece of pre-main state is left unset. MEASURED both frontends against a gcc dlopen host: a Pascal program whose body does `Flag := 4242` exports GetFlag, which returns 0; a C library reading `environ` gets (nil). Cause is one thing, not two -- a .so has no ELF entry point and elfwriter.inc emits NO DT_INIT and NO .init_array (neither string appears in the file), so the initialisers are compiled in and nothing calls them. Under --shared, naming environ costs 51 extra procs (451 vs 400) that provably cannot run; under --emit-obj it costs 0, correctly, because THAT object is linked into a program whose entry stub does run them. The dead code is the TELL, not the bug: do not 'fix' CNeedsEnvironInit by bailing under EmitSharedMode -- that deletes the evidence and keeps the wrong value."
---

# A shared library never runs its initialisation

`--shared` landed 2026-09-01 (`0419bab94`, `46586dba8`). It produces a file that
links and loads. Everything it was gated on is true. What no gate asked is
whether the code inside it has been INITIALISED when a caller arrives.

## Repro — both frontends, gcc host, dlopen + dlsym + call

```pascal
program pinit2;                        { --shared pinit2.pas pinit.so }
var Flag: Integer;
function GetFlag: Integer; cdecl;
begin GetFlag := Flag; end;
begin
  Flag := 4242;                        { the program body: pre-main state }
end.
```
`GetFlag()` through `dlopen` returns **0**, not 4242.

```c
extern char **environ;                 /* --shared envlib.c envlib.so */
char **get_env(void) { return environ; }
```
`get_env()` returns **(nil)**.

## Control, and it is what identifies the cause

| mode | names `environ` | does not |
| --- | --- | --- |
| `--emit-obj` | procs=400 | procs=400 |
| `--shared` | **procs=451** | procs=400 |

`--emit-obj` bails correctly: that object is linked into a program that HAS a
pxx entry stub, and the stub runs the initialisers. `--shared` inherited the
ACTIVATION without inheriting anything that could call it — 51 procs of
initialiser machinery, provably unreachable, in every C `.so` that mentions
`environ`.

## One cause, not two

`elfwriter.inc` contains **no `DT_INIT` and no `.init_array`** — neither string
appears in the file. A `.so` has no ELF entry point by design; the host supplies
one, and the loader is supposed to be told about initialisers through the
dynamic section instead. It is not being told.

So the Pascal program body and the C `environ` shell fail for the identical
reason, and a fix that addresses either one alone is a microfix.

## Why the obvious one-liner is the WRONG fix

`CNeedsEnvironInit` (`cparser.inc:9699`) bails on `EmitObjMode` and not on
`EmitSharedMode`. Widening it deletes the 51 dead procs and leaves `get_env()`
returning nil — it makes the symptom quieter and fixes nothing. The dead code is
evidence that someone intended initialisers to run.

Found as the sibling of `46586dba8`, which widened the entry-stub guard three
lines away for exactly the reason that applies here. That commit is right; this
is the next site along the same seam. The grep is `EmitObjMode` not followed by
`EmitSharedMode` — `asmfront.inc:420` and `:700` are the other two survivors and
are unmeasured.

## What the fix needs

1. `writeELFSharedX64` emits an init entry — `.init_array` +
   DT_INIT_ARRAY/DT_INIT_ARRAYSZ, or DT_INIT. A real choice: glibc honours both,
   `.init_array` is what a C toolchain emits, DT_INIT is fewer moving parts.
2. It must point at code that runs the same work the entry stub does — the
   Pascal program body, and `__pxx_run_initializers` (`cparser.inc:9973`), which
   today is emitted and patched only on the entry-stub path.
3. DCE must keep that alive with no in-image caller.

Only (1) is the ELF writer; (2) and (3) are the frontends and `dce.inc`. That
split, plus the DT_INIT-versus-.init_array choice, is why this is filed rather
than fixed where it was found.

## Not measured

Whether a `.so` also fails to run FINALISATION, and whether the RTL's heap or
string state needs the same treatment before a library call is safe at all.
Both are the obvious next questions and neither was tested.

## Log
- 2026-09-01 — resolved, commit PENDING-COMMIT.


## Resolved

Both halves fixed: Pascal in `7d1aed2b5`, C in `9b6ca0475`. A .so now runs its
global initialisers, its unit initialization sections and its program body, in
order, and its finalization at unload -- verified through `dlopen` AND through
`ld.so` at process startup, on both frontends.

**The cause was right and incomplete.** No DT_INIT and no .init_array is exactly
why nothing ran, and I confirmed that from a built artefact rather than from the
report. But the C side had a SECOND, independent mechanism the ticket does not
name: `CompilePendingGlobalInits` is emitted at the start of `main`, and a
library is precisely a translation unit with **no main**, so a C .so's
file-scope initialisers were never emitted anywhere at all. `static const char
*n = "lit"; return n;` came back NULL for that reason and not for the entry-stub
one. The two fail separately and are asserted separately now.

**`environ` needed more than a call site.** `__pxx_run_initializers` derives
envp from the Linux initial stack pointer, which a .so does not have -- at
DT_INIT time rsp is inside ld.so. The loader passes `(argc, argv, envp)`
instead, so crtl gained `__pxx_set_environ`, the half of the shell that knows
what `environ` IS, split from the half that knows where a PROCESS keeps it.

**The ticket's warning about the one-line fix was right, and for a second
reason.** Widening `CNeedsEnvironInit` to bail under `EmitSharedMode` would have
deleted the dead-code tell, as filed -- and it would also have made the
four-rationales note at the `cparser.inc` entry-stub guard WRONG rather than
merely incomplete, since that site and this one really do share the meaning
"there is no entry point". A note distinguishing meanings is tested by the first
site that genuinely shares one.

**Two things this ticket did not cover.**

`asmfront.inc:420` and `:700`, listed as unmeasured survivors, are still
unmeasured. They were not reached by either half of this fix.

And the object case is now its own ticket:
[[bug-a-c-an-emit-obj-object-linked-into-a-non-pxx-program-never-runs-its-initialisers]].
This ticket reasons that `--emit-obj` bails correctly because the object is
linked into a program with a pxx entry stub. That premise holds only when the
consumer is pxx-built -- and linking into foreign programs is what `--emit-obj`
is FOR. Measured: the same file as an object, linked by gcc, returns NULL too.
It is filed separately rather than folded in because a .so has a dynamic section
to carry DT_INIT and an object does not; it needs `.init_array`, a different
mechanism in a different writer. The `environ` half does not apply there at all.

**A test row had been reporting green while printing its own failure.** Found
while adding the C assertions: `tools/expect_same.sh` exits 1, but the
shared-library `@if` blocks chained with `;`, so the block's status was an
`echo`. The C row has been failing since it landed in `46586dba8` and reporting
success. Four chains changed to `&&` in `7d1aed2b5`, which is what made this
ticket's C half visible at all.
