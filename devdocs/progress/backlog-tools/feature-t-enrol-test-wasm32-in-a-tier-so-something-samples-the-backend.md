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
   and again by frank-coordinator). seven is the box that runs the watcher and is
   not reachable by message from the coordinator seat. The residual question has
   no incumbent owner, which is the whole reason it is written down.

## Adjacent, NOT claimed as a bug

frankwasm observed and explicitly declined to file: ordinary Pascal file I/O does
not compile for wasm32 at all — `Assign`/`Rewrite` on a `Text` pulls the POSIX
platform backend and dies with `undefined variable (SYS_getgid)`. **May be
expected PAL routing; may be a gap.** It is recorded here so the observation has
a home, not as a claim. Note for whoever probes it: this is the **loud** direction
of the same predicate whose **silent** direction is frankD's bug — which backend a
wasm32 module pulls for file I/O. The two apertures rule says probe both; the
settling check is whether the failing module pulled `wasibackend.pas` at all, or
whether `Text` routing simply has no WASI arm. Those are different findings and
only one of them is a bug.
