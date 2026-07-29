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

## Windows and BSD are coming — the boundary must be SEMANTIC, not mechanism

(User, 2026-07-29: Windows and BSD may become targets, so the PAL stays
relevant.) This sharpens the invariant, and it invalidates one of my earlier
judgements.

**The problem is not only raw syscall numbers. It is Linux-only MECHANISMS
leaking above the PAL.** `/proc/self/*` appears at **9 sites across 5 files**
(`pylib.pas`, `sysutils.pas`, `crtl/stdlib.c`, `unix.pas`, `palparallel.pas`) —
and `/proc` is a **Linux** interface, not a POSIX one:

- **FreeBSD** deprecated procfs; it is not mounted by default (`linprocfs` is
  opt-in). So `/proc/self/environ` fails there and every caller silently gets
  "no environment", because all three copies treat a failed open as "empty".
- **Windows** has no equivalent at all; the environment comes from
  `GetEnvironmentStringsW`.

Today's backends are only `posix` and `esp` — and `posix` is already the wrong
name for these callers, because what they actually require is *Linux*.

So the rule is not "raw syscalls only in the PAL". It is:

> **A PAL entry point names a CAPABILITY ("get the environment"), never a
> mechanism ("read /proc/self/environ"). Any OS-specific mechanism — syscall
> numbers, `/proc` paths, `GetEnvironmentStringsW` — lives below that boundary
> and nowhere else.**

Under that rule the three env copies are ALL wrong today, not just the NilPy
one: each hardcodes the mechanism, so all three break on the same day BSD or
Windows arrives, and the per-language PAL cannot absorb it because the
mechanism leaked above the boundary.

### Correction: the envp-on-the-stack route was the better one

`feature-rtl-environment-variables` proposed reading `envp` off the initial
stack (`BSS_INITIAL_RSP + 8*(argc+2)`). I dismissed that as unnecessary because
`/proc/self/environ` "needs no codegen". **That was short-sighted.** `envp` on
the initial stack is the ELF/SysV convention and works on Linux AND the BSDs
with one implementation; `/proc` works on Linux only. Windows needs its own
path either way, which is exactly what a PAL is for.

Recommend: the environment capability is implemented once per language PAL over
`envp`, with `/proc` retired rather than extended. The codegen cost I used to
argue against it buys BSD support outright.

### Backend split to plan for

`platform/posix` should become `platform/linux` + `platform/bsd` (sharing what
is genuinely POSIX), plus `platform/win`, alongside the existing
`platform/esp`. Worth doing the rename BEFORE a second OS lands, while there is
one caller set to fix.

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
