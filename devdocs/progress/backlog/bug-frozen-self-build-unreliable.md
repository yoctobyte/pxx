# Frozen-string compiler self-build (`bootstrap-frozen` / `stabilize-frozen`) is unreliable

- **Type:** bug (build/infra) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30
- **Found by:** incidental, while working bug-frozen-string-result-global (the
  frozen self-build is the only thing that exercises frozen-string returns in the
  compiler itself, so it was used as a probe).

## Symptom

A frozen-string compiler self-build does not reliably reach a fixpoint:

```
stable_linux_amd64/default/pinned -uPXX_MANAGED_STRING compiler/compiler.pas /tmp/frz1   # ok
/tmp/frz1                          -uPXX_MANAGED_STRING compiler/compiler.pas /tmp/frz2   # FAILS
```

`frz1` builds fine, but `frz1` compiling the compiler again produces **no output
file** — sometimes a `Segmentation fault (core dumped)`, sometimes a silent exit
with no file, occasionally exit 0. Reproduced on **pristine master** (pinned
compiler, unmodified source), so it is **pre-existing and independent of any
in-flight frozen-string-return work**.

## Likely cause (unconfirmed)

Resource / OOM, not necessarily a codegen bug. A frozen-mode compiler has a
**~490 MB BSS** (frozen strings use 8 MB `STRING_CAP` globals/temps pervasively);
`frz1` compiling the compiler holds its own ~490 MB resident *and* emits another
~490 MB image. Under concurrent load (the repo runs several agents at once) that
is a plausible OOM-kill — which presents exactly as "silent no-output" or an
inconsistent segfault. The intermittency (sometimes exit 0) fits OOM better than a
deterministic miscompile.

## Why it matters / why it's low-priority right now

- **Not in the gate.** `make test` is managed-only (`test-core test-debug-g
  lib-fpc-clean`); it does NOT do a frozen compiler self-build. So this does not
  block the daily loop. But `bootstrap-frozen` / `stabilize-frozen` /
  `test-frozen`-as-selfbuild are advertised targets and should work.
- It also means **the frozen self-build cannot currently be used as a
  byte-identical signal** when changing frozen-string codegen — a real gap for
  bug-frozen-string-result-global (which only frozen mode exercises in-compiler).

## To investigate

1. Run the failing step alone (no other agents) under `/usr/bin/time -v` and watch
   max RSS; check `dmesg` for an OOM-killer line. If OOM: either reduce frozen BSS
   (the 8 MB `STRING_CAP` temps — many could be `LOCAL_STR_CAP`, cf.
   bug-ansistring-concat-arg-static-bloat) or document a memory floor for frozen
   self-build.
2. If it segfaults deterministically under ample memory: it is a real frozen-mode
   miscompile — bisect which compiler routine, likely a frozen-string return or a
   frozen global temp.

## Acceptance

- `bootstrap-frozen` (or a `pinned -u… ×2 + cmp`) reaches a byte-identical
  fixpoint reliably, OR the memory requirement is understood + documented and the
  build is made to not silently produce a truncated/missing binary.
