#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""ghost_names — routine names that comments still cite and the code no longer has.

WHY THIS EXISTS. On 2026-09-06 frankD renamed `ArgListHasBracketElem` to
`ArgListBracketElemMask` (it had to return a slot rather than a Boolean),
updated the call site and the function's own header, and missed two sibling
comments 190 lines up. Their statement of the gap is the specification for this
tool:

    A comment naming a function that does not exist is invisible to every check
    we run, and the cost lands on the next person rather than on the author.

Not the build, not `gate.sh`, not a reviewer reading a diff -- the diff shows a
rename that looks complete, and prose is the one part of a source file the
compiler never reads. It surfaced an hour later because a PEER grepped for the
old name as a collision string and got a plausible thin result.

That is the expensive shape twice over: the ghost name reads as a live
cross-reference, and a check aimed at it comes back clear because a name nothing
defines is a name nothing has touched.

WHAT IT IS NOT. Not a gate, and PLEASE LEAVE IT THAT WAY. The tree has 25 of
these, so a row failing on any of them would be permanently red, and a gate that
can never pass is not a gate. It exits 0 and prints; `--strict` exits 1 for a
caller that has cleaned the tree and wants to keep it clean.

frankD's reason, which is better than mine and is the one to quote if someone
proposes wiring it in: making this a gate produces exactly the outcome the
never-passing-gate rule exists to prevent -- somebody bulk-edits 25 comments to
make it green, INCLUDING the past-tense ones that are correct history. The
`[reads as history]` marker is what keeps this readable rather than
actionable-in-bulk, and it is the part a later session will be tempted to drop
because it makes the output "noisy". It is not noise; it is the difference
between a citation and a defect, and only a reader can tell them apart.

THE POPULATION IS THE WHOLE DESIGN, and the two naive versions are worthless:

    CamelCase tokens in compiler/ comments                       2789
    ... appearing nowhere in compiler/ code                       588   <- flags everything
    ... and present in compiler/ 14 days ago (comments included)  246   <- same, laundered
    ... once DEFINED as a routine, absent from ALL tracked
        Pascal code today                                          18   <- this tool

The first two are a check that flags everything, which is as empty as one that
never fires: `AnsiChar`, `ArcTan2`, `AnObject`, `CapWords` -- RTL names, prose
words, and examples. The discriminators that matter are both necessary:

  * **was DEFINED as a `function`/`procedure` in `compiler/`** (not merely
    mentioned) -- so it named a real routine and not a concept; and
  * **absent from every tracked `*.pas`/`*.inc`, comments stripped** (not just
    from `compiler/`) -- so an RTL name a compiler comment mentions is live code
    somewhere and not a ghost.

A PAST-TENSE CITATION IS NOT A DEFECT AND THIS TOOL CANNOT TELL. `wasmenc.inc`
says "This used to be a public WasmFuncIndex() that the backend called", which is
correct history and should stay. So every hit prints its comment line and the
tool marks the ones whose wording looks historical -- the judgement is the
reader's, and the tool's job is to put the line in front of them. Reporting a
deliberate citation as a finding would be this repo's own favourite failure, so
the output is a LIST OF CITATIONS, never a list of defects.

    tools/ghost_names.py                  # report
    tools/ghost_names.py --since='90 days ago'
    tools/ghost_names.py --strict         # exit 1 if any are found
"""
import bisect
import collections
import os
import re
import subprocess
import sys

CAMEL = re.compile(r"\b[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]*)+\b")
DEF = re.compile(r"^\s*(?:function|procedure)\s+([A-Za-z_][A-Za-z0-9_]*)", re.I | re.M)
# A REAL SCANNER THAT HONOURS `{$NESTEDCOMMENTS}`, AND THE FOUR WRONG VERSIONS
# BEFORE IT ARE THE ARGUMENT. Telling a comment from code in Pascal is a LEXING
# problem whose RULES ARE SET BY A DIRECTIVE IN THE SOURCE, and every
# approximation broke in the same direction -- swallowing code as comment,
# silently, which is exactly the confusion this tool exists to detect:
#
#   1. `\{[^}]*\}|\(\*.*?\*\)|//[^\n]*` under re.S: 88 names instead of 26. The
#      error message `'(**mapping) is not supported; ...'` in pyparser.inc -- a
#      `(*` inside a STRING LITERAL -- opened a "comment" from line 9154 to line
#      18918. 446,638 characters of code scanned as prose.
#   2. Deleting the `(* *)` form fixed the count and was wrong: pyparser.inc uses
#      it as a real comment form, so the tool went quiet by giving up on nine
#      genuine comments. An instrument that agrees with you because it stopped
#      looking.
#   3. Consuming string literals first left `(**kw)`, written in PROSE, opening a
#      34,840-character span of its own.
#   4. A scanner with NON-NESTING `{ }` still produced that span, and this one is
#      the real lesson: `compiler/compiler.pas:11` says `{$NESTEDCOMMENTS ON}`.
#      Under that directive `{ ...  g(**{"a":1,"b":2}) ... }` is ONE comment; a
#      non-nesting scanner ends it at the inner `}`, hands the rest of the prose
#      back as code, and the `(*` in `def g(**kw)` opens a comment that runs 793
#      lines. THE COMMENT SYNTAX IS NOT A PROPERTY OF THE LANGUAGE, IT IS A
#      PROPERTY OF A DIRECTIVE IN THE FILE -- a scanner that does not read it is
#      correct about a different dialect, which is this repo's favourite way for
#      an instrument to be wrong.
#
# The codebase already knows the hazard from the other side: pyparser.inc:1140
# spells braces out in prose on purpose, because "a literal brace inside a
# brace-delimited comment desyncs the self-host lexer
# (project_nested_comment_brace_selfhost_landmine)".
#
# Pascal's rules, all of them: `{`..`}` and `(*`..`*)` (nesting, and nesting
# within each other, under the directive), `//` to end of line, `'`..`'` with
# `''` as an escaped quote and no line spanning.
def comment_spans(text, nested=True):
    """[(start, end)] of every comment, by scanning. Never returns code."""
    spans, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == "'":                                   # string literal
            i += 1
            while i < n and text[i] != "\n":
                if text[i] == "'":
                    if i + 1 < n and text[i + 1] == "'":
                        i += 2                         # '' -- an escaped quote
                        continue
                    i += 1
                    break
                i += 1
        elif c == "{":
            # Braces NEST (the directive), and a `(*` inside a brace comment is
            # NOT an opener. Both halves are forced by the tree: nesting is what
            # keeps `{ ... g(**{"a":1}) ... }` one comment, and ignoring `(*`
            # inside braces is what keeps `{ \`C(*xs)\` ... }` from running
            # 42,000 lines. Treating `(*` as a nested opener there -- which the
            # directive's wording invites -- produced a single 1,984,041-character
            # "comment" and 740 reported names. The file compiles, so the real
            # lexer does not do that either; the observable settles the dialect
            # question that the documentation does not.
            start, depth = i, 0
            while i < n:
                if text[i] == "{":
                    depth += 1
                elif text[i] == "}":
                    depth -= 1
                    if depth == 0:
                        i += 1
                        break
                i += 1
            spans.append((start, i))
        elif text.startswith("(*", i):
            j = text.find("*)", i + 2)
            j = n if j < 0 else j + 2
            spans.append((i, j))
            i = j
        elif text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            spans.append((i, j))
            i = j
        else:
            i += 1
    return spans


def strip_comments(text):
    out, prev = [], 0
    for a, b in comment_spans(text):
        out.append(text[prev:a])
        out.append(" ")
        prev = b
    out.append(text[prev:])
    return "".join(out)


HISTORICAL = re.compile(
    r"\b(used to|use to|was |were |formerly|no longer|until |replaced by|"
    r"there is one now|renamed|has since|previously|old name)\b", re.I)


def sh(*a):
    return subprocess.run(a, capture_output=True, text=True).stdout


def scan(since):
    root = sh("git", "rev-parse", "--show-toplevel").strip()
    if not root:
        print("not in a git repository", file=sys.stderr)
        sys.exit(3)
    os.chdir(root)

    # 1. Every CamelCase token that appears inside a comment in compiler/**,
    #    with the file, line and the line's text, so a reader can judge it.
    cites = collections.defaultdict(list)
    comp = [f for f in sh("git", "ls-files", "compiler/").split()
            if f.endswith((".inc", ".pas"))]
    for fn in comp:
        try:
            text = open(fn, errors="replace").read()
        except OSError:
            continue
        # Walk comments with their offsets so a hit can name a LINE. A comment
        # spanning 30 lines otherwise reports the line the brace opened on,
        # which sends the reader to the wrong paragraph of the right file --
        # the stale-line-number failure, rebuilt inside the tool that exists to
        # catch stale references.
        # Precompute the line index ONCE per file. The obvious spelling --
        # `text.count("\n", 0, off)` and `text.splitlines()[n]` per token -- is
        # O(file) per token and took this scan from 3 seconds to over two
        # minutes across 60 files. Same answer, and the slow version is the one
        # you write first because it reads more clearly.
        lines = text.splitlines()
        starts = []
        pos = 0
        for ln in lines:
            starts.append(pos)
            pos += len(ln) + 1
        for base, stop in comment_spans(text):
            block = text[base:stop]
            for tok in CAMEL.finditer(block):
                i = bisect.bisect_right(starts, base + tok.start()) - 1
                cites[tok.group(0)].append((fn, i + 1, lines[i].strip()))

    # 2. Everything live in tracked Pascal CODE today, comments stripped.
    live = set()
    for fn in sh("git", "ls-files", "*.pas", "*.inc").split():
        try:
            live |= {t.lower() for t in
                     CAMEL.findall(strip_comments(open(fn, errors="replace").read()))}
        except OSError:
            continue

    # 3. Names that were once DEFINED as a routine in compiler/. Read the diff
    #    with the +/- markers removed so a definition counts whether it was
    #    being added or removed -- either way the name existed.
    diff = sh("git", "log", f"--since={since}", "-p", "--format=", "--", "compiler/")
    was_defined = {n.lower() for n in DEF.findall(re.sub(r"^[+-]", "", diff, flags=re.M))}

    return {name: hits for name, hits in cites.items()
            if name.lower() in was_defined and name.lower() not in live}


def main():
    since, strict = "60 days ago", False
    for a in sys.argv[1:]:
        if a.startswith("--since="):
            since = a.split("=", 1)[1]
        elif a == "--strict":
            strict = True
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
    ghosts = scan(since)
    if not ghosts:
        print("ghost-names: none — every routine name cited in a compiler/ "
              "comment still exists in tracked Pascal code.")
        return 0
    files = {fn for hits in ghosts.values() for fn, _, _ in hits}
    print("ghost-names: %d name(s) across %d file(s) are cited in a compiler/ "
          "comment and defined nowhere." % (len(ghosts), len(files)))
    print("A PAST-TENSE CITATION IS CORRECT HISTORY, NOT A DEFECT — the marked "
          "lines are the tool's guess, the judgement is yours.\n")
    for name in sorted(ghosts):
        print("  %s" % name)
        for fn, line, txt in sorted(ghosts[name]):
            mark = "  [reads as history]" if HISTORICAL.search(txt) else ""
            print("    %s:%d%s" % (fn, line, mark))
            print("      %s" % txt[:100])
    return 1 if strict else 0


if __name__ == "__main__":
    sys.exit(main())
