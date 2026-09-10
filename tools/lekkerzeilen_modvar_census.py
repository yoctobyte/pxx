#!/usr/bin/env python3
"""How many module bindings in the lekkerzeilen corpus are read through a
VARIABLE rather than resolved as a qualifier at parse time?

frankZ asked for this number on bug-n-a-module-bound-by-an-import-is-not-a-value
as the thing to get BEFORE choosing option 2 (rewrite the seam with `as`):
"how many of the 99 module bindings are read through a variable, not how many
are used as values."

The filter must ask the FILESYSTEM which bound names are modules -- nothing in
the AST distinguishes `from . import world` (a module) from
`from .world import World` (a class). That mistake is on the record: the first
cut of the sibling census said 267 and was wrong for exactly this reason.
"""
import ast, os, sys
from pathlib import Path

SELFTEST = '--selftest' in sys.argv
args = [a for a in sys.argv[1:] if not a.startswith('-')]

if SELFTEST:
    # POSITIVE CONTROL for the one way this census is known to go wrong: the
    # filter over-including ordinary variables. The first cut of the sibling
    # census said 267 for that reason, and the first cut of THIS one flagged 37
    # sites across traffic.py and ui.py -- `route, entry = ...` are plain
    # variables assigned from a call, not modules. Both controls are drawn from
    # that real failure, not invented.
    import tempfile, textwrap
    td = Path(tempfile.mkdtemp())
    pkg = td / 'lekkerzeilen'; (pkg / 'sub').mkdir(parents=True)
    (pkg / '__init__.py').write_text('')
    (pkg / 'realmod.py').write_text('B = 1\n')
    (pkg / 'other.py').write_text('def helper():\n    return 1, 2\n')
    # MUST be flagged: a variable holding a module, read through
    (pkg / 'wanted.py').write_text(textwrap.dedent('''
        from . import realmod
        def sel():
            return realmod, "x"
        mod, name = sel()
        v = mod.B
    '''))
    # MUST NOT be flagged: ordinary tuple-unpack from a call returning non-modules
    (pkg / 'decoy.py').write_text(textwrap.dedent('''
        from .other import helper
        route, entry = helper()
        a = route.end
        b = entry.height
    '''))
    ROOT = td
else:
    ROOT = Path(args[0] if args else '/home/neo/lekkerzeilen')
PKG  = ROOT / 'lekkerzeilen'

# --- which names are MODULES, per the filesystem, not per the AST ------------
def module_names(pkgdir):
    out = set()
    for p in pkgdir.rglob('*.py'):
        out.add(p.stem)
        if p.name == '__init__.py':
            out.add(p.parent.name)
    return out

MODS = module_names(PKG)

files = sorted(PKG.rglob('*.py'))
bindings = {}        # (file, name) -> how it was bound
var_reads = []       # name read through a VARIABLE (assigned from a module)
value_uses = []      # module name in bare value position

for f in files:
    try:
        tree = ast.parse(f.read_text(encoding='utf-8'), filename=str(f))
    except SyntaxError as e:
        print(f"  SKIP (syntax) {f.relative_to(ROOT)}: {e}", file=sys.stderr)
        continue
    rel = f.relative_to(ROOT)

    # pass 1: names bound to a module in THIS file
    modbound = {}
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            for a in n.names:
                base = a.name.split('.')[0]
                nm = a.asname or base
                if base in MODS or a.name.split('.')[-1] in MODS:
                    modbound[nm] = f"import {a.name}" + (f" as {a.asname}" if a.asname else "")
        elif isinstance(n, ast.ImportFrom):
            for a in n.names:
                if a.name in MODS:                 # from . import <module>
                    nm = a.asname or a.name
                    modbound[nm] = f"from {'.'*(n.level or 0)}{n.module or ''} import {a.name}" + \
                                   (f" as {a.asname}" if a.asname else "")
    for nm, how in modbound.items():
        bindings[(str(rel), nm)] = how

    # pass 2: ASSIGNMENTS whose VALUE is a module name -> creates a variable
    #         holding a module, which is the shape that needs the feature
    # which local functions RETURN a module name? (the seam's `_select_backend`)
    modreturning = set()
    for fn in ast.walk(tree):
        if isinstance(fn, (ast.FunctionDef, ast.AsyncFunctionDef)):
            for r in ast.walk(fn):
                if isinstance(r, ast.Return) and r.value is not None:
                    rets = r.value.elts if isinstance(r.value, ast.Tuple) else [r.value]
                    if any(isinstance(e, ast.Name) and e.id in modbound for e in rets):
                        modreturning.add(fn.name)
    aliasvars = {}
    for n in ast.walk(tree):
        if isinstance(n, (ast.Assign, ast.AnnAssign)):
            val = n.value
            tgts = n.targets if isinstance(n, ast.Assign) else [n.target]
            # x = <modulename>            (bare)
            if isinstance(val, ast.Name) and val.id in modbound:
                for t in tgts:
                    if isinstance(t, ast.Name):
                        aliasvars[t.id] = (val.id, n.lineno)
            # x, y = f()  -- ONLY when f's own `return` yields a module name.
            # Assuming any tuple-unpack might hold a module is how the sibling
            # census got 267: `route, entry = ...` are ordinary variables. The
            # filter has to prove the callee returns a module.
            elif isinstance(val, ast.Call) and isinstance(val.func, ast.Name) \
                 and val.func.id in modreturning:
                for t in tgts:
                    names = t.elts if isinstance(t, ast.Tuple) else [t]
                    for el in names:
                        if isinstance(el, ast.Name):
                            aliasvars.setdefault(el.id, (f'{val.func.id}() returns a module', n.lineno))

    # pass 3: reads THROUGH those variables
    for n in ast.walk(tree):
        if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name) \
           and n.value.id in aliasvars:
            src, bl = aliasvars[n.value.id]
            var_reads.append((str(rel), n.lineno, f"{n.value.id}.{n.attr}", src))
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id == 'getattr' \
           and n.args and isinstance(n.args[0], ast.Name) and n.args[0].id in aliasvars:
            var_reads.append((str(rel), n.lineno, f"getattr({n.args[0].id}, ...)", 'GETATTR'))

    # pass 4: module name in BARE value position (the original ticket's count)
    parents = {}
    for p in ast.walk(tree):
        for c in ast.iter_child_nodes(p):
            parents[id(c)] = p
    for n in ast.walk(tree):
        if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load) and n.id in modbound:
            p = parents.get(id(n))
            if isinstance(p, ast.Attribute) and p.value is n:   # two.B -> qualifier
                continue
            if isinstance(p, ast.Call) and p.func is n:          # two() -> call
                continue
            value_uses.append((str(rel), n.lineno, n.id))

print(f"corpus: {ROOT}   modules on disk: {len(MODS)}   .py files: {len(files)}")
print(f"module BINDINGS (name bound to a module): {len(bindings)}")
print()
print(f"=== module name in BARE VALUE position: {len(value_uses)} site(s) ===")
for r, l, nm in value_uses:
    print(f"  {r}:{l}  {nm}")
print()
print(f"=== read THROUGH A VARIABLE holding a module: {len(var_reads)} site(s) ===")
seen_files = set()
for r, l, expr, src in sorted(var_reads):
    seen_files.add(r)
    print(f"  {r}:{l}  {expr:38s} (var from {src})")
print()
print(f"files touched by the variable-read shape: {len(seen_files)}")
getattrs = [v for v in var_reads if v[3] == 'GETATTR']
print(f"of which GETATTR sites (option 2 cannot serve these): {len(getattrs)}")


if SELFTEST:
    ok = True
    wanted = [v for v in var_reads if v[0].endswith('wanted.py')]
    decoy  = [v for v in var_reads if v[0].endswith('decoy.py')]
    if not wanted:
        print("SELFTEST FAIL: a variable holding a module, read through, was NOT flagged"); ok = False
    else:
        print(f"selftest: positive control flagged ({len(wanted)} site(s)) - the census can fire")
    if decoy:
        print(f"SELFTEST FAIL: {len(decoy)} ordinary variable(s) flagged as module-holding:")
        for d in decoy: print("   ", d)
        print("    this is the 267/37 over-inclusion bug; the filter must prove the callee returns a module")
        ok = False
    else:
        print("selftest: negative control clean - ordinary tuple-unpack from a call is not flagged")
    sys.exit(0 if ok else 1)
