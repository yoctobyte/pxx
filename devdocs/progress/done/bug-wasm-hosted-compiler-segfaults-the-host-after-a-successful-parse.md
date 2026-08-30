---
slug: bug-wasm-hosted-compiler-segfaults-the-host-after-a-successful-parse
title: "The wasm-hosted compiler segfaults node itself once it has done real work — including on the error path"
track: A
prio: 60
type: bug
status: done
owner: frankwasm
created: 2026-08-30
found-by: frankwasm (running compiler.pas under node's WASI, after the var-param fix)
summary: "With bug-wasm-hosted-compiler-faults-on-a-garbage-string-handle-in-the-unit-resolver fixed, compiler.pas under WASI resolves its whole unit chain, parses, and reaches output — then the NODE PROCESS dies with SIGSEGV, not a wasm trap. --version and --where exit 0. A source file with a SYNTAX ERROR prints the correct diagnostic and then also segfaults, so this is not codegen-specific. Non-deterministic: the output file is 0, absent or 3 bytes across identical runs. A guest cannot segfault its host, so this is V8/node crashing, most likely a native-stack overflow from deep guest recursion."
---

# What now works, so the boundary is exact

At the sha this was filed against, `compiler.pas` built with
`--target=wasm32 -Fulib/rtl/platform/wasi`:

* 3888 of 3888 bodies lowered, `wasm-validate` passes on the 7.0 MB module;
* `--version` and `--where` answer correctly and exit **0**;
* `pascal26 t.pas out.o` reaches the object-writer and emits the right
  refusal diagnostic (`--emit-obj: this program needs a general relocatable
  object …`);
* with a staged sandbox (`lib/`, `compiler/builtin/`), the unit resolver runs
  its full 23-probe chain and finds `compiler/builtin/builtinheap.pas`, then
  opens the output file.

That is the whole resolver and the whole front end. The predecessor ticket's
fault is gone.

# The fault

```
node --no-warnings test/wasm/wasihost.js pxx.wasm <sandbox> t.pas tout
Segmentation fault (core dumped)     # exit 139
```

**SIGSEGV of the node process — not a `RuntimeError`.** That distinction is the
whole content of this ticket: a wasm guest is sandboxed and cannot fault its
host. Every guest-side memory error surfaces as a trap, which is what the
predecessor bug did. A host segfault means V8 died.

# Measured

| observation | what it rules in or out |
| --- | --- |
| `--version` / `--where` exit 0 | not module size, not instantiation, not the 95 MB bss, not WASI setup |
| a source file with a SYNTAX ERROR prints the correct diagnostic, **then** segfaults | NOT codegen-specific. The crash needs only that real work was done — parse + allocate. It happens at or after the point the program is finished |
| output file is `none`, `none`, `3` bytes over three identical runs | non-deterministic, so not a fixed instruction. Consistent with ASLR moving a stack limit |
| `--stack-size=40000` with `ulimit -s unlimited` | still segfaults. Does not settle the stack hypothesis (V8 caps its own limit), but it is not a cheap win |
| 23 `path_open` calls traced, last is `tout` | it gets to output; the crash is late |

# The hypothesis worth measuring first

**Native-stack overflow from deep guest recursion.** V8 runs wasm frames on the
native stack, and a deep enough guest call chain overflows it; V8 does not
reliably convert that into a `RangeError` from inside wasm. The compiler's
recursive-descent parser and its scope-exit / arena release walk both recurse
in proportion to program size, and the shutdown walk runs on the error path
too — which is exactly the correlation observed.

It is a HYPOTHESIS. Nothing here has measured a stack depth, and the previous
ticket in this lane is a standing reminder that a plausible story is not a root
cause: five of them were ruled out by measurement there before the real one
turned up in a disassembly.

Cheapest discriminators, in order:

1. Count guest frame depth at the crash — instrument the prologue's `sp`
   decrement against a low-water mark, or bisect by input size. If depth
   scales with the input and the crash tracks it, that is the answer.
2. Run the guest on a worker thread with an explicitly large stack
   (`new Worker(..., { resourceLimits })`) and see whether the crash moves.
3. If it is NOT depth: a V8 bug with a ~117 MB grown memory is the next
   candidate, and the way to tell is a second host. **There is no `wasmtime`
   on this box** — installing one is the single highest-value thing for this
   ticket, because the whole point of the campaign is "pascal26 runs under
   wasmtime" and node is currently the only host we can observe at all.

# Not blocked, and what it does not block

`test/wasm/check_all.sh` is 33/33 green, including the new `check_varparam.sh`.
Every slice runs its program under WASI and diffs against the native build.
This is reached only by a program of compiler.pas's size and depth.


# ANSWERED — and the hypothesis in this ticket was WRONG

Two independent faults were wearing one symptom. The second host separated them
in a single run.

## What it actually was: an under-aligned WASI out-parameter. Ours.

```
wasmtime run --dir <sandbox>::. pxx.wasm t.pas tout
  In func wasi_snapshot_preview1::fd_seek at write filesize:
  Pointer not aligned to 8: Region { start: 2141564, len: 8 }
```

`2141564 = 0x20AC3C` is 4-aligned, not 8. WASI preview1 declares `fd_seek`'s
`filesize` and `clock_time_get`'s `timestamp` as **u64**, and a strict host
requires the pointer it writes them through to be 8-byte aligned.

Both WASI backends passed `@WasiScratch[0]`, declared
`WasiScratch: array[0..15] of Byte`. **`symtab.inc`'s `TypeAlign` aligns a
global to its ELEMENT type**, so a byte array is aligned to **one**. It landed
4-aligned by luck. An `Int64` global aligns to 8 by that same rule, so the fix
is a declaration rather than arithmetic — `WasiScratch64: Int64`, used for the
four u64 out-params.

**Fixed in BOTH copies of the capability model**, because both held it
identically: `compiler/builtin/wasibackend.pas` (`fd_seek` ×2 — the copy on the
wasm-hosted compiler's own path, and the only one ever observed failing) and
`lib/rtl/platform/wasi/platform_backend.pas` (`fd_seek`, `clock_time_get` ×2).
Fixing one and not the other is exactly the drift
`bug-a-two-copies-of-the-wasi-capability-model-one-in-the-pal-one-in-wasibackend`
was filed about, one day after it was filed.

## THE MILESTONE: pascal26 compiles under wasmtime, byte-identically

```
$ wasmtime run --dir <sandbox>::. pxx.wasm t.pas tout   ->  exit 0
$ ./tout
42
$ cmp tout <native pascal26's output for the same source>   ->  IDENTICAL
```

The compiler running under wasmtime produced a 68,248-byte x86-64 ELF that is
**byte-identical** to the one the native compiler produces from the same source,
and it runs. Five consecutive runs: exit 0, same artifact, same size.

Note which claim that is (CLAIMS DISCIPLINE, CLAUDE.md): it is not the
self-host fixedpoint. It is that **the same compiler sources, executed on two
different machines — x86-64 natively and wasm32 under wasmtime — emit the same
bytes.** Same program, two hosts, one output.

## Why this ticket's own hypothesis was wrong, and why that was reasonable

It proposed a native-stack overflow in V8 from deep guest recursion, and named
the boundary argument: *a sandboxed guest cannot fault its host, only trap.*

**The boundary argument is still true. The inference drawn from it was not.**
Node did not trap because node's WASI does not enforce the alignment, so the
guest's defect was invisible *as a guest defect* and surfaced only as host
death much later. Evidence that genuinely pointed away from our code, which is
why the ticket declined to claim a root cause — the right call, and the reason
no time was spent implementing the wrong fix.

The lesson is narrower than "the hypothesis was wrong": **a lenient host is not
a neutral instrument.** Every check in this suite ran under node, so the entire
class was structurally invisible to all of them.

## The residual: node still dies, and now it IS host-side

With the alignment fixed, measured five runs each on the same module:

| host | result |
| --- | --- |
| wasmtime | 5/5 exit 0, deterministic 68,248-byte artifact |
| node | 5/5 SIGSEGV, artifact 0–3 bytes |

Node handles `--version`, `--where` and `--list-libraries` (which walks a
directory) at exit 0, and dies only on a full compile. That remainder is a
different bug and now has real evidence behind the host-side reading rather
than an inference: filed as `bug-wasm-hosted-compiler-crashes-node-but-not-
wasmtime-on-a-full-compile`. **The campaign's host is wasmtime from here.**

## Regression coverage

`test/wasm/align_slice.pas` + `check_align.sh`, registered in `check_all.sh`
(now 34). It is the first check here that needs a second host to mean anything,
and that is asserted rather than assumed: **with the defect reinstated, the
slice prints every expected line under node and exits 0, while the same module
traps under wasmtime before its first line.**

It covers both backends' `fd_seek` and both clocks. wasmtime's absence is a
loud SKIP that says the box asserted nothing, rather than a silent pass.

One assertion had to be corrected during the work and the reason is recorded in
the slice: the first version asserted `PalMonotonicMillis > 0`, which is a
difference between HOSTS — wasmtime's monotonic clock starts near zero at
process start, node's does not — and it failed on correct code the moment it
met the second host. Monotonicity is promised; magnitude is not.

## Gate

`make compiler/pascal26` self-host fixedpoint, `converged after 1 round(s)`.
`test/wasm/check_all.sh` **34/34 green**, including `check_pal` and `check_wasi`,
which are what prove the PAL edit changed no behaviour.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
