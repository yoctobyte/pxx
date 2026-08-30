#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Compile every complete program snippet in docs/** against the PINNED compiler.

    tools/docsnip.py            # summary + failures
    tools/docsnip.py -v         # also list what was skipped, and why

WHY IT EXISTS. `docs/**` is published verbatim to the website and is read by
people who cannot check it against the tree, so a snippet that does not compile
fails in front of a stranger. Found on the first run: `docs/library/json.md`
used `E.Reason` on an exception that only has `Message`, directly under the
sentence *"It compiles and runs on the pinned compiler."*

WHAT IT WILL NOT TELL YOU, and these are the interesting half:

1. **A snippet that is SUPPOSED to fail.** `docs/language/name-resolution.md`
   deliberately shows a program that does not compile, with the expected
   diagnostic in a comment. A checker that counts failures reports it forever.
   Blocks carrying a `{ error: ... }` comment are therefore expected-fail, and
   the run is red only if such a block COMPILES.
2. **A snippet whose companion file is described in prose.** Several examples
   are `uses './mymath.c'` with the companion given as a comment rather than a
   block. Those are unverifiable as printed, and guessing the companion tests
   the guess. They are reported as SKIPPED-companion, not as failures. All five
   in the tree (six blocks) were verified by hand on 2026-08-30 by writing the companion the
   comment describes; every one compiled and printed exactly what its comments
   claim.
3. **Whether the output shown is the output produced.** json.md's output block
   matched a real run line for line EXCEPT the last, which is how the stale
   member was dated. Comparing recorded output needs a runner and an expected
   block convention; not built.

   Worth stating for whoever builds it: **a recorded output block is not
   decoration, it is a timestamp.** A PARTIAL match localises drift far better
   than pass/fail ever could -- nine identical lines and one changed one says
   the snippet was really run, and says which library change invalidated it. A
   runner that only reported "output differs" would throw that away.

Fragments (a `procedure` on its own, a type block) are counted and skipped.
Compiling a fragment means inventing the program around it, and then you have
tested the invention.
"""
import os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PXX = os.path.join(ROOT, 'stable_linux_amd64/default/pinned')
DOCS = os.path.join(ROOT, 'docs')

FENCE = re.compile(r'^```([a-z0-9+#-]*)\s*$')
# a flag the snippet asks for in its own comment: { compile with: ./pxx --threadsafe ... }
FLAGS = re.compile(r'compile with:.*?\bpxx\b([^}]*)', re.S)
# a companion the snippet needs but the page only describes
COMPANION = re.compile(r"uses\s+'\./[^']+'|^\s*uses\s+[a-z_][a-z0-9_]*\s*;.*\{[^}]*declares", re.M | re.I)
# `{ error: ... }` on its own -- the convention name-resolution.md uses. The
# looser `\{[^}]*error:` matched json.md, whose snippet parses the deliberately
# UNTERMINATED literal '{"name": "Alice"' and then prints a string containing
# "error:" -- the open brace never closes, so the window swallowed both. An
# unbalanced brace inside a string literal is not a comment; require the marker
# to open the brace.
EXPECT_FAIL = re.compile(r'\{\s*error:', re.I)


def blocks():
    for dirpath, _, files in os.walk(DOCS):
        for fn in sorted(files):
            if not fn.endswith('.md'):
                continue
            path = os.path.join(dirpath, fn)
            rel = os.path.relpath(path, ROOT)
            lines = open(path, errors='replace').read().split('\n')
            i = 0
            while i < len(lines):
                m = FENCE.match(lines[i])
                if not m:
                    i += 1
                    continue
                lang, j, body = m.group(1), i + 1, []
                while j < len(lines) and lines[j].strip() != '```':
                    body.append(lines[j])
                    j += 1
                yield rel, i + 1, lang, '\n'.join(body)
                i = j + 1


def main():
    verbose = '-v' in sys.argv
    if not os.path.exists(PXX):
        sys.exit('docsnip: no pinned compiler at %s' % PXX)
    work = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'pxx_docsnip.%d' % os.getpid())
    os.makedirs(work, exist_ok=True)

    total = whole = frag = 0
    fails, skipped, wrong_pass = [], [], []
    for rel, ln, lang, body in blocks():
        total += 1
        t = body.strip()
        if lang not in ('pascal', 'pas') or not (
                re.match(r'^program\s', t) and t.rstrip().endswith('end.')):
            frag += 1
            continue
        whole += 1
        if COMPANION.search(body):
            skipped.append((rel, ln, 'companion file described in prose, not shown'))
            continue
        expect_fail = bool(EXPECT_FAIL.search(body))
        src = os.path.join(work, 'sn%d.pas' % whole)
        out = os.path.join(work, 'sn%d' % whole)
        open(src, 'w').write(body + '\n')
        flags = []
        m = FLAGS.search(body)
        if m:
            flags = [x for x in m.group(1).split() if x.startswith('-')]
        r = subprocess.run([PXX] + flags + [src, out],
                           capture_output=True, text=True, timeout=180)
        ok = r.returncode == 0
        if ok and expect_fail:
            wrong_pass.append((rel, ln, 'documented as failing, but it compiles'))
        elif not ok and not expect_fail:
            msg = (r.stdout + r.stderr).strip().split('\n')
            fails.append((rel, ln, ' '.join(flags), msg[0] if msg else '(no message)'))

    print('docsnip: %d code blocks, %d complete Pascal programs, %d fragments/other'
          % (total, whole, frag))
    print('  compiled or failed-as-documented: %d   BROKEN: %d   skipped: %d'
          % (whole - len(fails) - len(wrong_pass) - len(skipped),
             len(fails) + len(wrong_pass), len(skipped)))
    for rel, ln, flags, msg in fails:
        print('\n  BROKEN  %s:%d  %s\n      %s' % (rel, ln, flags, msg[:200]))
    for rel, ln, why in wrong_pass:
        print('\n  BROKEN  %s:%d  %s' % (rel, ln, why))
    if verbose:
        for rel, ln, why in skipped:
            print('  skip    %s:%d  %s' % (rel, ln, why))
    return 1 if (fails or wrong_pass) else 0


if __name__ == '__main__':
    sys.exit(main())
