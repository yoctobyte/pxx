#!/usr/bin/env python3
"""Correct escaping for a `test "$(prog)" = "$(printf '%b' '...')"` Makefile assertion.

Measured rules (2026-08-02), each the source of a real bug tonight:
  - BACKSLASH first, else a backslash in the DATA merges with an escape we emit
    (`'both \' and "'` produced `\047` printed literally).
  - then TAB/newline, else printf %b turns a literal `\t` in the data into a TAB.
  - then the single quote as \047, since the whole thing sits in a '...' shell word.
  - % is NOT escaped: it is literal in a make recipe AND in a printf ARGUMENT
    (only special in printf's FORMAT).
"""
import subprocess, sys, re
prog, name, mkfile = sys.argv[1], sys.argv[2], 'Makefile'
out = subprocess.run([prog], capture_output=True, text=True).stdout.rstrip('\n')
esc = (out.replace('\\', '\\\\')
          .replace('\t', '\\t')
          .replace('\n', '\\n')
          .replace("'", '\\047'))
mk = open(mkfile).read()
new = re.sub(r"(" + re.escape(name) + r"\)\" = \"\$\$\(printf '%b' ')[^\n]*?('\)\")",
             lambda m: m.group(1) + esc + m.group(2), mk)
assert new != mk, "assertion line not found for " + name
open(mkfile, 'w').write(new)
print("re-escaped", name)
