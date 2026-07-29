---
track: U
prio: 70
type: decide
---

# Where does a runtime primitive live? — DECIDED: a PAL per language

## Decision (user, 2026-07-29)

**A proper PAL layer per language. Duplication across those PALs is accepted
and intentional.** These are a typical set of per-language intrinsics;
duplicating trivial code that then needs no further maintenance is the right
trade, and it is what keeps a C or NilPy program from linking sysutils to get
one function.

This supersedes the "one shared `palcore`" option originally recommended below
(option A), which would have bought de-duplication at the price of coupling
every language surface to one unit and to each other's constraints.

## What that means concretely — most of it already exists

Measured against the decision rather than assumed:

| language | PAL unit | state |
| --- | --- | --- |
| Pascal | `lib/rtl/platform.pas` | **conforms** — neutral facade, backend by unit path (`platform/posix`, `platform/esp`), **0** raw syscalls in the facade |
| C | `lib/rtl/pxxcio.pas` | **conforms** — the `__pxx_*` bridge crtl binds to; 4 raw sites, all in the one unit |
| NilPy | *none* | **the gap** — 32 raw `__pxxrawsyscall` sites inline in `pylib.pas` |
| shared runtime core (heap, strings — language-neutral, not a surface) | `compiler/builtin/builtinheap.pas` | already the bottom layer: `PXXSysRead` / `PXXSysWrite` / `PXXSysOpenRO` / `PXXSysClose` |

So the architecture the decision describes is **already 3 of 4 in place**. The
work is not a re-layering; it is one missing unit.

## The work

**1. Give NilPy its PAL — `compiler/builtin/pypal.pas` (Track N).**
Extract pylib's raw syscalls into one unit. They are already clustered in four
regions of `pylib.pas` (4019-4069, 4168-4181, 4266-4399, 5602-5675), i.e. a
de-facto PAL section that has never been named — so this is mostly a move, not
a rewrite. Where `builtinheap` already exposes the primitive (`PXXSysOpenRO`,
`PXXSysRead`, `PXXSysClose` — exactly what `os.environ` needs), call that
instead of re-issuing the syscall.

**2. The invariant, grep-checkable (Track A, gate).**
*A raw `__pxxrawsyscall` may appear ONLY in a per-language PAL unit or in
`builtinheap`.* Land as a shrink-only allowlist (65 sites today) so the
layering cannot rot back. This is what makes the decision durable rather than a
note in a doc.

**3. Conformance tests across the surfaces (Track T/B).**
The duplication is accepted; the surfaces silently DISAGREEING is not. One test
per primitive asserting Pascal, NilPy and C answer the same, against a
gcc/CPython oracle where one exists. This is the failure that actually bites —
a copy fixed in one surface and not the others — and it is cheap.

## Windows/BSD: a note, not a work item

(User, 2026-07-29: Windows and BSD may become targets one day — the point being
that the PAL stays relevant, not that either is scheduled. **Nothing here is
planned work.**)

One fact worth having written down, because it is cheap to record and would be
expensive to rediscover: `/proc/self/*` appears at 9 sites across 5 files, and
`/proc` is a **Linux** interface, not a POSIX one — FreeBSD does not mount
procfs by default, Windows has no equivalent. All of them treat a failed open
as "no environment", so on such a target they would return a plausible empty
answer rather than an error.

That suggests one sharpening of the rule above, which costs nothing to adopt
now and is the whole lesson here:

> **A PAL entry point should name a CAPABILITY ("get the environment"), not a
> mechanism ("read /proc/self/environ").**

Everything else this implies — splitting `platform/posix` into `linux`/`bsd`,
adding `platform/win`, moving the environment onto `envp` from the initial
stack — is work for the day a second OS is actually on the roadmap. Recorded
here so it is not rediscovered; **not** proposed as work now, and the existing
`/proc` implementations are fine as they stand.

## Eyes open: what the duplication does cost

Worth stating plainly so the trade is made knowingly. The part of a PAL that is
NOT frozen is the per-arch syscall number table: x86-64 `openat` is 257,
aarch64 is 56, and each target has its own. With a PAL per language, **adding a
new target means updating every language's table**, and a missed one is a
silent wrong-arch call rather than a build error.

That is still far better than today (65 scattered sites, 4 different kernel
paths, no name for any of it), and item 2's allowlist bounds it — but "needs no
further maintenance" holds for the LOGIC (record scanning, name matching), not
for the arch table, and NOT for the OS-mechanism choice once Windows/BSD land. Recommend each PAL keep its arch numbers in one clearly
marked table, and that adding a target be a checklist item naming all of them.

## Evidence that prompted this

`/proc/self/environ` is read in three places, each by a different mechanism:

| file | surface | kernel path |
| --- | --- | --- |
| `compiler/builtin/pylib.pas:4056` | NilPy `os.environ` | `__pxxrawsyscall(257 / 56, ...)` |
| `lib/rtl/sysutils.pas:1755` | Pascal `GetEnvironmentVariable` | `PalOpen` |
| `lib/crtl/src/stdlib.c:74` | C `getenv` | `__pxx_open` |

`getcwd` and `clock_gettime` are three-way as well. Under the decision above the
first two are CORRECT — each language reaching the kernel through its own PAL —
and only the NilPy one is misplaced, because it bypasses a PAL that does not
exist yet.

Prompted by [[feature-rtl-environment-variables]], where two of three surfaces
turned out to be already implemented and the third was a `return 0` stub that
made C code silently see an empty environment.

## Original options, kept for the record

- **A — one shared `compiler/builtin/palcore.pas`.** NOT TAKEN: couples every
  surface to one unit; the "don't link sysutils for one function" property is
  achievable without it.
- **B — keep copies, add conformance tests.** TAKEN, as item 3.
- **C — share logic via a Pascal `.inc`.** NOT TAKEN: looks like sharing but
  leaves the several kernel paths, which is where the per-arch bugs live.
