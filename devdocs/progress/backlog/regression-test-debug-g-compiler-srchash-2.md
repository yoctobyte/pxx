---
prio: 70
track: A
---

> **Track A from the job NAME `test-debug-g`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`tools/compiler_srchash.sh`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-debug-g#src:tools/compiler_srchash.sh at 7e5a0470a6b2 in step 1/2, `livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ "$liv…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T04:48:59Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +1
- **Failing step:** line 1 of 2 of the job's recipe; it names `tools/compiler_srchash.sh compiler/.pascal26.fixedpoint`.
  ```
  livesrc=$(tools/compiler_srchash.sh); \ stampsrc=$(sed -n 's/^srchash //p' compiler/.pascal26.fixedpoint); \ if [ "$livesrc" != "$stampsrc" ]; then \ echo "compiler/.pascal26.fixedpoint was written for DIFFERENT SOURCES than the tree has."; \ if [ -z "$stampsrc" ]; then \ echo " stamp sources: <none
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-debug-g#src:tools/compiler_srchash.sh'` at 7e5a0470a6b2fc7c8f66312889b1fd92c17c5443

## Range
> **The named sha `7e5a0470a6b2` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `7e5a0470a6b2`, last good `147b8a2ac642`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
compiler/.pascal26.fixedpoint was written for DIFFERENT SOURCES than the tree has.
  stamp sources: <none — written before the stamp carried a source hash>
  tree sources:  f9f7533766fa66785a4f5eb9712841e7af5d1eef8373cf5289eeb9c79eb02ced
A stamp NEWER than sources it does not describe is how this step
printed 'verified' three times in one day without building anything.
Recover with:  rm -f compiler/.pascal26.fixedpoint && make compiler/pascal26

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-06 — the seven watcher saw `test-debug-g#src:tools/compiler_srchash.sh` GREEN at 9046a2fdd628 (tier native) and did NOT close this: this is a repeat stub (`regression-test-debug-g-compiler-srchash-2`, not `regression-test-debug-g-compiler-srchash`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-06 — the seven watcher saw `test-debug-g#src:tools/compiler_srchash.sh` GREEN at 65dca57177b7 (tier native) and did NOT close this: this is a repeat stub (`regression-test-debug-g-compiler-srchash-2`, not `regression-test-debug-g-compiler-srchash`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.

## 2026-09-06 (frankH) — the guard is CORRECT; this is the stale-tree class, and it is now self-diagnosing

**Not a compiler regression.** The check this job runs is the fixedpoint stamp's
source-hash guard, and at current HEAD on plexus it passes. It is doing exactly
what it was built to do.

### What I measured

It reproduced here first, which was the useful part: `livesrc` and `stampsrc`
differed on my box immediately after a `git pull`. Then it went away after
`make compiler/pascal26`. **That is the guard working** — I had pulled 12
commits touching `compiler/**` and `lib/rtl/**` and not rebuilt, which is the
precise condition it exists to catch, and the one CLAUDE.md names as
*PUSH -> LET THE PULL SETTLE -> REBUILD -> MEASURE, with REBUILD dropped.*

So a job failing at the `$(COMPILER)` dependency across several unrelated tiers
(`test-emit-obj`, `test-zlib`, `test-lua`, `test-lua-cross`) is one tree-state
fact reported once per job, not N defects. The lua framing is a red herring, as
this ticket's own header predicted for the `test-debug-g` framing.

### The mechanism I could not distinguish, and why it mattered

The hashed set is five GLOBS (`compiler/compiler.pas`, `compiler/*.inc`,
`compiler/builtin/*.pas`, `lib/rtl/*.pas`, `lib/asmcore/*.pas`), so **an
untracked stray file dropped into any of them counts as a source**. Verified:
one `compiler/zz_stray_probe.inc` moves the hash and the count 214 -> 215.

But a stray alone is self-healing — it is also a make prerequisite, so the next
`make` rebuilds and re-stamps *including* it. Persistence therefore requires
either a stray created DURING a run, or a stamp from a genuinely different tree.
**Those two have different repairs and the message could not tell them apart:**
it printed two opaque 64-char hashes and one generic recovery line.

### What changed

The stamp now records `srccount N` beside `srchash`, and the failure branch
reports which way the difference goes:

- different count -> **the file SET changed**, plus the untracked/modified
  `.inc`/`.pas` in those directories, named
- equal count -> a hashed file's **CONTENTS** changed
- nothing dirty locally -> says so explicitly, because an empty suspect list is
  the informative case: it means the stamp came from a different tree

A stamp with no `srccount` (every checkout until its next rebuild) falls through
to the original message and claims neither.

Asserted in `tools/selfhost_stamp_devtest.sh`: both directions, the legacy
shape, and two tripwires below — a diagnostic that always picks one branch is
the same animal as a guard that cannot fail. Every new row was positive-controlled
by planting the violation and watching it go red.

### The first version of this fix turned `testmgr --tier quick` RED, and that is the second finding

I wrote the diagnostic as ~17 extra lines in the `$(COMPILER)` recipe plus a
recursive `$(MAKE)` to a helper target. `gate.sh quick` went RED with
`sh: 45: Syntax error: "(" unexpected` — and the recipe was fine in isolation
(`dash -n` clean), which is what made it confusing.

**`tools/compiler_srchash.sh`'s own header had already written the reason down**,
one target away from where I was typing:

> WHY A SCRIPT AND NOT A MAKE EXPRESSION ... a recipe that inlines
> `$(COMPILER_SRC) $(COMPILER_INC)` is echoed verbatim by `make -n` ... into the
> dry-run output that testmgr's `make_dry_run()` parses

I read that header, took it as being about the *file list* specifically, and
grew the same recipe anyway. It applies to **any** growth: the dry run went
24 -> 75 lines. And `make -n` **executes** `$(MAKE)` lines for real rather than
printing them, so a recursive sub-make in a recipe is worse than long.

The repair is the pattern the header prescribes — the logic moved into
`compiler_srchash.sh --diagnose`, costing the dry run one line (26 total).

Two tripwires now exist, because this trap had none: the recipe's dry run must
stay under 40 lines, and it must contain no recursive make. Both were confirmed
falsifiable by planting a violation (57 lines / a planted `$(MAKE)` both go red).

### Residual, and who owns it

I could not inspect seven, so **I did not establish which sub-cause fired there**
and I am not claiming it. That question belongs with Track T (harness build
ordering), not Track A — the compiler is not implicated either way. The next
occurrence answers it without anyone bisecting: the message now says whether the
set or the contents moved, and names the files if they are local.

## 2026-09-06, later — CORRECTION: the srchash check never failed. This is a job NAME.

Everything above about *which sub-cause fired* is answering a question that does
not exist. Read the 17:09Z full tier at `b76fce8` — which contains `85f8ad370`,
so the improved message was live — and the row reads:

> `self-host fixedpoint: verified — 1 round(s), 5375cb2828e8 (stamp read back;
> sources match it) | building gcc oracle ... | compiling pxx zlib runner ... | pascal`

**That is the guard PASSING**, inside the row we were all calling a srchash
failure. The job died later, compiling the zlib runner. The sibling row,
`test-emit-obj#src:tools/compiler_srchash.sh`, carries no srchash text at all —
it is `an i386 object's file-scope initialisers run under a gcc -m32 main`.

**Why 40 jobs carry a `compiler_srchash.sh` row.** `tools/testmgr.py:2538`:

```python
return "%s#src:%s" % (job.target, srcs[0])
```

A job is named after its FIRST source file, and every job depending on
`$(COMPILER)` inherits that target's own prerequisites at the head of its list
(`tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +11`). No single check
runs in 40 jobs and fails in 4.

### The two rows, correctly stated

| row | actual failure | lane |
| --- | --- | --- |
| `test-zlib#src:tools/compiler_srchash.sh` | pxx compile error in the zlib runner, after the gcc oracle builds | A or B |
| `test-emit-obj#src:tools/compiler_srchash.sh` | **WRONG — SUPERSEDED, see the second correction below.** This sentence is a log-tail success echo, not the failure. | A, i386 |

Neither is Track T, neither is harness ordering, neither is a stale tree.

### This ticket's own header said so, and I read it and misapplied it

> This job names a MECHANISM rather than a subject — the source it was fed
> (`tools/compiler_srchash.sh`) is what the mechanism was run ON, not what is
> being tested, so a lane guessed from it would be wrong by construction.

I quoted that line the same afternoon as being about the *lua* framing and did
not apply it to the *srchash* framing in the same sentence.

**And my local reproduction was real and about something else.** I made
`livesrc != stampsrc` fire on my own box by pulling without rebuilding, and took
it as reproducing the CI failure. It never errors; it answers a different
question — which is the failure mode CLAUDE.md names for every instrument that
lies.

### What survives

`85f8ad370` improves a genuine diagnostic and is green, positive-controlled, and
carries two dry-run tripwires that caught a real trap. **It is not a fix for
these rows and must not be cited as one.** The `srccount` field will help the
next real stamp mismatch, of which this was not one.

**Re-pointed, not resolved.** The row belongs to whoever takes the zlib compile
error; this ticket should be closed as MISNAMED rather than fixed.

## 2026-09-06, later still — the SECOND correction: the reason is a log TAIL, so the row's stated subject is the last thing that WORKED

The table above corrects the job NAME and then makes the same error one layer
up with the job REASON. **Row 2's stated subject is wrong**, and it is wrong by
the same mechanism it was written to expose.

`test-emit-obj#src:tools/compiler_srchash.sh` is **green at HEAD** and was fixed
by **`fc000b076`** — *"fix(A): the i386 PIC prefix guard stops reading a
displacement byte as a prefix"*. Its subject was never the file-scope
initialisers.

### Where the wrong subject came from

`tools/testmgr.py:job_reason()` returns **the log's tail**, deliberately and for
a good reason its own docstring gives (a signature list goes stale silently; a
tail is true for every failure shape). `tools/twatch.py:stub_reason()` then cuts
that to `CASCADE_REASON_MAX = 200` chars for a cascade bullet. What survived for
this row in `regression-cascade-6758c7ce7dbd.md` was:

> `ok: $TMP [code=470952B …] | test-emit-obj: an i386 object's file-scope initialisers run under a gcc -m32 main | ok: $TMP [code=186531B data=1360B bss=38460B procs=490]…`

All three fragments are **success echoes**. The middle one is the Makefile's own
`echo` on the line *after* the assertion it describes, i.e. the line that prints
only when that check has already PASSED. It became "the actual failure" in the
table above because it was the last human-readable sentence in a truncated
string, and the other two fragments are compiler statistics that do not look
like a subject.

**A tail brackets the failure; it does not contain it.** Read the last fragment
as *"everything up to here worked"* and go to the recipe line AFTER it. Here
that is the third fragment — building `i386_pcrel_globals.o` — and the very next
assertion is the one that was red:

```
if [ "$abs" -ne 0 ]; then echo "test-emit-obj: i386 .text still has $abs absolute relocation(s) ..."
```

### The real defect, and why the green is not the accidental one

`compiler/emit.inc:I386PrefixBefore` refuses a PC-relative rewrite when the byte
before the opcode is a legacy prefix. It could not tell a prefix from the last
byte of the previous instruction, so **a displacement byte that happens to equal
`$F0` reads as LOCK**. `Halt(code)` in `PXXIoCheck` emits `8b 45 f0`
(`mov -0x10(%ebp),%eax`) followed by the absolute store, and the `f0` of
`-0x10` disarmed the conversion — one absolute `.text` relocation, nothing
wrong with the code. `fc000b076` adds `X386InstrStart`, which lets a call site
announce that its opcode begins the instruction.

**This row could go green by accident and this green is not that.** One extra
unrelated local in `PXXIoCheck` moves `code` off `-0x10`, the displacement stops
ending in a prefix byte, and the count goes 1 -> 0 with the defect untouched —
measured by frankH, and the reason a green here needs a discriminator rather
than an exit code. The discriminator is **whether the load-bearing condition is
still present in the artefact**, and it is:

```
28f22: 8b 45 f0              mov    eax,DWORD PTR [ebp-0x10]   <- code still at -0x10
28f25: 51                    push   ecx                         <- converted store wrapper
28f26: 8b 8d ec ff ff ff     mov    ecx,DWORD PTR [ebp-0x14]    <- PIC anchor
28f2c: 89 81 46 94 00 00     mov    DWORD PTR [ecx+0x9446],eax  <- ModRM rebased
28f32: 59                    pop    ecx
```

Same offset, same `f0`, and the store converts anyway. Measured at HEAD
`2699f5769`, binary `c9de36a3754e`, `pascal26 -Fulib/rtl --target=i386
--emit-obj test/test_emit_obj.pas`: **0 absolute `R_386_32` in `.rel.text`, 587
`R_386_PC32`.** The row's own single-job repro line (the one printed at the top
of every auto-filed regression stub) returns **PASS, 1/1, GREEN**, with the i386
arm exercised rather than skipped (`gcc -m32` present on this box).

### Row 2 of the table above is superseded

| row | actual failure | lane |
| --- | --- | --- |
| `test-emit-obj#src:tools/compiler_srchash.sh` | i386 `.text` carried an absolute relocation because a `$F0` displacement byte read as a LOCK prefix — **fixed, `fc000b076`** | A, i386 |

### The durable half

This ticket's thesis is *"the name is not the thing"*. The sharpening is that
**the reason is not the thing either, and it is more dangerous than the name**,
because a name is obviously an identifier while a reason looks like content. A
truncated tail is the worst case of all: it reads as a finished sentence about
the subject, and it is a receipt for the last step that succeeded.

Nothing here is a defect in `job_reason` — the tail is the right thing for it to
return, and the untruncated 400-char form in `tstate/<host>.json` may well
contain the error line that the 200-char bullet cut. The failure is entirely in
the READING, which is why the fix is this paragraph and not a patch.
