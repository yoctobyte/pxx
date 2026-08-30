#!/usr/bin/env python3
"""The four-reader sweep's census, made executable.

Not a grep for the IDENT/FIELD shape -- that query is blind to a reader that
never had the logic. This enumerates every way C can REACH an array (the
spelling) crossed with every thing C can DO with one (the construct), and lets
gcc decide each cell.  A cell pxx gets wrong is a hole whether the code that
should handle it is divergent or absent.
"""
import os, subprocess, sys, tempfile

PRELUDE = r'''
#include <stdio.h>
#include <string.h>
struct Inner { int m[3][4]; char c[2][8]; };
struct S    { int m[3][4]; char c[2][8]; int t[2][3][4]; struct Inner in; };
struct S  gs;
struct S  garr[2];
struct S *gp;
int  gm[3][4];
char gc[2][8];
int  gt[2][3][4];
static void setup(void){
  int i,j,k;
  for(i=0;i<3;i++) for(j=0;j<4;j++){
    gm[i][j]=10*i+j; gs.m[i][j]=10*i+j; garr[0].m[i][j]=10*i+j; gs.in.m[i][j]=10*i+j;
  }
  for(i=0;i<2;i++) for(j=0;j<3;j++) for(k=0;k<4;k++){ gt[i][j][k]=100*i+10*j+k; gs.t[i][j][k]=100*i+10*j+k; }
  strcpy(gc[0],"ab"); strcpy(gc[1],"cd");
  strcpy(gs.c[0],"ab"); strcpy(gs.c[1],"cd");
  strcpy(garr[0].c[0],"ab"); strcpy(garr[0].c[1],"cd");
  strcpy(gs.in.c[0],"ab"); strcpy(gs.in.c[1],"cd");
  gp = &gs;
}
static int rowsum(int (*r)[4]){ return r[0][0] + r[0][3] + r[1][2]; }
'''

# how the array is REACHED.  {I} = an int[3][4], {C} = a char[2][8], {T} = an int[2][3][4]
SPELLINGS = [
  ("global-ident",   {"I": "gm",           "C": "gc",           "T": "gt"}),
  ("local-ident",    {"I": "lm",           "C": "lc",           "T": "lt"}),
  ("struct-field",   {"I": "gs.m",         "C": "gs.c",         "T": "gs.t"}),
  ("ptr-arrow",      {"I": "gp->m",        "C": "gp->c",        "T": "gp->t"}),
  ("nested-field",   {"I": "gs.in.m",      "C": "gs.in.c",      "T": None}),
  ("elem-of-array",  {"I": "garr[0].m",    "C": "garr[0].c",    "T": None}),
]

# what is DONE with it.  each entry: (name, which array, expression)
CONSTRUCTS = [
  ("row-stride",      "I", '(int)((char*)({I} + 1) - (char*)({I})))'),
  ("row-stride-2",    "I", '(int)((char*)({I} + 2) - (char*)({I})))'),
  ("partial-elem",    "I", '*({I}[1] + 1))'),
  ("partial-elem-2",  "I", '*({I}[2] + 3))'),
  ("noop-deref",      "I", '**{I})'),
  ("deref-plus",      "I", '*(*({I} + 1) + 2))'),
  ("deref-partial",   "I", '*{I}[2])'),
  ("sizeof",          "I", '(int)sizeof({I}))'),
  ("sizeof-row",      "I", '(int)sizeof({I}[0]))'),
  ("ptrdiff",         "I", '(int)(&{I}[1][0] - &{I}[0][0]))'),
  ("row-var",         "I", '(rv = {I} + 1, rv[0][2]))'),
  ("row-into-fn",     "I", 'rowsum({I}))'),
  ("row-into-ptr",    "I", '(ip = {I}[1], ip[2]))'),
  ("char-load",       "C", '(int)*{C}[1])'),
  ("char-noop-deref", "C", '(int)**{C})'),
  ("char-strcmp",     "C", 'strcmp(*({C} + 1), "cd"))'),
  ("char-row-stride", "C", '(int)((char*)({C} + 1) - (char*)({C})))'),
  ("3d-stride",       "T", '(int)((char*)({T} + 1) - (char*)({T})))'),
  ("3d-partial",      "T", '*(*({T}[1] + 2) + 3))'),
  ("3d-all-star",     "T", '*(*(*({T} + 1) + 2) + 3))'),
  ("3d-row-var",      "T", '(rv = {T}[1] + 1, rv[0][2]))'),
]

def source(expr):
    return (PRELUDE +
            "int main(void){ int lm[3][4]; char lc[2][8]; int lt[2][3][4];\n"
            "  int (*rv)[4]; int *ip; int i,j,k;\n"
            "  setup();\n"
            "  for(i=0;i<3;i++) for(j=0;j<4;j++) lm[i][j]=10*i+j;\n"
            "  for(i=0;i<2;i++) for(j=0;j<3;j++) for(k=0;k<4;k++) lt[i][j][k]=100*i+10*j+k;\n"
            "  strcpy(lc[0],\"ab\"); strcpy(lc[1],\"cd\");\n"
            "  (void)rv; (void)ip;\n"
            "  printf(\"%d\\n\", (int)(" + expr + ");\n"
            "  return 0; }\n")

def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=40, **kw)

tmp = sys.argv[1]
pxx = sys.argv[2]
rows = []
for cname, which, tmpl in CONSTRUCTS:
    for sname, arrays in SPELLINGS:
        arr = arrays.get(which)
        if arr is None:
            rows.append((cname, sname, "n/a", "n/a", "skip")); continue
        src = source(tmpl.format(**{which: arr}))
        cfile = os.path.join(tmp, "cell.c")
        open(cfile, "w").write(src)
        g = run(["gcc", "-w", "-O2", "-o", os.path.join(tmp, "cell_g"), cfile])
        if g.returncode != 0:
            rows.append((cname, sname, "REJECT", "-", "gcc-reject")); continue
        gr = run([os.path.join(tmp, "cell_g")])
        gv = gr.stdout.strip() if gr.returncode == 0 else "rc=%d" % gr.returncode
        p = run([pxx, cfile, os.path.join(tmp, "cell_p")])
        if p.returncode != 0:
            rows.append((cname, sname, gv, "COMPILE-FAIL", "FAIL")); continue
        pr = run([os.path.join(tmp, "cell_p")])
        pv = pr.stdout.strip() if pr.returncode == 0 else ("SIGSEGV" if pr.returncode == -11 else "rc=%d" % pr.returncode)
        rows.append((cname, sname, gv, pv, "ok" if gv == pv else "FAIL"))

hdr = ["construct"] + [s for s, _ in SPELLINGS]
w = max(len(c) for c, _, _ in CONSTRUCTS) + 1
print(("%-*s" % (w, "construct")) + "".join("%-16s" % s for s, _ in SPELLINGS))
byc = {}
for cname, sname, gv, pv, verdict in rows:
    byc.setdefault(cname, {})[sname] = (gv, pv, verdict)
nfail = 0
for cname, _, _ in CONSTRUCTS:
    line = "%-*s" % (w, cname)
    for sname, _ in SPELLINGS:
        gv, pv, verdict = byc[cname][sname]
        if verdict == "ok":         cell = "ok"
        elif verdict == "skip":     cell = "-"
        elif verdict == "gcc-reject": cell = "(gcc rej)"
        else:                       cell = "%s!=%s" % (gv, pv); nfail += 1
        line += "%-16s" % cell
    print(line)
print()
print("cells wrong: %d" % nfail)
