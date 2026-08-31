---
slug: decide-openbsd-pinsyscalls-vs-the-rt-sigreturn-residual
title: Does OpenBSD's pinsyscalls permit our one irreducible raw syscall (rt_sigreturn)?
track: U
type: decide
prio: 45
status: backlog
found: 2026-08-31
found-by: frank-rust
owner: unassigned
blocked-by: []
summary: "MEASURED, both halves, on x86-64 Linux. NON-THREADED: --rtl-libc takes a Pascal binary 75 -> 1 raw kernel entries, and --no-signals gives 0, so the residual is exactly one rt_sigreturn (ir_codegen.inc:585, emitted via the syscall_raw mnemonic that is never thunked). THREADED (frankS, re-measured independently by frank-rust on test_atomic_counter): 142 -> 4 -> 3, and the three are the clone stub, INDEPENDENT of the rt_sigreturn rather than one instruction double-counted. So the floor is FOUR, not one, and each is irreducible for its OWN reason: rt_sigreturn restores context from a signal frame at a fixed offset from rsp; SYS_clone's RETURN is the point (a wrapper returns into a frame the child does not have); arch_prctl installs GS before TLS exists; and the child's SYS_exit has no frame to return to. None is a missed thunk routing. THE FORK: does OpenBSD pinsyscalls accept a binary whose kernel entries are these four? feature-port-openbsd-libc's acceptance says "disassembly contains no raw syscall" and its own item 3 says that criterion is wrong -- this is that decide. Options: (a) signals off, measured to give 0 non-threaded but still 3 threaded, so it does NOT reach zero; (b) route sigreturn via libc's sigreturn and the clone stub via libc's own thread creation -- recommended, but it is a per-OS contract, not a flag; (c) restate the criterion as PINSYSCALLS COMPLIANCE rather than zero raw syscalls, which is worth doing whichever way the rest lands, because a binary can have four raw syscalls and comply."
---

# The measurement

On x86-64 Linux, HEAD `26b5a5d066ed`, compiler `d85fc3e152c4`, using
`tools/syscall_scan.py` (which the port ticket correctly says to use instead of
`objdump -d`, since our ELFs are section-less and objdump reports a false zero):

| program | default | `--rtl-libc` | `--rtl-libc --no-signals` |
| --- | --- | --- | --- |
| `Writeln` hello | 75 | **1** | **0** |
| `try/except` + `Writeln` | 86 | **1** | — |

The thunk itself contributes **zero** instructions, because it `call`s libc's
`syscall()` rather than executing one.

## The residual is identified, not merely counted

The surviving instruction is the `rt_sigreturn` at `compiler/ir_codegen.inc:585`,
emitted as `EmitAsmX64(['mov rax, %', 15, 'syscall_raw'])`. `syscall_raw` is a
distinct mnemonic that `asmtext.inc:400` encodes directly and which is *never*
rewritten into a thunk call, on any target or flag.

**Confirmed by the drop to 0 under `--no-signals`**, which is the control: had
the surviving 1 been the thunk, or an unrouted RTL entry, turning signals off
would not have removed it.

It cannot be routed through the thunk, and this is not an implementation gap:
`rt_sigreturn` restores the entire register context from a signal frame at a
fixed offset from `rsp`. Wrapping it in a call changes `rsp` before the kernel
reads the frame, so it is a SIGSEGV on the first delivered signal, not a
slow path.

# The fork

`feature-port-openbsd-libc`'s acceptance criterion reads *"an OpenBSD amd64 ELF
whose disassembly contains no raw `syscall`"*, and its own item 3 already says
that criterion is wrong and should become a `decide-*` rather than assume the
Linux shape transfers. So:

**Does OpenBSD's pinsyscalls accept a binary whose only kernel entry is a
sigreturn?** I do not know, and I cannot find out on this box — no OpenBSD is
installed and the port's test infra (qemu via `autoinstall`) does not exist yet.
This needs someone with OpenBSD knowledge or a VM, which is exactly why it is
Track U and not a bug.

Options, if the answer is no:

- **(a) Ship the OpenBSD target with managed signals off.** Measured to give a
  genuine 0. Costs graceful Ctrl-C and the FPC-style runtime-error hooks.
- **(b) Route sigreturn through libc's own `sigreturn`**, which on OpenBSD is
  the sanctioned path and is already a pinned syscall inside libc. Plausible and
  the most likely right answer, but it is a per-OS signal-frame contract, so it
  is real work rather than a flag.
- **(c) The port is infeasible as specified** and the acceptance criterion
  should be restated in terms of *pinsyscalls compliance* rather than *zero raw
  syscalls* — which are different properties, and conflating them is what
  produced the current criterion.

**Recommendation: (b), with the criterion restated per (c) regardless of which
is chosen.** "No raw syscall" was a proxy for "satisfies pinsyscalls", and the
proxy is measurably not the thing — a binary can have one raw syscall and comply,
or zero and still fail for unrelated reasons.

# Not established

**The clone child stub** in `thread_emit.inc` is raw for the same class of
reason and I did **not** measure it — no threaded program was scanned, so the
"residual is exactly 1" result above is for **non-threaded** programs only.
Whoever takes this should scan a threaded binary before treating 1 as the
ceiling. Naming it because a measured 1 is the kind of number that gets quoted
as the general case.


---

# The threaded residual, measured (frankS, 2026-08-31)

The ticket's one stated gap — *"NOT measured: the clone child stub in
thread_emit.inc ... no threaded program was scanned"* — closed. Compiler
`8cceeabd547f`, same `tools/syscall_scan.py`.

A `TThread` descendant that starts, prints and is waited on:

| build | kernel entries |
| --- | --- |
| `--threadsafe` | 198 |
| `--threadsafe --rtl-libc` | **4** |
| `--threadsafe --rtl-libc --no-signals` | **3** |

The one that drops between rows 2 and 3 is the `rt_sigreturn` this ticket
already identified, confirming the two residuals are independent and additive
rather than the same instruction counted twice. **The binary runs correctly in
every configuration** — `--rtl-libc` does not break threading.

## The three are identified, and no two share a reason

All in the x86-64 `__pxxclone` stub (`thread_emit.inc`), addresses 22 and 13
bytes apart, matching the stub's layout exactly:

1. **`SYS_clone` (56).** Cannot be a call, and the file already says so: after
   the syscall the CHILD resumes, so a wrapper would return into a frame the
   child does not have. This is the same class as `rt_sigreturn` — an
   instruction whose *return* is the point.
2. **`arch_prctl(ARCH_SET_GS)` (158).** Runs in the child **before TLS exists**,
   deliberately ("install the TLS block FIRST, before anything Pascal runs"). A
   libc call before the thread pointer is installed is exactly what this
   instruction is preventing.
3. **`SYS_exit` (60).** The thread's own exit. There is no frame to return to,
   by construction.

So the residual is not one awkward instruction plus three incidental ones: it
is **four instructions, in two stubs, each of which is raw because a `call`
would need a stack or a thread pointer that does not exist at that point.**
None is a missed thunk routing.

## What this changes about the fork

It does not change the question, it prices it. If OpenBSD's `pinsyscalls`
requires literally zero raw kernel entries from arbitrary text, then:

- a **non-threaded, signals-off** program is already compliant today;
- a **non-threaded** program needs one decision (`rt_sigreturn`);
- a **threaded** program needs the whole `__pxxclone` stub replaced by
  `pthread_create`, which is a different port task from "route the RTL through
  libc" and is not currently filed.

That third row is the one worth the owner's attention, because it is the only
one where the answer changes the *shape* of the work rather than a flag.

---

## 2026-08-31 — the threaded half is measured, and it moves the floor from 1 to 4

Filed with *"Not measured: the clone child stub... do not quote 1 as the
ceiling."* **frankS measured it, and the caveat was load-bearing.**

| program | default | `--rtl-libc` | `+ --no-signals` |
| --- | --- | --- | --- |
| non-threaded (`hello`, `try/except`) | 75 / 86 | 1 | **0** |
| threaded (frankS) | 198 | 4 | **3** |
| threaded (`test_atomic_counter`, frank-rust) | 142 | **4** | **3** |

Re-measured independently before writing it here. The base figures differ
because we used different threaded programs; **the residuals — 4 and 3 — match
exactly**, which is the part the decision rests on. The three surviving sites
span 0x23 bytes (`41a574`, `41a58a`, `41a597`): one small stub, not three
scattered call sites.

### The four are independent, and that is what the decision needs

Not one instruction counted four times, and not a thunk-routing gap. Each is
irreducible **for its own reason** (mechanisms: frankS):

| entry | why it cannot be thunked |
| --- | --- |
| `rt_sigreturn` | restores the whole context from a signal frame at a fixed offset from `rsp`; a call wrapper moves `rsp` before the kernel reads it |
| `SYS_clone` | its **return** is the point — a wrapper returns into a frame the child does not have |
| `arch_prctl` | installs GS **before TLS exists**, so there is no thread context for a wrapper to run in |
| child `SYS_exit` | no frame to return to |

**This kills option (a) as a route to zero.** `--no-signals` was measured to give
0 on a non-threaded program, which made "ship OpenBSD with managed signals off"
look like a clean escape. On a threaded program it gives **3**. Any option that
has to reach zero must address thread creation, which is a much larger
commitment than dropping graceful Ctrl-C.

**It strengthens (c) correspondingly.** Four irreducible entries with four
distinct mechanisms is not a tidiness problem to be optimised away; it is the
shape of the target. Restating the criterion as *pinsyscalls compliance* rather
than *zero raw syscalls* stops being a nicety and becomes the only formulation
the port can actually satisfy.

### Note on this ticket's own history

The first version of this summary said the residual was "exactly ONE
instruction". True, and true only for the population I had measured — which the
body said explicitly and the summary did not carry. **The summary is the part
everyone reads**, so a scope caveat that lives only in the body is a caveat that
does not exist. Both figures are now in the summary.
