---
track: C
prio: 60
type: bug
status: working
owner: frankb-56
created: 2026-09-06
found-by: frankA
tags: [tls, threads, c-frontend, errno]
blocked-by: []
summary: "RESOLVED 2026-09-16: `__thread`/`_Thread_local` now get real per-thread storage on x86-64 scalars, reusing the Pascal TLS mechanism (no new mechanism). Verified against gcc as oracle and against the PINNED compiler as positive control (1/4 kept, main-copy=103, FAIL). Degrades to today's shared copy with a specific reason where the mechanism cannot work, rather than refusing, because __thread compiles today and single-threaded programs using it are CORRECT. Residual owned by bug-c-thread-local-storage-still-shares-one-copy-off-x86-64."
---

# `__thread` is accepted and silently ignored

## Measured, 2026-09-06, at `1b903c1dd` / compiler `26b8b0adf442`

    __thread int tv = 7;
    int main(void){ printf("%d\n", tv); return 0; }

compiles clean, runs, prints `7`. The object:

    865: ... 4 OBJECT WEAK   DEFAULT 5 errno
    866: ... 4 OBJECT GLOBAL DEFAULT 5 tv        <- section 5 is .bss

`readelf -SW` finds **no `.tbss` and no `.tdata`** in any pxx object. The
storage class is dropped: `cparser.inc:11904` lists `_Thread_local` and
`__thread` in `CIsTopLevelSkipIdent`, whose own comment describes the set as
*"storage-class and function specifiers pxx does not model as type tokens but
tolerates by skipping"*.

Tolerating by skipping is right for `register` and `__restrict`, which are
hints. It is wrong for `__thread`, which changes what the program MEANS. Under
*"on par with the language, not with FPC"* this is squarely a bug and not a
compat item: a programmer writing `__thread` meant one copy per thread, that is
what the source says, and we give them one copy shared.

## The two frontends disagree about the same missing feature

| frontend | spelling | what happens |
| --- | --- | --- |
| Pascal | `threadvar tv: Integer;` | **refused**: `expected 'begin' before 'threadvar'` |
| C | `__thread int tv;` | **accepted, ignored** |

The Pascal refusal is the honest failure — it stops, and nobody ships a program
believing it has per-thread state. The C side is the silent one, and C is where
`errno` lives. Same absent mechanism, opposite failure modes, and the dangerous
one is in the frontend that needs it most.

## Why this is the general form of the errno bug

[[bug-a-errno-is-one-global-across-all-threads-so-a-thread-reads-another-threads-failure]]
reports `errno` shared across threads and names its root as
`lib/crtl/include/errno.h:5`'s `extern int errno;`. That is accurate, but it is
one *instance*: C11 7.5 requires `errno` to be thread-local, and pxx has no
thread-local anything. Fixing `errno` alone leaves every other `__thread`
declaration silently shared.

Reproduced the errno race independently while measuring this, at `1b903c1dd`
with a separately written probe: **A saw a foreign errno 33 times, B 4 times,
over 200000 iterations each; gcc/glibc 0 and 0.** That is the third independent
reading (franks-ab, frankD, and this one), each with its own probe.

## THE CONSTRAINT THAT BOUNDS ANY FIX — CORRECTED 2026-09-06 (frankC)

**The constraint recorded here was measured on the wrong register, and the
step-1 it prescribes is already done.** What stood here said *"pxx programs run
with FS base ZERO, in every thread"* and concluded that emitting TLS symbols
alone *"would be worse than nothing"* because there is no per-thread base to
resolve against. The FS reading is correct and the conclusion drawn from it is
not, because **pxx deliberately does not use FS.**

`thread_emit.inc:142`, in the clone stub, says so in its own comment: *"GS, not
fs: fs belongs to libc, and a pxx program may link one."* The stub issues
`arch_prctl(ARCH_SET_GS)` on every thread it creates, before anything Pascal
runs.

Re-measured with the same sentinel control (out variable preloaded with
`$DEADBEEFDEADBEEF`, syscall rc kept, so "the base is 0" and "arch_prctl never
ran" stay distinguishable), reading **both** registers:

**A pxx-native thread, via `BeginThread` — i.e. through pxx's own clone stub:**

    thread   rc   FS                  rc   GS
    main      0   0000000000000000     0   000000000042D110   <- .bss, the main block
    child     0   0000000000000000     0   00007BDB21FF7A80   <- carved off its own stack

    gs-differs-per-thread = TRUE      fs-differs-per-thread = FALSE

**So a per-thread base EXISTS on x86-64, is distinct per thread, is non-zero in
both, and is installed before user code runs.** Step (1) of the ordering below
is not work that needs doing; it is work that was done and filed under another
ticket (`feature-a-thread-local-storage-via-clone-settls`). There is even a slot
map already — `TLS_SLOT_*` in `defs.inc`, `TLS_BLOCK_SIZE = 1152`,
`TLS_SLOT_FIRST_FREE = 13` with three free map slots and a 64-slot tail — and
`ir_codegen.inc:78` records that **nothing uses it yet**, which is a different
fact from it not existing and is the one that matters here.

### Two real constraints replace the one that was wrong

**(a) GS-relative is not the psABI.** Standard x86-64 ELF TLS is FS-relative,
so a GS-based scheme serves pxx-compiled code and does NOT interoperate with
TLS relocations in a gcc-built object. For `errno` and for `__thread` in
pxx-compiled sources that is sufficient; for linking against foreign objects
that expect standard TLS it is not. **This is a genuine fork and it should be
decided, not defaulted** — the comment in the clone stub already argues one
side of it ("fs belongs to libc, and a pxx program may link one").

**(b) A thread pxx did not create does not get its own block — it INHERITS the
parent's.** Measured on the same probe with `pthread_create` from
`libpthread.so.0` instead of `BeginThread`:

    thread   FS                  GS
    main     0000737CBB197740    00000000004298F0
    child    0000737CBADFF6C0    00000000004298F0   <- IDENTICAL to main

    gs-differs-per-thread = FALSE    fs-differs-per-thread = TRUE

GS base is inherited across `clone`, and a glibc-created thread never passes
through pxx's stub, so it silently shares the creator's block. The FS column
flips at the same time for the same reason — glibc is present and sets FS.
**This is the failure mode the original entry was reaching for, and it is real;
it just is not "the base is zero", it is "the base is someone else's".** That
is strictly worse to debug, because it is a valid-looking pointer into another
thread's storage rather than a null you could test for — the exact hazard the
clone stub's own comment cites as its reason for installing GS first.

**Neither correction makes this ticket smaller.** `__thread` still compiles to
one shared `.bss` object and still warns rather than refuses. What changes is
the plan: the missing piece is not a per-thread base, it is (2) and (3) below
plus a ruling on (a) and a decision about (b).

**(c) THE EXISTING BLOCK CANNOT HOLD `__thread` VARIABLES — it is exactly
full.** Counted rather than estimated: `TLS_BLOCK_SIZE = 1152` is **144 slots**
of 8 bytes; 0..12 are taken, `TLS_SLOT_FIRST_FREE = 13`, and the heap magazine
starts at `TLS_SLOT_HEAP_MAG = 16` with `HEAP_MAG_BINS = 64` heads (16..79) and
64 counts (80..143). So slots 13, 14 and 15 are free — **three** — and the last
magazine count lands on the block's final slot.

An arbitrary number of `__thread` variables does not fit in three slots, so
this needs a growable per-thread area rather than the existing map. That is not
free: a cloned thread **carves its block off its own stack**
(`thread_emit.inc`), so growing `TLS_BLOCK_SIZE` costs stack in every thread,
and the main thread's block is a fixed `.bss` reservation (`BSS_TLS_MAIN`).
Whoever implements (2) is choosing an allocation strategy, not picking a spare
slot — and the three free slots are a trap, because they are enough to make a
one-variable proof of concept work and are not enough for the feature.

### Ordering, corrected

1. ~~a per-thread TCB with a distinct FS base~~ — **done, on GS, x86-64 only**.
   `__pxxTlsBase` refuses on every other target, and that refusal is the real
   target-set constraint: aarch64 and arm32 have a readable thread register
   (`tpidr_el0`, `tpidruro`) and no way to SET one yet.
2. per-thread storage for `__thread` variables, GS-relative, allocated out of
   the existing block — and a ruling on (a) before anyone emits a relocation.
3. `__thread` stops being skipped in `cparser.inc`.
4. and (b): decide what a foreign-created thread gets, because today it gets
   the creator's block and nothing says so.

## A cheaper path exists for errno alone, and it is worth pricing before (1)-(3)

`errno` does not need ELF TLS. glibc itself does not use a bare TLS object for
it in the ABI sense — the header is `#define errno (*__errno_location())`, and
the same shape works here:

- `lib/crtl/include/errno.h` declares `int *__errno_location(void)` and defines
  the macro, instead of `extern int errno;`
- the definition (today `int errno;` at `lib/crtl/src/stdio.c:66`) becomes a
  per-thread slot

**The open question is how a slot is found without TLS, and it has a real cost.**
`lib/crtl/src/pthread.c` already keeps a 64-slot registry keyed by tid
(`pxx_thr_reg`), so a lookup exists — but `__pxx_pthread_self` is a PAL symbol
that a non-`--threadsafe` build does not link, and `gettid(2)` on every errno
access puts a syscall on every error path. Neither is obviously right, which is
why this is written down rather than chosen here.

**It also does not fix `__thread`,** so it is a repair for the ticket next door
and not for this one. Worth doing first if the errno race is the urgent part;
worth knowing it does not close this.

## Acceptance

**Assert the RELATION, never a per-target constant** — two threads writing and
reading the same `__thread` variable must never see each other's value — so the
row needs no expected value and cannot pass by agreeing with a default.

**A row per target with an object writer.** TLS is emitted per backend and the
FS-base equivalent differs per architecture, so one green on x86-64 closes
nothing. The pre-fix build must come out WRONG on each, and it does today: the
variable is one `.bss` object everywhere.

**And assert the FS base is distinct per thread**, separately from the variable
test. The two can fail independently, and a probe that only reads the variable
cannot tell "TLS is not emitted" from "TLS is emitted and every thread resolves
it to the same block".

## RELEASE-RISK: DIAGNOSED

**Re-categorised 2026-09-06 by frankC, who owns the sweep — this was
`RELEASE-RISK: SILENT-WRONG` and the heading changed because the FACT changed,
not because the ticket got smaller.** frankA left the old heading in place and
asked rather than demoting it, which is the right way round: the set is derived
from these headings, so an edit is a ruling and should be made by whoever has to
defend the list.

The ruling: **a defect that gains a diagnostic changes STATE, it does not leave
the family.** The storage is still shared and the ticket is still open. What
changed is the only property the sweep was ever about — whether a user can
discover it from a message rather than from a race. Verified independently here
before re-tagging: 0 warnings for a program with no thread storage class, 1 for
one declaration, 1 for two (`__thread` + `_Thread_local`), and the defect
unchanged — still runs, still prints `tv=7`, still zero `.tbss`/`.tdata`.

It is now the ONLY member of the family a user can find out about, which is a
release-notes distinction and not a bookkeeping one.

### The original marker text, kept for history

The program compiles, runs, and is WRONG with no diagnostic — so a user cannot
discover it from a message and cannot work around what they cannot see. Marked
2026-09-06 for the beta 0.1 release sweep; a beta may ship known REFUSALS, but
an unenumerated silent-wrong is the class it must not ship.

Re-measured 2026-09-06 by this lane, independently of the filing: `__thread int tv = 7;` compiles, runs, prints `tv=7`, and `readelf -SW` finds ZERO `.tbss`/`.tdata` sections in the pxx object against gcc's one. Every thread shares one copy.

**AND IT IS NO LONGER SILENT — a warning landed the same evening, hours after
this marker.** The storage is still shared, so the DEFECT is unchanged and this
ticket stays open; what changed is that the compiler now says so, which is the
property the marker is about. Left marked rather than quietly demoted, so it
does not vanish from `grep -rl 'RELEASE-RISK: SILENT-WRONG'` without the sweep's
owner seeing it: **whether a diagnosed limitation still belongs in that set is
frankC's call, not a decision to take by editing a heading.** For release notes
the distinction is real — a user can now discover this one from a message, which
is exactly what the other members of the set cannot offer.

## 2026-09-06 (frankA) — IT WARNS NOW, and that is a different ticket from fixing it

The storage is still shared. What changed is that the compiler says so:

    pascal26:2: warning: '__thread' is not implemented and is being IGNORED — the
    variable gets ONE copy shared by every thread, not one per thread.
    Single-threaded code is unaffected; threaded code will read and write another
    thread's value with no further warning

Once per compilation, not once per declaration — two `_Thread_local`
declarations produce one warning, measured. A program with no thread storage
class produces none, also measured, because a warning that fires on everything
is not a warning.

**A warning and not a refusal, and the reason is not the empty population.** The
measured count of `__thread` under `test/`, `lib/` and `examples/` is ZERO, so
refusing would be free in this tree — that is exactly why it is not the
argument. Refusing would stop a SINGLE-threaded program that merely mentions
`__thread`, and such a program is correct today: one copy shared is one copy.
It would break working programs to protect broken ones. Real C from outside
this tree is where that cost lands.

**What this does and does not change.** A user can now discover the limitation
from a diagnostic instead of from a race, which moves it out of the
silent-wrong class a release cannot publish unenumerated. It does not implement
thread-local storage, and the FS-base constraint above is untouched.

Canary rather than a reading: the site was confirmed by planting an `Error` in
`CIsTopLevelSkipIdent` and watching it fire on `__thread int tv = 7;`, because
the declaration-specifier loop at `cparser.inc:5779` also consumes storage
classes and does NOT list these two — reading the source would have left two
candidate sites and no way to choose. The backward scanner `CDeclSawSpecifier`
calls the same predicate and deliberately does not warn: it READS the token
stream rather than skipping a declaration.

Verified: `make compiler/pascal26` converged, `dd5f6da0ac5b`.
`tools/gate.sh quick` GREEN.

## UNBLOCKED 2026-09-09 — the mechanism exists, and C needs a rewrite rather than a mechanism

`7a166c995` (frankH, Track P) shipped Pascal `threadvar` on the GS block.
Verified here rather than taken on the message: `TLS_USER_BYTES = 3072` and
`TLS_BLOCK_SIZE = TLS_USER_FIRST_OFF + TLS_USER_BYTES` in `defs.inc`,
`SymTlsOffset` in `defs.inc:4787` written at `pasparser_decl.inc:2723`, and
`ThreadVarRewriteRange` at `ir_codegen.inc:13783` called from `CompileAST`.

**Constraint (c) above is RESOLVED, and the trap it named was avoided.** This
ticket warned that three free slots are enough for a one-variable demo and not
for the feature, so whoever implemented it must size the area first. That is
what happened: a user area past slot 143 with a bump allocator, and the three
map slots untouched. Worth recording that the warning was followed rather than
just vindicated.

### What C actually needs

**One rewrite at the C frontend's own single lowering entry**, turning a
thread-local identifier into `AN_DEREF(AN_TLSBASE + const)`. There is no
addressing change and no new mechanism — the Pascal side does exactly this in
`ThreadVarRewriteRange` before anything lowers the tree, and `AN_TLSBASE`'s
`ASTIVal` is a **byte offset** from the base (0 for the `__pxxTlsBase`
intrinsic), which sidesteps whether `Pointer + Integer` scales: at IR level an
`IR_BINOP` on a `tyPointer` operand is a raw byte add.

**Do NOT add a fourth `TSymKind`.** frankH's reasoning, worth carrying because
it is the kind of thing a C implementer would rediscover the hard way: there are
**175 `Kind = skGlobal` tests tree-wide**, essentially all written
`if Kind = skGlobal then <absolute/RIP> else <rbp-relative>`. A fourth kind
lands in the `else` at every untaught site — a thread-local addressed as a
LOCAL, i.e. a plausible wrong address in the current frame. Keeping the symbol
`skGlobal` with its ordinary (unused) BSS storage means an untaught path reads a
process-wide global instead: still wrong, but it links and it is findable. That
is the same "prefer the failure that stays visible" choice this ticket's own
refusal argument rests on.

### The trap that cost frankH a round, and would cost C the same

**"AST nodes are only ever appended" is FALSE.** The arena is rolled back per
statement (`ASTNodeCount := ASTArenaFloor`, twelve sites), so node indices are
REUSED. A sweep using a high-water mark on `ASTNodeCount` silently skips any
statement whose tree is smaller than the previous one's — it failed on exactly
one statement, and adding an unrelated line in front of it made it pass. Sweep
`[ASTArenaFloor .. ASTNodeCount)` plus the unswept permanent region; see
`ThreadVarRewriteHigh`.

A bug that appears and disappears when you add an unrelated line is the shape
that gets called flaky and closed.

### Constraints C inherits unchanged

x86-64 only; scalars only (ordinal, pointer, float); refused under
`--emit-obj`/`--shared`. Managed types need per-thread init/final at thread
start and exit, for which no hook exists — a rung above, and the same rung for
both frontends.

**This does not fix `errno`.** C11 7.5 wants `errno` thread-local and the
mechanism now exists to make it so, but `errno` is declared in the crtl and
reached by the whole C runtime; that is a separate change with its own
measurement.

## RESOLVED 2026-09-16 (frankb-56) — `__thread` gets real per-thread storage on x86-64 scalars

**No new mechanism was written.** `7a166c995`'s TLS block, `SymTlsOffset` and
`ThreadVarRewriteRange` are frontend-agnostic — the rewrite runs from
`CompileAST` and fires on any `AN_IDENT` whose symbol has an offset — so C
needed declaration-side work only. Verified the precondition rather than
assuming it: a C global read lowers as `AN_IDENT` carrying its symbol index
(`PXXDBG=a.ast`, `kind=3 ival=294`).

### What landed

- **`TryAssignThreadVarStorage(idx, spelling, var why)`** — the Pascal allocator
  split so the refusal list and the bump allocator exist **once**. Pascal's
  `AssignThreadVarStorage` is now a four-line wrapper that `Error`s on `why`.
  A second allocator is the path that stays broken.
- **`CDeclSawThreadLocal`** — the same backward token scan as
  `CDeclSawStatic`/`CDeclSawExtern`, covering **both** spellings. `__thread` and
  `_Thread_local` are skipped without being recorded in three separate top-level
  loops, so the token stream is the only place the answer survives.
- **`CApplyThreadLocalStorage`**, called from **both** declarator arms of
  `ParseCGlobalVarDecl`. There are two, both registering through
  `CRecordGlobalLinkage`; hooking one would have left the sibling shape broken.
- The pre-emptive top-level warning is **retired**. It ran before the
  declaration was parsed, so it could not tell a variable that now works from
  one that degrades; the reason is known one layer down and that is where the
  warning now lives.

### The fork, decided against this ticket's own prescription, with the reason

This ticket specified C inherits *"refused under `--emit-obj`/`--shared`, x86-64
only, scalars only"*. **That was written before x86-64 worked — a prediction —
and it does not survive re-derivation against the built thing.** `__thread`
COMPILES TODAY: it is skipped, the variable gets one shared copy, and **for a
single-threaded program one copy shared IS one copy per thread**, so those
programs are correct and refusing them would break working programs to protect
broken ones. That is this ticket's own warn-not-refuse argument, which does not
expire because x86-64 started working. Pascal refuses because `threadvar` has
never compiled at any scope and has no population to break.

So C **implements where it can and degrades where it cannot**, naming which of
the four reasons applied. Net effect: **strictly better on x86-64 scalars,
byte-identical everywhere else, no regression anywhere.**

The in-tree population of `__thread` is **zero** (re-counted), so a refusal
would have been free here — which is exactly why that is not the argument. What
it costs is real C from outside this tree, the corpus this frontend is for.

### Measured

`test/c_thread_local_is_per_thread.c`, six rows, asserting the RELATION and no
per-target constant. Wired into `test-core`.

| compiler | kept | zeroed-on-entry | no-crosstalk | distinct-tids | main-copy | verdict |
| --- | --- | --- | --- | --- | --- | --- |
| **pxx, fixed** | 4/4 | 4/4 | 4/4 | 4/4 | 7 | OK |
| **gcc -O2 (oracle)** | 4/4 | 4/4 | 4/4 | 4/4 | 7 | OK |
| **pxx, PINNED (unfixed)** | 1/4 | 0/4 | 1/4 | 4/4 | **103** | **FAIL** |

**THE POSITIVE CONTROL IS THE PINNED COMPILER AND IT IS NOT PASSING FOR AN
UNRELATED REASON** — the caveat that usually sinks this instrument. Its run
emits the OLD `'__thread' is not implemented and is being IGNORED` warning,
which proves it reached the subject code path rather than feature-detecting
around it.

**Under `taskset -c 0` the fixed compiler still passes 6/6 and the pinned one
still FAILS** — `kept` and `no-crosstalk` stop discriminating when threads do not
overlap (a plain global reads back each thread's own last write), and the
verdict survives on `zeroed-on-entry=0/4` and `main-copy=103`. That property is
inherited from the Pascal twin, which measured it after a load-dependent control
went red on a busy box, and is documented in the C file so nobody trims the two
rows that look redundant on a 12-core host.

Also verified: `_Thread_local` behaves identically; a mixed TU
(`__thread` + two ordinary globals) matches gcc exactly (`6 12 23`); a program
with no thread-locals is untouched (`TlsUserUsed = 0` short-circuits the
rewrite); all three degradation paths compile with their specific reason.

### Residual, with an owner — this is not an all-clear

**"No regression anywhere" is true and is not the whole finding.** Multi-threaded
C using `__thread` off x86-64, or on an array, or under `--emit-obj`, or **at
function scope** still gets one shared copy. That is byte-identical to the
behaviour before this fix and it is still a wrong answer, so it is filed rather
than left implied:
[[bug-c-thread-local-storage-still-shares-one-copy-off-x86-64-and-a-warning-is-all-that-stands-there]].
**Function scope is the only member with no diagnostic at all** and should be
taken first.

Gate: `make compiler/pascal26` **converged after 1 round** (85e4f3c83aeb);
`tools/gate.sh quick` **GREEN**.
