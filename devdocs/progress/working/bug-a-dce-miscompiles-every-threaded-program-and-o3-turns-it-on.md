---
slug: bug-a-dce-miscompiles-every-threaded-program-and-o3-turns-it-on
track: A
prio: 80
type: bug
blocked-by: []
status: working
found: 2026-09-01
found-by: frankZ
owner: frankZ
summary: "`--dce` produces a broken binary for ANY program that starts a thread: segfault at -O0, infinite spin at -O2/-O3. Deterministic, 9-line repro, and `--no-dce` fixes it at every level — so it is the DCE pass alone, not an -O3 interaction. -O3 turns --dce on by default, which is the whole of why five optdiff shards went red. It is NOT fixed: d402a25b2 only stopped those programs COMPILING under optdiff, so the sweep will report green while the miscompile is live."
---

# `--dce` miscompiles every threaded program, and `-O3` turns it on

Measured 2026-09-01 by frankZ at commit `130b9a3e9`, binary
`59699dc0833f8110` (`converged after 1 round(s)`).

## The repro is nine lines and two flags

```pascal
{$threadsafe on}
program tsthr;
uses palthreadobj, sysutils;
type TW = class(TThread) public procedure Execute; override; end;
procedure TW.Execute; begin end;
var t: TW;
begin
  t := TW.Create(True); t.FreeOnTerminate := False; t.Start; t.WaitFor; t.Free;
  writeln('TSTHR OK');
end.
```

| build | result |
| --- | --- |
| `--threadsafe -O0` | `TSTHR OK` |
| `--threadsafe -O0 --dce` | **SIGSEGV**, no output |

The thread body is empty. Nothing about this program is a race.

## Do NOT narrow this to threading

The title says where it was OBSERVED, not what it is about. A whole-body DCE
defect is observable wherever a body **looks** dead and is not; threading is
simply where five shards happened to sit. Two reasons to hold that line:

- The owner, 2026-09-01: *"dead code elimination is a wasp nest.. because gcc
  and tcc do that even in O0. and that is exactly what broke busybox."* So DCE
  is closer to a lowering step than to an optimisation, **it has broken a real
  program in this repo before**, and that earlier break was not threaded.
  frankC landed busybox rung 2 (`833980766`, twelve applets, both targets) and
  holds that context — ask it before bisecting.
- `--dce` is separable from `-O`. The level and the pass are orthogonal, so
  **the -O level is the wrong axis to search along** — searching it is what
  made this look like an optimiser regression to three sessions in a row.

Two manifestations that fail DIFFERENTLY (a threaded lock test that
self-deadlocks, a busybox applet) are worth far more than two that fail the
same way. Look for what they share — what DCE believes is unreachable — before
bisecting either.

**If you build a harness that sweeps -O levels: `-O4` DOES NOT EXIST.**
`compiler.pas:1034` accepts `-O0`/`-O1`/`-O2`/`-O3` only and the compiler
answers `unknown option: -O4`. Sweep `-O0..-O3`, and make the harness FAIL on a
level it cannot run rather than skip it — a skipped level inside a stated sweep
is how `bug-t-an-actual-acceptance-record-cites-a-sweep-at-an-o-level-the-compiler-rejects`
happened.

## It is the DCE pass alone — not an -O3 pass, not a flag/directive mismatch

`test/lib_criticalsection_blocking.pas`, `--threadsafe`, same binary:

| build | 5 runs |
| --- | --- |
| `-O0` / `-O1` / `-O2` | `rc=0`, `count=8000` + `CSBLOCK OK` |
| `-O3` | `rc=124` (timeout) ×5 |
| `-O3 --no-dce` | `rc=0` ×3 |
| `-O3 -g` (`-g` disables DCE, `dce.inc:228`) | `rc=0` ×3 |
| `-O0 --dce` | **SIGSEGV** |
| `-O1 --dce` | **SIGSEGV** (frankC) |
| `-O2 --dce` | `rc=124` |

`--no-dce` fixes all five of the shards' programs, checked one by one by
frankC: `test_threadsafe_heap_lock_release`, `test_threadsafe_layout_rtti`,
`lib_criticalsection_blocking`, `lib_fpc_thread_surface` (all `-O3` rc=124),
and `lib_classes_tthread` (`-O3` rc=139).

DCE moves with the failure at every level and nothing else does. `-O3` is
implicated only because `compiler.pas:1799` turns `--dce` on there.

Two hypotheses this kills:

- **Not the rip-relative / PIE codegen** suspected in
  [[bug-a-five-optdiff-shards-are-one-o3-threading-hang]]. `--no-dce` leaves
  every one of those -O3 passes on and the program passes.
- **Not the `{$threadsafe on}` directive-vs-flag mismatch** that `d402a25b2`
  fixed. Every measurement above passes `--threadsafe` explicitly, which is
  the matched configuration.

## The hang shape

`-O3`, no `-g`: **one thread, state R, 100% CPU**, no output at all — it spins
before `TBumper` is ever created, so this is not lock contention.
`-O0 --dce` faults at `_start+214` (an inlined managed-pointer guard:
`test %rax,%rax; je; cmpq $0x40000000,-0x10(%rax)`), called from a frame the
map cannot name.

## Where to look

`--dce-report` on the criticalsection program: `bodies 785  live 127  dead 655`,
`code 322797B -> 72837B`. Diffing the map of `-O0` against `-O0 --dce` on the
nine-line repro, DCE keeps `ThreadObjLauncher`, `BeginThreadLauncher`,
`PalThreadCreate`, `PalThreadJoin`, `TThread.*`, `TW.Execute` — and drops
`PalThreadExit`, `EndThread`, `WaitForThreadTerminate`, `CurrentThread`,
`MainThreadID`, `PalHasThreads`, `PalFutexWaitTimeout`.

Whether a dropped body or a mis-repatched call site is the defect is **not
settled**. `dce.inc`'s own comment says the only reference shape it can
re-patch is x86-64 rel32 call/jmp, so any reference that is not a
CallFix-registered rel32 is invisible to BOTH the reachability walk and the
re-patching. Do not close this on the strength of the dropped-symbol list
alone.

**Measured independently by frankC, from the other end** — disassembly and a
live read rather than flag ablation, so this is two sources that fail
differently, not one source twice:

- With DCE the program never creates its threads at all: `/proc/<pid>/task`
  holds **one** task for the whole run, where `--no-dce` shows four and then
  prints `count=8000` / `CSBLOCK OK`.
- The surviving thread spins in `EmitAcquireHeapLock`'s
  test-and-test-and-set-with-PAUSE (`ir_codegen.inc:36`) — the **codegen heap
  spinlock, not a futex** — and the lock word at `0x41a950` reads **1**. The
  lock is HELD with exactly one thread alive: a lost release or a re-entrant
  acquire, self-deadlock either way. Wrapping `PXXObjFree` produced exactly
  this deadlock once before and was reverted (`cb2ed843`).
- Dropped includes `BeginThread`, `EnterCriticalSection`,
  `LeaveCriticalSection` and the whole `InterLocked*` family, while
  `TThread.Start`, `TCriticalSection.Enter`/`Leave`, `MutexLock`/`MutexUnlock`
  and `PalThreadCreate` stay live. **`BeginThread` dropped with
  `TThread.Start` live is the row to look at first.** The palsync rows are not
  evidence on their own — `TCriticalSection.Enter` calls `MutexLock`, not
  `EnterCriticalSection`, so dropping that API may be correct.
- `lib_classes_tthread` SIGSEGVs at -O3 where the others hang, and `--no-dce`
  fixes it too. That is shard1's `Illegal instruction` — the same family seen
  from the other end.

Two traps that cost time:

- **`-g` disables DCE outright** (`dce.inc:228`), so a debug build cannot
  reproduce this at all. Same for `--emit-obj` / `--shared`, a non-Pascal
  frontend, and any target that is not x86-64.
- `--proc-map` dumps at `compiler.pas:2381`, AFTER `DceRun` at 2371, so its
  addresses are real (confirmed by extent: 70731B of map against a reported
  `code=73496B`). But **attribution inside it is coarse** — a PC landing +624
  into a range the map calls `TWaiter.Execute` is only as good as that body's
  real extent, and the next live proc is 3797 bytes later. Do not build an
  argument on a name read that way.
- `ptrace_scope` on plexus blocks `gdb -p`. Launching under gdb works.

## The regression window

`-O3` has turned DCE on since `e33e10a14` (2026-08-21) and optdiff was green
under it until `caa34fdeab46` (2026-09-01T04:41Z), so the break is inside
`caa34fdeab46..297a6755c0bd`.

**Read that window for what it is.** `-O0 --dce` segfaults, and there is no
optimiser in that build at all — so the window is an argument about when DCE's
RE-PATCHING SURFACE last changed, not about an optimisation pass. The two
commits in it that touch that surface:

- `8d1bc1508` refactor(A): one image-fixup pass, because there were two and
  they had drifted
- `d0537380a` feat(A): rip-relative global operands on x86-64

`44b256356` (objects link into a PIE) and `a3b1af61a` (@proc relocations) are
in the same neighbourhood. **This is a window, not a finding — bisect it.**
Build each parent with `rm compiler/.pascal26.fixedpoint` first and refuse to
judge any build that does not print `converged after N round(s)`.

## Why this is not already fixed, and the false green coming

`d402a25b2` made `{$threadsafe on}` without `--threadsafe` a hard error. Every
program optdiff reported as an -O3 hang carries that directive, and optdiff
compiles with a bare `pascal26 -ON file` — no `--threadsafe`. So all seven of
them now **BUILD-FAIL, which optdiff counts as a skip.**

Shards 0/1/2/3/5 will therefore go GREEN on the next `opt` run **while this
miscompile is still live**, and the threading programs will have left the -O3
differential sweep entirely. A guard that cannot fail is not a guard. See
[[bug-t-optdiff-cannot-see-any-threading-program-since-the-threadsafe-directive-became-an-error]].

## Land it green

`make compiler/pascal26` cannot see this: `compiler.pas` starts no threads, and
the fixedpoint runs at the default `-O` where DCE is off. Carry the nine-line
repro above at `-O0 --dce` as the probe.
