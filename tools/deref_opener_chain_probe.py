#!/usr/bin/env python3
"""Openers x chains for `a . on a value that is still a POINTER`.

Every row is one program, compiled by pxx and by fpc 3.2.2 -Mdelphi -O1, and
the two outputs compared. The openers are the axis: the same chain off a plain
pointer VARIABLE has always been right, so a row that differs names the opener.
Row `ctl` is the must-differ control -- if it agrees, the harness is not
comparing anything.
"""
import os, subprocess, sys, tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PXX = os.environ.get("PXX", os.path.join(REPO, "compiler", "pascal26"))
OUT = os.environ.get("DEREF_OUT") or tempfile.mkdtemp(prefix="derefrows.")
os.makedirs(OUT, exist_ok=True)

HEAD = """program row;
{$mode delphi}
type
  TRec = record
    a, b: Integer;
    function GetA: Integer;
    property PA: Integer read GetA;
  end;
  PRec  = ^TRec;
  PPRec = ^PRec;
  PPPRec = ^PPRec;
function TRec.GetA: Integer; begin Result := a; end;
var r: TRec; p: PRec; pp: PPRec; ppp: PPPRec; q, qq, qqq: Pointer;
function GetP: PRec; begin Result := p; end;
function GetPP: PPRec; begin Result := pp; end;
begin
  r.a := 11; r.b := 22;
  p := @r; pp := @p; ppp := @pp;
  q := @r; qq := @p; qqq := @pp;
"""
TAIL = "end.\n"

# (opener label, expression prefix that yields a value still needing N implicit derefs)
OPENERS = [
    ("var1",    "p"),
    ("var2",    "pp^"),
    ("var3",    "ppp^^"),
    ("cast1",   "PRec(q)"),
    ("cast2",   "PPRec(qq)^"),
    ("cast3",   "PPPRec(qqq)^^"),
    ("callres1","GetP"),
    ("callres2","GetPP^"),
    ("varexpl", "p^"),        # already a record: the implicit rule must NOT fire
    ("castexpl","PRec(q)^"),
]
CHAINS = [
    ("field",  ".a"),
    ("field2", ".b"),
    ("method", ".GetA"),
    ("prop",   ".PA"),
]

rows = []
for oname, opener in OPENERS:
    for cname, chain in CHAINS:
        rows.append((f"{oname}_{cname}", f"  WriteLn('v=', {opener}{chain});\n"))
rows.append(("ctl_mustdiffer", "  WriteLn('v=', r.a + 900);\n"))

def run(src, tag):
    pas = os.path.join(OUT, tag + ".pas")
    open(pas, "w").write(src)
    pb = os.path.join(OUT, tag + ".pxx")
    rp = subprocess.run([PXX, pas, pb], capture_output=True, text=True)
    if rp.returncode != 0:
        pxx = ("REFUSED", rp.stdout + rp.stderr)
    else:
        rr = subprocess.run([pb], capture_output=True, text=True)
        pxx = ("OK", rr.stdout)
    fb = os.path.join(OUT, tag + ".fpc")
    rf = subprocess.run(["fpc", "-Mdelphi", "-O1", "-vw", pas, "-o" + tag + ".fpc"],
                        capture_output=True, text=True, cwd=OUT)
    if rf.returncode != 0:
        fpc = ("REFUSED", rf.stdout)
    else:
        rr = subprocess.run([fb], capture_output=True, text=True)
        fpc = ("OK", rr.stdout)
    return pxx, fpc

if not os.path.exists(PXX):
    sys.exit("no compiler at %s -- set PXX or run `make compiler/pascal26`" % PXX)
print("probe: PXX=%s" % PXX)
print("probe: rows land in %s" % OUT)

agree = differ = pxxref = fpcref = both = 0
control_differed = False
for tag, body in rows:
    src = HEAD + body + TAIL
    if tag == "ctl_mustdiffer":
        # the control: pxx sees +900, fpc sees +901 -- they MUST differ
        pxx, _ = run(HEAD + "  WriteLn('v=', r.a + 900);\n" + TAIL, tag + "_A")
        _, fpc = run(HEAD + "  WriteLn('v=', r.a + 901);\n" + TAIL, tag + "_B")
    else:
        pxx, fpc = run(src, tag)
    if pxx[0] == "REFUSED" and fpc[0] == "REFUSED":
        v = "both-refused"; both += 1
    elif pxx[0] == "REFUSED":
        v = "PXX-REFUSES"; pxxref += 1
    elif fpc[0] == "REFUSED":
        v = "fpc-refuses"; fpcref += 1
    elif pxx[1] == fpc[1]:
        v = "agree"; agree += 1
    else:
        v = "DIFFER"; differ += 1
    if tag == "ctl_mustdiffer":
        control_differed = (v == "DIFFER")
    print(f"{tag:22s} {v}")
    if v == "DIFFER":
        print(f"      pxx: {pxx[1].strip()!r}")
        print(f"      fpc: {fpc[1].strip()!r}")
print(f"\nagree={agree} DIFFER={differ} PXX-REFUSES={pxxref} fpc-refuses={fpcref} "
      f"both-refused={both} total={len(rows)}")
print("note: the ctl_mustdiffer row is counted in DIFFER -- subtract 1 for real disagreements")

# Branch on the control. A precondition you do not branch on is a comment:
# without this, a harness that compiled nothing at all still prints a table.
if not control_differed:
    sys.exit("CONTROL FAILED: ctl_mustdiffer did not differ, so this run compared "
             "nothing and every 'agree' above is vacuous")
