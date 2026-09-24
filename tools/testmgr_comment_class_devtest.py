#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a COMMENT line never makes a job a conformance job.

`classify()` gives the "conformance" class to any job whose text matches
run_<lang>_conformance, and that class is the one generate() REWRITES: every
line gets ` --shard i/N` appended. `make -n` prints a recipe's `@# ...` lines as
`# ...`, so a comment naming tools/run_c_conformance_esp.sh inside test-emit-obj
turned it into six shard jobs whose every pxx line refused with "too many
arguments ... IGNORED: --shard" -- six NEW-RED at 0a101662f25f (2026-09-24),
for a comment.

Cases:
  * positive control: a real run_c_conformance.sh COMMAND still classes
    "conformance" (else the fix would silently unshard the real battery);
  * the regression: the same name in a `#` line, beside ordinary commands,
    does not;
  * an indented comment does not either.

Run: python3 tools/testmgr_comment_class_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tm", os.path.join(HERE, "testmgr.py"))
tm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tm)

failures = 0


def case(name, lines, want_conformance):
    global failures
    got = tm.classify(lines)
    ok = (got == "conformance") == want_conformance
    print("%s %s -> %s" % ("PASS" if ok else "FAIL", name, got))
    if not ok:
        failures += 1


case_real = ["tools/run_c_conformance.sh ./compiler/pascal26 "
             "library_candidates/c-testsuite/tests/single-exec --target riscv32"]
case("a real conformance command", case_real, True)
case("the same name in a comment line",
     ["# The values are proven by booting:",
      "# tools/run_c_conformance_esp.sh --chip esp32s3.",
      "./compiler/pascal26 --target=xtensa --emit-obj test/x.c /tmp/x.o"], False)
case("an indented comment",
     ["   # see tools/run_pascal_conformance.sh",
      "nm /tmp/x.o | grep -q ' T main$'"], False)

if failures:
    print("\nFAIL testmgr_comment_class_devtest (%d failure(s))" % failures)
    sys.exit(1)
print("\nOK testmgr_comment_class_devtest")
