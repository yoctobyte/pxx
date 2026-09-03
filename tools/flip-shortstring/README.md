# The phase-4 shortstring flip: the measurement, while both modes exist

**These four scripts have a lifetime, and it is short.** They compare the tree
as it stands against `-dPXX_SHORTSTRING`, which today IS the post-flip state.
**The commit that deletes `PXX_SHORTSTRING` should delete this directory in the
same diff** — after that there is no "off" mode left to compare against and
every script here silently measures one thing twice.

They are here rather than in a scratchpad because the flip is not finished:
franka-29 owns the four defects, and each fix wants the affected rows
re-measured on all seven targets before the flag goes.

    tools/flip-shortstring/sweep.sh   <out.tsv> <artifactdir> <target>
    tools/flip-shortstring/oracle_fpc.sh <out.tsv> <fpcdir>
    tools/flip-shortstring/noise.sh   <artifactdir> <target>:<test> ...
    tools/flip-shortstring/matrix.py  <dir holding the .tsv files>

Targets: `x86_64 i386 aarch64 arm32 riscv32 xtensa wasm32`. xtensa needs
`--platform=posix --xtensa-soft-mulhigh` (the sweep passes both), so its rows
are not bit-identical to hardware for multiplies; wasm32 emits `.wasm` and runs
under wasmtime.

**Run `noise.sh` on every differing row before believing any of them.** Three
of this sweep's first sixteen "findings" were the instrument: wasmtime names
the binary in its trap message, its backtrace prints code offsets that move
with code size, and i386 `test_rtti_reg` dumps a stack address so the same
binary differs from ITSELF by 3 of 47557 bytes under ASLR. `matrix.py`
normalises the first two and excludes the third by name.

Results as of 2026-09-03: `devdocs/dev/shortstring-flip-cross-target-matrix.md`.

**Layout `matrix.py` expects** (all under one directory): `<target>.tsv` per
target from `sweep.sh`, the binaries and their captured output in `x/`, and the
FPC oracle's per-test directories in `f/`. Pass `x/` as `sweep.sh`'s
artifactdir and `f/` as `oracle_fpc.sh`'s, and it joins them.
