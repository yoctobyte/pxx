---
prio: 60
---

# C differential fuzzing (csmith vs gcc) — campaign, PAUSED with the harness live

- **Type:** feature / ongoing campaign — Track C (with Track A fixes as they fall out)
- **Status:** harness LANDED and productive. Paused 2026-07-13 to refocus on Pascal (user).
  Resume by running the one command below; nothing needs rebuilding or rediscovering.
- **Origin:** step 4 of [[feature-c-corpus-expansion]] ("csmith differential fuzzing").

## Resume in one line

```sh
make fuzz-csmith FUZZ_ITERS=200          # or: tools/csmith_fuzz.py --iters 200
```

Prereqs are already satisfied on this box: `csmith` (apt) and the runtime headers, which
`tools/install_lib_candidates.sh csmith` vendors WITHOUT root (`apt-get download` +
`dpkg-deb -x` into `library_candidates/csmith/include`, gitignored).

## Why it works — the oracle needs no judgement

csmith generates C that is free of undefined behaviour BY CONSTRUCTION, and every program
ends by printing a checksum of all its globals. So: build the same program with gcc and
with pxx, run both, compare the checksum. A difference is a real miscompile in one of the
two — and it is not gcc. The harness also builds at several pxx `-O` levels and compares
them against each other, which catches our own optimiser without needing gcc at all.

Findings are bucketed (`MISCOMPILE_VS_GCC`, `MISCOMPILE_OPT`, `PXX_CRASH`,
`PXX_COMPILE_FAIL`, `PXX_TIMEOUT`) and DEDUPLICATED — csmith throws thousands of programs
at the same few gaps, and 500 copies of one bug is not 500 bugs. Each distinct hit is
saved with its seed and a REPRO.md.

## Scoreboard when paused

**Nine bugs found and fixed in the first sitting** (2026-07-13). Every one was SILENT, and
not one was reachable by the real-world corpora we already run (lua, sqlite, tcc, zlib,
c-testsuite) — those are *written by humans who avoid dark corners*:

| # | bug | why the corpora missed it |
| --- | --- | --- |
| b306 | signed bitfields never sign-extended (`signed f:7` = -5 read as 123) | corpora use UNSIGNED bitfields |
| — | signed bitfield FILLING its unit (`signed f:8` -7 → 249) | the storage load is always unsigned |
| — | enum bitfields must stay UNSIGNED while plain `int x:8` is SIGNED | both map to tyInt32 |
| b307 | struct-valued comma passed by value → SEGV; also on the RHS of `=` | a comma is not an lvalue |
| b308 | a discarded expression statement did not RUN (`f() ^ 3;` never called f()) | values were right, only side effects vanished |
| b309 | multidim array of POINTERS ignored its brace initializer (local AND global) | 1-D and multidim-int both worked |
| b310 | anonymous bit-fields (`unsigned : 0;`) made the whole aggregate OPAQUE — sizeof 0 | rejected outright, silently |
| b311 | multidim LOCAL array of STRUCTS initialised only its first element | nDims hard-coded to 1 |
| b312 | global pointer to a multidim array element lost its initializer → null | only one `[...]` was consumed |
| — | C99 hex float (`0x1.0p-28f`) + leading-dot (`.5f`) literals | blocked csmith from running at all |

After these, **MISCOMPILE_VS_GCC is at zero** across a 40-program sweep; the residual
failures are crashes (still one dominant class — see below).

## What is still open

- **A residual crash class.** `/tmp` findings are gone by now, but it reproduces in
  minutes: run the harness and reduce (recipe below). Last known unreduced crashers were
  csmith seeds 901 and 1502 (generated with the DEFAULT csmith flags).
- **Bitfield LAYOUT** ([[bug-c-bitfield-packing-sizeof-vs-gcc]]) — `sizeof` of a packed
  bitfield struct is 12 where gcc gives 8. Values are right, so the checksum oracle CANNOT
  see it; it breaks ABI/interop instead.
- **Brace elision over rows** ([[bug-c-multidim-brace-elision-flattens-rows]]) —
  `int q[2][3] = {{1},{2}}` gives q[0][1]=2 instead of 0. Pre-existing.
- **`--opts 0,2,3`** — the harness only ran `-O0,-O2` in anger. Adding `-O3` would point
  the same oracle at Track O's newer passes for free.
- **Cross targets.** Everything so far is x86-64. The same programs under qemu would
  exercise aarch64/arm32/i386/riscv32 codegen against the same oracle. High value, cheap:
  the harness only needs a `--target` pass-through and `tools/run_target.sh`.

## Reduction recipe (no creduce on this box — these work without it)

1. **Name the guilty variable in seconds.** csmith programs take an argv flag that prints a
   checksum after EVERY global:
   ```sh
   ./t_gcc 1 > g.txt ; ./t_pxx 1 > p.txt ; diff g.txt p.txt | head
   ```
   The first divergent line names the variable. This is how the bitfield bug went from
   2474 lines to a 6-line repro.
2. **For a crash, find the last function entered:** inject `printf("TR func_N\n"); fflush(stdout);`
   at the top of each function. Match the brace on the line AFTER the signature — csmith
   writes `{ /* block id: 0 */`, not a bare `{`. Then bisect inside that function the same way.
3. **Shrink the search space, not the program:**
   ```sh
   tools/csmith_fuzz.py --iters 30 "--csmith-args=--max-funcs 2 --max-block-depth 2 --max-expr-complexity 2"
   ```
   gives ~300-line crashers instead of 1700. NOTE the `=` — argparse eats a bare
   `--csmith-args --no-x`.
4. `sudo apt install creduce` would make all of this much faster and is worth it.

## Traps (paid for in wasted time)

- **Call ORDER differing from gcc is NOT a bug.** C leaves argument evaluation order
  unspecified; csmith only guarantees the OUTPUT is order-independent. Do not chase it.
- **Replaying a seed without the same `--csmith-args` generates a DIFFERENT program.**
  Use the saved `t.c` in the findings directory, not just the seed.
- **A `printf` you inject can move or hide the crash** — that means memory corruption, and
  it is a signal, not an annoyance.
