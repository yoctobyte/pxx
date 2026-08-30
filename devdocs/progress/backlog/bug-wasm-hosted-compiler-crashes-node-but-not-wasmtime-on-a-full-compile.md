---
slug: bug-wasm-hosted-compiler-crashes-node-but-not-wasmtime-on-a-full-compile
title: "The wasm-hosted compiler SIGSEGVs node on a full compile; wasmtime runs the same module clean 5/5"
track: A
prio: 25
type: bug
status: backlog
owner: ""
created: 2026-08-30
found-by: frankwasm (splitting bug-wasm-hosted-compiler-segfaults-the-host-after-a-successful-parse)
summary: "The residual after the WASI u64-alignment defect was fixed. On the SAME module, wasmtime compiles a program to a byte-identical ELF five times out of five at exit 0; node segfaults five times out of five, leaving a 0-3 byte artifact. Node handles --version, --where and --list-libraries (a directory walk) at exit 0 and dies only on a full compile. A sandboxed guest cannot fault its host, only trap, so this is host-side — and unlike the predecessor ticket that inference now has a control behind it. LOW PRIO: wasmtime is the campaign's host and the milestone is met without node."
---

# The measurement

Same module (`compiler.pas` built `--target=wasm32`), same sandbox, same input,
five runs each:

| host | result |
| --- | --- |
| `wasmtime 48.0.1` | 5/5 exit 0, deterministic 68,248-byte ELF, byte-identical to the native compiler's output for the same source |
| `node v22.22.1` (`node:wasi`) | 5/5 SIGSEGV (exit 139), artifact 0–3 bytes |

Node is fine on everything lighter, measured:

| invocation | node | wasmtime |
| --- | --- | --- |
| `--version` | 0 | 0 |
| `--where` | 0 | 0 |
| `--list-libraries` (walks a directory: `PxxListDir` → `sysgetdents64` → `fd_readdir`) | 0 | 0 |
| `t.pas tout` (full compile) | **139** | 0 |

It also dies on the SYNTAX-ERROR path, after printing the correct diagnostic —
so it does not need codegen to have succeeded, only for real work to have been
done. Non-deterministic in the artifact size across identical runs.

# Why this is host-side, with a control this time

A sandboxed wasm guest cannot fault its host; every guest-side memory error is
a trap. The predecessor ticket made that argument and was **wrong to conclude
from it**, because node's leniency was hiding a genuine guest defect (an
under-aligned u64 WASI out-param) that surfaced only as late host death.

That defect is now fixed and wasmtime — a strict host that refused it — runs the
same module cleanly and repeatedly. So the argument now has the control it
lacked: the guest is demonstrably well-formed enough for an independent
preview1 implementation to execute it to completion, five times.

**That is not proof.** wasmtime could tolerate a different latent guest defect
just as node tolerated the alignment one. The honest statement is that the
evidence has moved from "inference from a sandbox property" to "inference plus
a passing second implementation", and the way to settle it is a third host or a
node build with symbols.

# Why it is prio 25 and not 60

The milestone this was blocking — *pascal26 runs under wasmtime* — is **met**.
wasmtime is the campaign's host from here, node stays useful as the lenient
comparison every other slice in `test/wasm/` runs under. Nothing is blocked on
this; it is a portability data point about one embedder.

Raise it if the campaign ever needs a browser or node target, where V8 *is* the
engine and this stops being optional.

# Where to look, if it is picked up

The stack-overflow hypothesis from the predecessor ticket is still the leading
one and still unmeasured: V8 runs wasm frames on the native stack and does not
reliably convert exhaustion into a `RangeError` from inside wasm, and the
compiler's recursive-descent parser and arena release walk both recurse with
program size — which fits "dies only on the heaviest workload" and "dies on the
error path too".

Cheapest discriminators, in order:

1. Bisect by INPUT SIZE. If the crash threshold tracks source complexity rather
   than any particular construct, depth is the answer.
2. Run the guest on a node worker thread with an explicit `resourceLimits`
   stack and see whether the threshold moves.
3. `--stack-size=40000` with `ulimit -s unlimited` was already tried and does
   not help, which does NOT settle it (V8 caps its own limit independently).
4. If it is not depth, the ~117 MB grown memory is the next candidate.

Do not spend long here without a reason: it is one embedder's failure on a
module a different embedder runs correctly.
