#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a type alias COPIED out of lib/rtl must still agree with its original.

feature-t-a-type-alias-copied-from-the-rtl-can-drift-and-nothing-reports-it.

`lib/rtl/typinfo.pas` moved `TRttiStr = string[255]` to `string[256]` on
2026-09-04 — deliberately, with a comment predicting the exact symptom if it
were not moved, because `string[N<=255]` was about to become the byte-prefixed
tyShortString. `test/test_rtti_reg.pas` held a duplicate `TRttiStr` and was not
moved with it, so a byte-prefix reader was pointed at a word-prefixed blob.

THE COPY IS NOT WRONG WHEN IT IS MADE — it is identical. It becomes wrong when
the original moves, and the move is usually the correct act. So no instrument
that looks at either file alone can see it: the compiler sees two well-formed
declarations of the same name in different units, which is legal and often
intended, and a grep run before the migration reports agreement.

WHY THIS IS THE ANNOTATION AND NOT A CENSUS. The ticket lists a second option —
enumerate every `X = <type expr>` in test/ and report pairs whose right-hand
sides differ from an `lib/rtl` declaration of the same name — and warns not to
start with it alone. MEASURED 2026-09-04 by frankZ, and the warning is right by
a wide margin: 33 type names are declared in both `lib/rtl/**` and a
`test/*.pas`, and 26 of those carry a spelling that matches no RTL spelling.
Essentially all 26 are DELIBERATE. `test_typename_alias_wins_b304.pas` exists
to redeclare `TDateTime`, `Currency`, `ValReal`, `Comp`, `WideChar` and
`SizeInt` as different types and check the source wins;
`test_builtin_pointer_types_b303.pas` does the same for `PWord` and `PInteger`;
the rest are single-letter locals (`S`, `I`, `X`) that collide by accident. A
census guard would print ~26 findings, all fine, on every run — which is how a
check earns the habit of being scrolled past, and the one real pair would be
inside it.

So the population is OPT-IN and tiny, and the annotation is written at the
moment someone copies, which is the moment they know:

    TRttiStr = string[256];   { COPY-OF lib/rtl/typinfo.pas TRttiStr }

A MARKER THAT RESOLVES TO NOTHING IS A FAILURE, NOT A PASS. If the named file
or the named declaration is gone, this reports it rather than skipping — a
guard whose population can silently empty out is the failure this repo keeps
paying for, and a renamed RTL type is exactly how that would happen.

Run: python3 tools/rtl_alias_copy_devtest.py
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MARKER = re.compile(r"\{\s*COPY-OF\s+(\S+)\s+([A-Za-z_]\w*)\s*\}")
fails = []


def check(cond, what, detail=""):
    if callable(cond):
        try:
            cond = cond()
        except Exception as e:                                      # noqa: BLE001
            cond, detail = False, "RAISED %s: %s" % (type(e).__name__, e)
    print("  %-4s %-58s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


def strip_comments(line):
    """Drop a trailing `{...}` / `//` comment. The marker itself lives in one,
    so this runs only on the ORIGINAL's line, never on the annotated copy."""
    return line.split("{")[0].split("//")[0]


def declaration_of(path, name):
    """The right-hand side of `name = <rhs>;`, normalised on whitespace.

    Returns None when the file or the declaration is absent — the caller treats
    that as a failure, which is the point: a marker pointing at a name that no
    longer exists is drift of the loudest kind."""
    f = ROOT / path
    if not f.exists():
        return None
    pat = re.compile(r"^\s*%s\s*=\s*([^;]+);" % re.escape(name), re.IGNORECASE)
    for line in f.read_text(errors="replace").splitlines():
        m = pat.match(strip_comments(line))
        if m:
            return " ".join(m.group(1).split())
    return None


def copies():
    """Every annotated copy in the tree, as (file, lineno, target, name, rhs)."""
    out = []
    for sub in ("test", "examples", "lib", "compiler", "tools"):
        base = ROOT / sub
        if not base.is_dir():
            continue
        for f in sorted(base.rglob("*.pas")) + sorted(base.rglob("*.inc")):
            try:
                lines = f.read_text(errors="replace").splitlines()
            except OSError:
                continue
            for i, line in enumerate(lines, 1):
                m = MARKER.search(line)
                if not m:
                    continue
                rel = f.relative_to(ROOT).as_posix()
                decl = re.match(r"^\s*%s\s*=\s*([^;]+);" % re.escape(m.group(2)),
                                strip_comments(line), re.IGNORECASE)
                out.append((rel, i, m.group(1), m.group(2),
                            " ".join(decl.group(1).split()) if decl else None))
    return out


def main():
    found = copies()

    print("1. every COPY-OF marker resolves, and the two declarations agree")
    # Non-vacuity first: a run over an empty population passes every row below
    # and means nothing.  The floor is 1 because the known instance is 1 -- it
    # is a collapse detector for the marker convention, not a ratchet on how
    # many copies exist.
    check(len(found) >= 1,
          "the annotated population is not empty",
          "%d marker(s): %s" % (len(found),
                                ", ".join("%s:%d" % (f, n) for f, n, _, _, _ in found)))

    for path, line, target, name, mine in found:
        theirs = declaration_of(target, name)
        where = "%s:%d %s" % (path, line, name)
        check(mine is not None,
              "the marked line declares %s" % name,
              where if mine is not None else
              "%s — a COPY-OF marker belongs ON the declaration line, "
              "not above it" % where)
        check(theirs is not None,
              "%s still exists in %s" % (name, target),
              "%s" % where)
        if mine is not None and theirs is not None:
            check(mine.lower() == theirs.lower(),
                  "and the two spellings agree",
                  "%s: copy `%s` vs %s `%s`" % (where, mine, target, theirs))

    print("2. the comparison discriminates — the 2026-09-04 drift is recognised")
    # POSITIVE CONTROL DRAWN FROM THIS POPULATION, as the ticket requires: the
    # real pair, with the copy put back to the value it actually held while the
    # bug was live.  A guard nobody proved can fail is the failure this file is
    # about.
    live = declaration_of("lib/rtl/typinfo.pas", "TRttiStr")
    check(live is not None,
          "the original is readable", "lib/rtl/typinfo.pas TRttiStr = %s" % live)
    check(live is not None and live.lower() != "string[255]",
          "and it is not the pre-migration spelling",
          "would-have-been-red pairing: copy `string[255]` vs original `%s`" % live)
    check(live is not None and live.lower() == "string[256]",
          "it is string[256], the migrated value the copy must track",
          "N<=255 selects the BYTE-prefixed tyShortString; RTTI names are "
          "word-prefixed. Do not tidy this back to 255")

    print("\n  %d guard(s), %d FAIL" % (5 + 3 * len(found), len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
