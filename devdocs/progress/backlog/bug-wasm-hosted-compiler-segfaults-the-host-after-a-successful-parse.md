---
slug: bug-wasm-hosted-compiler-segfaults-the-host-after-a-successful-parse
title: "The wasm-hosted compiler segfaults node itself once it has done real work — including on the error path"
track: A
prio: 60
type: bug
status: backlog
owner: ""
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
