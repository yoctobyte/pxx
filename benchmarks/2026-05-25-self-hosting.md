# Self-Hosting Baseline - 2026-05-25

This records the first performance baseline after recursive self-hosting was
made the normal build path.

## Milestone Note

The project owner described this result as making his day, particularly
because FPC is already regarded as a very fast compiler compared with many
development environments. This reaction is part of the historical record:
recursive self-hosting did not merely work; its first measured build path was
immediately fast enough to feel significant.

## Subject

- Source revision: `de8c297` (`build: make self-hosting the default`)
- Self-hosting milestone: `milestone/full-recursive-self-hosting`
- Workload A: compile `compiler/compiler.pas` into an executable compiler
- Workload B: compile `test/hello.pas` twenty times per timed sample
- Both generated programs were executed after measurement; `hello` printed
  `Hello, World!`, and the self-built compiler compiled and ran it.

## Environment

- OS: Linux 6.17.0-23-generic x86_64
- CPU: Intel Core i7-6700 CPU @ 3.40GHz, 4 cores / 8 threads
- FPC: 3.2.2
- Timing tool: hyperfine 1.18.0

## Protocol

Compiler-source compilation used 3 warmups and 30 measured runs:

```sh
hyperfine --warmup 3 --runs 30 \
  --command-name 'FPC 3.2.2' \
  'fpc -O2 -Tlinux -Px86_64 -FU/tmp/frankonpiler-bench-fpc-units -o/tmp/pascal26-bench-fpc compiler/compiler.pas >/dev/null' \
  --command-name 'self-hosted pascal26' \
  './compiler/pascal26 compiler/compiler.pas /tmp/pascal26-bench-self >/dev/null'
```

Small-source compilation was batched because a single self-hosted `hello`
compile completes below hyperfine's reliable short-command threshold. It used
1 warmup and 10 measured runs:

```sh
hyperfine --warmup 1 --runs 10 \
  --command-name 'FPC 3.2.2: 20 x hello' \
  'for i in $(seq 1 20); do fpc -O2 -Tlinux -Px86_64 -FU/tmp/frankonpiler-bench-hello-fpc-units -o/tmp/hello-bench-fpc test/hello.pas >/dev/null; done' \
  --command-name 'self-hosted pascal26: 20 x hello' \
  'for i in $(seq 1 20); do ./compiler/pascal26 test/hello.pas /tmp/hello-bench-self >/dev/null; done'
```

## Results

| Workload | FPC mean | Self-hosted mean | Ratio |
| --- | ---: | ---: | ---: |
| Compile compiler source once | 225.9 ms +/- 16.3 ms | 10.5 ms +/- 1.3 ms | 21.54x faster |
| Compile `hello` 20 times | 888.3 ms +/- 138.0 ms | 8.3 ms +/- 0.3 ms | 106.69x faster |

The second line corresponds to approximately `44.42 ms` versus `0.42 ms` per
`hello` invocation, but the batched measurement is the recorded value.

| Output executable | FPC | Self-hosted |
| --- | ---: | ---: |
| Compiler | 597328 bytes | 135119 bytes |
| `hello` | 191072 bytes | 287 bytes |

## Interpretation

This is a build-speed baseline, not an optimizer or language-completeness
comparison. FPC emits a general-purpose Pascal executable with its runtime;
the self-hosted compiler emits the currently supported direct ELF subset. The
meaningful result for the project is that recursive self-builds are already
cheap enough to use as the default development path while FPC remains a
compatibility and recovery compiler.

This lead is not assumed to be permanent. As the compiler grows beyond its
current subset, stronger semantic analysis, diagnostics, optimizations,
additional language frontends, and runtime support may add real compilation
cost. Keep this baseline as the starting point, and rerun `make benchmark`
after substantial compiler-capability changes so future speed comparisons
remain honest.
