# FPC-seeded pascal26 binary segfaults at runtime

- **Type:** bug
- **Track:** A (compiler / bootstrap)
- **Status:** DONE (2026-06-30, pin v94, commit pending)
- **Opened:** 2026-06-29

## Symptom

An FPC-built `pascal26` (e.g. `fpc -O2 -Tlinux -Px86_64 compiler/compiler.pas`)
**compiles cleanly** but the resulting binary **segfaults at runtime on any
input**, including `test/hello.pas`:

```
$ /tmp/pascal26-bench-fpc test/hello.pas /tmp/out
Segmentation fault (core dumped)
```

This breaks the FPC-seeded cold paths:
- `make bootstrap` — segfaults when the FPC gen0 compiles `compiler.pas`.
- `make benchmark-compiler-runtime` — runs the FPC-built binary, so it segvs.
  (`make benchmark` is unaffected: it only *times* `fpc` compiling, never runs
  the FPC-built binary.)

## Not a regression from the forward-decl fix

This surfaced only *after* `53dcd69b` (hoisting the cpreproc macro-expander
forward decls) made FPC able to compile `compiler.pas` at all — previously FPC
errored at compile time (`Identifier not found "CPSetTempStrLength"`), masking
this. The pascal26 self-host gate is unaffected and byte-identical
(gen1==gen2==prior binary); only the FPC-codegen path is broken.

## Likely area

FPC-vs-pascal26 codegen/runtime divergence. Candidates (unverified):
- managed-string / default-string-mode init (self-builds are FROZEN, user/FPC
  default is managed — see memory `feedback_fpc_optional_workflow`).
- early RTL/heap init the FPC build lays out differently.

Repro is cheap (segv on hello), so a debugger backtrace on
`/tmp/pascal26-bench-fpc test/hello.pas` should localize fast.

## Why it matters / priority

Daily workflow is FPC-free (self-host off the pinned binary), so this is **not
urgent** — it does not block `make test`, `stabilize`, `pin`, or `make
benchmark`. It does block release-compliance (`make test-fpc`) and any genuine
cold-start bootstrap from FPC. Note `2a473bda fix(bootstrap): restore FPC seed
build` recently touched this path.

## 2026-06-30 — compile blocker cleared; runtime segfault confirmed still open

The FPC **compile** failure (7 errors, all from `ParseCSubroutine`'s undeclared
`for j` counter) is fixed: `j` is now a real local, and the new decl-order gating
([[feature-implicit-identifier-binding-strictness-switch]], pin v93) would flag any
recurrence. `fpc -O2 -Tlinux -Px86_64 compiler/compiler.pas` now builds clean.

The **runtime segfault is still here** — the FPC-built binary segfaults on
`test/hello.pas` (SIGSEGV, exit 139), exactly as this ticket describes. So the two
were independent: a compile-time strictness gap on top of a separate FPC-codegen /
runtime divergence. This ticket now tracks only the runtime segfault. Next:
debugger backtrace on `compiler/pascal26-fpc test/hello.pas` (cheap repro), and
check the managed-string / early-heap-init suspects already listed below. A
candidate worth checking given today's review: the frozen-string `Result` shared
global ([[bug-frozen-string-result-global-not-reentrant]]) — FPC's heap/BSS layout
or init order could expose a latent slot issue differently than pxx codegen does.

## RESOLVED (2026-06-30, pin v94)

Root cause: **`LoadFile` allocated an 8 MB array on the stack**
(`buf: array[0..STRING_CAP-1] of Byte`, STRING_CAP = 8 MB). The pxx runtime gives
a large process stack so the pxx-built compiler was fine; the FPC binary uses the
default 8 MB stack (`ulimit -s` 8192 KB), so the 8 MB local overflowed the guard
page in LoadFile's prologue → SIGSEGV (the nil `PATH`/`DST` params in the gdb
backtrace were the unallocated frame, not bad arguments — `inFile` was valid in the
caller).

Fix (commit in this pin): stage the read through a global `LoadFileBuf` (BSS),
like `TokChars` already is. Verified at the default stack: FPC binary compiles
hello (output runs), compiles the compiler, and reaches a byte-identical
fixedpoint — FPC→gen1→gen2 with gen1==gen2==pxx-self-host. `make bootstrap` green.

### Follow-up (separate, low priority) — cross-backend big stack locals
The same 8 MB-stack-local pattern exists in the **cross backends**, only hit when
the FPC-seeded compiler *cross-compiles* (not the x86-64 cold-start, so not
blocking): `LabelPositions`/`LabelFixupPos`/`LabelFixupTarget:
array[0..MAX_IR-1] of Integer` locals in `ir_codegen_riscv32.inc`,
`ir_codegen_xtensa.inc`, `ir_codegen_aarch64.inc` (MAX_IR*4 bytes each, ×3). If a
default-stack FPC-built compiler is ever used to cross-compile, move these to
globals too. Filed as a note here; spin out if it bites.
