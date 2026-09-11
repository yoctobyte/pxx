#!/usr/bin/env python3
"""SECOND FILTER for "which packages guard an import?", built to fail DIFFERENTLY
from the grep that produced the first answer.

The first filter was `grep -rln 'except ImportError'`. It is TEXTUAL, so it misses
every guard whose handler is not spelled with that literal:
    except Exception:        except:          except ModuleNotFoundError:
    except (OSError, ImportError) via an alias, importlib.util.find_spec, ...
This one is STRUCTURAL: any ast.Try whose body (at any depth) contains an Import
or ImportFrom, whatever the handlers say -- plus it reports the handler spelling,
so a disagreement between the two filters is visible rather than silent.
"""
import ast, sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else '/home/neo/lekkerzeilen')
PKG = ROOT / 'lekkerzeilen'

def handler_names(h):
    if h.type is None: return 'bare except'
    return ast.unparse(h.type)

rows = []
for f in sorted(PKG.rglob('*.py')):
    try: tree = ast.parse(f.read_text(encoding='utf-8'), filename=str(f))
    except SyntaxError as e:
        print(f"  SKIP {f.relative_to(ROOT)}: {e}", file=sys.stderr); continue
    for n in ast.walk(tree):
        if not isinstance(n, ast.Try): continue
        imps = [x for b in n.body for x in ast.walk(b)
                if isinstance(x, (ast.Import, ast.ImportFrom))]
        if not imps: continue
        spell = [ast.unparse(i).strip() for i in imps]
        hs = ' | '.join(handler_names(h) for h in n.handlers) or '(no handler)'
        rows.append((str(f.relative_to(ROOT)), n.lineno, spell, hs))

print(f"corpus {ROOT}   .py files scanned: {len(list(PKG.rglob('*.py')))}")
print(f"=== try/except blocks containing an import: {len(rows)} ===")
seen = set()
for rel, ln, spell, hs in rows:
    seen.add(rel)
    print(f"  {rel}:{ln}")
    for sp in spell: print(f"      {sp}")
    print(f"      handlers: {hs}")
print()
print(f"FILES with a guarded import: {len(seen)}")
for r in sorted(seen): print(f"  {r}")
print()
# which of those files are PACKAGE inits (the shape that breaks an importer)?
inits = [r for r in seen if r.endswith('__init__.py')]
print(f"of which PACKAGE __init__.py (the shape that poisons a from-import): {len(inits)}")
for r in sorted(inits): print(f"  {r}")
