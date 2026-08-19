#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: no NEW hardcoded /tmp path in a compiled test source.

A Makefile sweep can only reach paths the RECIPE names, and testmgr privatizes
the recipe text it executes — not string constants inside a binary it runs. So a
`/tmp` path written at RUNTIME by a compiled test is invisible to both, and two
concurrent runs share it even under testmgr, the one runner everyone assumes is
isolated (chore-t-test-binaries-hardcode-unsweepable-tmp-paths).

This is a RATCHET, not a repair. The 61 existing pairs are listed in KNOWN and
the guard is green on them; anything NOT listed fails. Track T owns the shape and
this guard; the individual sources belong to their lanes — the `.c` fixtures to
C, the `.npy` ones to N, `lib_*`/`examples` to B — so the fixes are theirs to
make and each removal here is one line.

Measured while writing this, and it is the argument for a ratchet: the ticket
recorded 37 files at its landing commit, and there are 40 now. `/tmp/x` went away
and `/tmp/b` arrived (test_nilpy_oserror_class_and_message.npy). The class grows
on its own.

TWO CORRECTIONS to that ticket's counts, both from scanning STRING LITERALS
rather than raw text:

  * `/tmp/httpdemo` in examples/net/httpdemo.pas is in a COMMENT showing the
    build command, not a runtime path;
  * likewise `/tmp/x` in test/csqlite_thread_test.c and
    test/csqlite_parity_selfcompiled.c — the ticket calls these the most likely
    name in the repo to be clobbered from outside, and at runtime neither test
    opens it at all.

A path a binary never writes is not a collision, so the residue is smaller than
the ticket says.

LOAD-BEARING, do not "fix" these by sweeping them into $TESTTMP — the path is
what the test ASSERTS about:

  * test/lib_platform_esp.pas — `/tmp/no-host-fallback*` exist to prove the ESP
    PAL REFUSES them. A different path still proves it; a rewritten one that
    silently succeeds does not.
  * test/crtl_stat_errno_enoent_b235.c — `/tmp/pxx_b235_no_such_dir_zzz/nope.file`
    depends on NOT existing. Relocating it under a fresh scratch dir is fine;
    creating it is not.

Run: python3 tools/testmgr_hardcoded_tmp_devtest.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PAT = re.compile(r'["\']((?:/tmp/[^"\']*))["\']')
EXTS = {".c", ".pas", ".npy", ".lua", ".h", ".inc", ".py"}
ROOTS = ("test", "lib", "examples")

# Fine as they are, with the reason.
ALLOWED_FILES = {
    "lib/rtl/sysutils.pas":
        "RTL implementation, not a test — it names /tmp as the default temp "
        "directory, which is the thing under test rather than a scratch file",
}
ALLOWED_PATHS = {
    "/tmp/test_nilpy_sqlite_crud.db":
        "PINNED: the recipe names it too, so recipe and source must agree",
    "/tmp/pxx_lua_input.lua":
        "PINNED: same — test/lua/runner.c and the Makefile share the name",
}

KNOWN = {
    # test/cdup.c
    ("test/cdup.c", "/tmp/pxx_dup_probe.txt"),
    # test/cfile_stdio_b87.c
    ("test/cfile_stdio_b87.c", "/tmp/pxx_crtl_file_stdio_b87.txt"),
    # test/cfileops.c
    ("test/cfileops.c", "/tmp/pxx_fops_probe"),
    ("test/cfileops.c", "/tmp/pxx_fops_probe/hard.txt"),
    ("test/cfileops.c", "/tmp/pxx_fops_probe/orig.txt"),
    ("test/cfileops.c", "/tmp/pxx_fops_probe/sym.txt"),
    ("test/cfileops.c", "/tmp/pxx_no_such_dir_zz"),
    # test/cjson/runner.c
    ("test/cjson/runner.c", "/tmp/pxx_cjson_input.json"),
    # test/cposix_io.c
    ("test/cposix_io.c", "/tmp/pxx_cposix_io.txt"),
    # test/crtl_lfs64_aliases_b234.c
    ("test/crtl_lfs64_aliases_b234.c", "/tmp/pxx_crtl_lfs64_b234.tmp"),
    # test/crtl_libc_oracle.c
    ("test/crtl_libc_oracle.c", "/tmp/crtl_stdio_probe.txt"),
    # test/crtl_posix_io_leaf_b238.c
    ("test/crtl_posix_io_leaf_b238.c", "/tmp/pxx_crtl_posix_io_b238.dir"),
    ("test/crtl_posix_io_leaf_b238.c", "/tmp/pxx_crtl_posix_io_b238.tmp"),
    ("test/crtl_posix_io_leaf_b238.c", "/tmp/pxx_no_such_file_b238"),
    # test/crtl_stat_errno_enoent_b235.c
    ("test/crtl_stat_errno_enoent_b235.c", "/tmp/pxx_b235_no_such_dir_zzz/nope.file"),
    # test/csqlite_file_probe.c
    ("test/csqlite_file_probe.c", "/tmp/pxx_sqlite_file_probe.db"),
    # test/cstat_fields.c
    ("test/cstat_fields.c", "/tmp/pxx_stat_probe"),
    ("test/cstat_fields.c", "/tmp/pxx_stat_probe/f.txt"),
    ("test/cstat_fields.c", "/tmp/pxx_stat_probe/h.txt"),
    ("test/cstat_fields.c", "/tmp/pxx_stat_probe/sub"),
    # test/lib_directory.pas
    ("test/lib_directory.pas", "/tmp/pxx_dir_suite"),
    ("test/lib_directory.pas", "/tmp/pxx_dir_suite/alpha.txt"),
    ("test/lib_directory.pas", "/tmp/pxx_dir_suite/child"),
    # test/lib_fpc_surface_2026_08.pas
    ("test/lib_fpc_surface_2026_08.pas", "/tmp/lib_fpcsurf_a.txt"),
    ("test/lib_fpc_surface_2026_08.pas", "/tmp/lib_fpcsurf_b.txt"),
    ("test/lib_fpc_surface_2026_08.pas", "/tmp/lib_fpcsurf_c.txt"),
    ("test/lib_fpc_surface_2026_08.pas", "/tmp/lib_fpcsurf_d.txt"),
    # test/lib_platform.pas
    ("test/lib_platform.pas", "/tmp/pxx_pal_platform.txt"),
    ("test/lib_platform.pas", "/tmp/pxx_pal_platform_dir"),
    ("test/lib_platform.pas", "/tmp/pxx_pal_platform_renamed.txt"),
    # test/lib_platform_esp.pas
    ("test/lib_platform_esp.pas", "/tmp/no-host-fallback"),
    ("test/lib_platform_esp.pas", "/tmp/no-host-fallback-2"),
    ("test/lib_platform_esp.pas", "/tmp/no-host-fallback-dir"),
    # test/lib_textfile.pas
    ("test/lib_textfile.pas", "/tmp/pxx_lib_textfile.txt"),
    # test/lib_textreadchar.pas
    ("test/lib_textreadchar.pas", "/tmp/lib_textreadchar_1.txt"),
    ("test/lib_textreadchar.pas", "/tmp/lib_textreadchar_2.txt"),
    ("test/lib_textreadchar.pas", "/tmp/lib_textreadchar_3.txt"),
    # test/lua/files.lua
    ("test/lua/files.lua", "/tmp/pxx_lua_file_api.txt"),
    # test/test_cross_sysopen_family.pas
    ("test/test_cross_sysopen_family.pas", "/tmp/frankonpiler_sysopen_family.tmp"),
    # test/test_nilpy_bare_genexpr_arguments.npy
    ("test/test_nilpy_bare_genexpr_arguments.npy", "/tmp/pxx_gx_probe.txt"),
    # test/test_nilpy_file_close_readlines.npy
    ("test/test_nilpy_file_close_readlines.npy", "/tmp/pxx_test_close_readlines.txt"),
    # test/test_nilpy_file_read_follows_the_mode.npy
    ("test/test_nilpy_file_read_follows_the_mode.npy", "/tmp/pxx_nilpy_read_mode.txt"),
    # test/test_nilpy_file_write_text.npy
    ("test/test_nilpy_file_write_text.npy", "/tmp/pxx_test_write_append.txt"),
    ("test/test_nilpy_file_write_text.npy", "/tmp/pxx_test_write_text.txt"),
    ("test/test_nilpy_file_write_text.npy", "/tmp/pxx_test_write_text2.txt"),
    ("test/test_nilpy_file_write_text.npy", "/tmp/pxx_test_write_text3.txt"),
    ("test/test_nilpy_file_write_text.npy", "/tmp/pxx_test_write_text5.txt"),
    # test/test_nilpy_file_writelines.npy
    ("test/test_nilpy_file_writelines.npy", "/tmp/pxx_test_writelines.txt"),
    # test/test_nilpy_json_module.npy
    ("test/test_nilpy_json_module.npy", "/tmp/pxx_test_json_module.json"),
    # test/test_nilpy_len_of_a_file_read.npy
    ("test/test_nilpy_len_of_a_file_read.npy", "/tmp/test_nilpy_len_read.txt"),
    # test/test_nilpy_open_one_class_every_mode.npy
    ("test/test_nilpy_open_one_class_every_mode.npy", "/tmp/pxx_test_open_one_class.txt"),
    # test/test_nilpy_os_path_more.npy
    ("test/test_nilpy_os_path_more.npy", "/tmp/pxx_osp_test.txt"),
    # test/test_nilpy_oserror_class_and_message.npy
    ("test/test_nilpy_oserror_class_and_message.npy", "/tmp/b"),
    # test/test_nilpy_typeerror_is_catchable.npy
    ("test/test_nilpy_typeerror_is_catchable.npy", "/tmp/pxx_absent_file_zz.txt"),
    # test/test_nilpy_with_name_reuse.npy
    ("test/test_nilpy_with_name_reuse.npy", "/tmp/pxx_test_with_name_reuse.txt"),
    # test/test_nilpy_with_protocol.npy
    ("test/test_nilpy_with_protocol.npy", "/tmp/test_nilpy_with_protocol.txt"),
    # test/test_nilpy_write_overload_by_arg_type.npy
    ("test/test_nilpy_write_overload_by_arg_type.npy", "/tmp/pxx_test_write_overload.txt"),
    # test/test_sqlite_crud.pas
    ("test/test_sqlite_crud.pas", "/tmp/test_sqlite_crud26.db"),
    # test/test_textfile.pas
    ("test/test_textfile.pas", "/tmp/test_textfile_data26.txt"),
    # test/test_textfile_in_unit.pas
    ("test/test_textfile_in_unit.pas", "/tmp/pxx_textfile_unit_test.txt"),
    # test/test_writeln_text_char.pas
    ("test/test_writeln_text_char.pas", "/tmp/test_writeln_text_char.txt"),
}


def main():
    seen, unlisted = set(), []
    for r in ROOTS:
        for p in sorted((ROOT / r).rglob("*")):
            if p.suffix not in EXTS or not p.is_file():
                continue
            rel = str(p.relative_to(ROOT))
            if rel in ALLOWED_FILES:
                continue
            try:
                text = p.read_text(errors="replace")
            except OSError:
                continue
            for q in sorted(set(PAT.findall(text))):
                if q in ALLOWED_PATHS:
                    continue
                if (rel, q) in KNOWN:
                    seen.add((rel, q))
                else:
                    unlisted.append((rel, q))

    fixed = sorted(KNOWN - seen)
    for rel, q in fixed:
        print("  ok   %s no longer hardcodes %s — remove it from KNOWN" % (rel, q))

    if unlisted:
        print("\nFAIL: new hardcoded /tmp path(s) in compiled test sources. These "
              "are written at RUNTIME, so no Makefile sweep reaches them and "
              "testmgr cannot privatize them — two concurrent runs share the file:")
        for rel, q in unlisted:
            print("  %-52s %s" % (rel, q))
        print("\nRead the directory from the environment instead ($TESTTMP, which "
              "the sweep already exports; default /tmp keeps it byte-identical), "
              "or add it to ALLOWED_PATHS with a reason.")
        return 1

    print("\n  ok   no unlisted hardcoded /tmp path (%d known, %d allowed file(s), "
          "%d allowed path(s))" % (len(KNOWN), len(ALLOWED_FILES), len(ALLOWED_PATHS)))
    if fixed:
        print("  NOTE %d KNOWN entr(y/ies) above are stale — delete them so the "
              "ratchet keeps tightening" % len(fixed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
