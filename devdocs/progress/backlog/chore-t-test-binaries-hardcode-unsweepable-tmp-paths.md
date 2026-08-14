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
