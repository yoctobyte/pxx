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

TWO FAMILIES, and the second exists because the first was GREEN while six
defects sat in the alias door (2026-09-06). The first family sweeps 29
integer/char/boolean NAMES at 3 truncating VALUES, storing each result in a
variable of the cast type. Its three exclusions do not look like exclusions:
the names are all ONE CATEGORY, the operand is always an Int64, and STORING the
result is the position that HIDES a reinterpret because the store coerces. So
the second family holds the route axis and varies the target CATEGORY, the
operand KIND, the RESULT POSITION and a file-scoped DIRECTIVE instead.

Positive control, run against the pre-fix binary (tree at 4be17cb8f): the
category family reports 4 DIFFER and 7 route mismatches -- the three
identifier-spelled float names reinterpreting, a variant alias reading the tag
word, an enum alias losing its identity with and without {$PACKENUM 1}, and an
`operator Explicit` answering at one door only. It is clean at HEAD.

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

# THE NAME SET IS THE UNION OF WHAT THE DOORS RECOGNISE, not a list of the ones
# I thought of. BuiltinScalarTypeKind's own table is the widest and is read out
# of the source (symtab.inc); a name that one door knows and another does not is
# precisely the defect this family produces, so a sweep drawn from the
# intersection would be green by construction.
NAMES = ["Byte", "ShortInt", "SmallInt", "Word", "Integer", "LongInt",
         "Cardinal", "LongWord", "DWord", "Int64", "QWord", "UInt64",
         "NativeInt", "PtrInt", "Int8", "UInt8", "Int16", "UInt16",
         "Int32", "UInt32", "Boolean", "Char", "AnsiChar", "WideChar",
         # ...and the tail of BuiltinScalarTypeKind's table that no earlier
         # sweep in this family covered:
         "SizeInt", "SizeUInt", "NativeUInt", "PtrUInt", "TSystemCodePage"]
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

# ---------------------------------------------------------------------------
# THE SECOND FAMILY, and it exists because the sweep above was GREEN while six
# defects sat in the alias door (2026-09-06, all fixed: 96d805e3d, 8d5f89579,
# 0a9ae4cca, 1e0323c82). Every one of them was outside its population, and the
# three exclusions are worth naming because none of them looks like an exclusion:
#
#   1. NAMES is entirely the INTEGER/CHAR/BOOLEAN family. The float names, the
#      variant names, enums and the four float KEYWORDS were never in it, and a
#      cast's behaviour is decided by the target's CATEGORY far more than by
#      which integer name it is. 29 names, one category.
#   2. THE OPERAND IS ALWAYS AN Int64. A record with an `operator Explicit`, an
#      already-variant value and a Double reach different arms entirely.
#   3. THE RESULT IS ALWAYS STORED IN A VARIABLE OF THE CAST TYPE. That is
#      CLAUDE.md's compatibility test and it is right for the truncation
#      question above -- and it is the one position that HIDES a reinterpret,
#      because the store coerces. `c := Currency(i)` was correct at both doors
#      while `Show(Currency(i))` handed on the integer's bit pattern.
#
# So these rows hold the ROUTE axis and vary the target CATEGORY, the operand
# KIND and the RESULT POSITION -- passing the cast to a procedure rather than
# storing it. fpc refuses several of them outright (`Currency(LongInt)` is an
# "Illegal type conversion"), which is not a problem: the twin check compares
# our two routes with each other and needs no oracle to do it.
# The PRINTER column is load-bearing and one row taught it the hard way. A
# typed procedure parameter carries the target type, so `ShowE(TAlias(i))`
# reconstructs an enum identity the cast node had already lost, and the row
# scored agree/agree against a binary where the defect was live. Rows whose
# defect is a lost IDENTITY must print INLINE (printer ""); rows whose defect is
# a REPRESENTATION -- a float reinterpret, a variant tag read -- are safe through
# a parameter and read better there. That is CLAUDE.md's "store it in its
# declared type" rule pointing the OTHER WAY: the position that proves a value
# is right is the position that hides a lost identity.
#
# The DIRECTIVE column exists because {$PACKENUM 1} narrows an enum's storage
# kind from tyInteger to tyUInt8, and a guard written on the layout kind is a
# bet that the layout kind never narrows. Each category row is its own program,
# so a FILE-SCOPED directive can be an axis here even though it cannot be one
# inside a single test file.
CATEGORY_ROWS = [
    # label            target       extra decls              operand + init          printer directive
    ("float-currency",  "Currency",  "",                   "i: LongInt; i := 7",     "Show",  ""),
    ("float-tdatetime", "TDateTime", "",                   "i: LongInt; i := 7",     "Show",  ""),
    ("float-valreal",   "ValReal",   "",                   "i: LongInt; i := 7",     "Show",  ""),
    ("float-keyword",   "Extended",  "",                   "i: LongInt; i := 7",     "Show",  ""),
    ("variant-of-int",  "Variant",   "",                   "i: LongInt; i := 233",   "ShowV", ""),
    ("variant-of-var",  "Variant",   "",                   "v: Variant; v := 41",    "ShowV", ""),
    ("int-of-variant",  "Int64",     "",                   "v: Variant; v := 41",    "ShowI", ""),
    ("enum",            "TEnum",     "TEnum = (eA, eB, eC);", "i: LongInt; i := 1",  "",      ""),
    ("enum-packed",     "TEnum",     "TEnum = (eA, eB, eC);", "i: LongInt; i := 1",  "",      "{$PACKENUM 1}"),
    ("explicit-op",     "Integer",   None,                 "f: TFoo; f.v := 4",      "ShowI", ""),
]

FOO = ("  TFoo = record v: Integer;\n"
       "    class operator Explicit(a: TFoo): Integer;\n  end;\n")

def catsrc(row, viaAlias):
    label, target, extra, operand, printer, directive = row
    decl, init = operand.split(";", 1)
    ty = "TCatAlias" if viaAlias else target
    types = ""
    if extra is None:                 # the Explicit row needs the record type
        types += FOO
        impl = ("class operator TFoo.Explicit(a: TFoo): Integer;\n"
                "begin Result := a.v * 10; end;\n")
    else:
        types += ("  " + extra + "\n") if extra else ""
        impl = ""
    types += "  TCatAlias = %s;\n" % target
    shows = {
        "Show":  "procedure Show(d: Double);\nbegin WriteLn(d:0:4); end;\n",
        "ShowV": "procedure ShowV(v: Variant);\nbegin WriteLn(v); end;\n",
        "ShowI": "procedure ShowI(i: Int64);\nbegin WriteLn(i); end;\n",
        "": "",
    }[printer]
    arg = decl.split(":")[0].strip()
    call = ("WriteLn(%s(%s))" % (ty, arg) if printer == ""
            else "%s(%s(%s))" % (printer, ty, arg))
    return ("program scdcat;\n{$mode delphi}\n%s\ntype\n%s%s%s"
            "var %s;\nbegin\n %s;\n  %s;\nend.\n"
            % (directive, types, impl, shows, decl, init.strip(), call))

print()
print("%-16s %-6s %-26s %-26s %s" % ("category", "route", "fpc", "pxx", "verdict"))
cres, ctally = {}, {}
for row in CATEGORY_ROWS:
    for viaAlias in (False, True):
        route = "alias" if viaAlias else "direct"
        s = catsrc(row, viaAlias)
        tag = "cat_%s_%s" % (row[0], route)
        f, x = run(tag, s, "fpc"), run(tag, s, "pxx")
        if f == "REFUSED" and x == "REFUSED":   v = "both-refused"
        elif f == "REFUSED":                    v = "PXX-ONLY(no oracle)"
        elif x == "REFUSED":                    v = "PXX REFUSES"
        elif f == x:                            v = "agree"
        else:                                   v = "DIFFER"
        ctally[v] = ctally.get(v, 0) + 1
        cres[(row[0], route)] = x
        print("%-16s %-6s %-26s %-26s %s" % (row[0], route, f, x, v))

print("  ".join("%s=%d" % kv for kv in sorted(ctally.items())),
      " category rows=%d" % (2 * len(CATEGORY_ROWS)))
cbad = [r[0] for r in CATEGORY_ROWS
        if cres.get((r[0], "direct")) != cres.get((r[0], "alias"))]
for n in cbad:
    print("ROUTE MISMATCH  %-16s direct=%r alias=%r"
          % (n, cres.get((n, "direct")), cres.get((n, "alias"))))
if any(v == "REFUSED" for v in cres.values()) and not cbad:
    print("note: a row pxx REFUSES at BOTH routes is twin-consistent and says "
          "nothing -- read the table, not only the exit code")
if cbad:
    raise SystemExit("%d category row(s) answer differently through the two routes"
                     % len(cbad))
print("category check: %d rows answer identically direct and through an alias"
      % len(CATEGORY_ROWS))
