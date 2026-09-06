#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest for testmgr's corpus self-skip (CORPUS_RE / CORPUS_GUARD_RE).

Two defects, both from bug-t-corpus-regex-invents-phantom-tree:

1. The old pattern `library_candidates/([^/\\s"']+)` accepted punctuation, so it
   matched the prose inside a shell SKIP message and invented the corpus name
   `stb)`. `library_candidates/stb)` can never be a directory, so the job
   self-skipped on EVERY host — fetched or not — and the fix the warning
   printed (`install_lib_candidates.sh stb)`) was itself rejected as an unknown
   candidate.

2. A recipe line that guards its own corpus use still contributed to the
   job-level skip decision, so one absent corpus took unrelated tests down with
   it: the stb probe shares a job with cswitch_noncompound_duff_b207.c, the
   non-compound switch + Duff's device regression, which has no corpus
   dependency whatsoever.

Both are silent in a green verdict, because a skipped job is published as
"pass" — which is why they want a test rather than an eyeball.

Reads the repo's real Makefile for the phantom case (the recipe that provoked
it is still there); no repo state touched. Run:
    python3 tools/testmgr_corpus_skip_devtest.py
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import testmgr  # noqa: E402

REPO = pathlib.Path(testmgr.REPO)

# The line that produced the phantom, verbatim in shape.
SKIP_MSG_LINE = ('\t@if [ -f library_candidates/stb/stb_sprintf.h ]; then '
                 './pascal26 -Ilibrary_candidates/stb test/gamelib/stb_sprintf_probe.c '
                 '/tmp/stb_sprintf_probe26; '
                 'else echo "stb_sprintf_probe: SKIP (no library_candidates/stb)"; fi')
PLAIN_USE_LINE = ('\t./pascal26 -Ilibrary_candidates/quickjs '
                  'library_candidates/quickjs/quickjs.c /tmp/qjs26')
# The SECOND phantom, and the reason this file grew a third case: the same
# defect one character narrower. Verbatim in shape from `make -n test-zlib`,
# where `$(ZLIB_SRC)` has already been expanded -- which is the whole reason
# case_real_makefile_yields_only_real_trees below could not see it. That case
# reads the Makefile SOURCE, where this line still says `$(ZLIB_SRC).`, so the
# string `library_candidates/zlib.` never appears in the population it scans.
# A control drawn from the wrong population passes and certifies the broken
# instrument; this line is drawn from the right one.
PROSE_PERIOD_LINE = ("\t: '  other zlib header still resolves out of "
                     "library_candidates/zlib.'; \\")


def corpora(*lines):
    """What the skip scan would charge a job carrying these lines with."""
    unguarded = "\n".join(ln for ln in lines
                          if not testmgr.CORPUS_GUARD_RE.search(ln))
    return sorted(set(testmgr.CORPUS_RE.findall(unguarded)))


def case_no_phantom_from_prose():
    """The regex alone must not invent a name out of a SKIP message."""
    found = testmgr.CORPUS_RE.findall(SKIP_MSG_LINE)
    bad = [m for m in found if not m.replace("-", "").replace(".", "")
           .replace("_", "").replace("+", "").isalnum()]
    assert not bad, f"punctuation leaked into corpus names: {bad}"
    assert "stb)" not in found, "the 'stb)' phantom is back"
    return f"names from the SKIP line: {sorted(set(found))}"


def case_real_makefile_yields_only_real_trees():
    """Against the actual Makefile: every extracted name must be a plausible
    directory name, and the known phantom must be gone."""
    text = (REPO / "Makefile").read_text(encoding="utf-8", errors="replace")
    names = sorted(set(testmgr.CORPUS_RE.findall(text)))
    assert names, "no corpora found at all — pattern over-tightened?"
    bad = [n for n in names if any(c in n for c in "()[]{};\"'`$")]
    assert not bad, f"phantom corpus names from Makefile prose: {bad}"
    return f"{len(names)} corpora, none phantom"


def case_trailing_period_is_not_part_of_the_name():
    """A sentence-ending full stop after a corpus path is PROSE, not a name.

    Measured on seven, 2026-09-06: the tier at 18:02Z ran test-zlib (skips 6,
    holes 1); the tier at 18:37Z skipped it as
    `corpus absent: library_candidates/zlib.` (skips 7, holes 2). Between them,
    at 18:20Z, 2523453c4 added a shell-comment line ending in `$(ZLIB_SRC).` --
    a commit whose entire purpose was to make this row measurable. The corpus
    had been present on that box since 2026-08-29 and was present throughout.

    So the failure this guards is not "a corpus is missing" but "a job stops
    running and says something true-sounding about why", on the row that backs
    a public claim ("zlib matches the gcc oracle"). It is invisible in a green
    verdict, because a skipped job publishes as pass."""
    found = testmgr.CORPUS_RE.findall(PROSE_PERIOD_LINE)
    assert "zlib." not in found, (
        "a trailing full stop is still captured as part of the corpus name — "
        "`library_candidates/zlib.` can never be a directory, so the job "
        "self-skips on every host, fetched or not")
    assert found == ["zlib"], found
    assert corpora(PROSE_PERIOD_LINE) == ["zlib"], corpora(PROSE_PERIOD_LINE)
    return "prose full stop does not enter the name"


def case_a_dot_inside_a_name_survives():
    """...and the fix must not become the opposite defect. Only a TRAILING dot
    is prose; the character class has always admitted one inside a name, and
    narrowing that would invent a fresh phantom the day a corpus is fetched
    into a directory with a version in it.

    SAYS SO OUT LOUD: this case passes under the PRE-FIX regex too, measured.
    It is not a regression control and must not be counted as one -- it guards
    the fix from being over-applied, which is a direction only a FUTURE change
    can break. The regression control for the trailing dot is the case above,
    which does fail without the fix."""
    line = "\t./pascal26 -Ilibrary_candidates/lua5.4 /tmp/x26"
    assert testmgr.CORPUS_RE.findall(line) == ["lua5.4"], (
        testmgr.CORPUS_RE.findall(line))
    return "an interior dot is still part of the name"


def case_self_guarded_line_does_not_skip_the_job():
    """The blast-radius half: a guarded probe must not take its jobmates with
    it. The recipe already handles the absence itself."""
    assert corpora(SKIP_MSG_LINE) == [], (
        "a self-guarded corpus line still charges the job with a corpus — "
        "an unrelated regression test in the same job would never run")
    return "guarded line contributes no corpus"


def case_unguarded_line_still_skips():
    """...and the guard exemption must not disarm the mechanism it lives in:
    an UNguarded corpus use still self-skips, which is the whole contract with
    twatch-setup."""
    assert corpora(PLAIN_USE_LINE) == ["quickjs"], corpora(PLAIN_USE_LINE)
    assert corpora(SKIP_MSG_LINE, PLAIN_USE_LINE) == ["quickjs"], (
        "mixed job: the unguarded corpus must still register")
    return "unguarded use still registers quickjs"


CASES = [
    case_no_phantom_from_prose,
    case_trailing_period_is_not_part_of_the_name,
    case_a_dot_inside_a_name_survives,
    case_real_makefile_yields_only_real_trees,
    case_self_guarded_line_does_not_skip_the_job,
    case_unguarded_line_still_skips,
]


def main():
    rc = 0
    for case in CASES:
        name = case.__name__.removeprefix("case_").replace("_", "-")
        try:
            note = case()
        except AssertionError as e:
            print(f"  FAIL {name}: {e}")
            rc = 1
        else:
            print(f"  ok   {name} — {note}")
    print("corpus self-skip OK" if rc == 0 else "corpus self-skip BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
