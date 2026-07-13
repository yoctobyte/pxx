---
prio: 60
---

# bug: pxx-built csmith program segfaults (csmith seed 2), -O0

- **Track:** A/C
- **Found:** 2026-07-13 by the csmith differential fuzzer (`tools/csmith_fuzz.py`).

## Repro

```sh
tools/csmith_fuzz.py --seed 2
```

or by hand (the fuzzer saves the exact program):

```sh
csmith --seed 2 --output t.c
gcc -O0 -w -Ilibrary_candidates/csmith/include t.c -o t_gcc && ./t_gcc   # prints a checksum
./compiler/pascal26 -Ilibrary_candidates/csmith/include t.c t_pxx && ./t_pxx   # SIGSEGV (exit -11)
```

gcc builds and runs it fine and prints its checksum; the pxx-built binary dies with
SIGSEGV. At **-O0**, so this is core codegen or the frontend, not an optimiser bug.

Still present after the signed-bitfield fix (63595f27) — that fix cleared the *checksum*
divergence (seed 4) but not this crash.

## Not yet reduced

The program is ~1700 lines. No `creduce`/`cvise` on the box (`sudo apt install creduce`
would give us one, and is worth it — it is the standard tool for exactly this).

Reduction hint that works without creduce: csmith programs take an argv flag that makes
them print a checksum after EVERY global, so

```sh
./t_gcc 1 > gcc.txt ; ./t_pxx 1 > pxx.txt ; diff gcc.txt pxx.txt | head
```

names the first global that goes wrong — that is how the signed-bitfield bug was pinned
down in minutes. For a crash, run the pxx binary under gdb and get the faulting function,
then narrow to that function's body.

## Feature-space bisect (cheaper than line reduction)

csmith can switch whole feature classes off, so a handful of runs tells you which feature
the crash needs:

```sh
tools/csmith_fuzz.py --iters 20 --csmith-args '--no-bitfields'
tools/csmith_fuzz.py --iters 20 --csmith-args '--no-packed-struct'
tools/csmith_fuzz.py --iters 20 --csmith-args '--no-unions'
tools/csmith_fuzz.py --iters 20 --csmith-args '--no-volatiles'
```
