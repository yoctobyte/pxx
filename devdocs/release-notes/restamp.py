#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Restamp the beta 0.1 release pages for the pin the release is frozen on.

    python3 devdocs/release-notes/restamp.py markers             # any day
    python3 devdocs/release-notes/restamp.py identity --pin v4NN  # freeze day
    python3 devdocs/release-notes/restamp.py check --pin v4NN     # after both

Run from the repository root. Nothing is committed or pushed; read the diff.

markers   Recomputes every "`<sha>` (vNNN)" and "`<sha>` (next pin)" marker in
          the "## Since v441" section of the release notes. The first pin
          that carries a commit is the first pin.log line (v441 or later)
          whose SOURCE commit (the line's last field) has the commit as an
          ancestor. The pin commit ("chore(stable): pin vNNN") is not the
          source commit and is not used for this.
identity  Rewrites the lines that say which pin IS the release, and nothing
          else: CLAUDE.md, the release notes' header comment and
          "This release is" line, known-issues.md's opening, and
          docs/release-notes/index.md's opening. Each pattern must match
          exactly once, so a reworded line stops the script instead of being
          skipped. Lines that say what was MEASURED with v441 are history and
          are left alone.
check     Lists what still needs a person: "(next pin)" markers the frozen
          pin does not carry, known-issues rows that say "Wrong in v441 to
          vNNN" for a fix the frozen pin now carries, and DRAFT comments.
"""
import re
import subprocess
import sys

PIN_LOG = 'stable_linux_amd64/default/pin.log'
NOTES = 'devdocs/release-notes/v0.1.0-beta.1.md'
FIRST = 441


def git(*args):
    return subprocess.run(('git',) + args, capture_output=True, text=True)


def pins():
    """[(n, sha256, source commit)] for v441 and later, in pin order."""
    out = []
    for line in open(PIN_LOG):
        m = re.search(r'pinned v(\d+)\s+([0-9a-f]{64}).*\s([0-9a-f]{40})\s*$', line)
        if m and int(m.group(1)) >= FIRST:
            out.append((int(m.group(1)), m.group(2), m.group(3)))
    return out


def pin_commit(n):
    r = git('log', '-1', '--format=%h', '--grep', 'chore(stable): pin v%d --' % n)
    h = r.stdout.strip()
    if not h:
        sys.exit('no "chore(stable): pin v%d" commit found' % n)
    return h


def first_pin(sha, pl):
    for n, _, src in pl:
        if git('merge-base', '--is-ancestor', sha, src).returncode == 0:
            return 'v%d' % n
    return 'next pin'


def since_section(text):
    a = text.index('## Since v441')
    b = text.index('\n## ', a + 1)
    return a, b


# One or more shas, then the marker, possibly on the next line:
#   `abc1234` (v446)     `abc1234`, `def5678` (v442)     `abc1234`\n  (next pin)
MARK = re.compile(r'(`[0-9a-f]{7,40}`(?:, `[0-9a-f]{7,40}`)*)(\s+)\((v\d+|next pin)\)')


def shas(group):
    return re.findall(r'[0-9a-f]{7,40}', group)


def first_pin_all(group, pl):
    """The first pin carrying every sha in the group."""
    order = ['v%d' % p[0] for p in pl] + ['next pin']
    return max((first_pin(h, pl) for h in shas(group)), key=order.index)


def markers():
    pl = pins()
    s = open(NOTES).read()
    a, b = since_section(s)
    sec = s[a:b]
    changed = []

    def fix(m):
        want = first_pin_all(m.group(1), pl)
        if want != m.group(3):
            changed.append('%s: %s -> %s' % (m.group(1), m.group(3), want))
        return '%s%s(%s)' % (m.group(1), m.group(2), want)

    sec = MARK.sub(fix, sec)
    open(NOTES, 'w').write(s[:a] + sec + s[b:])
    print('markers: latest pin v%d; %d changed' % (pl[-1][0], len(changed)))
    for c in changed:
        print('  ' + c)


def identity(n):
    pl = {p[0]: p for p in pins()}
    if n not in pl:
        sys.exit('v%d is not in %s' % (n, PIN_LOG))
    _, h256, src = pl[n]
    V, H, C, T = 'v%d' % n, h256[:12], pin_commit(n), src[:10]
    edits = [
        # AGENTS.md names no pin since 2026-09-28: it points at the release
        # notes and pin.log instead, so there is nothing there to go stale.
        ('CLAUDE.md',
         r'beta 0\.1 "Blaise" \(pin v\d+\)',
         'beta 0.1 "Blaise" (pin %s)' % V),
        (NOTES,
         r'Release pin: v\d+ \(commit [0-9a-f]+, compiler sha256 [0-9a-f]+,\n  tree [0-9a-f]+\)',
         'Release pin: %s (commit %s, compiler sha256 %s,\n  tree %s)' % (V, C, H, T)),
        (NOTES,
         r'This release is \*\*pin v\d+\*\*\.',
         'This release is **pin %s**.' % V),
        ('docs/reference/known-issues.md',
         r'in the beta 0\.1 compiler, \*\*pin v\d+\*\*\n\(commit `[0-9a-f]+`, compiler sha256 `[0-9a-f]+…`\)',
         'in the beta 0.1 compiler, **pin %s**\n(commit `%s`, compiler sha256 `%s…`)' % (V, C, H)),
        ('docs/release-notes/index.md',
         r'"Blaise" is pin v\d+\.',
         '"Blaise" is pin %s.' % V),
        ('docs/release-notes/index.md',
         r'This page describes \*\*pin v\d+\*\*: commit `[0-9a-f]+`, compiler binary sha256\n`[0-9a-f]+…`\.',
         'This page describes **pin %s**: commit `%s`, compiler binary sha256\n`%s…`.' % (V, C, H)),
    ]
    bad = []
    for path, pat, rep in edits:
        s = open(path).read()
        k = len(re.findall(pat, s))
        if k != 1:
            bad.append('%s: pattern matched %d times: %s' % (path, k, pat))
            continue
        open(path, 'w').write(re.sub(pat, lambda m: rep, s))
    print('identity: %s, commit %s, sha256 %s, source %s' % (V, C, H, T))
    if bad:
        print('NOT DONE (edit by hand, then fix the pattern here):')
        for x in bad:
            print('  ' + x)
        sys.exit(1)


def check(n):
    pl = [p for p in pins() if p[0] <= n]
    if not pl or pl[-1][0] != n:
        sys.exit('v%d is not in %s' % (n, PIN_LOG))
    s = open(NOTES).read()
    a, b = since_section(s)
    todo = []
    for m in MARK.finditer(s[a:b]):
        if first_pin_all(m.group(1), pl) == 'next pin':
            todo.append('release notes: %s is not in v%d; drop its line' % (m.group(1), n))
    for m in re.finditer(r'`[0-9a-f]{10}`', s[a:b]):
        if not any(mm.start() <= m.start() < mm.end() for mm in MARK.finditer(s[a:b])):
            todo.append('release notes: %s has no pin marker' % m.group(0))
    ki = 'docs/reference/known-issues.md'
    inside = False
    for i, line in enumerate(open(ki), 1):
        if line.startswith('## '):
            inside = line.startswith('## Fixed since v441')
        elif inside and line.startswith('- **'):
            todo.append('%s:%d: fixed row, move to "Fixed in this release" (and to the '
                        'release notes if the pin carries it): %s' % (ki, i, line[2:70].strip()))
    for path in (NOTES, 'docs/release-notes/index.md', ki):
        for i, line in enumerate(open(path), 1):
            if 'draft pin' in line.lower():
                continue          # history: "the draft pin v425"
            if 'DRAFT' in line or re.search(r'\bdraft\b', line, re.I):
                todo.append('%s:%d: draft wording: %s' % (path, i, line.strip()[:80]))
    print('check against v%d: %d items' % (n, len(todo)))
    for t in todo:
        print('  ' + t)


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ('markers', 'identity', 'check'):
        sys.exit(__doc__)
    if sys.argv[1] == 'markers':
        return markers()
    if len(sys.argv) != 4 or sys.argv[2] != '--pin' or not re.fullmatch(r'v\d+', sys.argv[3]):
        sys.exit('usage: %s %s --pin vNNN' % (sys.argv[0], sys.argv[1]))
    n = int(sys.argv[3][1:])
    (identity if sys.argv[1] == 'identity' else check)(n)


if __name__ == '__main__':
    main()
