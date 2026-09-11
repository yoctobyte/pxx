#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""A lib unit with a Python surface must be REACHABLE by a bare NilPy import.

A bare `import X` has three routes and only one of them is silent:

    mimic_X.pas in scope            -> substitution, prints "note: X -> mimic_X"
    X in PyRtlUnitServesPython      -> lib/rtl/X.pas
    neither                         -> the HOST's /usr/include/X.h, SILENTLY

So a unit that carries Python marshalling types and is neither named `mimic_*`
nor listed in PyRtlUnitServesPython has a Python surface that NO import can
reach -- and worse, the import that should have reached it binds a host C header
instead. Measured 2026-09-11 on exactly that: `import zlib` took
/usr/include/zlib.h while lib/rtl/zlib.pas sat in the tree with the right answer
in it. C's crc32 is 3-arg where Python's is 1- or 2-arg, so the correct spellings
were refused and the 3-arg spelling COMPILED, LINKED SYSTEM libz AND RETURNED A
WRONG NUMBER. No diagnostic at any point.

WHY THIS IS A GUARD AND NOT A TICKET: the mistake is a recurring STEP, not a list
of names. Add a Python surface to a lib unit, forget the list entry. The author
who did it had both halves in hand and spent five experiments on the wrong file,
because every edit to the declaration changed nothing -- nothing he edited was
ever consulted. This fires at the moment the surface is added rather than when
someone's import silently binds a header months later.

    tools/py_surface_is_reachable.py               # the check
    tools/py_surface_is_reachable.py --selftest    # its controls only
    tools/py_surface_is_reachable.py --self-check  # controls THEN the check
                                                   # (what gate.sh runs)

WHAT THIS GUARD CANNOT SEE, measured 2026-09-11 and stated because the docstring
above reads broader than the instrument is. `MARSHALLING` is a PARTIAL proxy for
"has a Python surface": **5 of the 17 listed units carry zero marshalling hits** --
collections, math, pathlib, random, tempfile -- and all five are genuinely the
Python module of their name. They need no marshalling types because their surface
is plain-typed: `math.gcd(12, 18)` takes Integers and returns one. So this guard
catches a unit whose Python surface USES TPy*/pyvar_* and is unreachable (the zlib
class, which is the one that bit us), and it is BLIND to a plain-typed Python
surface that is unreachable. A `lib/rtl/foo.pas` exposing `foo.bar(x: Integer)` as
a Python entry point, unlisted, would pass this check and still bind
/usr/include/foo.h.

AND THE INVERSE DIRECTION IS THEREFORE UNWRITABLE FROM THIS SIGNAL. "A name is
listed but its unit has no Python surface" would be the right guard against
reading the curated list as a COLLISION TABLE -- the error frankB's fixture
comment made on 2026-09-10, which would have led someone to add menu, netdb, png
and regex to the list. Written against `MARSHALLING` it is BORN RED with those
same five names, which is the "an assertion written from a prediction pins the
prediction" failure. It needs a real signal for "this unit intends a Python
surface" and there is none today. Do not add it on this proxy.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIBDIRS = ('lib/rtl', 'lib/pcl')

# The marshalling TYPES, not "mentions pylib". frankB's proxy check caught this:
# `sysutils` and `typinfo` both mention pylib and both are comment references with
# zero marshalling hits, so "mentions pylib" would have reported two false
# positives in a two-row answer. A type name cannot appear by commentary accident
# the way a unit name can.
MARSHALLING = re.compile(r'TPyList|TPyBytes|TPyDict|TPyIter|pyvar_|pystar_|pystr_of|pynone')


def listed_names(src):
    m = re.search(r"function PyRtlUnitServesPython.*?\n(.*?)\nend;", src, re.S)
    if not m:
        sys.exit("py_surface: cannot find PyRtlUnitServesPython in "
                 "compiler/pasparser_proc.inc -- it was renamed or moved, and "
                 "this guard is now measuring nothing. Fix the guard.")
    return set(re.findall(r"lo = '([a-z0-9_]+)'", m.group(1)))


def scan(listed):
    """Units with a Python surface that no bare import can reach."""
    bad = []
    for d in LIBDIRS:
        full = os.path.join(ROOT, d)
        if not os.path.isdir(full):
            continue
        for f in sorted(os.listdir(full)):
            if not f.endswith('.pas'):
                continue
            name = f[:-4].lower()
            if name.startswith('mimic_'):
                continue                      # reachable by the shim route
            if name in listed:
                continue                      # reachable by the list route
            body = open(os.path.join(full, f), errors='replace').read()
            hits = len(MARSHALLING.findall(body))
            if hits:
                bad.append((os.path.join(d, f), name, hits))
    return bad


def main():
    src = open(os.path.join(ROOT, 'compiler/pasparser_proc.inc'), errors='replace').read()
    listed = listed_names(src)

    want_self = ('--selftest' in sys.argv) or ('--self-check' in sys.argv)
    want_scan = ('--selftest' not in sys.argv)

    if want_self:
        # POSITIVE CONTROL, drawn from the REAL population rather than a fixture.
        # lib/rtl/zlib.pas genuinely carries a Python surface, so removing `zlib`
        # from the list reconstructs the exact tree state this guard exists to
        # catch -- the ~20 minutes on 2026-09-11 when the surface was in and the
        # list entry was not. A synthetic unit would test the scan; this tests the
        # scan over the file the bug actually happened to.
        if 'zlib' not in listed:
            sys.exit("selftest: `zlib` is not in PyRtlUnitServesPython, so the "
                     "control cannot be constructed. Pick another listed unit "
                     "with marshalling hits and update this selftest.")
        must_flag = scan(listed - {'zlib'})
        if not any(n == 'zlib' for _, n, _ in must_flag):
            sys.exit("selftest FAILED (positive control): with `zlib` removed from "
                     "the list, the scan did not flag lib/rtl/zlib.pas. This guard "
                     "cannot fail and is therefore certifying nothing.")
        # NEGATIVE CONTROL: a guard that flags everything passes the above.
        if any(n == 'zlib' for _, n, _ in scan(listed)):
            sys.exit("selftest FAILED (negative control): zlib is listed and was "
                     "still flagged, so the scan ignores the list.")
        print("py_surface selftest OK: flags zlib when unlisted, clears it when listed")
        if not want_scan:
            return 0

    bad = scan(listed)
    if not bad:
        # Scoped deliberately: this says nothing about a PLAIN-TYPED Python
        # surface, which carries no marshalling types and which this check
        # cannot see. See the module docstring. 5 of the listed units are in
        # that category, so the blindness is the common case, not a corner.
        print("py_surface: OK -- every lib unit with a MARSHALLING-using Python "
              "surface is reachable (%d names listed; plain-typed surfaces are "
              "not checked)" % len(listed))
        return 0

    print("py_surface: FAIL -- %d unit(s) carry Python marshalling types but no "
          "bare import can reach them:" % len(bad))
    for path, name, hits in bad:
        print("    %-34s %d marshalling hits" % (path, hits))
        print("        A bare `import %s` will NOT find this unit. It falls through"
              % name)
        print("        to /usr/include/%s.h if the host has one -- silently, and" % name)
        print("        with a wrong VALUE if the C arities happen to agree.")
    print()
    print("    THE FIX IS ONE LINE: add (lo = '<name>') to PyRtlUnitServesPython in")
    print("    compiler/pasparser_proc.inc. That list is curated on PURPOSE -- read")
    print("    its comment first; it records whether a unit was WRITTEN TO BE the")
    print("    Python module of that name, and `tk` is the counterexample for why")
    print("    the question is not 'does a Python package exist by this name'.")
    print("    If the unit is NOT meant to be that Python module, rename it")
    print("    mimic_<module>.pas instead, or the surface is unreachable by design.")
    return 1


if __name__ == '__main__':
    sys.exit(main())
