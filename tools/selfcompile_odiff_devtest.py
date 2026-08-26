#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a comparison must state that its reference exists.

`tools/selfcompile_odiff.sh` builds the compiler at every -O level and diffs
what the results EMIT. It replaces a bench-harness loop that had the purest
instance of the asserts-nothing family in this repo:

    ref_out = None
    ...
    if lvl == "-O0": ref_out = out
    if out is None or ref_out is None or out != ref_out:
        print("CANARY-DIFF vs -O0")

When the -O0 BUILD failed, `ref_out` stayed None and every other level reported
a difference from a baseline that was never produced. **One defect, three red
rows**, and nothing in the output separated *the levels disagree* — an optimizer
bug — from *there was nothing to compare against*. A diff against a missing
operand.

So the script names four states apart, and this drives all of them with fake
compilers, because on a healthy tree only one of them ever executes and a branch
that has never run is not yet known to work:

    BUILD-FAIL    this level's compiler did not build
    NO-BASELINE   the baseline emitted nothing; this level was NOT compared
    EMIT-FAIL     this level's compiler could not compile the input
    DIFF          the levels genuinely disagree  <- the only optimizer finding

Also pinned: when -O0 fails, the remaining levels are still compared against
each other. The old loop threw that away with the baseline, and "do -O1/-O2/-O3
agree" is a real optimizer signal that survives -O0 being broken.

And: LOWER -O levels emit MORE code, so -O0 is where a size ceiling bites first.
Nothing here may assume -O0 is the easy case.

Run: tools/selfcompile_odiff_devtest.py   (exit 0 = pass)
"""
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "selfcompile_odiff.sh")

FAILS = []


def has_diff_finding(out):
    """Is there an actual DIFF *finding line*, as opposed to the word 'DIFF'?

    The RED summary reads "only DIFF is an optimizer finding", so a bare
    substring test matches the script explaining itself. Asserting on the
    finding line is the whole point — checking for the word was a check about
    the wrong subject, which is the family this script exists to leave.
    """
    return any(ln.strip().startswith("DIFF ") for ln in out.splitlines())


def check(name, cond, detail=""):
    if cond:
        print("  ok   %s" % name)
    else:
        print("  RED  %s" % name)
        FAILS.append("%s\n      %s" % (name, detail))


def fake_compiler(d, behaviour):
    """A stand-in compiler. `behaviour` maps a -O level to what it should do:

        "ok"        build a stage that emits identical bytes
        "buildfail" fail when asked to build compiler.pas
        "emitfail"  build fine, but the stage fails on any input
        "differ"    build fine, and the stage emits DIFFERENT bytes

    Written with str.replace rather than %-formatting on purpose: the generated
    shell is full of printf format specifiers, and interpolating it was the
    first draft's bug.
    """
    beh_path = os.path.join(d, "behaviour")
    body = r"""#!/usr/bin/env bash
# $1 = -O level, $2 = source, $3 = output
lvl="$1"; src="$2"; out="$3"
beh=$(awk -v l="$lvl" '$1==l{print $2}' @BEH@)
[ -z "$beh" ] && beh=ok
case "$src" in
  *compiler.pas)
      if [ "$beh" = buildfail ]; then echo "code section too large"; exit 1; fi
      {
        echo '#!/usr/bin/env bash'
        echo "beh=$beh"
        echo "lvl=$lvl"
        echo 'out="$2"'
        echo 'if [ "$beh" = emitfail ]; then echo "stage cannot compile that"; exit 1; fi'
        echo 'if [ "$beh" = differ ]; then echo "BYTES-$lvl" > "$out"; else echo "BYTES-SAME" > "$out"; fi'
      } > "$out"
      chmod +x "$out"
      exit 0 ;;
esac
exit 0
""".replace("@BEH@", beh_path)
    p = os.path.join(d, "fakecc")
    with open(p, "w") as f:
        f.write(body)
    os.chmod(p, 0o755)
    with open(beh_path, "w") as f:
        for lvl, b in behaviour.items():
            f.write(lvl + " " + b + "\n")
    return p


def run(behaviour, levels="-O0 -O1 -O2"):
    d = tempfile.mkdtemp(prefix="odiff-devtest-")
    cc = fake_compiler(d, behaviour)
    env = dict(os.environ, PXX_ODIFF_CC=cc, PXX_ODIFF_LEVELS=levels)
    r = subprocess.run(["bash", SCRIPT], env=env, capture_output=True,
                       text=True, timeout=120, cwd=os.path.dirname(HERE))
    return r.returncode, r.stdout + r.stderr


def main():
    print("odiff: a comparison must state that its reference exists")

    # 1. All levels agree — the only green.
    rc, out = run({})
    check("all levels agreeing is GREEN", rc == 0 and "GREEN" in out, out)
    check("...and says nothing about DIFF", not has_diff_finding(out), out)

    # 2. THE FOUNDING BUG: baseline fails to build.
    rc, out = run({"-O0": "buildfail"})
    check("a failed baseline build reports BUILD-FAIL",
          "BUILD-FAIL -O0" in out or "BUILD-FAIL  -O0" in out, out)
    check("...and does NOT report the other levels as DIFF",
          not has_diff_finding(out),
          "this is the three-red-rows-one-defect bug: levels reported a "
          "difference from a baseline that was never produced:\n%s" % out)
    check("...and still compares the surviving levels to each other",
          "same" in out,
          "'do -O1 and -O2 agree' is a real optimizer signal that survives -O0 "
          "being broken; the old loop threw it away with the baseline:\n%s" % out)
    check("...and says which level became the baseline",
          "baseline is -O1" in out,
          "a silently substituted baseline is a comparison whose subject the "
          "reader cannot see:\n%s" % out)
    check("a failed build is still RED overall", rc != 0, "rc=%d" % rc)

    # 3. A genuine disagreement — the only optimizer finding.
    rc, out = run({"-O2": "differ"})
    check("levels that disagree report DIFF", has_diff_finding(out), out)
    check("...and name it as the optimizer changing what it emits",
          "changed what it emits" in out, out)
    check("a real diff is RED", rc != 0, "rc=%d" % rc)

    # 4. A stage that builds but cannot compile: not a diff.
    rc, out = run({"-O1": "emitfail"})
    check("a stage that cannot compile reports EMIT-FAIL, not DIFF",
          "EMIT-FAIL" in out and not has_diff_finding(out), out)

    # 5. Every level failing to build: a build failure, not an optimizer finding.
    rc, out = run({"-O0": "buildfail", "-O1": "buildfail", "-O2": "buildfail"})
    check("no level building says so plainly", "NO LEVEL BUILT" in out, out)
    check("...and calls it a build failure, not an optimizer finding",
          "not" in out and "optimizer finding" in out, out)
    check("...and does not emit DIFF", not has_diff_finding(out), out)

    # 6. The summary must say which line is the actionable one.
    rc, out = run({"-O2": "differ"})
    check("the RED summary points at DIFF as the only optimizer finding",
          "only DIFF is an optimizer finding" in out, out)

    if FAILS:
        print("\nselfcompile_odiff_devtest: %d RED" % len(FAILS))
        for f in FAILS:
            print("  - %s" % f)
        return 1
    print("selfcompile_odiff_devtest: all green")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001
        print(fail_detail(e))
        sys.exit(1)
