#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""check_test_wiring.py — a file in test/ is not a test until a rule runs it.

Writing a test and confirming it passes are both true, and neither makes it
covered. The only fact that establishes "this is gated" is a build rule
referencing the file — and `test-core` / `test-nilpy` both ENUMERATE their
tests rather than globbing, so a new file is gated only if someone also edited
the Makefile. Two confirmed cases landed with a passing test and no rule; one
sat ungated for two weeks with a `Gate:` line and an `.expected` beside it.

Both were caught by eye. This converts the class from "someone notices" to
"the check notices" (feature-t-fail-when-a-test-file-is-wired-into-no-build-rule).

WHAT COUNTS AS WIRED: the file's path appears in the Makefile, or in a script
under tools/ that a Makefile rule invokes. The second is why a bare grep of the
Makefile is not enough — whole suites (conformance batteries, the corpus
runners) are driven by a script that enumerates its own inputs.

EXEMPTIONS live in test/UNWIRED.txt, one `<path>  <reason>` per line. An
exemption without a reason is refused: an unexplained exemption is the same
invisible-work problem one level down, and this checker exists to remove exactly
that.

Exit 0 = every test file is wired or explained; 1 = at least one is neither.
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXEMPT = os.path.join(ROOT, "test", "UNWIRED.txt")

# Extensions that are SUBJECTS of a test run. `.expected` is deliberately not
# here: it is an assertion belonging to a subject, and it is checked through its
# sibling instead, so a missing pair reports once rather than twice.
SUBJECT_EXT = (".pas", ".npy", ".c", ".lua", ".fth")

# Directories under test/ that are inputs to a suite rather than test subjects:
# a conformance corpus enumerates its own members, and a fixture is data.
SKIP_DIRS = ("test/pascal-conformance/", "test/c-conformance/", "test/fixtures/",
             "test/cjson/", "test/quickjs/", "test/lua/", "test/nilpy-stack/")


def read_exemptions():
    """{path: reason}. A line with no reason is fatal, not ignored."""
    out, bad = {}, []
    if not os.path.exists(EXEMPT):
        return out, bad
    with open(EXEMPT) as f:
        for n, line in enumerate(f, 1):
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            parts = line.split(None, 1)
            if len(parts) < 2 or not parts[1].strip():
                bad.append((n, parts[0] if parts else line))
                continue
            out[parts[0]] = parts[1].strip()
    return out, bad


def wired_paths():
    """Every test/ path mentioned by the Makefile or by a tools/ script.

    One pass over each file, collecting `test/...` tokens. Deliberately textual:
    the question is whether anything REFERENCES the file, and a reference is
    textual regardless of which variable expands around it.
    """
    seen = set()
    pat = re.compile(r"test/[A-Za-z0-9_./+-]+")
    files = [os.path.join(ROOT, "Makefile")]
    tools = os.path.join(ROOT, "tools")
    for fn in sorted(os.listdir(tools)):
        if fn.endswith((".sh", ".py")):
            files.append(os.path.join(tools, fn))
    for path in files:
        try:
            with open(path, errors="replace") as f:
                text = f.read()
        except OSError:
            continue
        seen.update(pat.findall(text))
    return seen


def consumed_by(wired, subject_paths):
    """Paths reached INDIRECTLY from something already wired.

    A bare "is this path in the Makefile" test has two large false-positive
    classes, and both are real wiring rather than gaps:

      * a helper compiled through a DIRECTORY reference -- `-Futest/case_units`
        names the dir, never `uPSUtils.pas`;
      * a unit or header pulled in by a wired test's own `uses` / `#include`
        -- `cenum_lib.c` is exercised by the test that includes it.

    Both are "something runs it", which is the question. Reporting them would
    train people to ignore the check, which costs more than the gaps it finds.
    """
    reached = set()
    # 1. directory references: any test/ subdir named anywhere counts for its
    #    contents. `test/` itself is excluded -- it names everything.
    dirs = {w.rstrip("/") for w in wired
            if w.count("/") >= 1 and not os.path.splitext(w)[1]}
    dirs.discard("test")
    for p in subject_paths:
        d = os.path.dirname(p)
        while d and d != "test":
            if d in dirs:
                reached.add(p)
                break
            d = os.path.dirname(d)
    # 2. imports from a wired subject: uses <name> / #include "<name>"
    stem = {}
    for p in subject_paths:
        stem.setdefault(os.path.splitext(os.path.basename(p))[0].lower(), []).append(p)
    uses_re = re.compile(r"^\s*uses\s+([^;]+);", re.I | re.M)
    inc_re = re.compile(r'#\s*include\s+"([^"]+)"')
    # NilPy imports a sibling .npy as a MODULE, so the reference is a bare
    # identifier with no path and no extension -- nothing the other two patterns
    # can see. Missed on the first cut, and it surfaced exactly as predicted: a
    # legitimate helper (test_nilpy_file_dunder_helper.npy, imported by
    # test_nilpy_file_dunder.npy) sitting in the report, which is how a list
    # becomes something people skim.
    py_re = re.compile(r"^\s*(?:import\s+([\w.]+)|from\s+([\w.]+)\s+import)",
                       re.M)
    for p in subject_paths:
        if p not in wired and p not in reached:
            continue                     # only follow from something wired
        try:
            with open(os.path.join(ROOT, p), errors="replace") as f:
                text = f.read()
        except OSError:
            continue
        names = []
        for m in uses_re.findall(text):
            names += [n.strip().lower() for n in m.split(",")]
        names += [os.path.splitext(os.path.basename(i))[0].lower()
                  for i in inc_re.findall(text)]
        for a, b in py_re.findall(text):
            # last dotted component; stdlib names simply match no test file
            names.append((a or b).split(".")[-1].lower())
        for n in names:
            for q in stem.get(n, ()):
                reached.add(q)
    return reached


def subjects():
    """Test subjects, git-tracked only.

    Tracked-only on purpose: an untracked file in test/ is somebody's scratch,
    and failing a shared check on it would make the check something people
    learn to bypass.
    """
    out = subprocess.run(["git", "ls-files", "test/"], cwd=ROOT,
                         capture_output=True, text=True).stdout.split()
    keep = []
    for p in out:
        if not p.endswith(SUBJECT_EXT):
            continue
        if any(p.startswith(d) for d in SKIP_DIRS):
            continue
        keep.append(p)
    return sorted(keep)


def main():
    exempt, bad = read_exemptions()
    if bad:
        print("check-test-wiring: %s has %d entr(y/ies) with no REASON:"
              % (os.path.relpath(EXEMPT, ROOT), len(bad)))
        for n, p in bad:
            print("  line %d: %s" % (n, p))
        print("  An exemption without a reason is the invisible-work problem "
              "this check exists to remove. Give each one a reason.")
        return 1

    wired = wired_paths()
    subs = subjects()
    reached = consumed_by(wired, subs)
    unwired = [p for p in subs
               if p not in wired and p not in reached and p not in exempt]

    # An exemption for a file that IS wired (or no longer exists) is stale, and
    # a stale exemption silently widens the check's blind spot over time.
    stale = [p for p in exempt
             if p in wired or not os.path.exists(os.path.join(ROOT, p))]

    if not unwired and not stale:
        print("check-test-wiring: OK — %d test subject(s), all referenced by a "
              "rule or explained in %s"
              % (len(subjects()), os.path.relpath(EXEMPT, ROOT)))
        return 0

    if unwired:
        print("check-test-wiring: %d test file(s) NOT referenced by any build "
              "rule or tools/ script — they exist, and nothing runs them:"
              % len(unwired))
        for p in unwired:
            print("  %s" % p)
        print("  Wire each into a rule, or add it to %s with a reason."
              % os.path.relpath(EXEMPT, ROOT))
    if stale:
        print("check-test-wiring: %d STALE exemption(s) — wired or gone, so the "
              "entry now only hides future gaps:" % len(stale))
        for p in stale:
            print("  %s" % p)
    return 1


if __name__ == "__main__":
    sys.exit(main())
