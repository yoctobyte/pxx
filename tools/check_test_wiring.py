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


def wired_paths(prov=None, dir_refs=None):
    """Every test/ path mentioned by the Makefile or by a tools/ script.

    One pass over each file, collecting `test/...` tokens. Deliberately textual:
    the question is whether anything REFERENCES the file, and a reference is
    textual regardless of which variable expands around it.

    `dir_refs`, if given, is filled with the tokens that genuinely name a
    DIRECTORY whose whole contents are reached -- see the classifier below.
    consumed_by() uses that set instead of re-deriving one from the token text,
    which is what let a truncated path blanket a directory it never ran.
    """
    seen = set()
    var_dirs = set()
    pat = re.compile(r"test/[A-Za-z0-9_./+-]+")
    # A COMMENT IS NOT WIRING. The scan below is textual on purpose (a
    # reference is a reference regardless of which variable expands around
    # it), but it read a mention inside a comment as a build rule, and the
    # failure direction is the bad one: a commented-out mention makes an
    # orphan look WIRED, so the checker reports nothing and the gap it exists
    # to surface stays invisible. Measured on csqlite_file_probe.c, whose only
    # two mentions in the tree are "same shape as csqlite_file_probe.c" in a
    # Makefile comment and the same sentence in a C comment -- enough to mark
    # it wired, and then to report its (correct) exemption as STALE, which is
    # the same defect twice: once hiding a gap, once inviting someone to
    # delete the exemption that was covering it.
    #
    # APERTURE: full-line comments only -- a line whose first non-blank
    # character is `#`, which covers Makefile comments, `#`-led shell and
    # Python lines, and a `#` comment inside a recipe body. A TRAILING comment
    # is deliberately NOT stripped: `#` is legal inside a recipe's shell
    # quoting, so cutting at one would drop real references, and dropping a
    # real reference is the worse direction here. Prose inside a Python
    # docstring is likewise still counted as a reference.
    #
    # A TOOL MUST NOT BE ITS OWN WITNESS. This file is in tools/ and scans
    # tools/, so its own SKIP_DIRS literal -- `("test/pascal-conformance/",
    # "test/c-conformance/", ...)` -- was collected as a reference and credited
    # those directories. Nothing was lost, because SKIP_DIRS excludes them from
    # the subject list anyway, so the credit was granted to files that were
    # never going to be reported. But the check was reading its own
    # documentation as evidence, and the next path someone writes into a
    # literal here would silently widen the blanket with no rule behind it.
    files = [os.path.join(ROOT, "Makefile")]
    tools = os.path.join(ROOT, "tools")
    for fn in sorted(os.listdir(tools)):
        if fn.endswith((".sh", ".py")) and fn != os.path.basename(__file__):
            files.append(os.path.join(tools, fn))
    for path in files:
        try:
            with open(path, errors="replace") as f:
                text = f.read()
        except OSError:
            continue
        for n, line in enumerate(text.splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            for m in pat.finditer(line):
                tok = m.group(0)
                seen.add(tok)
                if prov is not None:
                    prov.setdefault(tok, []).append(
                        (os.path.relpath(path, ROOT), n))
                if dir_refs is not None:
                    d = classify_dir_ref(tok, line, m.end())
                    if d:
                        dir_refs.add(d)
                    elif tok.endswith("/") and os.path.isdir(
                            os.path.join(ROOT, tok.rstrip("/"))):
                        var_dirs.add((tok.rstrip("/"), path))
    # A path built around a variable -- `$ROOT/test/gui/$name.pas` -- does not
    # blanket its directory (that is the bug this classifier exists to stop),
    # but it is not nothing either: the script that writes it supplies `$name`
    # somewhere, and in every instance in this tree it does so as a bare word
    # (`run_gui_test test_pcl_click`). So credit exactly the files in that
    # directory whose STEM the same file names, and no others. That is what
    # separates the ten test_pcl_* cases gui_suite.sh really runs from the five
    # beside them that it does not -- a distinction the blanket erased in the
    # direction that hides work.
    for d, path in sorted(var_dirs):
        try:
            with open(path, errors="replace") as f:
                text = "\n".join(l for l in f.read().splitlines()
                                 if not l.lstrip().startswith("#"))
        except OSError:
            continue
        for rel in git_ls(d):
            # DIRECT children only. `test/gui/$name.pas` can name a file in
            # test/gui; it cannot reach one in a subdirectory, because the
            # token ends at the variable and `.pas` follows it. Without this,
            # tools/check_test_wiring_devtest.py -- which carries `test/gui/`
            # inside a FIXTURE string and defines its own `def main()` --
            # credited test/gui/helloworld/main.pas on the strength of that
            # `main`. Measured, and it is the same shape as everything else in
            # this file: a mention that describes the check was read as
            # evidence about the tree.
            if os.path.dirname(rel) != d:
                continue
            stem = os.path.splitext(os.path.basename(rel))[0]
            # The lookbehind excludes `/` on purpose: gui_suite.sh names
            # `$ROOT/apps/ide/eliah/main.pas`, and without it that credited
            # test/gui/helloworld/main.pas -- a DIFFERENT file with the same
            # stem, reached through a path component. A bare word is the
            # evidence; a path component naming something else is not.
            if re.search(r"(?<![\w./-])%s(?![\w-])" % re.escape(stem), text):
                seen.add(rel)
                if prov is not None:
                    prov.setdefault(rel, []).append(
                        (os.path.relpath(path, ROOT), 0))
    return seen


def git_ls(d):
    """Tracked paths under a directory, relative to ROOT."""
    out = subprocess.run(["git", "ls-files", d], cwd=ROOT,
                         capture_output=True, text=True)
    return [l for l in out.stdout.splitlines() if l.strip()]


def classify_dir_ref(tok, line, end):
    """Is this token a reference that reaches a whole DIRECTORY's contents?

    `-Futest/case_units` names a directory and never the unit inside it, so
    crediting every file under it is right. The old rule inferred that from the
    token alone -- a `/` and no extension -- and a truncated path satisfies it
    just as well as a real one, because the collector's pattern excludes `$`:

        tools/gui_suite.sh:28   local src="$ROOT/test/gui/$name.pas"

    yields the token `test/gui/`, which rstrips to a directory with no
    extension and blanketed all 26 files under test/gui. The line that caused
    it is the line proving only SOME of them run: five files there were run by
    nothing while the report read zero. The failure is one-directional -- it can
    only ever remove entries from the report, never add one -- which is what
    makes it a false all-clear rather than noise, and a green that is wrong
    waits years where a red is triaged within the hour.

    So the trailing `/` is the tell, and it separates the two cases exactly:

      * `test/fgl`, `test/case_units`, `test/nilpy_units/pkgcorpus` -- the token
        ENDS at the directory name because the text did. A real reference.
      * `test/gui/` -- the token ends at a `/` because the pattern hit something
        it cannot match, i.e. a variable. Truncated; it names a file we cannot
        see, not the directory.

    The one truncation that IS a directory reference is a glob over its
    contents (`for p in test/lua/*.lua`), which does run them all, so a `*`
    immediately after the token keeps the credit.

    Finally the token must actually BE a directory. `test/test_asm_emit_$$t.pas`
    truncates to `test/test_asm_emit_`, which has a `/` and no extension and is
    not a directory at all.
    """
    d = tok.rstrip("/")
    if "/" not in d or os.path.splitext(d)[1]:
        return None
    if d == "test":                      # names everything; never a reference
        return None
    if tok.endswith("/") and line[end:end + 1] != "*":
        return None                      # truncated at a variable, not a dir
    if not os.path.isdir(os.path.join(ROOT, d)):
        return None
    return d


def consumed_by(wired, subject_paths, dir_refs=None):
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
    # 1. directory references, as classified by classify_dir_ref() -- NOT
    #    re-derived from the token text here. Deriving them from "has a slash
    #    and no extension" is what let `test/gui/`, truncated at a shell
    #    variable, blanket 26 files of which five were run by nothing.
    dirs = set(dir_refs or ())
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

    prov = {}
    dir_refs = set()
    wired = wired_paths(prov, dir_refs)
    subs = subjects()
    reached = consumed_by(wired, subs, dir_refs)
    unwired = [p for p in subs
               if p not in wired and p not in reached and p not in exempt]

    # An exemption for a file that IS wired (or no longer exists) is stale, and
    # a stale exemption silently widens the check's blind spot over time.
    #
    # BUT A STALE REPORT INVITES A DELETION, and deleting a CORRECT exemption
    # re-opens the very gap it was covering -- so the claim needs evidence
    # proportional to what acting on it costs. Two strengths, because they are
    # not equally sure:
    #
    #   hard      the file is gone, or the Makefile names it in a live line.
    #             Acting on this is safe.
    #   advisory  the only reference is a tools/ script NAMING the path. That
    #             is not proof anything RUNS it: a devtest that lists test
    #             files as DATA mentions them exactly like a runner that
    #             executes them. Measured -- csqlite_file_probe.c was reported
    #             stale on the strength of a `("test/csqlite_file_probe.c",
    #             "/tmp/...")` tuple in testmgr_hardcoded_tmp_devtest.py, which
    #             asserts about the file's CONTENT and never builds it. Its
    #             exemption is correct and deleting it would have been a real
    #             loss.
    #
    # Deliberately not resolved by a heuristic ("does this script look like it
    # runs the file"): that is a signature list wearing a different hat, it
    # goes stale silently, and the honest move is to hand the reader the
    # citation and let them judge.
    def _mk_backed(path):
        return any(f == "Makefile" for f, _ in prov.get(path, []))

    gone = [p for p in exempt if not os.path.exists(os.path.join(ROOT, p))]
    stale = [p for p in exempt if p in wired and _mk_backed(p)] + gone
    advisory = [p for p in exempt
                if p in wired and p not in stale and not _mk_backed(p)]

    if not unwired and not stale and not advisory:
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
    if advisory:
        print("check-test-wiring: %d exemption(s) whose only reference is a "
              "tools/ script NAMING the path — a mention is not proof anything "
              "runs it, so verify before deleting:" % len(advisory))
        for p in advisory:
            where = ", ".join("%s:%d" % fl for fl in prov.get(p, [])[:3])
            print("  %-46s named by %s" % (p, where))
    return 1 if (unwired or stale) else 0


if __name__ == "__main__":
    sys.exit(main())
