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
