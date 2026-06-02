# Benchmark: Pascal Runtime Gate - 2026-06-02

This follow-up snapshot records the coarse Pascal runtime-reachability gate in
`1f9739a` (`perf(runtime): gate unused Pascal support`).

## Result

Plain `test/hello.pas` no longer emits unused Linux heap startup or the managed
`AnsiString` helper bundle:

| Pascal hello ELF | Before gate | After gate | Reduction |
| --- | ---: | ---: | ---: |
| Self-hosted `pascal26` | 1,134 bytes | 287 bytes | 847 bytes (74.7%) |

The directly emitted output remains a static ELF64 executable with one program
header and no section table.

## Benchmark

Environment matches [`2026-06-02-vs-fpc.md`](2026-06-02-vs-fpc.md). Hyperfine
used 3 warmups and 30 measured runs for compiler source, then 1 warmup and 10
measured runs for the 20-compile hello batch.

| Workload | FPC | Self-hosted `pascal26` | Relative |
| --- | ---: | ---: | ---: |
| Compile compiler source once | 874.8 +/- 19.0 ms | 782.3 +/- 11.2 ms | 1.12x faster |
| Compile Pascal hello 20 times | 720.5 +/- 17.7 ms | 38.3 +/- 0.4 ms | 18.80x faster |

Binary sizes:

| Output executable | FPC | Self-hosted `pascal26` |
| --- | ---: | ---: |
| Compiler | 1,100,896 bytes | 840,361 bytes |
| Pascal hello | 191,072 bytes | 287 bytes |

## Scope

The new Pascal token pre-scan is deliberately conservative. It retains heap
startup and managed-string helpers when allocation-capable syntax, managed
strings, Variants, classes, arrays, or imported units may need them. Nil Python
remains eager for now because its dynamic fallback makes a similarly narrow
gate less obvious.

Finer helper-level reachability remains optional cleanup.
