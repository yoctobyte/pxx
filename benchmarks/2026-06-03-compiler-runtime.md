# Benchmark: FPC-built vs self-hosted pascal26 runtime - 2026-06-03

This benchmark measures the speed of the `pascal26` compiler executable itself
when that executable is compiled by FPC, compared with the checked-in
self-hosted `pascal26` executable.

It answers a different question than the FPC-vs-`pascal26` build-speed
benchmark: not "how fast is FPC as a compiler?", but "how much does the
compiler's own generated-code quality affect compiler runtime?"

## Environment

- Revision: `97ed833` (`docs: record callee-return inference and auto string->const char* as landed`)
- OS: Linux 6.17.0-29-generic x86_64
- CPU: Intel Core i7-6700 CPU @ 3.40GHz, 4 cores / 8 threads
- FPC: 3.2.2
- FPC flags: `-O2 -Tlinux -Px86_64`
- Timing tool: hyperfine 1.18.0
- Compiler source plus includes: 23,342 lines

## Compiler Runtime On Large Input

Workload: compile `compiler/compiler.pas` once with each `pascal26` executable.
Hyperfine used 3 warmups and 30 measured runs.

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `FPC-built pascal26 compiles compiler` | 364.2 +/- 17.3 | 345.9 | 434.8 | 1.00 |
| `self-hosted pascal26 compiles compiler` | 839.8 +/- 56.3 | 797.9 | 1017.2 | 2.31 +/- 0.19 |

For the full compiler source workload, the FPC-built `pascal26` executable ran
**2.31x faster** than the self-hosted executable.

## Compiler Runtime On Tiny Inputs

Workload: compile `test/hello.pas` 20 times per sample. Hyperfine used 1
warmup and 10 measured runs.

| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `FPC-built pascal26: 20 x hello` | 264.1 +/- 24.5 | 234.8 | 305.4 | 6.10 +/- 0.66 |
| `self-hosted pascal26: 20 x hello` | 43.3 +/- 2.4 | 39.7 | 45.7 | 1.00 |

For repeated tiny compiles, the self-hosted executable ran **6.10x faster**.
This workload is dominated by process startup, dynamic loader/runtime startup,
and fixed per-invocation overhead rather than parser/codegen throughput.

## Output Checks

Before timing, the target checks that the FPC-built and self-hosted compiler
executables produce byte-identical compiler outputs:

| Output | Size |
| --- | ---: |
| FPC-built `pascal26` executable | 1,121,376 bytes |
| Compiler output from FPC-built `pascal26` | 859,322 bytes |
| Compiler output from self-hosted `pascal26` | 859,322 bytes |
| Pascal hello from FPC-built `pascal26` | 287 bytes |
| Pascal hello from self-hosted `pascal26` | 287 bytes |

Both hello outputs print `Hello, World!`.

## Method

Run:

```sh
make benchmark-compiler-runtime
```

The target writes:

- `/tmp/frankonpiler-compiler-runtime-bench.md`
- `/tmp/frankonpiler-compiler-runtime-hello-bench.md`

## Interpretation

Generated-code optimization is clearly relevant for sustained compiler
throughput: FPC's optimized build more than doubles speed on the large
self-compile workload. The self-hosted binary still has much lower fixed
overhead on tiny repeated compiles, mostly because it is a small direct ELF
with no FPC runtime startup.
