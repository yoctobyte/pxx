# FPC-seeded pascal26 binary segfaults at runtime

- **Type:** bug
- **Track:** A (compiler / bootstrap)
- **Status:** backlog
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
