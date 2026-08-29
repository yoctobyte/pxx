#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""docaudit -- check the LIVE reference docs against the tree.

    tools/docaudit.py              both checks, live docs under devdocs/dev/
    tools/docaudit.py cites        only the citation check (hard findings)
    tools/docaudit.py limits       only the stated-limit scan (advisory)
    tools/docaudit.py --dir docs   audit a different tree (e.g. Track D's docs/**)
    tools/docaudit.py targets  compiler/ir.inc ...
                               DERIVED, not matched: for each comment naming
                               targets, diff the set it names against the
                               TARGET_* constants the code right below it
                               actually tests. The one check here with a real
                               oracle -- see check_targets()
    tools/docaudit.py comments compiler/builtin/builtinheap.pas ...
                               the limit scan over Pascal { } comments. Weaker
                               filter on purpose -- see check_comments(): prose
                               explains itself, comments assert, and requiring
                               a because-word drops 80% of source candidates

TWO CHECKS, AND THEY ARE NOT THE SAME KIND OF THING
---------------------------------------------------
`cites` is MECHANICAL and its findings are facts: a cited file that does not
exist, a line number past the end of a file, a ticket cited by a directory it
has moved out of. Exit 1 when any are found.

`limits` is a HEURISTIC and its findings are candidates. It scans for a stated
LIMIT with a MECHANISM attached -- the shape that has produced five wrong claims
in this repo, because a bare wrong claim invites a check while an explained one
supplies its own defence. It never affects the exit code and it is not a lint:
every hit needs a person, and most hits are correct claims.

  Calibration, and this is the point of the tool rather than a caveat:
  a pattern that finds 15 and confirms 3 is worth running; one that found 15
  and confirmed 15 would mean the grep was written to match what its author
  already knew. If `limits` ever stops reporting true claims, it has been
  narrowed into uselessness. Do not tune it toward a clean run.

WHY THE EXCLUSION LIST IS READ, NOT HARDCODED -- AND WHY FROM ONE BLOCK
----------------------------------------------------------------------
`devdocs/dev/` holds live references, session records and carried prompts in one
directory, with opposite editing rules -- a record is SUPPOSED to be wrong, and
correcting one falsifies history. The list of records lives in
`devdocs/dev/README.md` and this tool parses it from there. Hardcoding it would
give this tool the exact defect it exists to find: a second copy of a fact, free
to drift from the first. If the README is missing, or its record block cannot be
found, the run refuses rather than guessing.

It parses the FENCED BLOCK under the SESSION RECORDS heading, not the whole
page, and that distinction is load-bearing. The first version scanned the README
for anything shaped like a filename and excluded `claude-B-prompt.md` and
`session-roster.md` -- both of which that page names precisely in order to say
they are LIVE. Reading a document that distinguishes three categories, and
throwing the distinction away by grepping it flat, would have silently dropped
two live references out of every audit. **A machine-readable region is what makes
a doc a source of truth; prose that mentions a filename is not a list.**

Only records are excluded. Carried prompts stay IN the audit: correcting one
falsifies nothing, so a stale fact in one is worth reporting.

FINDINGS THIS TOOL CANNOT MAKE
------------------------------
It reports that a citation does not RESOLVE. It cannot tell you a citation
resolves to the wrong CONTENT -- a drifted line number does not dangle, it
lands on other real code -- so a clean `cites` run is not evidence the
citations are right. And it cannot tell a stale path from a path that is
absent because the doc successfully argued against building it. Both need a
reader.

The third class it is MOSTLY blind to: a claim that is TRUE AND NO LONGER
SUFFICIENT. A comment that named the gates it covered, was correct when
written, and is silent about the gates added since has no limit-word problem
and no broken citation -- `cites` and `limits` both pass it. That class is not
findable by pattern; it needs ENUMERATION -- derive the real set with a
command, diff it against the set the prose names. Count things, do not grep
for them.

`targets` is one instance of that, and only one. It works because the set has
an oracle in the code: the `TARGET_*` constants a condition tests. Wherever the
prose names a set with no such oracle -- optimisation gates, call sites,
"every backend" -- there is nothing to diff against and no generic tool can
help. That needs a per-claim command, chosen by whoever knows what the sentence
means. Do not read a clean `targets` run as coverage of the class.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

SRC_DIRS = r'(?:compiler|lib|tools|test|examples|docs|devdocs|stable_linux_amd64)'
SRC_EXT = r'(?:inc|pas|py|sh|c|h|md|npy|rs|zig|json|log)'
CITE = re.compile(r'\b(' + SRC_DIRS + r'/[A-Za-z0-9_./-]+?\.' + SRC_EXT + r')(?::(\d+))?\b')

TICKET_DIRS = ('urgent', 'working', 'unfinished', 'backlog', 'backlog_new',
               'blocked', 'done', 'done-followup', 'rejected', 'decided',
               'float', 'experimental', 'rainy-day')
TICKET = re.compile(r'devdocs/progress/(' + '|'.join(TICKET_DIRS) + r')/([A-Za-z0-9_.-]+?)\.md')

LIMIT = re.compile(r'\b(only|cannot|can not|can\'t|no way to|impossible|unsupported|'
                   r'not supported|never|rejected|refuses?|refused|does not exist|'
                   r'is absent|not implemented|blind to|there is no)\b', re.I)
MECH = re.compile(r'\b(because|since|so that|so the|so a|so it|which means|'
                  r'as a result|therefore|the reason)\b', re.I)
SCOPE = re.compile(r'\b(x86-64|x86_64|i386|aarch64|arm32|xtensa|riscv32|wasm32|'
                   r'linux|windows|only on|-only)\b', re.I)


def records_from_readme(docdir):
    """The session records, parsed from the fenced block in the directory's README.

    Returns None when there is no README, or no fenced block under a SESSION
    RECORDS heading -- the caller refuses rather than guessing, because guessing
    here means editing history.

    Deliberately NOT a scan of the whole page: that page names live files too,
    in order to say they are live."""
    readme = os.path.join(docdir, 'README.md')
    if not os.path.exists(readme):
        return None
    text = open(readme, errors='replace').read()
    m = re.search(r'^#+.*SESSION RECORDS.*?$(.*?)(?=^#+\s|\Z)', text,
                  re.S | re.M | re.I)
    if not m:
        return None
    fenced = re.findall(r'^```.*?^```', m.group(1), re.S | re.M)
    if not fenced:
        return None
    names = set()
    for block in fenced:
        names |= set(re.findall(r'\b([A-Za-z0-9][A-Za-z0-9_.-]*\.md)\b', block))
    return (names | {'README.md'}) if names else None


def live_docs(docdir, skip):
    for fn in sorted(os.listdir(docdir)):
        if fn.endswith('.md') and fn not in skip:
            yield fn


def check_cites(docdir, skip):
    missing, past_eof, moved = [], [], []
    for fn in live_docs(docdir, skip):
        text = open(os.path.join(docdir, fn), errors='replace').read()

        for m in TICKET.finditer(text):
            named, slug = m.group(1), m.group(2)
            found = [d for d in TICKET_DIRS
                     if os.path.exists(os.path.join(ROOT, 'devdocs/progress', d, slug + '.md'))]
            if found and named not in found:
                moved.append((fn, slug, named, '/'.join(found)))

        for m in CITE.finditer(text):
            rel, line = m.group(1), m.group(2)
            full = os.path.join(ROOT, rel)
            if not os.path.exists(full):
                missing.append((fn, rel))
            elif line:
                n = sum(1 for _ in open(full, errors='replace'))
                if int(line) > n:
                    past_eof.append((fn, rel, int(line), n))

    print("== ticket cited by a directory it has MOVED out of ==")
    print("   (a ticket's directory IS its state, so the citation breaks when")
    print("    the work SUCCEEDS -- and 'not found' reads as 'abandoned')")
    for fn, slug, named, actual in sorted(set(moved)):
        print("   %-34s %s\n       says %-12s now in %s" % (fn, slug, named, actual))
    if not moved:
        print("   none")

    print("\n== cited path does not exist in this checkout ==")
    print("   (check origin/wasm and other branches before calling it stale;")
    print("    and a path can be absent because the doc argued against it)")
    for fn, rel in sorted(set(missing)):
        on_branch = ''
        for br in ('origin/wasm', 'origin/rust'):
            if subprocess.run(['git', '-C', ROOT, 'cat-file', '-e', '%s:%s' % (br, rel)],
                              capture_output=True).returncode == 0:
                on_branch = '   [on %s]' % br
                break
        print("   %-34s %s%s" % (fn, rel, on_branch))
    if not missing:
        print("   none")

    print("\n== citation past end of file ==")
    for fn, rel, line, n in sorted(set(past_eof)):
        print("   %-34s %s:%d  (file has %d lines)" % (fn, rel, line, n))
    if not past_eof:
        print("   none")

    return len(moved) + len(missing) + len(past_eof)


def check_limits(docdir, skip):
    rows = []
    for fn in live_docs(docdir, skip):
        text = open(os.path.join(docdir, fn), errors='replace').read()
        for para in re.split(r'\n\s*\n', text):
            flat = ' '.join(para.split())
            for sent in re.split(r'(?<=[.!?])\s+', flat):
                if not (40 <= len(sent) <= 420):
                    continue
                if LIMIT.search(sent) and MECH.search(sent):
                    rows.append((SCOPE.search(sent) is not None, fn, sent))

    scoped = [r for r in rows if r[0]]
    print("== stated limits with a mechanism attached (ADVISORY) ==")
    print("   %d candidates, %d naming a target or scope. Most are TRUE claims."
          % (len(rows), len(scoped)))
    print("   Check the CONSEQUENCE, not the mechanism: the mechanism is the half")
    print("   that stays true while the conclusion moves under it.\n")
    for _, fn, sent in sorted(scoped, key=lambda r: r[1]):
        print("   [%s]\n     %s\n" % (fn, sent))
    return 0


def pascal_comments(path):
    """Yield the bodies of `{ ... }` comments.

    Braces NEST in practice here: standard Pascal says the first `}` closes the
    comment, but both pxx and FPC accept `{ ... span_{nd-1} ... }` as one. A
    scanner that disagrees with both compilers about where a comment ends is not
    a check, it is a generator of plausible-looking failures -- measured by
    forwardlint, whose narrow first version had to be thrown away for exactly
    this. So track depth rather than stopping at the first `}`.
    """
    text = open(path, errors='replace').read()
    depth, start = 0, None
    for i, ch in enumerate(text):
        if ch == '{':
            if depth == 0:
                start = i + 1
            depth += 1
        elif ch == '}' and depth:
            depth -= 1
            if depth == 0:
                body = text[start:i]
                if not body.startswith('$'):          # a compiler directive, not prose
                    yield body


def check_comments(paths):
    """Scoped limits in Pascal comments.

    NOTE the filter is DELIBERATELY WEAKER here than for markdown: a comment
    need only state a limit that names a target, not explain it. Measured on
    `builtinheap.pas` + `ir_codegen386.inc`: 26 scoped-limit sentences, of which
    only 5 carry a because-word. Requiring the mechanism throws away 80% of the
    candidates in source -- including `PXXStrIncRef`'s *"NON-atomic --
    threadsafe mode is x86-64 only"*, a KNOWN-false claim tracked in
    bug-a-threadsafe-is-x86-64-only-is-asserted-in-five-places.

    Prose explains itself; comments assert. Same defect, different register, so
    the filter that fits one is the wrong filter for the other -- and running
    the markdown pattern over source would have returned a reassuring near-clean
    sweep over files with five known-false claims in them."""
    rows = []
    for path in paths:
        full = path if os.path.isabs(path) else os.path.join(ROOT, path)
        if not os.path.exists(full):
            print("docaudit: no such file: %s" % path, file=sys.stderr)
            continue
        rel = os.path.relpath(full, ROOT)
        for body in pascal_comments(full):
            flat = ' '.join(body.split())
            for sent in re.split(r'(?<=[.!?])\s+', flat):
                if not (40 <= len(sent) <= 420):
                    continue
                if LIMIT.search(sent) and SCOPE.search(sent):
                    rows.append((MECH.search(sent) is not None, rel, sent))

    explained = sum(1 for r in rows if r[0])
    print("== limits naming a target, in Pascal comments (ADVISORY) ==")
    print("   %d over %d file(s); %d also explain themselves (marked +why)."
          % (len(rows), len(paths), explained))
    print("   Check the CONSEQUENCE, not the mechanism. A comment that merely")
    print("   ASSERTS is not safer than one that explains -- it is just terser,")
    print("   which is why this mode does not require the explanation.\n")
    for why, rel, sent in sorted(rows, key=lambda r: r[1]):
        print("   [%s]%s\n     %s\n" % (rel, '  +why' if why else '', sent))
    return 0


TARGET_WORDS = {
    'TARGET_X86_64': ('x86-64', 'x86_64', 'x86-64'),
    'TARGET_I386': ('i386',),
    'TARGET_AARCH64': ('aarch64', 'arm64'),
    'TARGET_ARM32': ('arm32',),
    'TARGET_XTENSA': ('xtensa',),
    'TARGET_RISCV32': ('riscv32', 'risc-v'),
    'TARGET_WASM32': ('wasm32', 'wasm'),
}
CODE_LOOKAHEAD = 6


def check_targets(paths):
    """Comments that name targets, diffed against the targets the code tests.

    This is the only check here with an ORACLE rather than a pattern. It does
    not ask whether a sentence looks like a limit; it asks whether the set of
    targets the prose names equals the set of `TARGET_*` constants the
    condition immediately below it actually tests. A widening that edits the
    condition and not the comment is exactly the shape this catches, and it is
    the shape with no sibling arm to grep for -- one edit invalidates every
    sentence that stated the old scope, in files nobody touched.

    Worked example it reproduces: `ir.inc`'s AN_WRITE lowering says *"x86-64
    only -- --threadsafe atomics are x86-64-only today"* on the line directly
    above a condition testing four targets.

    Reports a comment/code MISMATCH, which is not automatically a defect: a
    comment may name a target for a reason unrelated to the test below it.
    Every hit needs a reader. But unlike `limits`, a hit here is a measured
    disagreement between two things in the same file, not a guess about tone.
    """
    findings = 0
    for path in paths:
        full = path if os.path.isabs(path) else os.path.join(ROOT, path)
        if not os.path.exists(full):
            print("docaudit: no such file: %s" % path, file=sys.stderr)
            continue
        rel = os.path.relpath(full, ROOT)
        lines = open(full, errors='replace').read().split('\n')

        depth, start = 0, None
        for i, line in enumerate(lines):
            for ch in line:
                if ch == '{':
                    if depth == 0:
                        start = i
                    depth += 1
                elif ch == '}' and depth:
                    depth -= 1
                    if depth == 0 and start is not None:
                        body = ' '.join(' '.join(lines[start:i + 1]).split())
                        code = ' '.join(lines[i + 1:i + 1 + CODE_LOOKAHEAD])
                        said = {k for k, ws in TARGET_WORDS.items()
                                if any(re.search(r'\b' + re.escape(w) + r'\b', body, re.I)
                                       for w in ws)}
                        tested = {k for k in TARGET_WORDS
                                  if re.search(r'\b' + k + r'\b', code)}
                        if said and tested and said != tested:
                            findings += 1
                            short = body if len(body) <= 300 else body[:297] + '...'
                            print("   [%s:%d]" % (rel, start + 1))
                            print("     comment names : %s" %
                                  ', '.join(sorted(x[7:].lower() for x in said)))
                            print("     code tests    : %s" %
                                  ', '.join(sorted(x[7:].lower() for x in tested)))
                            print("     %s\n" % short)
                        start = None

    print("== comment/code target MISMATCHES: %d ==" % findings)
    print("   The comment names one set of targets; the condition within %d lines"
          % CODE_LOOKAHEAD)
    print("   below it tests another. Not automatically a defect -- a comment can")
    print("   name a target for an unrelated reason -- but it is a measured")
    print("   disagreement between two things in the same file, not a guess.")
    return findings


def main():
    argv = sys.argv[1:]
    docdir = os.path.join(ROOT, 'devdocs/dev')
    if '--dir' in argv:
        i = argv.index('--dir')
        docdir = os.path.join(ROOT, argv[i + 1])
        del argv[i:i + 2]
    what = argv[0] if argv else 'all'

    if what == 'targets':
        if len(argv) < 2:
            sys.exit("docaudit targets: name at least one source file")
        sys.exit(1 if check_targets(argv[1:]) else 0)

    if what == 'comments':
        if len(argv) < 2:
            sys.exit("docaudit comments: name at least one source file")
        sys.exit(check_comments(argv[1:]))

    if not os.path.isdir(docdir):
        sys.exit("docaudit: no such directory: %s" % docdir)

    skip = records_from_readme(docdir)
    if skip is None:
        sys.exit("docaudit: %s has no README.md with a fenced list under a\n"
                 "SESSION RECORDS heading. Refusing to guess -- a record is\n"
                 "SUPPOSED to be wrong, and 'correcting' one falsifies history."
                 % docdir)

    n = len(list(live_docs(docdir, skip)))
    print("docaudit: %s -- %d live docs (%d session records excluded per README)\n"
          % (os.path.relpath(docdir, ROOT), n, len(skip) - 1))

    hard = 0
    if what in ('all', 'cites'):
        hard = check_cites(docdir, skip)
    if what in ('all', 'limits'):
        if what == 'all':
            print()
        check_limits(docdir, skip)
    sys.exit(1 if hard else 0)


if __name__ == '__main__':
    main()
