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

BOTH HALVES OF THE PREDICATE ARE REQUIRED. The fpc side alone answers "fpc
resolves this ambiently" and over-reports: five of its names are ambiently
reachable HERE too (four parser intrinsics and one builtin export), so they are
not a gap at all. The second half asks the pxx side of the same question and is
frankH's, who found it the expensive way -- their first two probe shapes both
reported ALL of their candidates as absent, because neither shape is how pxx
resolves an intrinsic. A CENSUS REPORTING EVERY ONE OF ITS CANDIDATES IS THE
TELL, and Copy/Pos/UpCase as must-find rows are what catch it.

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
PARSERS = ["compiler/pasparser_expr.inc", "compiler/pasparser_stmt.inc",
           "compiler/pasparser_decl.inc", "compiler/pasparser_prog.inc"]
AMBIENT = ["compiler/builtin/builtin.pas", "compiler/builtin/builtinheap.pas"]

# Controls, branched on. THE ORACLE'S CONTROLS ARE PROBED DIRECTLY, NOT LOOKED
# FOR IN THE RESULT -- the first version required Delete and Insert to appear in
# the output, and `475528dae` removed both from our sysutils interface hours
# later, so the census exited 3 on a tree where nothing was wrong. A control that
# encodes a defect stops being a control the moment the defect is fixed. These
# three are names fpc resolves ambiently, which stays true whatever we declare.
MUST_BE_SYSTEM = ["Delete", "Insert", "DynArraySize"]
MUST_NOT_BE_SYSTEM = ["Format", "IntToStr", "UpperCase", "ChangeFileExt"]
# One control that IS about our tree: frankS measured this row on tarray13.
MUST_BE_A_GAP = "DynArraySize"
# The pxx side has its own controls, and they earned themselves (frankH): these
# three are ambiently reachable here and a probe that misses them is measuring
# its own blindness, not the tree.
MUST_BE_REACHABLE_HERE = ["Copy", "Pos", "UpCase"]
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


def reachable_here(names):
    """Of `names`, those a pxx program can use with NO uses clause: a parser
    intrinsic, or a routine an ambient unit's interface exports."""
    intrinsic = set()
    for path in PARSERS:
        try:
            txt = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for m in re.finditer(r"CaseEqual\([A-Za-z_][A-Za-z0-9_]*,\s*'([A-Za-z0-9_]+)'\)",
                             txt):
            intrinsic.add(m.group(1).lower())

    exported = set()
    for path in AMBIENT:
        try:
            txt = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        lo = txt.lower()
        i = lo.find("\ninterface")
        j = lo.find("\nimplementation")
        iface = txt[i:j] if (i >= 0 and j > i) else txt
        for m in re.finditer(
                r"(?im)^\s*(function|procedure)\s+([A-Za-z_][A-Za-z0-9_]*)\s*[;(:]",
                iface):
            exported.add(m.group(2).lower())

    out = {}
    for n in names:
        why = []
        if n.lower() in intrinsic:
            why.append("parser intrinsic")
        if n.lower() in exported:
            why.append("ambient unit export")
        if why:
            out[n] = " + ".join(why)
    return out


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

    for n in MUST_BE_SYSTEM:
        if not any(probe(work, n, m) for m in MODES):
            print("CONTROL FAILED: fpc resolves %s with no uses clause and the "
                  "oracle says it does not." % n)
            return 3
    for n in MUST_NOT_BE_SYSTEM:
        if any(probe(work, n, m) for m in MODES):
            print("CONTROL FAILED: %s is sysutils' in fpc too; an oracle that "
                  "resolves it resolves everything." % n)
            return 3

    system_names = {}
    for n in names:
        hit = [m for m in MODES if probe(work, n, m)]
        if hit:
            system_names[n] = hit

    here = reachable_here(sorted(system_names))
    for n in MUST_BE_REACHABLE_HERE:
        if n in system_names and n not in here:
            print("CONTROL FAILED: %s is ambiently reachable in pxx and the "
                  "reachability probe did not see it. The probe is measuring "
                  "its own blindness." % n)
            return 3
    if system_names and len(here) == len(system_names):
        print("CONTROL FAILED: every candidate came back reachable. A census "
              "that flags none of its population is as empty as one that flags "
              "all of it.")
        return 3
    if reachable_here(["ZzNotARealName"]):
        print("CONTROL FAILED: a nonsense name came back reachable.")
        return 3

    gap = [n for n in sorted(system_names, key=str.lower) if n not in here]
    if MUST_BE_A_GAP not in gap:
        print("CONTROL FAILED: %s is a measured gap (tarray13 dies at line 23 "
              "without it) and this census does not report it." % MUST_BE_A_GAP)
        return 3

    print("names declared in %s's interface:            %d" % (SYSUTILS, len(names)))
    print("of those, FPC resolves with NO uses clause:  %d" % len(system_names))
    print("of those, ambiently reachable in pxx too:    %d" % len(here))
    print("THE GAP -- fpc has it ambiently, we do not:  %d\n" % len(gap))

    for n in gap:
        modes = system_names[n]
        tag = "" if len(modes) == len(MODES) else "   [%s only]" % "/".join(modes)
        print("  %s%s" % (n, tag))

    print("\nreachable here, so NOT a gap:")
    for n in sorted(here, key=str.lower):
        print("  %-16s %s" % (n, here[n]))

    print("\nA gap row is a name an FPC program uses with no uses clause and a"
          " pxx program cannot.\nIt is a POPULATION TO CHECK, not a confirmed"
          " bug: whether each one actually breaks a\nreal program the way"
          " DynArraySize breaks tarray13 is the reachability half, and this\n"
          "census does not ask it. Nor does it tell a gap from a name our"
          " sysutils SHADOWS --\nthat is the other sign of the same class.")
    print("\ncontrols: %s in / %s out / nonsense rejected on both sides / "
          "%s reachable here / not-all-reachable"
          % ("+".join(MUST_BE_SYSTEM), "+".join(MUST_NOT_BE_SYSTEM),
             "+".join(MUST_BE_REACHABLE_HERE)))
    print("scratch left at %s (mktemp, reaped in 6h)" % work)
    return 0


if __name__ == "__main__":
    sys.exit(main())
