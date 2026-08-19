---
track: T
prio: 45
type: chore
summary: "60 /tmp paths are hardcoded in 37 COMPILED TEST SOURCES and written by the test binary at runtime, so no Makefile sweep can reach them and testmgr does not privatize them either. Two concurrent runs still share those files EVEN UNDER testmgr. Split out of chore-makefile-testtmp-parameterize, which closed the recipe half."
---

# Test binaries hardcode /tmp paths that no Makefile sweep can reach

- **Type:** chore/infra — **Track T** (the shape, and testmgr's pin rule).
  Individual sources belong to their owning lane; see Ownership below.
- **Split out of** [[chore-makefile-testtmp-parameterize]], which landed the
  recipe half (6855 sites routed through `$(TESTTMP)`) and said explicitly:
  *"Do not widen this ticket to cover them — it is a separate, smaller job…
  Just do not read a green Gate here as 'no shared temp files remain'."*
  This is that job.

## The gap, measured

A Makefile sweep can only reach paths the **recipe** names. A path the compiled
test writes **at runtime** is invisible to it — and testmgr's privatization does
not apply either, because testmgr rewrites the recipe text it executes, not the
string constants inside a binary it runs.

Measured at the sweep's landing commit:

| | count |
|---|---|
| distinct `/tmp` paths hardcoded in compiled sources under `test/`, `lib/`, `examples/` | **63** |
| of those, also named in the Makefile → **pinned** literal by the sweep, correctly | 3 |
| written **only at runtime** by the binary — the residue this ticket is about | **60** |
| source files involved | **37** |

The three pinned ones (`/tmp/test_nilpy_sqlite_crud.db`,
`/tmp/pxx_lua_input.lua`, `/tmp/httpdemo`) stay literal on purpose: recipe and
source must agree on the name. That is the pin rule working — but they are still
collisions, just visible ones.

## The race is live, including under testmgr

Worth stating plainly, because the sweep's green gate invites the opposite
conclusion: **two concurrent runs still share these files even under testmgr**,
the one runner everyone assumes is isolated. Two runs opening
`/tmp/test_nilpy_sqlite_crud.db` at once is a data race on a database file, not
a flaky string compare — and `test/csqlite_parity_selfcompiled.c` and
`test/csqlite_thread_test.c` both write plain `/tmp/x`, so they collide with
each other *and* with any ad-hoc scratch file a human or agent leaves there.
`/tmp/x` is the single most likely name in the repo to be clobbered from
outside.

## The files

Each needs a decision, which is why this is not a scripted sweep: some paths are
**load-bearing** (a recipe or a second process must agree on the name, a fixture
the test asserts about) and some are pure scratch.

| source | hardcoded paths |
|---|---|
| `test/cdup.c` | `/tmp/pxx_dup_probe.txt` |
| `test/cfile_stdio_b87.c` | `/tmp/pxx_crtl_file_stdio_b87.txt` |
| `test/cfileops.c` | `/tmp/pxx_fops_probe`, `/tmp/pxx_fops_probe/hard.txt`, `/tmp/pxx_fops_probe/orig.txt`, `/tmp/pxx_fops_probe/sym.txt`, `/tmp/pxx_no_such_dir_zz` |
| `test/cjson/runner.c` | `/tmp/pxx_cjson_input.json` |
| `test/cposix_io.c` | `/tmp/pxx_cposix_io.txt` |
| `test/crtl_lfs64_aliases_b234.c` | `/tmp/pxx_crtl_lfs64_b234.tmp` |
| `test/crtl_libc_oracle.c` | `/tmp/crtl_stdio_probe.txt` |
| `test/crtl_posix_io_leaf_b238.c` | `/tmp/pxx_crtl_posix_io_b238.dir`, `/tmp/pxx_crtl_posix_io_b238.tmp`, `/tmp/pxx_no_such_file_b238` |
| `test/crtl_stat_errno_enoent_b235.c` | `/tmp/pxx_b235_no_such_dir_zzz/nope.file` |
| `test/csqlite_file_probe.c` | `/tmp/pxx_sqlite_file_probe.db` |
| `test/csqlite_parity_selfcompiled.c` | `/tmp/x` |
| `test/csqlite_thread_test.c` | `/tmp/x` |
| `test/cstat_fields.c` | `/tmp/pxx_stat_probe`, `/tmp/pxx_stat_probe/f.txt`, `/tmp/pxx_stat_probe/h.txt`, `/tmp/pxx_stat_probe/sub` |
| `test/lib_directory.pas` | `/tmp/pxx_dir_suite`, `/tmp/pxx_dir_suite/alpha.txt`, `/tmp/pxx_dir_suite/child` |
| `test/lib_fpc_surface_2026_08.pas` | `/tmp/lib_fpcsurf_a.txt`, `/tmp/lib_fpcsurf_b.txt`, `/tmp/lib_fpcsurf_c.txt`, `/tmp/lib_fpcsurf_d.txt` |
| `test/lib_platform.pas` | `/tmp/pxx_pal_platform.txt`, `/tmp/pxx_pal_platform_dir`, `/tmp/pxx_pal_platform_renamed.txt` |
| `test/lib_platform_esp.pas` | `/tmp/no-host-fallback`, `/tmp/no-host-fallback-2`, `/tmp/no-host-fallback-dir` |
| `test/lib_textfile.pas` | `/tmp/pxx_lib_textfile.txt` |
| `test/lib_textreadchar.pas` | `/tmp/lib_textreadchar_1.txt`, `/tmp/lib_textreadchar_2.txt`, `/tmp/lib_textreadchar_3.txt` |
| `test/lua/files.lua` | `/tmp/pxx_lua_file_api.txt` |
| `test/quickjs/runner.c` | `/tmp/qjs_runner` |
| `test/test_cross_sysopen_family.pas` | `/tmp/frankonpiler_sysopen_family.tmp` |
| `test/test_nilpy_file_close_readlines.npy` | `/tmp/pxx_test_close_readlines.txt` |
| `test/test_nilpy_file_read_follows_the_mode.npy` | `/tmp/pxx_nilpy_read_mode.txt` |
| `test/test_nilpy_file_write_text.npy` | `/tmp/pxx_test_write_append.txt`, `/tmp/pxx_test_write_text.txt`, `/tmp/pxx_test_write_text2.txt`, `/tmp/pxx_test_write_text3.txt`, `/tmp/pxx_test_write_text5.txt` |
| `test/test_nilpy_json_module.npy` | `/tmp/pxx_test_json_module.json` |
| `test/test_nilpy_len_of_a_file_read.npy` | `/tmp/test_nilpy_len_read.txt` |
| `test/test_nilpy_open_one_class_every_mode.npy` | `/tmp/pxx_test_open_one_class.txt` |
| `test/test_nilpy_os_path_more.npy` | `/tmp/pxx_osp_test.txt` |
| `test/test_nilpy_typeerror_is_catchable.npy` | `/tmp/pxx_absent_file_zz.txt` |
| `test/test_nilpy_with_name_reuse.npy` | `/tmp/pxx_test_with_name_reuse.txt` |
| `test/test_nilpy_with_protocol.npy` | `/tmp/test_nilpy_with_protocol.txt` |
| `test/test_nilpy_write_overload_by_arg_type.npy` | `/tmp/pxx_test_write_overload.txt` |
| `test/test_sqlite_crud.pas` | `/tmp/test_sqlite_crud26.db` |
| `test/test_textfile.pas` | `/tmp/test_textfile_data26.txt` |
| `test/test_textfile_in_unit.pas` | `/tmp/pxx_textfile_unit_test.txt` |
| `test/test_writeln_text_char.pas` | `/tmp/test_writeln_text_char.txt` |

(`examples/net/httpdemo.pas` also hardcodes `/tmp/httpdemo`, but that one is in
the pinned set — recipe and source agree on it deliberately.)

## Suggested approach

Read the directory from the **environment** rather than inventing a per-test
convention: the sweep already `export`s `TESTTMP`, so a test can honour it with
a getenv and fall back to `/tmp`. That keeps the default byte-identical, needs
no recipe change, and makes `make <suite> TESTTMP=$(mktemp -d)` isolate the
runtime half exactly as it now isolates the recipe half — **one mechanism, not
two**, which is the whole point.

Where a path really is load-bearing, pass it from the recipe as an argument or
an env var instead of duplicating the literal in two places. Duplication is what
made these unsweepable to begin with.

A caveat worth honouring: some of these paths are load-bearing *for what the
test asserts* — `test/lib_platform_esp.pas`'s `/tmp/no-host-fallback` names are
there to prove the ESP PAL **refuses** them, and `crtl_stat_errno_enoent_b235`
depends on its path NOT existing. Those want reading before rewriting.

## Ownership

Track T owns the shape and testmgr's pin rule. Individual sources belong to
their lane — the C fixtures are Track C, the `.npy` ones N, `lib_*`/`examples`
B. Per CLAUDE.md, **T owns the tool, never the bug**: if honouring `TESTTMP` in
a given test turns up a compiler or RTL gap, file it into the owning lane rather
than working around it here.

## Gate

No `/tmp` path hardcoded in a compiled test source outside the agreed pinned
set; a suite run with a non-default `TESTTMP` leaves `/tmp` untouched; two
concurrent runs with different `TESTTMP` values share no file.

## 2026-08-19, Track T — the guard is built; here is the per-lane split

T's half is done: `tools/testmgr_hardcoded_tmp_devtest.py`, in `make tools-devtest`
(limited + full), so the class is **detectable** instead of rediscovered. The
per-source work stays with the owning lanes, as this ticket's Ownership section
says and as T's boundary requires.

It is a **RATCHET**: the 61 existing pairs sit in `KNOWN` and the guard is green
on them; anything not listed FAILS. Verified by adding a probe source with a
hardcoded path — it failed, naming the file and the path — and green again once
removed. When a lane fixes a file, the guard prints
`… no longer hardcodes … — remove it from KNOWN`, so the list tightens rather
than drifting into a permanent allowlist.

**The ratchet is the right shape because the class is still GROWING.** This
ticket recorded 37 files at its landing commit; there are **40** today. `/tmp/x`
went away and `/tmp/b` arrived
(`test/test_nilpy_oserror_class_and_message.npy`), along with
`test_nilpy_bare_genexpr_arguments.npy`, `test_nilpy_file_writelines.npy` and
`test_nilpy_sqlite_crud.npy`. Fixing 60 while the 61st is being written is not
progress.

### Two corrections to the counts above

Both come from scanning **string literals** rather than raw text, which is the
right measure for "a path the binary writes at runtime":

- **`/tmp/httpdemo` is a comment**, not a runtime path — `examples/net/httpdemo.pas`
  line 13 shows the build command. It is in the "pinned" set above on the
  strength of the Makefile also naming it, but the SOURCE never opens it.
- **`/tmp/x` is a comment too**, in both `test/csqlite_thread_test.c` and
  `test/csqlite_parity_selfcompiled.c`. The ticket calls it *"the single most
  likely name in the repo to be clobbered from outside"* — and at runtime
  neither test opens it at all. That collision does not exist.

A path a binary never writes cannot collide, so the residue is **61 pairs across
39 files**, not 60 across 37, and it is differently distributed than the table
suggests.

### The split, ready to route

| lane | files | paths | what they are |
| --- | --- | --- | --- |
| **C** | 12 | 21 | the `.c` fixtures plus `test/lua/files.lua` |
| **N** | 14 | 18 | the `.npy` tests, mostly one path each |
| **B** | 6 | 17 | `test/lib_*.pas` — directory, textfile, platform, fpc-surface |
| **P** | 5 | 5 | the remaining `test/*.pas` — sysopen, sqlite_crud, textfile, writeln |

N is the largest by file count and the cheapest per file (14 files, 18 paths,
almost all a single scratch file honouring `$TESTTMP` with a getenv). C is the
largest by path count and holds both load-bearing cases. **B and P are small
enough to be one sitting each.**

### Load-bearing — these are NOT sweepable, and the guard says so in its header

Recorded here because a future sweeper will otherwise "fix" both and break them
silently, and until now the only place this was written down was a chat message:

- **`test/lib_platform_esp.pas`** — `/tmp/no-host-fallback`,
  `-2`, `-dir` exist to prove the ESP PAL **refuses** them. Any path proves it;
  one that silently succeeds does not.
- **`test/crtl_stat_errno_enoent_b235.c`** —
  `/tmp/pxx_b235_no_such_dir_zzz/nope.file` depends on **not existing**.
  Relocating it under a fresh scratch dir is fine; creating it is not.

`test/lib_directory.pas`, `cfileops.c` and `cstat_fields.c` create directory
TREES rather than single files, so they want reading before rewriting too — they
are not one-line getenv changes.

### What T is not doing

Not editing the 39 sources (three other lanes own them), and not filing the four
lane tickets — routing is the coordinator's. This section is the proposal.

### Routing, decided by the coordinator 2026-08-19

| lane | files | state |
| --- | --- | --- |
| **C** | 12 | **ROUTED** — active lane under the current mandate |
| **P** | 5 | **ROUTED** — same |
| **N** | 14 | **HELD on the Track N deferral.** Not unowned and not an oversight: the user has deferred Track N entirely, and A/P/C outranks everything N including N bugs. These are the cheapest of the four groups (14 files, 18 paths, almost all one scratch file honouring `$TESTTMP` via getenv), so they will close quickly whenever N resumes |
| **B** | 6 | **PARKED — no worker.** frank2 is on A/P/C triage. Not deferred by policy, just unstaffed |

Recorded per lane because an unrouted item with no reason reads as an oversight,
and the next reader would otherwise spend the time re-deriving why 20 of the 37
files have nobody on them.

The ratchet means none of this is urgent: nothing new can be added while the
groups wait, which is the property a cleanup would not have had.
