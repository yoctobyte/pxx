#!/usr/bin/env python3
"""What would --dce be worth on a wasm32 module, measured from the OUTSIDE.

Independent of pxx's own tables on purpose: the call graph comes from wabt's
disassembler, the roots from wabt's section dump. If this and a future
in-compiler pass agree, they agree from two decoders, not one.

Roots are the REAL entry points -- exports named _start/main, plus every
element-segment entry (address-taken, reachable by call_indirect) -- and
NOT the blanket per-routine export the wasm32 backend currently emits.
That is the whole question: the blanket export makes every body a root.
"""
import re, subprocess, sys, collections

mod = sys.argv[1]
REAL_ENTRY = set(sys.argv[2].split(',')) if len(sys.argv) > 2 else {'_start', 'main'}

def run(*a):
    return subprocess.run(['wasm-objdump', *a, mod], capture_output=True, text=True).stdout

# --- sizes and the defined/import split -------------------------------------
x = run('-h')
n_imp_func = len(re.findall(r'^ - func\[', run('-x', '-j', 'Import'), re.M))

# --- roots ------------------------------------------------------------------
roots, exported = set(), {}
for m in re.finditer(r'^ - func\[(\d+)\](?: <([^>]*)>)? -> "([^"]*)"', run('-x', '-j', 'Export'), re.M):
    idx, _sym, name = int(m.group(1)), m.group(2), m.group(3)
    exported.setdefault(idx, []).append(name)
    if name in REAL_ENTRY:
        roots.add(idx)
elem_roots = set()
for m in re.finditer(r'ref\.func:(\d+)', run('-x', '-j', 'Elem')):
    elem_roots.add(int(m.group(1)))
roots |= elem_roots

# --- the call graph, and each body's byte extent ----------------------------
edges = collections.defaultdict(set)
size, name_of, cur = {}, {}, None
starts = []
for line in run('-d').splitlines():
    h = re.match(r'^([0-9a-f]+) func\[(\d+)\](?: <(.*)>)?:', line)
    if h:
        cur = int(h.group(2)); name_of[cur] = h.group(3) or ''
        starts.append((int(h.group(1), 16), cur)); continue
    if cur is None: continue
    c = re.search(r'\|\s+call (\d+)', line)
    if c: edges[cur].add(int(c.group(1)))
# extent = distance to the next function header; the last runs to the section end
code_end = int(re.search(r'Code start=0x[0-9a-f]+ end=0x([0-9a-f]+)', x).group(1), 16)
for i, (off, f) in enumerate(starts):
    size[f] = (starts[i+1][0] if i+1 < len(starts) else code_end) - off

# --- reachability -----------------------------------------------------------
live, work = set(), list(roots)
while work:
    f = work.pop()
    if f in live: continue
    live.add(f)
    work.extend(edges.get(f, ()))

defined = set(size)
live_def = live & defined
dead = defined - live_def
lb = sum(size[f] for f in live_def)
db = sum(size[f] for f in dead)

print(f'module           {mod}')
print(f'imported funcs   {n_imp_func}')
print(f'defined funcs    {len(defined)}   code {lb+db}B')
print(f'exports (func)   {sum(len(v) for v in exported.values())} naming {len(exported)} distinct functions'
      f'  -- {len(set(exported) & defined)} of {len(defined)} defined bodies are exported')
print(f'roots            {len(roots)}  = entry {sorted(roots & set(i for i,v in exported.items() if set(v) & REAL_ENTRY))}'
      f' + {len(elem_roots)} table entries')
print(f'LIVE             {len(live_def)} bodies, {lb}B')
print(f'DEAD             {len(dead)} bodies, {db}B   ({100.0*db/(lb+db):.1f}% of the code section)')
