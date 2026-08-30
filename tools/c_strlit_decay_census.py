#!/usr/bin/env python3
"""C string-literal decay census: every way to WRAP a literal x every SITE
that consumes one, with gcc deciding each cell.

WHY A MATRIX. In C a string literal IS a char*, but it lowers to a frozen
string HANDLE (8-byte length prefix, then the data). Consumers that add the 8
themselves must recognise the literal -- and the ones keyed on
`ASTKind[<operand>] = AN_STR_LIT` are asking what NODE produced their operand,
so ANY node in between defeats them. Reading those sites cannot tell you which
wrappers exist; enumerating the wrappers can. That is how the five live wrong
values this tool found were found: every one was a comma operator, which is
simply a shape nobody had written a test for.

A wrong answer here is SILENT and looks benign: the pointer lands on the length
prefix, whose first byte is the length and whose rest is zero, so the program
prints an empty string rather than crashing.

WHAT IT IS BLIND TO.
  - Only the wrappers in the list. It is an enumeration of MY model of C, and a
    shape nobody listed is invisible; it will not tell you it is missing.
  - Sites are the five below. A consumer not modelled here is not covered.
  - One literal, one element type, native x86-64 at the default -O.
  - `n/a` cells are ones GCC ITSELF rejects (a static initializer must be a
    constant expression). They are neither passes nor failures. An earlier
    version scored them as failures and reported 11 wrong where 5 was right --
    a skip counted as a verdict is a lie in whichever direction it is counted.

Usage: c_strlit_decay_census.py <tmpdir> <pxx-binary>
  refactor-c-string-literal-decay-belongs-at-the-producer"""
import os, subprocess, sys

# name -> C expression producing a char* from the literal LIT
WRAPPERS = [
    ("plain",        '{L}'),
    ("paren",        '({L})'),
    ("paren2",       '(({L}))'),
    ("comma",        '(1, {L})'),
    ("comma-nested", '(1, (2, {L}))'),
    ("ternary-T",    '(1 ? {L} : "zz")'),
    ("ternary-F",    '(0 ? "zz" : {L})'),
    ("cast",         '((const char *){L})'),
    ("cast-comma",   '((const char *)(1, {L}))'),
    ("comma-cast",   '(1, (const char *){L})'),
    ("tern-comma",   '(1 ? (1, {L}) : "zz")'),
    ("comma-tern",   '(1, 1 ? {L} : "zz")'),
    ("cast-tern",    '((const char *)(1 ? {L} : "zz"))'),
]

# name -> template with {E} the wrapped expression; must print the string
SITES = [
    ("assign",  'const char *v = {E}; printf("%s\\n", v);'),
    ("return",  'printf("%s\\n", site_ret());'),
    ("arg",     'take({E});'),
    ("init-st", 'static const char *sv = {E}; printf("%s\\n", sv);'),
    ("direct",  'printf("%s\\n", {E});'),
]

def source(site, expr):
    ret_fn = 'const char *site_ret(void) { return %s; }' % expr
    body = SITES[[s[0] for s in SITES].index(site)][1].replace('{E}', expr)
    return ('#include <stdio.h>\n#include <string.h>\n'
            'void take(const char *s) { printf("%s\\n", s); }\n'
            + ret_fn + '\n'
            'int main(void) { ' + body + ' return 0; }\n')

def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=40, **kw)

def main():
    tmp, pxx = sys.argv[1], sys.argv[2]
    LIT = '"OK42"'
    rows = []
    for sname, _ in SITES:
        for wname, wtmpl in WRAPPERS:
            expr = wtmpl.format(L=LIT)
            src = source(sname, expr)
            cf = os.path.join(tmp, "cell.c")
            open(cf, "w").write(src)
            g = run(["gcc", "-w", "-O2", "-o", os.path.join(tmp, "g"), cf])
            if g.returncode != 0:
                rows.append((sname, wname, "REJECT", "-", "gcc-reject")); continue
            gv = run([os.path.join(tmp, "g")]).stdout.strip()
            p = run([pxx, cf, os.path.join(tmp, "p")])
            if p.returncode != 0:
                rows.append((sname, wname, gv, "COMPILE-FAIL", "FAIL")); continue
            pr = run([os.path.join(tmp, "p")])
            pv = pr.stdout.strip() if pr.returncode == 0 else (
                "SIGSEGV" if pr.returncode == -11 else "rc=%d" % pr.returncode)
            rows.append((sname, wname, gv, pv, "ok" if gv == pv else "FAIL"))

    wnames = [w[0] for w in WRAPPERS]
    print("%-10s" % "site", end="")
    for w in wnames: print("%-14s" % w, end="")
    print()
    bad = 0
    for sname, _ in SITES:
        print("%-10s" % sname, end="")
        for w in wnames:
            r = [x for x in rows if x[0] == sname and x[1] == w][0]
            if r[4] == "ok":
                cell = "ok"
            elif r[4] == "gcc-reject":
                # gcc will not compile the cell at all (a static initializer
                # must be a constant expression). NOT a pxx defect and not a
                # skip we may score passlike either -- print it as its own
                # symbol so it can never be read as evidence in either
                # direction.
                cell = "n/a"
            else:
                bad += 1
                cell = "%s!=%s" % (r[2] or "''", r[3] or "''")
            print("%-14s" % cell[:13], end="")
        print()
    nap = len([x for x in rows if x[4] == "gcc-reject"])
    print("\ncells wrong: %d   (of %d measured; %d n/a -- gcc rejects the program)"
          % (bad, len(rows) - nap, nap))

main()
