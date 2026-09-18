#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: an ESP suite on a box without Espressif's qemu fork SKIPS, loudly.

The ESP recipes guard every row inline -- `if [ -z "$QEMU" ]; then echo "...
not installed; ... skipped"; else ...` -- and exit 0. So a tier that enrolled
them on a box without the fork would publish a GREEN for ~30 assertions that
never ran. apply_esp_skips() turns that into a hole-counted skip with the
command that closes it. bug-t-the-esp-bare-suite-is-in-no-tier-so-nothing-ever-runs-it

Guards, both directions:
  1. the ESP suites are ENROLLED (full for bare+softfloat, slow for idf) --
     a skip guard for targets in no tier guards nothing.
  2. a fake HOME with both forks and ESP-IDF: nothing is missing, nothing skips.
  3. an empty HOME: every ESP job skips, the reason is a hole prefix and names
     tools/install_esp32_target.sh; a non-ESP job is untouched.
  4. ONE fork present: the whole target still skips (half the rows would pass
     silently otherwise), naming only the absent fork.
  5. ESP-IDF absent but both forks present: only test-esp-idf skips.
  6. an already-skipped job keeps its first reason.
  7. the globs are the ones tools/esp_run_bare.sh resolves, verbatim -- if the
     script moves its lookup this guard would probe a path nothing uses and
     pass every job forever.
  8. twatch's fingerprint (ESP_SYSTEM_EMULATORS) probes the same globs, so the
     archive answers about the binary the rows actually need.

Run: python3 tools/testmgr_esp_skip_devtest.py
"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import testmgr as tm  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
fails = []


def check(cond, what, detail=""):
    print("  %-4s %-60s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


def fake_home(forks=("riscv32", "xtensa"), idf=True):
    h = tempfile.mkdtemp(prefix="esp-skip-devtest-")
    for arch in forks:
        d = os.path.join(h, ".espressif/tools/qemu-%s/esp_develop_x/qemu/bin" % arch)
        os.makedirs(d)
        exe = os.path.join(d, "qemu-system-%s" % arch)
        with open(exe, "w") as fh:
            fh.write("#!/bin/sh\n")
        os.chmod(exe, 0o755)
    if idf:
        os.makedirs(os.path.join(h, "esp/esp-idf"))
        open(os.path.join(h, "esp/esp-idf/export.sh"), "w").close()
    return h


def jobs():
    out = []
    for tgt in ("test-esp-bare", "test-esp-softfloat", "test-esp-idf",
                "test-xtensa"):
        j = tm.Job(tgt, 0, ["true"])
        out.append(j)
    return out


def by_target(js):
    return {j.target: j for j in js}


def main():
    print("1. the ESP suites are enrolled")
    check("test-esp-bare" in tm.TIERS["full"], "test-esp-bare is in full")
    check("test-esp-softfloat" in tm.TIERS["full"], "test-esp-softfloat is in full")
    check("test-esp-idf" in tm.TIERS["slow"], "test-esp-idf is in slow")

    print("2. everything present: nothing skips")
    m = tm.missing_esp_prereqs(fake_home())
    check(m == {"qemu": [], "idf": []}, "nothing reported missing", repr(m))
    js = jobs()
    check(tm.apply_esp_skips(js, m) == 0, "zero jobs skipped")
    check(all(j.status != "skip" for j in js), "every job still runnable")

    print("3. nothing present: every ESP job skips, with a hole reason")
    m = tm.missing_esp_prereqs(fake_home(forks=(), idf=False))
    js = jobs()
    n = tm.apply_esp_skips(js, m)
    t = by_target(js)
    check(n == 3, "three ESP jobs skipped", "n=%d" % n)
    for tgt in ("test-esp-bare", "test-esp-softfloat", "test-esp-idf"):
        r = t[tgt].skip_reason or ""
        check(t[tgt].status == "skip" and r.startswith(tm.SKIP_HOLE_PREFIXES),
              "%s skipped as a hole" % tgt)
        check(tm.ESP_INSTALL_HINT in r, "%s names the installer" % tgt)
    check(t["test-xtensa"].status != "skip", "test-xtensa untouched")

    print("4. one fork present: the target still skips, naming the other")
    m = tm.missing_esp_prereqs(fake_home(forks=("riscv32",)))
    js = jobs()
    tm.apply_esp_skips(js, m)
    r = by_target(js)["test-esp-bare"].skip_reason or ""
    check(by_target(js)["test-esp-bare"].status == "skip", "test-esp-bare skipped")
    check("qemu-system-xtensa" in r and "qemu-system-riscv32" not in r,
          "reason names only the absent fork", r[:70])

    print("5. forks present, ESP-IDF absent: only test-esp-idf skips")
    m = tm.missing_esp_prereqs(fake_home(idf=False))
    js = jobs()
    tm.apply_esp_skips(js, m)
    t = by_target(js)
    check(t["test-esp-idf"].status == "skip", "test-esp-idf skipped")
    check(t["test-esp-bare"].status != "skip"
          and t["test-esp-softfloat"].status != "skip", "bare suites still run")

    print("6. an earlier skip reason survives")
    js = jobs()
    js[0].status, js[0].skip_reason = "skip", "corpus absent: first"
    tm.apply_esp_skips(js, tm.missing_esp_prereqs(fake_home(forks=(), idf=False)))
    check(js[0].skip_reason == "corpus absent: first", "first reason kept")

    print("7. the globs are esp_run_bare.sh's own")
    src = open(os.path.join(ROOT, "tools/esp_run_bare.sh")).read()
    for name, pat in tm.ESPRESSIF_QEMU:
        # the script spells $HOME inside double quotes: "$HOME"/.espressif/...
        want = pat.replace("$HOME/", '"$HOME"/')
        check(want in src, "%s glob present in esp_run_bare.sh" % name)

    print("8. twatch fingerprints the same emulators")
    import twatch  # noqa: E402
    check([p for _, p in twatch.ESP_SYSTEM_EMULATORS]
          == [p for _, p in tm.ESPRESSIF_QEMU],
          "twatch.ESP_SYSTEM_EMULATORS globs == testmgr.ESPRESSIF_QEMU")

    print("\n%s testmgr_esp_skip_devtest (%d failure(s))"
          % ("PASS" if not fails else "FAIL", len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
