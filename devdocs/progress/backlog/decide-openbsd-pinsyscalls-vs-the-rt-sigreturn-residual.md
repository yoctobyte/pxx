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
summary: "MEASURED on x86-64 Linux at 26b5a5d066ed: with --rtl-libc a Pascal binary's raw kernel-entry count falls 75 -> 1 (hello) and 86 -> 1 (try/except), and --rtl-libc --no-signals gives 0. So the entire residual for a non-threaded program is exactly ONE instruction, the rt_sigreturn in ir_codegen.inc:585, emitted via the syscall_raw mnemonic that is never routed through the thunk. It cannot be routed: rt_sigreturn restores the whole context from a signal frame at a fixed offset from rsp, so a call wrapper is a SIGSEGV on the first delivered signal. feature-port-openbsd-libc's acceptance says 'disassembly contains no raw syscall' and its own item 3 says that criterion is wrong and should be raised as a decide-*. This is that ticket. The fork: does OpenBSD pinsyscalls accept a binary whose only kernel entry is a sigreturn, and if not, does the OpenBSD target ship signals-off, use libc's sigreturn path, or is the port infeasible as specified? NOT measured: the clone child stub in thread_emit.inc, which is raw for the same class of reason -- no threaded program was scanned."
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
