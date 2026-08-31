---
summary: "OpenBSD/amd64 target — route RTL through libc.so; pinsyscalls satisfied by construction"
type: feature
prio: 50
blocked-by: [feature-port-rtl-over-libc]
---

# OpenBSD native target (amd64) — libc-through, ELF

- **Type:** feature (Track A — linking/ELF/RTL lowering). Portability campaign.
- **Status:** backlog (blocked on [[feature-port-rtl-over-libc]])
- **Owner:** —
- **Opened:** 2026-07-17, OS-portability mapping session. Full map in
  [`devdocs/dev/portability-axes.md`](../../dev/portability-axes.md).

## Why it's small (once RTL-over-libc exists)

OpenBSD forbids raw syscalls from arbitrary text: `msyscall(2)` (6.4) →
**`pinsyscalls`** (7.3/7.4) let the kernel kill any `syscall` instruction not issued
from the pinned libc site. This is **anti-ROP call-site allowlisting, not signing**
(see portability-axes.md for the honest rationale — it is a defensible mitigation, not
a flaw).

Route the RTL through **libc.so** and the whole problem evaporates: the pxx binary
emits **zero `syscall` instructions**, so every syscall originates inside OpenBSD's own
libc — exactly and only what `pinsyscalls` permits. **Compliant by construction; no pin
table, no `msyscall` call needed.** And it's still ELF, which pxx already writes and
dynamic-imports — so this is mostly *configuration* on top of [[feature-port-rtl-over-libc]].

## What differs

- **Interp** → `/usr/libexec/ld.so`; **`DT_NEEDED`** → OpenBSD `libc.so.<maj>.<min>`.
- Static-PIE is OpenBSD's norm; emit position-independent, or dynamic-link (simpler).
- RTL primitives lower to libc symbols (from [[feature-port-rtl-over-libc]]); errno via
  OpenBSD's `__errno`.
- **No Linux compat on OpenBSD** (removed ~2014) — there is no linuxulator escape
  hatch; testing is native-only.

## Acceptance

- An OpenBSD amd64 ELF that dynamic-links libc.so, runs natively (qemu, autoinstall
  image), and whose disassembly contains **no raw `syscall`** — proving pinsyscalls
  compliance structurally.
- Output byte-identical to the reference for a scalar + heap/string/exception torture.
- Gate: `make test` + self-host byte-identical (Linux default untouched); OpenBSD run
  under qemu.

## Test infra

qemu OpenBSD via `autoinstall` (no pre-built qcow2). Runner may live in the Track T
clone.

## Update 2026-08-30 — the lowering this depends on now exists

`feature-port-rtl-over-libc` landed (`3a0ed43fb`). On x86-64 Linux, `--rtl-libc`
routes compiler-generated kernel entries through an out-of-line thunk that calls
libc's `syscall()`, taking a Pascal binary from **73 raw kernel-entry
instructions to 1**. That is the mechanism this ticket's acceptance criterion
("disassembly contains no raw `syscall`") was waiting on; what remains here is
the OpenBSD *target*, not the lowering.

Four things carry over, and the last two are the ones that will bite:

1. `tools/syscall_scan.py <binary> --list` prints every kernel-entry site with
   its address, and works on our section-less ELFs — `objdump -d` does **not**
   (it disassembles *sections*, so it reports a clean zero on any pxx binary).
   The acceptance check here should use the scanner, not a grep.
2. Every compiler-generated kernel entry funnels through `x64_syscall`
   (`x64enc.inc`), so a target-specific policy has one seam rather than ~22.
3. **The residual will not be zero, and the criterion above should say so.**
   `rt_sigreturn` must stay a bare instruction — it restores the whole context
   from a signal frame at a fixed offset from rsp, so routing it through a thunk
   is a SIGSEGV on the first delivered signal. It is emitted via the
   `syscall_raw` mnemonic, which never becomes a call. `clone`'s child stub in
   `thread_emit.inc` is raw for the same class of reason. If OpenBSD's
   pinsyscalls genuinely requires *zero*, that is a real design question for
   this port — raise it as a Track U `decide-*` rather than assuming the Linux
   shape transfers.
4. A pxx-created thread inherits the parent's FS base, so the thunk's
   FS-relative errno fixup resolves to the **main thread's** errno slot. Reasoned
   and unobserved on Linux; see
   `feature-rtl-libc-frontend-sites-and-thread-errno` for the trigger to test.

**Not closed by that work** — this ticket is the OpenBSD target, and none of it
has been exercised on OpenBSD.

## 2026-08-31 (frank-rust) — item 3's decide ticket now exists, with the number

Item 3 above says the "no raw `syscall`" criterion is wrong and should be raised
as a Track U `decide-*` rather than assuming the Linux shape transfers. Filed:
[[decide-openbsd-pinsyscalls-vs-the-rt-sigreturn-residual]], with the residual
measured rather than estimated.

**The residual is 1, and it is identified.** `--rtl-libc` takes a hello-world
from 75 raw kernel entries to **1**, a try/except program from 86 to **1**, and
`--rtl-libc --no-signals` gives **0** — which is the control proving the
survivor is the `rt_sigreturn` at `ir_codegen.inc:585` and not the thunk or an
unrouted RTL entry. The thunk contributes zero, because it `call`s libc's
`syscall()` rather than executing one.

So the acceptance criterion should be restated in terms of **pinsyscalls
compliance**, not zero raw syscalls: those are different properties, and a
binary can have one raw syscall and comply. That restatement is worth doing
whichever way the OpenBSD question resolves.

**Not measured:** the clone child stub in `thread_emit.inc`. No threaded binary
was scanned, so "1" is the non-threaded figure only — do not quote it as the
ceiling.

Nothing else in this ticket is started; the OpenBSD target itself is untouched,
and its acceptance still needs the qemu/autoinstall infra that does not exist.
