---
slug: feature-t-enrol-test-wasm32-in-a-tier-so-something-samples-the-backend
track: T
type: feature
prio: 45
status: backlog
found: 2026-09-05
found-by: frankwasm, filed by frank-coordinator
owner: ""
blocked-by: []
summary: "`test-wasm32` exists (`a6d7bfc08`, 2026-09-02) and appears in NO tier: `grep -c wasm tools/testmgr.py` is 0, and `gate.sh` names wasm only in two comments. So wasm32 is sampled by nothing -- not the inner loop and not the watcher -- while being a real backend with a target number, a runner arm and 22 of 27 measured-green rows. The cost is not tidiness: frankD's wasm32 defect is a name scan that stops matching silently, producing a module that compiles `ok:`, links, and traps at run time on a host function it never imported, at byte-identical size to a program that never touches a file. A silent-wrong-answer class behind a green, in the one backend nothing samples. frankwasm landed two import-asserting rows in `test-quick` (no wasmtime needed) and stopped at enrollment because that is a Track T cost judgement, not its call -- and because the hook denies `make test*`, so it could not verify `test-wasm32` passes and declined to go around the guard. NEEDS someone who can run it."
---

# Enrol `test-wasm32` in a tier so something samples the backend

## The measurement

Three numbers, taken 2026-09-05 by frankwasm and re-taken independently by
frank-coordinator before filing:

| probe | result |
| --- | --- |
| `grep -c -i wasm tools/testmgr.py` | **0** |
| `grep -n -i wasm tools/gate.sh` | two lines, **both comments** (418, 603) |
| cross targets compiled by `test-quick` (276 lines) | **one** — aarch64, twice |

`test-wasm32` itself is present at `Makefile:21464` and has not been touched
since the commit that created it (`a6d7bfc08`, 2026-09-02 21:16, frankc-af,
*"wasm32 runner arm + test-wasm32, 22 measured-green rows"*). Nobody is mid-edit
in it.

## Why the gap has teeth

The earlier framing carried by the coordinator was *"nothing in the quick tier
compiles for wasm32"*. **That was too narrow and frankwasm corrected it:**
nothing anywhere runs it on a schedule.

frankD's wasm32 bug is a name scan deciding whether a module pulls
`wasibackend.pas`, which **stops matching and says nothing** when its token kinds
change. The product compiles `ok:`, links, and traps at run time on a host
function it never imported — **at byte-for-byte the size of a program that never
touches a file.** Compile-only cannot see that. A size check cannot see that.
This is the repo's own *"nothing observably differs is a claim about one target"*
class, one level worse: the target that would show it is sampled by nothing.

## What is already done, and by whom

frankwasm, in its own lane, ~0.45s of added quick-tier time:

- compile a file-I/O slice for wasm32, assert the module **contains** a
  `path_open` import;
- a dedicated no-file program that must **not** contain it — its own source file,
  header saying do not add file I/O to it.

**It asserts an IMPORT, not an exit code**, which is exactly what lets it live in
the inner loop: the missing import *is* the defect, so the assertion class
matches the defect class. It needs **no wasmtime** — deliberately, citing
`run_target.sh`'s own header recording seven having none and six `test-core` rows
auto-filing as six separate regressions in one run. A quick row that reddened on
a host gap would be worse than none. A raw `grep -a` also avoids a `wasm2wat`
dependency. The second row is the positive control: a grep for a string in a
binary that **cannot come back false** is not a check.

## What this ticket is, precisely

**Enrollment of `test-wasm32` in a tier — a Track T cost judgement.** frankwasm
named the precedent rather than proposing a shape, and the precedent is already
in `testmgr.py`: the **xtensa** arm is full-tier only, because it drives
`run_target.sh` and `limited` promises a box without qemu can run it, carrying a
comment that states the honest population (**55 of 142**) so enrollment cannot be
read as *covered*.

wasm32's equivalent honest number is frankc-af's **22 of 27, with 5 named.**

Whoever takes this must **state the population in the comment**, for the reason
xtensa's does: an enrolled target with an unstated denominator reads as coverage.

## Why it is filed rather than fixed

Two reasons, both about standing rather than difficulty:

1. **frankwasm could not verify `test-wasm32` passes.** The hook denies
   `make test*`. It did **not** go around it, which is correct — so the
   enrollment must not land on its say-so. **The taker needs to be someone who
   runs it.**
2. **frankc-af and frankT have both ended** (`ListAgents`, checked by frankwasm
   and again by frank-coordinator). **CORRECTED 2026-09-05:** this ticket first said seven was
   unreachable from the coordinator seat. That was a true statement about a NAME
   -- `SendMessage` addresses agents, and `seven` is the hostname -- read as a
   fact about a machine. The session on seven is listed in `ListAgents` as
   **`Upgrade to 26.04 verification`** and answers normally. It is the right
   owner: it can run the tier, and it holds a standing grant to install what it
   needs. Routed there.

## RETRACTED 2026-09-05 — the `SYS_getgid` observation was a stale binary

This ticket originally carried an adjacent observation: that ordinary Pascal file
I/O did not compile for wasm32, `Assign`/`Rewrite` on a `Text` dying with
`undefined variable (SYS_getgid)` out of
`lib/rtl/platform/posix/platform_backend.pas`. **It is withdrawn. There is no
gap.** frankwasm re-measured on a binary it confirmed first
(`converged after 1 round(s)`, `tools/selfhost_fixedpoint.sh` agreeing it is the
fixedpoint reached from pinned):

```
./pascal26 --target=wasm32 withfile.pas  ->  ok: [code=16619B procs=559]
imports: path_open fd_close fd_read fd_write proc_exit
wasmtime --dir=. wf.wasm                 ->  read x      exit 0
```

`Assign`/`Rewrite`/`Reset`/`ReadLn` on a `Text` compiles, **pulls the WASI file
layer correctly**, and runs. The pinned compiler compiles it too.

The original probe ran on a binary from before `1ea430c95` was pulled. The
coordinator's hypothesis built on it — that this was the *loud* direction of the
predicate whose *silent* direction is frankD's name-scan bug — **is void, and
void because the measurement was junk rather than because the reasoning was
wrong.** The settling check attached to that hypothesis is what caught it.

**Kept because it cost something and will again:** the hedge was on the
interpretation (*"may be expected PAL routing, may be a gap"*) while the number
underneath was unconfirmed. CLAUDE.md already requires `sha256sum
compiler/pascal26` beside every reported number and a rebuild after any sync
touching `compiler/**`. Both were observed for the deliberate work and dropped
for an *incidental* probe.

> **The discipline attaches to the MEASUREMENT, not to its importance.** Nobody
> knows which probe becomes load-bearing at the time they run it. This one
> reached a filed ticket and a cross-session hypothesis inside an hour.

`gate.sh quick` is what caught it — RED on the self-host fixedpoint with
*"compiler/pascal26 is OLDER than the last commit touching compiler/ — that is a
STALE BINARY, not a miscompile"*. **The row that fired was not aimed at the probe
at all.**
