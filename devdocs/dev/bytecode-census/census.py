#!/usr/bin/env python3
"""Bytecode-VM census: estimate a register-VM bytecode from pxx's --dump-ir.

Usage: census.py IR_DUMP SRC_DIR NATIVE_OBJ [NAME,NAME,...]

IR_DUMP is the output of a compiler built with dump-ir-scope.patch (which adds
the symbol kind, so locals and globals can be told apart). App procedures are
those whose last name component is declared (procedure/function/def) in
SRC_DIR, or exactly the comma-separated NAMEs when given. NATIVE_OBJ is the
same compile's object; native sizes come from symbol spacing (nm -n).

The cost model is a rough per-IR-node estimate, documented in
devdocs/dev/bytecode-vm-format-proposal.md. Static counts, not dynamic.
"""
import re,collections,subprocess,sys
OPS={30:'and',31:'or',33:'div',34:'mod',64:'eq',65:'ne',66:'lt',67:'le',68:'gt',69:'ge',70:'add',71:'sub',72:'mul',73:'fdiv',103:'shl',117:'xor',147:'shr?'}
CMP={'eq','ne','lt','le','gt','ge'}
app=set()
for f in subprocess.run("ls "+sys.argv[2]+"/*",shell=True,capture_output=True,text=True).stdout.split():
    for m in re.finditer(r'^\s*(?:procedure|function|def)\s+([\w.]+)',open(f,errors='replace').read(),re.M|re.I):
        app.add(m.group(1).split('.')[-1].lower()); app.add('create')
procs=[];cur=None
rx=re.compile(r'^(\d+): (\S+) a=(-?\d+) b=(-?\d+) c=(-?\d+) ival=(-?\d+) tk=(\d+)(.*)')
for line in open(sys.argv[1]):
    if line.startswith('PXXDBG'):
        cur={'name':line.split()[-1],'n':[]};procs.append(cur);continue
    m=rx.match(line)
    if m and cur is not None:
        i,k,a,b,c,iv,tk,rest=m.groups()
        sm=re.search(r'\[sym=(\S+) k=(\d)\]',rest); pm=re.search(r'\[proc=(\S+)\]',rest)
        cur['n'].append(dict(k=k,a=int(a),b=int(b),c=int(c),iv=int(iv),tk=int(tk),sym=sm.group(1) if sm else None,sk=int(sm.group(2)) if sm else None,callee=pm.group(1) if pm else None))
# dedupe by name (keep last)
byname={}
for p in procs: byname[p['name']]=p
if len(sys.argv)>4:
    APP=set(sys.argv[4].split(','))
else:
    APP={n for n in byname if n.split('.')[-1].split('$')[0].lower() in app}
ap=[p for n,p in byname.items() if n in APP]
print('procs dumped',len(byname),'app procs',len(ap),'app IR nodes',sum(len(p['n']) for p in ap))
STRTK=None
opfreq=collections.Counter(); totals=collections.Counter()
regs=[];imm=collections.Counter();dist=[];perproc={}
for p in ap:
    N=p['n']; users=collections.defaultdict(list)
    for i,n in enumerate(N):
        for f in ('a','b','c'):
            pass
    # operand references: per kind
    ref=lambda n:[n['a'],n['b']] if n['k'] in('binop',) else ([n['b']] if n['k'] in('store_sym','jump_if_false','arg','store_mem','field','index','load_mem','not','neg') else [])
    for i,n in enumerate(N):
        for r in ref(n):
            if 0<=r<len(N): users[r].append(i)
        if n['k']=='store_mem' and 0<=n['a']<len(N): users[n['a']].append(i)
        if n['k']=='index' and 0<=n['a']<len(N): users[n['a']].append(i)
    cnt=0; pos={}; labelpos={}; branches=[]
    locs=set()
    for i,n in enumerate(N):
        k=n['k']; c=0; op=None
        if k=='load_sym':
            if n['sk']==1: c=1; op='ld.global'
            else: locs.add(n['sym'])
        elif k=='store_sym':
            if n['sk']!=1: locs.add(n['sym'])
            v=N[n['b']] if 0<=n['b']<len(N) else None
            if n['tk']==23 or (v and v['tk']==23 and v['k'] in('load_sym','const_str')): c=1; op='str.assign'
            elif n['sk']==1: c=1; op='st.global'
            elif v and v['k'] in('load_sym','const_int'): c=1 if v['k']=='load_sym' else 0; op='mov' if c else None
        elif k=='const_int':
            v=n['iv']; us=[N[u]['k'] for u in users[i]]
            b=('imm5' if -16<=v<16 else 'imm7' if -64<=v<64 else 'imm14' if -8192<=v<8192 else 'imm22' if -(1<<21)<=v<(1<<21) else 'pool32/64')
            imm[b]+=1
            if us and all(u in('binop','jump_if_false') for u in us) and b in('imm5','imm7'): c=0
            else: c=1; op='li' if b!='pool32/64' else 'ld.pool'
        elif k=='binop':
            o=OPS.get(n['c'],'op%d'%n['c'])
            us=[N[u]['k'] for u in users[i]]
            if o in CMP and us==['jump_if_false']: c=0
            else: c=1; op=o+'.'+str(n['tk'])
        elif k=='jump_if_false':
            cond=N[n['b']] if 0<=n['b']<len(N) else None
            c=1
            if cond and cond['k']=='binop' and OPS.get(cond['c']) in CMP:
                ot=N[cond['a']]['tk'] if 0<=cond['a']<len(N) else 0
                op='br.'+OPS[cond['c']]+'.tk'+str(ot)
            else: op='br.false'
            branches.append((cnt,n['a']))
        elif k=='jump': c=1; op='jmp'; branches.append((cnt,n['a']))
        elif k=='label': labelpos[n['iv']]=cnt
        elif k=='terminate': c=1; op='ret'
        elif k=='call':
            c=1; op='call:'+(n['callee'] or '?')
        elif k=='arg':
            v=N[n['b']] if 0<=n['b']<len(N) else None
            if v and v['k'] in('load_sym','const_int','const_str'): c=1; op='mov.arg'
        elif k in('block','nop','field'): c=0
        elif k=='index': c=1; op='index'
        elif k=='const_str': c=1; op='ld.str'
        else: c=1; op=k
        if op: opfreq[op]+=c if c else 0
        if op and c: totals['instr']+=c
        cnt+=c
    for at,lab in branches:
        if lab in labelpos: dist.append(abs(labelpos[lab]-at))
    regs.append(len(locs)); perproc[p['name']]=cnt
tot=sum(perproc.values())
print('estimated VM instructions',tot,'=> bytes at 4/instr',tot*4)
# native size of app procs
out=subprocess.run(['nm','-n',sys.argv[3]],capture_output=True,text=True).stdout.split('\n')
syms=[(int(l.split()[0],16),l.split()[2]) for l in out if len(l.split())==3 and l.split()[1] in 'tT']
nat={}
for (a,n),(b,_) in zip(syms,syms[1:]+[(None,None)]):
    if b is not None: nat[n]=b-a
natapp=sum(v for n,v in nat.items() if n in APP)
print('native .text of app procs (rv32, from symbol spacing)',natapp)
print('\nTOP VM ops (by static count):')
print("calls total",sum(v for o,v in opfreq.items() if o.startswith("call:")));
for o,v in opfreq.most_common(45): print('%6d  %s'%(v,o))
def pct(xs,q): xs=sorted(xs); return xs[min(len(xs)-1,int(q*len(xs)))]
print('\nlocals+params per proc: median',pct(regs,.5),'p90',pct(regs,.9),'max',max(regs),' >16:',sum(r>16 for r in regs),' >128:',sum(r>128 for r in regs),'of',len(regs))
print('branch distance (VM instrs): median',pct(dist,.5),'p90',pct(dist,.9),'p99',pct(dist,.99),'max',max(dist),' >127:',sum(d>127 for d in dist),'of',len(dist))
print('immediates:',dict(imm))
import collections as C
h=C.Counter(regs); print('locals histogram',sorted(h.items()))
print('procs >8:',sum(r>8 for r in regs),' instr in procs >8:',sum(perproc[p['name']] for p,r in zip(ap,regs) if r>8),'of',tot)
g=C.Counter()
for o,v in opfreq.items(): g['call' if o.startswith('call:') else o]+=v
tot2=sum(g.values()); acc=0
for i,(o,v) in enumerate(g.most_common()):
    acc+=v
    if i+1 in (15,24,31,48,64): print('top',i+1,'ops cover %.1f%%'%(100*acc/tot2))
print('distinct ops',len(g))
import sys; sys.setrecursionlimit(100000)
peaks=[];maxargs=[]
for p,nloc in zip(ap,regs):
    N=p['n']; memo={}
    def args(i):
        out=[]; j=N[i]['b'] if N[i]['k']=='call' else -1
        while 0<=j<len(N) and N[j]['k']=='arg' and len(out)<64: out.append(N[j]['a']); j=N[j]['b']
        return out
    def need(i):
        if not(0<=i<len(N)): return 0
        if i in memo: return memo[i]
        n=N[i];k=n['k'];r=1
        if k=='load_sym' and n['sk']!=1: r=0
        elif k=='const_int' and -16<=n['iv']<16: r=0
        elif k=='call':
            a=args(i); r=max([1,len(a)]+[ix+need(x) for ix,x in enumerate(a)])
        elif k in('binop','store_mem','index'):
            la,lb=need(n['a']),need(n['b']); r=max(1,la+1 if la==lb else max(la,lb))
        elif k in('neg','not','load_mem','field','store_sym','jump_if_false','arg'):
            r=max(1 if k not in('store_sym','jump_if_false') else 0,need(n['a'] if k in('neg','not','load_mem','field','arg') else n['b']))
        memo[i]=r; return r
    used=set()
    for n in N:
        for f in('a','b'):
            if n['k'] not in('load_sym','store_sym','lea','call','label','jump','jump_if_false') or f=='b': used.add(n[f])
    t=max([need(i) for i in range(len(N))]+[0])
    ma=max([len(args(i)) for i,n in enumerate(N) if n['k']=='call']+[0])
    peaks.append(nloc+t); maxargs.append(ma)
print('peak regs (named + expression temps): median',pct(peaks,.5),'p90',pct(peaks,.9),'max',max(peaks))
print('peak histogram',sorted(C.Counter(peaks).items()))
print('max call args: median',pct(maxargs,.5),'max',max(maxargs))
for lim in (8,16,32): print('instr in procs with peak >',lim,':',sum(perproc[p['name']] for p,r in zip(ap,peaks) if r>lim))
for (p,r,pk) in zip(ap,regs,peaks): print(p["name"], perproc[p["name"]], len(p["n"]), r, pk, nat.get(p["name"]))
