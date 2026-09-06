#!/usr/bin/env python3
"""Which names does OUR lib/rtl/sysutils.pas declare that FPC keeps in `system`?

That set is the population of one defect class, and the class has TWO SIGNS that
point in opposite directions:

  * the name ALSO exists in our implicit surface, so our declaration SHADOWS it
    -- measured by frankD: `uses sysutils` took dynamic-array Delete and Insert
    away from every program in the tree (fix f5ad23c32);
  * the name exists ONLY in our sysutils, so a program that FPC compiles with no
    uses clause needs `uses sysutils` here -- measured by frankS on tarray13:
    `undefined variable (DynArraySize)` at line 23, and one `uses sysutils` line
    advances it to line 68.

Same root -- the unit boundary drawn in the wrong place -- and the same tell, one
`uses` line changing the answer. A fix that handles only the shadowing sign
reads as complete, which is why this is a census and not a grep.

THE ORACLE IS FPC ITSELF, not a grep of its sources. For each name we declare in
our sysutils interface, compile a one-statement program with NO uses clause and
ask whether fpc says `Identifier not found`. Any other outcome -- a wrong-number-
of-parameters error, a type error, success -- means the name RESOLVED, i.e. fpc
has it in `system`. A grep of systemh.inc would answer a different question (what
is written in one header) and would miss names reaching `system` through the
include chain or through objpas.

Report, never a gate. Exit 0 on a clean run whatever it finds; exit 3 if a
control fails, because a census whose controls did not fire is not a measurement.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

SYSUTILS = "lib/rtl/sysutils.pas"

# Controls, branched on. Drawn from the population the question is about: three
# names measured by two seats today, and four that are sysutils' in fpc too.
MUST_BE_SYSTEM = ["Delete", "Insert", "DynArraySize"]
MUST_NOT_BE_SYSTEM = ["Format", "IntToStr", "UpperCase", "ChangeFileExt"]
MIN_DISCOVERED = 100

MODES = ["fpc", "objfpc"]


def interface_routines(path):
    """Routine names declared in the INTERFACE section only."""
    src = open(path, encoding="utf-8", errors="replace").read()
    lo = src.lower()
    i = lo.index("\ninterface")
    j = lo.index("\nimplementation")
    iface = src[i:j]
    out = []
    for m in re.finditer(
            r"(?im)^\s*(function|procedure)\s+([A-Za-z_][A-Za-z0-9_]*)\s*[;(:]",
            iface):
        out.append(m.group(2))
    return sorted(set(out), key=str.lower)


def probe(work, name, mode):
    """True if fpc resolves `name` with no uses clause."""
    p = os.path.join(work, "p.pas")
    with open(p, "w") as f:
        f.write("program p;\n{$mode %s}\nbegin\n  %s;\nend.\n" % (mode, name))
    r = subprocess.run(["fpc", "-Cn", "-vq", "-l-", p],
                       cwd=work, capture_output=True, text=True)
    out = r.stdout + r.stderr
    # The discriminator, and it is the only one read.
    return "Identifier not found" not in out


def main():
    if shutil.which("fpc") is None:
        print("SKIP: no fpc on this host -- the oracle is absent, not silent.")
        return 0

    names = interface_routines(SYSUTILS)
    if len(names) < MIN_DISCOVERED:
        print("CONTROL FAILED: discovery found %d interface routines in %s, "
              "expected >= %d. The interface split is wrong, not the tree."
              % (len(names), SYSUTILS, MIN_DISCOVERED))
        return 3

    work = tempfile.mkdtemp(prefix="unitboundary.")

    # The oracle must be shown WORKING before its answers are read: a name that
    # cannot resolve must come back not-found, or every answer is "resolved".
    if probe(work, "ZzNoSuchIdentifierZz", "fpc"):
        print("CONTROL FAILED: the oracle called a nonsense identifier resolved."
              " Every answer it gives would be 'in system'. Scratch: %s" % work)
        return 3

    system_names = {}
    for n in names:
        hit = [m for m in MODES if probe(work, n, m)]
        if hit:
            system_names[n] = hit

    for n in MUST_BE_SYSTEM:
        if n not in system_names:
            print("CONTROL FAILED: %s is measured in fpc's system by two seats "
                  "and this census did not find it." % n)
            return 3
    for n in MUST_NOT_BE_SYSTEM:
        if n in system_names:
            print("CONTROL FAILED: %s is sysutils' in fpc too; a census that "
                  "flags it flags everything." % n)
            return 3

    print("names declared in %s's interface: %d" % (SYSUTILS, len(names)))
    print("of those, FPC resolves with NO uses clause: %d\n" % len(system_names))
    for n in sorted(system_names, key=str.lower):
        modes = system_names[n]
        tag = "" if len(modes) == len(MODES) else "   [%s only]" % "/".join(modes)
        print("  %s%s" % (n, tag))
    print("\nEach row is a name a program can use in FPC without `uses sysutils`"
          " and cannot here,\nor -- if our implicit surface also has it -- a name"
          " whose declaration SHADOWS ours.\nWhich sign a row has is the next"
          " question and this census does not answer it.")
    print("\ncontrols: %s in / %s out / nonsense-identifier rejected"
          % ("+".join(MUST_BE_SYSTEM), "+".join(MUST_NOT_BE_SYSTEM)))
    print("scratch left at %s (mktemp, reaped in 6h)" % work)
    return 0


if __name__ == "__main__":
    sys.exit(main())
