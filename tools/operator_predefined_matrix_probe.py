#!/usr/bin/env python3
"""Which (operator, operand-pair) combinations does FPC consider ALREADY DEFINED?

FPC refuses `operator <op> (a, b: T)` exactly when the operation is predefined
for those operand types, and accepts it otherwise -- including plenty of pairs
that look built-in but are not (`operator ** (a, b: LongInt)`,
`operator >< (a, b: LongInt)`, `operator div (a, b: Single)`). pxx approximates
the rule as "at least one operand must be a record or class", which is much
stricter, so it refuses 91 of the 209 same-type cells fpc accepts.

This probe MEASURES the table rather than deriving it. It compiles one tiny
program per (op, T) cell with both compilers and reports three lists: what fpc
refuses (which IS the predefined table), what pxx accepts, and the count.

Run it before changing the declaration check in pasparser_call.inc, and again
after -- the fpc column is the specification and it must not move.
bug-p-the-operator-predefined-check-is-an-aggregate-approximation
"""
import os, subprocess, sys, tempfile
# Scratch OUTSIDE the repo: this writes a .pas plus fpc's unit output per cell,
# 209 of them, and /tmp is reaped on a 6h timer.
S = tempfile.mkdtemp(prefix='opmatrix-')
PXX = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   'compiler', 'pascal26')
OPS=['+','-','*','/','div','mod','shl','shr','and','or','xor','=','<>','<','<=','>','>=','><','**']
TYPES={
 'LongInt':'LongInt','AnsiString':'AnsiString','ShortString':'ShortString','Char':'Char',
 'Single':'Single','Double':'Double','Boolean':'Boolean','Pointer':'Pointer',
 'TSet':'TSet','TEnum':'TEnum','TRec':'TRec',
}
PRE = """{$mode objfpc}
program probe;
type
  TEnum = (eA, eB, eC);
  TSet  = set of TEnum;
  TRec  = record v: LongInt; end;
"""
def src(op, t1, t2, rt='LongInt'):
    return PRE + "operator %s (left: %s; right: %s) res : %s;\nbegin\nend;\nbegin\nend.\n" % (op, t1, t2, rt)
rows=[]
for op in OPS:
    for t in TYPES:
        p=os.path.join(S,'p.pas')
        open(p,'w').write(src(op,t,t))
        fdir=os.path.join(S,'fo'); os.makedirs(fdir, exist_ok=True)
        r=subprocess.run(['fpc','-Mobjfpc','-FE'+fdir,'-FU'+fdir,'-o'+fdir+'/o',p],
                         capture_output=True, text=True)
        fpc_ok = (r.returncode==0)
        r2=subprocess.run([PXX,p,os.path.join(S,'pb')],
                          capture_output=True, text=True)
        pxx_ok = (r2.returncode==0)
        rows.append((op,t,fpc_ok,pxx_ok))
print("FPC REFUSES (= the operation IS predefined for that operand pair):")
for op,t,f,x in rows:
    if not f: print("  %-4s %s" % (op,t))
print("--- pxx accepts (non-TRec):")
for op,t,f,x in rows:
    if x and t!='TRec': print("  %-4s %s" % (op,t))
print("--- fpc refuses count:", sum(1 for r in rows if not r[2]), "of", len(rows))
