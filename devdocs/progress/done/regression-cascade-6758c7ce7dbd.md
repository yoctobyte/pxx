---
prio: 70
---

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 23 jobs newly red in b8e3b3010..6758c7ce7 (105 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host seven).
  Untriaged. 23 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-09-05T18:47:38Z
- **Root-cause suspects in the red set:** none of the known root jobs (`fpc-bootstrap`, `selfhost-fixedpoint`). That is the ONLY heuristic applied here — it does not imply a harness event, and nothing in this filing looked at the build, the box or the range. See the Range section below for commits worth checking.

## Range
bad `6758c7ce7dbd`, last good `b8e3b3010249`, **105 commit(s) in range** (105 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `6758c7ce7dbd` fix(A+S): no program declaring a class could build for --esp-profile=bare
- `3bfc63fefb02` fix(C): the silent arm — an undeclared identifier in a file-scope initializer
- `78fc2dab3db3` feat(A/O): inline record-returning leaf functions at -O3
- `2bdbe4249c6f` fix(T): TSTATE.md renders the toolchain, and a FIRST report says it is the first
- `9bd00df4637b` fix(T): the canary devtest asserted a variable NAME, and went red on a rename
- `36ee694fae30` docs(D): pin v404 clears the gate, and the library aperture closes rather than being repor
- `8844c8c42a94` chore(stable): pin v404 -- binary sha256 fe1e9c37d322 -- unblocks 20 lib/rtl units and all
- `08ba24128a38` fix(P): a class property may be backed by a class var — one cause, two diagnostics, two ph
- `e7b33cf2f2a1` docs(D): make docsnip report what it cannot check, and enumerate every scope claim
- `13d8f7801d48` test(S): assert xtensa's dyn-array ownership guards, which became reachable unwatched
- `2d6bfadd6025` Revert "fix(P): a bare function name in a procedural slot segfaulted on four paths"
- `5d7cd32e143d` fix(A): SysOpen's ShortString path fed the kernel the length byte on riscv32 and xtensa
- ...and 93 earlier commit(s) in the range, not listed

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier full --job '<job>'` at 6758c7ce7dbd49121c88313f7dff14a59506d798

(The sha above is the right one to REPRODUCE at — the jobs really are red
there — even when the Range section says it cannot be the CAUSE. Reproducing
and blaming are different questions and this line answers the first.)

## Newly red jobs
> Each job's own recorded failure REASON is printed under its name. **When the
> reasons and the Range section disagree, the reasons win.** The range is
> computed from what CHANGED, not from what the job can SEE — a missing guest
> loader, an absent dev package or a job that has never once passed on this box
> all produce a red that no commit in the range caused.

- `test-emit-obj#src:test/c_obj_data_dup_a.c`
  - test-emit-obj: the Pascal object reads three C globals and its write is visible to C | ok: $TMP [code=107486B data=2720B bss=42304B procs=136] | test-emit-obj: the i386 Pascal object imports C global…
- `test-emit-obj#src:test/test_emit_obj.pas@3`
  - (.text+0x3036c): undefined reference to `lwip_accept' | /home/seven/.espressif/tools/xtensa-esp-elf/esp-15.2.0_20251204/xtensa-esp-elf/bin/../lib/gcc/xtensa-esp-elf/15.2.0/../../../../xtensa-esp-elf/…
- `test-emit-obj#src:tools/compiler_srchash.sh` — **CLEARED 2026-09-06 (frankD).** Fixed by `fc000b076` (i386 PIC prefix guard read a `$F0` displacement byte as LOCK); `git merge-base --is-ancestor 6758c7ce7dbd fc000b076` is TRUE, so the fix landed ABOVE the tested tree and there was never anything to bisect. Re-run green at HEAD `2699f5769`, binary `c9de36a3754e`. **The reason quoted below names the last step that PASSED, not the failure** — it is a 200-char cut of the log tail; see the second correction in `regression-test-debug-g-compiler-srchash-2.md`.
  - ok: $TMP [code=470952B data=12856B bss=70000B procs=854] | test-emit-obj: an i386 object's file-scope initialisers run under a gcc -m32 main | ok: $TMP [code=186531B data=1360B bss=38460B procs=490]…
- `test-pascal-conformance#shard1/6`
  - SKIP tmoperator9.pp — gap: record management operators Initialize/Finalize called for locals | SKIP tprop1.pp — gap: global `property` section in a program (FPC-mode global properties) | SKIP tstatic…
- `test-sqlite-threads-aarch64#src:tools/compiler_srchash.sh`
  - self-host fixedpoint: verified — 1 round(s), f519214f643f (stamp read back; sources match it) | test-sqlite-threads: building threadsafe sqlite (aarch64) ... | pascal26:43694: error: undeclared ident…
- `test-sqlite-threads-arm32#src:tools/compiler_srchash.sh`
  - self-host fixedpoint: verified — 1 round(s), f519214f643f (stamp read back; sources match it) | test-sqlite-threads: building threadsafe sqlite (arm32) ... | pascal26:43694: error: undeclared identif…
- `test-sqlite-threads-i386#src:tools/compiler_srchash.sh`
  - self-host fixedpoint: verified — 1 round(s), f519214f643f (stamp read back; sources match it) | test-sqlite-threads: building threadsafe sqlite (i386) ... | pascal26:43694: error: undeclared identifi…
- `test-sqlite-threads-x86_64#src:tools/compiler_srchash.sh`
  - self-host fixedpoint: verified — 1 round(s), f519214f643f (stamp read back; sources match it) | test-sqlite-threads: building threadsafe sqlite (x86_64) ... | pascal26:43694: error: undeclared identi…
- `test-uforth#src:tools/compiler_srchash.sh@1`
  - self-host fixedpoint: verified — 1 round(s), f519214f643f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@10`
  - self-host fixedpoint: verified — 1 round(s), f519214f643f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@11`
  - self-host fixedpoint: verified — 1 round(s), f519214f643f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@12`
  - self-host fixedpoint: verified — 1 round(s), f519214f643f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@13`
  - self-host fixedpoint: verified — 1 round(s), f519214f643f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@2`
  - self-host fixedpoint: verified — 1 round(s), f519214f643f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@3`
  - self-host fixedpoint: verified — 1 round(s), f519214f643f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@4`
  - self-host fixedpoint: verified — 1 round(s), f519214f643f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@5`
  - self-host fixedpoint: verified — 1 round(s), f519214f643f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@6`
  - self-host fixedpoint: verified — 1 round(s), f519214f643f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@7`
  - self-host fixedpoint: verified — 1 round(s), f519214f643f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@8`
  - self-host fixedpoint: verified — 1 round(s), f519214f643f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@9`
  - self-host fixedpoint: verified — 1 round(s), f519214f643f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-xtensa#src:test/test_cross_record.pas@3`
  - 1 | ok: $TMP [code=491372B data=2808B bss=42300B procs=173] | ok: $TMP [code=446316B data=2808B bss=42300B procs=173] | ok: $TMP [code=122648B data=2832B bss=43500B procs=134] | xt_bigcall: expected…
- `test-zlib#src:tools/compiler_srchash.sh`
  - self-host fixedpoint: verified — 1 round(s), f519214f643f (stamp read back; sources match it) | building gcc oracle ... | compiling pxx zlib runner ... | pascal26:202: error: conflicting types for ty…

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*

## Log
- 2026-09-06 — auto-closed by the seven watcher: `cascade@6758c7ce7dbd` passes at c543b335fb2f (tier full); it was red at 6758c7ce7dbd. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
