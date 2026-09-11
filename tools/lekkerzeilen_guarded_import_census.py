#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Which modules poison a from-import by containing a guarded import?

THE DEFECT (frankZ, fixed at `0f0c04b8b`, STILL PRESENT IN PIN v407 `095ef4811a5b`):
a module containing a guarded import makes every `from <that module> import NAME`
bind NAME to None -- silently, no diagnostic, for plain constants. `KEY_ESCAPE = 27`
reads as None.

THE CRITERION TOOK THREE TRIES AND EACH WIDENING FELT FINAL. Recorded because the
tool is only as good as the criterion, and a widened filter is exactly when nobody
questions it again:

  1. `grep -rln 'except ImportError'`        -- TEXTUAL. Missed two of three guards
     in this corpus, because their handlers are `Exception` and
     `platform.PlatformError | OSError` and contain the string nowhere.
  2. ast.Try + "is it a package __init__.py" -- PACKAGE-NESS, and it is not a
     dimension at all. Measured on both compilers: a PLAIN module leaks exactly as
     well, and a guard INSIDE A FUNCTION leaks exactly as well as a module-level one.
  3. what this tool does now: any `ast.Try` whose body contains an Import/ImportFrom
     AT ANY DEPTH, in ANY module, cross-referenced against whether that module is
     actually FROM-IMPORTED anywhere. The from-import side is what makes a site live.

So: guarded-import modules are SUSPECTS; suspects that are from-imported are LIVE.
Nothing about packages, nothing about placement.

    tools/lekkerzeilen_guarded_import_census.py            # the census
    tools/lekkerzeilen_guarded_import_census.py --selftest # its controls only
"""
import ast, sys, tempfile, textwrap
from pathlib import Path


def handler_spelling(h):
    return 'bare except' if h.type is None else ast.unparse(h.type)


def guarded_import_modules(pkgdir, root):
    """module stem -> [(relpath, lineno, [import spellings], handlers)]"""
    out = {}
    for f in sorted(pkgdir.rglob('*.py')):
        try:
            tree = ast.parse(f.read_text(encoding='utf-8'), filename=str(f))
        except SyntaxError as e:
            print(f"  SKIP {f.relative_to(root)}: {e}", file=sys.stderr)
            continue
        stem = f.parent.name if f.name == '__init__.py' else f.stem
        for n in ast.walk(tree):
            if not isinstance(n, ast.Try):
                continue
            imps = [x for b in n.body for x in ast.walk(b)
                    if isinstance(x, (ast.Import, ast.ImportFrom))]
            if not imps:
                continue
            out.setdefault(stem, []).append((
                str(f.relative_to(root)), n.lineno,
                [ast.unparse(i).strip() for i in imps],
                ' | '.join(handler_spelling(h) for h in n.handlers) or '(no handler)'))
    return out


def from_import_sites(pkgdir, root):
    """module stem -> [(relpath, lineno, [names])] for every `from <stem> import ...`"""
    out = {}
    for f in sorted(pkgdir.rglob('*.py')):
        try:
            tree = ast.parse(f.read_text(encoding='utf-8'), filename=str(f))
        except SyntaxError:
            continue
        for n in ast.walk(tree):
            if not isinstance(n, ast.ImportFrom) or n.module is None:
                continue
            stem = n.module.split('.')[-1]
            out.setdefault(stem, []).append(
                (str(f.relative_to(root)), n.lineno, [a.name for a in n.names]))
    return out


def census(root):
    pkg = root / root.name if (root / root.name).is_dir() else root
    suspects = guarded_import_modules(pkg, root)
    froms = from_import_sites(pkg, root)
    live = {m: v for m, v in suspects.items() if m in froms}
    return suspects, froms, live, pkg


def main():
    if '--selftest' in sys.argv:
        td = Path(tempfile.mkdtemp()); p = td / td.name; p.mkdir()
        (p / '__init__.py').write_text('')
        # LIVE: a PLAIN module with a guard INSIDE A FUNCTION, from-imported.
        # Both halves are the ones criterion 2 got wrong, so a tool that still
        # filters on package-ness or on module-level placement fails here.
        (p / 'plainmod.py').write_text(textwrap.dedent('''
            KEY = 27
            def probe():
                try:
                    import no_such_module
                    return 1
                except Exception:
                    return 0
        '''))
        (p / 'user.py').write_text('from .plainmod import KEY\n')
        # SUSPECT-NOT-LIVE: guarded, never from-imported. Must NOT be reported live.
        (p / 'lonely.py').write_text(textwrap.dedent('''
            try:
                import no_such_module
            except ImportError:
                pass
        '''))
        # CLEAN: from-imported, no guard. Must appear nowhere.
        (p / 'clean.py').write_text('OTHER = 1\n')
        (p / 'user2.py').write_text('from .clean import OTHER\n')
        suspects, froms, live, _ = census(td)
        ok = True
        if 'plainmod' not in live:
            print("SELFTEST FAIL: a PLAIN module with a FUNCTION-LOCAL guard, "
                  "from-imported, was not reported LIVE -- the tool is still "
                  "filtering on package-ness or on placement."); ok = False
        else:
            print("selftest: positive control LIVE (plain module, function-local guard)")
        if 'lonely' in live:
            print("SELFTEST FAIL: a guarded module nobody from-imports was reported "
                  "LIVE; the from-import cross-reference is not being applied."); ok = False
        else:
            print("selftest: negative control clean (guarded but never from-imported)")
        if 'clean' in suspects:
            print("SELFTEST FAIL: a module with no guard at all was listed as a "
                  "suspect."); ok = False
        else:
            print("selftest: unguarded module not a suspect")
        return 0 if ok else 1

    root = Path(sys.argv[1] if len(sys.argv) > 1 else '/home/neo/lekkerzeilen')
    suspects, froms, live, pkg = census(root)
    print(f"corpus {root}   .py files: {len(list(pkg.rglob('*.py')))}")
    print()
    print(f"=== SUSPECTS: modules containing a guarded import: {len(suspects)} ===")
    for m, rows in sorted(suspects.items()):
        for rel, ln, spell, hs in rows:
            print(f"  {rel}:{ln}   handlers: {hs}")
            for sp in spell:
                print(f"      {sp}")
    print()
    print(f"=== LIVE: of those, from-imported somewhere: {len(live)} ===")
    if not live:
        print("  none -- every guarded module is unreachable by a from-import today")
    for m in sorted(live):
        print(f"  module `{m}`  poisons:")
        for rel, ln, names in froms[m]:
            print(f"      {rel}:{ln}   {len(names)} name(s): {', '.join(names[:6])}"
                  + (" ..." if len(names) > 6 else ""))
    print()
    dormant = sorted(set(suspects) - set(live))
    print(f"DORMANT suspects (guarded, not from-imported — one `from X import` from "
          f"going live): {len(dormant)}")
    for m in dormant:
        print(f"  {m}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
