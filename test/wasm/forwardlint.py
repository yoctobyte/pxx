#!/usr/bin/env python3
"""Flag a call to a routine defined later in the same file with no forward.

FPC resolves names in source order within a unit; pxx does not. A file can
therefore self-host and still break the bootstrap seed, silently, and the only
thing that looks today is a 48-second FPC build run once per phase.

Deliberately narrow. It reports a name only when ALL of these hold, so that a
report is worth acting on rather than worth suppressing:

  * the name is DEFINED in this file (so an RTL or shared-file routine, which
    FPC resolves from an earlier include, is never reported);
  * the use is on a line before the definition;
  * no `forward;` declaration for it appears before the use;
  * the use is not inside a comment or a string literal.

A check that cries wolf is worse than no check, for the same reason a
diagnostic that names a cause is: it does the reader's reasoning for them,
wrongly. So the failure mode chosen here is a MISS, not a false alarm — the
gate's real FPC build stays the backstop.
"""
import re
import sys

DEF = re.compile(r'^\s*(?:function|procedure)\s+([A-Za-z_]\w*)', re.I)
FWD = re.compile(r'\bforward\s*;', re.I)
IDENT = re.compile(r'[A-Za-z_]\w*')


def strip(line, in_comment):
    """Remove { } and (* *) comments, // rest-of-line, and 'string' literals."""
    out, i, n = [], 0, len(line)
    while i < n:
        if in_comment:
            j = line.find('}', i)
            if j < 0:
                return ''.join(out), True
            i, in_comment = j + 1, False
            continue
        c = line[i]
        if c == '{':
            in_comment = True
            i += 1
        elif c == "'":
            j = i + 1
            while j < n and line[j] != "'":
                j += 1
            i = j + 1
        elif c == '/' and i + 1 < n and line[i + 1] == '/':
            break
        else:
            out.append(c)
            i += 1
    return ''.join(out), in_comment


def scan(path):
    raw = open(path, encoding='utf-8', errors='replace').read().split('\n')
    code, in_comment = [], False
    for line in raw:
        c, in_comment = strip(line, in_comment)
        code.append(c)

    define_at, forward_at, uses = {}, {}, []
    for ln, c in enumerate(code, 1):
        m = DEF.match(c)
        if m:
            name = m.group(1)
            # A `forward;` may sit on this line or the next (a long signature
            # wraps). Two lines is what this file's style actually produces.
            tail = ' '.join(code[ln - 1:ln + 2])
            if FWD.search(tail):
                forward_at.setdefault(name, ln)
            else:
                define_at.setdefault(name, ln)
            continue
        for um in IDENT.finditer(c):
            uses.append((ln, um.group(0)))

    bad = []
    for ln, name in uses:
        d = define_at.get(name)
        if d is None or ln >= d:
            continue
        f = forward_at.get(name)
        if f is not None and f < ln:
            continue
        bad.append((ln, name, d))
    return bad


def main(argv):
    failed = False
    for path in argv[1:]:
        bad = scan(path)
        # Report each name once, at its first offending use.
        seen = set()
        for ln, name, d in bad:
            if name in seen:
                continue
            seen.add(name)
            failed = True
            print(f'FAIL {path}:{ln}: calls {name}, defined at line {d}, '
                  f'with no forward — FPC cannot resolve this')
    if failed:
        print('     pxx accepts a forward reference within a file and FPC does')
        print('     not, so this self-hosts and breaks the bootstrap seed.')
        print('     Add a `forward;` beside the others near the top of the file.')
        return 1
    print(f'ok  no forward references without a declaration '
          f'({len(argv) - 1} files)')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
