#!/usr/bin/env python3
"""Named-type SCALAR CASTS, swept by the ROUTE the name is recognised through.

`SomeName(expr)` reaches a cast through one of several recognition rules in
ParseFactorCore -- the type KEYWORD token, OrdinalNameToTk, BuiltinScalarTypeKind,
and FindTypeAlias for a user alias whose target is scalar. Four of them build
the identical node and differ only in WHICH NAMES THEY RECOGNISE, which is why
every bug in this family has been one door fixed while the next stayed shut
(refactor-p-five-dispatch-sites-for-one-named-type-cast lists four such rounds).

THE AXIS IS THE ROUTE, NOT THE VALUE. A sweep that varies the operand at a fixed
spelling cannot see a door: every door is correct for the values its own tests
used. So each type name is cast through TWO spellings of the same request --
the name directly, and a user alias declared to it -- and the two must agree
with fpc and with each other.

Values are chosen to make truncation VISIBLE: 258 does not fit a byte, -1 is
the all-ones pattern that separates signed from unsigned, and 4294967298 is
2^32+2, which no 32-bit type can hold. A probe value that fits both widths
cannot discriminate.

PXX= to point at another binary; SCD_OUT= to keep the generated rows.
"""
import os, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PXX = os.environ.get("PXX", os.path.join(ROOT, "compiler", "pascal26"))
OUT = os.environ.get("SCD_OUT") or tempfile.mkdtemp(prefix="scalarcast.")
os.makedirs(OUT, exist_ok=True)
if not os.path.exists(PXX):
    sys.exit("no compiler at %s -- set PXX or run `make compiler/pascal26`" % PXX)
print("probe: PXX=%s" % PXX)
print("probe: rows land in %s" % OUT)

NAMES = ["Byte", "ShortInt", "SmallInt", "Word", "Integer", "LongInt",
         "Cardinal", "LongWord", "DWord", "Int64", "QWord", "UInt64",
         "NativeInt", "PtrInt", "Int8", "UInt8", "Int16", "UInt16",
         "Int32", "UInt32", "Boolean", "Char", "AnsiChar", "WideChar"]
VALUES = ["258", "-1", "4294967298"]

def src(name, viaAlias):
    ty = "TCastAlias" if viaAlias else name
    decl = "type TCastAlias = %s;\n" % name if viaAlias else ""
    body = []
    # HOW THE STORED VALUE IS PRINTED IS PER-TYPE, AND BOTH CHOICES WERE FORCED
    # BY A MEASUREMENT RATHER THAN PICKED FOR TIDINESS.
    #   * Ord() for the character and boolean types, because WriteLn of a
    #     WideChar is an ENCODING question and not a cast one: pxx emits the
    #     character as UTF-8 and fpc 3.2.2 converts to the system codepage and
    #     prints `?`, so `WideChar(258)` reported DIFFER on a cast both
    #     compilers get right. Ord is 8- or 16-bit here and cannot narrow.
    #   * the bare value everywhere else, because Ord() of a 64-bit UNSIGNED
    #     narrows in pxx: Ord(QWord(-1)) answers -1 against fpc's
    #     18446744073709551615 while `q := QWord(v); WriteLn(q)` matches exactly.
    # One uniform printer would have been wrong for one half of the sweep in
    # each direction, and both failures land on the -1 row -- the row the sweep
    # exists for.
    ordwrap = name in ("Char", "AnsiChar", "WideChar", "Boolean")
    for i, v in enumerate(VALUES):
        # STORE THE RESULT IN ITS DECLARED TYPE AND PRINT THAT -- CLAUDE.md's
        # stated compatibility test, and here it is also the only version that
        # measures the CAST. Wrapping in Ord() instead reported QWord and UInt64
        # as DIFFER on the -1 row (pxx -1, fpc 18446744073709551615) when the
        # casts are identical and it is pxx's Ord that narrows a 64-bit unsigned
        # to Int64. A wrapper you add for uniformity is a second mechanism under
        # test, and it fails on exactly the rows the sweep is for.
        shown = "Ord(t)" if ordwrap else "t"
        body.append("  t := %s(v%d); WriteLn('%s=', %s);" % (ty, i, v, shown))
    return ("program scd;\n{$mode delphi}\n%s"
            "var v0: Int64; v1: Int64; v2: Int64; t: %s;\n"
            "begin\n  v0 := 258; v1 := -1; v2 := 4294967298;\n%s\nend.\n"
            % (decl, ty, "\n".join(body)))

def run(tag, s, comp):
    p = os.path.join(OUT, "%s_%s.pas" % (tag, comp))
    open(p, "w").write(s)
    exe = os.path.join(OUT, "e_%s_%s" % (tag, comp))
    cmd = (["fpc", "-Mdelphi", "-vw", "-o" + exe, "-FE" + OUT, p] if comp == "fpc"
           else [PXX, p, exe])
    if subprocess.run(cmd, capture_output=True).returncode != 0:
        return "REFUSED"
    # BYTES, decoded latin-1, because a Char row prints the raw byte and 0xFF is
    # not valid UTF-8: text=True raised UnicodeDecodeError and took the whole
    # sweep with it. latin-1 round-trips every byte, so two different wrong
    # bytes still compare as different.
    r = subprocess.run([exe], capture_output=True, timeout=20)
    if r.returncode != 0:
        return "CRASH(%d)" % r.returncode
    return r.stdout.decode("latin-1").strip().replace("\n", " | ")

print("%-11s %-6s %-38s %-38s %s" % ("name", "route", "fpc", "pxx", "verdict"))
tally, res = {}, {}
rows = [(n, a) for n in NAMES for a in (False, True)]
rows.append(("__CONTROL__", False))
for name, viaAlias in rows:
    route = "alias" if viaAlias else "direct"
    if name == "__CONTROL__":
        # must-differ: the two sides are given different programs on purpose
        f = run("ctl", src("Byte", False).replace("v0 := 258", "v0 := 258"), "fpc")
        x = run("ctl", src("Byte", False).replace("v0 := 258", "v0 := 259"), "pxx")
    else:
        s = src(name, viaAlias)
        f, x = run("%s_%s" % (name, route), s, "fpc"), run("%s_%s" % (name, route), s, "pxx")
    if f == "REFUSED" and x == "REFUSED":   v = "both-refused"
    elif f == "REFUSED":                    v = "PXX-ONLY(no oracle)"
    elif x == "REFUSED":                    v = "PXX REFUSES"
    elif f == x:                            v = "agree"
    else:                                   v = "DIFFER"
    tally[v] = tally.get(v, 0) + 1
    res[(name, route)] = x
    print("%-11s %-6s %-38s %-38s %s" % (name, route, f, x, v))

print()
print("  ".join("%s=%d" % kv for kv in sorted(tally.items())), " total=%d" % len(rows))

# THE ROUTE TWIN CHECK. Both spellings are one request; a door that disagrees
# with its twin is the defect this family keeps producing, and it is visible
# even where fpc refuses both.
bad = [n for n in NAMES if res.get((n, "direct")) != res.get((n, "alias"))]
for n in bad:
    print("ROUTE MISMATCH  %-11s direct=%r alias=%r"
          % (n, res.get((n, "direct")), res.get((n, "alias"))))
if tally.get("DIFFER", 0) < 1:
    raise SystemExit("CONTROL FAILED: the must-differ row agreed, so this run "
                     "compared nothing and every agree above is vacuous")
if bad:
    raise SystemExit("%d type name(s) answer differently through the two routes" % len(bad))
print("route check: %d names answer identically direct and through an alias" % len(NAMES))
