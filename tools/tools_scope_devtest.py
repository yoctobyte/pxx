#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a name bound in ONE function must not be called from another.

Written after landing a live `NameError` in twatch.py's bisect path: the repair
called `testable_only(...)`, which reads as a module helper and is in fact a
closure nested inside `test_sha`. It parsed, it passed review, it passed a
devtest that grepped the source for the call — and it would have raised the
first time the daemon reached that branch, on an idle cycle, hours later, in a
process nobody was watching.

No pyflakes, flake8 or ruff on these boxes, so this is the narrowest useful
substitute rather than a general linter. It reports ONE class and ignores
everything else:

    a Name that is LOADED where it is not in scope, but IS bound somewhere
    else in the same file.

That pairing is what makes it near-false-positive-free. An unbound name might
be a builtin, a star-import, a conditional definition, something injected at
runtime — all noise. A name bound in a *sibling* function and read here is
almost never anything but the mistake above, and it is exactly the mistake a
big file with nested helpers invites.

Deliberately NOT a full linter: a checker that reports everything gets
suppressed, and a suppressed checker asserts nothing. Verified against the real
defect before landing (re-injecting the `testable_only` call makes it fire).

Run: tools/tools_scope_devtest.py   (exit 0 = pass)
"""
import ast
import builtins
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
# Track T's own Python. Not tools/*.py wholesale: other lanes own files here.
CHECKED = ("twatch.py", "testmgr.py", "trackt.py")
BUILTINS = set(dir(builtins))


def _bindings(node):
    """Names this node binds directly (not descending into nested scopes)."""
    out = set()
    for n in ast.walk(node):
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            out.add(n.name)
        elif isinstance(n, ast.Name) and isinstance(n.ctx, (ast.Store, ast.Del)):
            out.add(n.id)
        elif isinstance(n, ast.arg):
            out.add(n.arg)
        elif isinstance(n, (ast.Import, ast.ImportFrom)):
            for a in n.names:
                out.add((a.asname or a.name).split(".")[0])
        elif isinstance(n, ast.ExceptHandler) and n.name:
            out.add(n.name)
        elif isinstance(n, (ast.Global, ast.Nonlocal)):
            out.update(n.names)
    return out


def _scopes(node, stack, found, everywhere):
    """Walk functions, carrying the enclosing scopes' bindings."""
    for child in ast.iter_child_nodes(node):
        if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef,
                              ast.ClassDef)):
            own = _bindings(child)
            everywhere.update(own)
            inner = stack + [own]
            visible = set().union(*inner) | BUILTINS
            for n in ast.walk(child):
                if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load):
                    if n.id not in visible:
                        found.append((n.lineno, n.id, getattr(child, "name", "?")))
            _scopes(child, inner, found, everywhere)


def check(path):
    with open(path) as f:
        tree = ast.parse(f.read(), path)
    top = _bindings_module(tree)
    everywhere = set(top)
    found = []
    _scopes(tree, [top], found, everywhere)
    # Only the pairing: unbound HERE but bound SOMEWHERE. Anything else is the
    # noise this check exists not to produce.
    return [(l, n, fn) for (l, n, fn) in found if n in everywhere]


def _bindings_module(tree):
    """Module-level bindings only — nested function bodies excluded."""
    out = set()
    for n in tree.body:
        out |= _bindings_shallow(n)
    return out


def _bindings_shallow(node):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
        return {node.name}
    out = set()
    for n in ast.walk(node):
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            out.add(n.name)
        elif isinstance(n, ast.Name) and isinstance(n.ctx, ast.Store):
            out.add(n.id)
        elif isinstance(n, (ast.Import, ast.ImportFrom)):
            for a in n.names:
                out.add((a.asname or a.name).split(".")[0])
    return out


def t_track_t_tools_have_no_out_of_scope_names():
    bad = []
    for name in CHECKED:
        path = os.path.join(HERE, name)
        if not os.path.exists(path):
            continue
        for line, ident, fn in check(path):
            bad.append("%s:%d  %s() calls `%s`, which is bound in another "
                       "function's scope" % (name, line, fn, ident))
    assert not bad, "out-of-scope names:\n  " + "\n  ".join(bad)
    return "%d file(s) clean" % len(CHECKED)


def t_the_checker_catches_the_defect_it_was_written_for():
    """A checker that has never been seen to fire is not yet a checker.

    Reproduces the exact shape: a helper nested in one function, called from
    another. If this stops firing, the guard above has become decorative.
    """
    src = (
        "def outer():\n"
        "    def helper(x):\n"
        "        return x\n"
        "    return helper(1)\n"
        "\n"
        "def elsewhere(rng):\n"
        "    return helper(rng)\n"
    )
    tree = ast.parse(src)
    top = _bindings_module(tree)
    found, everywhere = [], set(top)
    _scopes(tree, [top], found, everywhere)
    hits = [(l, n, fn) for (l, n, fn) in found if n in everywhere]
    assert any(n == "helper" and fn == "elsewhere" for (_l, n, fn) in hits), (
        "the checker no longer detects a closure called from a sibling "
        "function — the exact NameError it was written for")
    return "fires on a closure called from a sibling function"


def t_the_checker_is_quiet_on_legitimate_shapes():
    """The other half: a checker that reports everything gets suppressed, and a
    suppressed checker asserts nothing."""
    src = (
        "import os\n"
        "TOP = 1\n"
        "def f(a, b=2):\n"
        "    c = a + b + TOP\n"
        "    def g():\n"
        "        return c + a\n"        # closure reading enclosing scope
        "    return [g() for _ in range(3)] + [os.sep]\n"
        "def h():\n"
        "    try:\n"
        "        pass\n"
        "    except ValueError as e:\n"
        "        return str(e)\n"
    )
    tree = ast.parse(src)
    top = _bindings_module(tree)
    found, everywhere = [], set(top)
    _scopes(tree, [top], found, everywhere)
    hits = [(l, n, fn) for (l, n, fn) in found if n in everywhere]
    assert not hits, "false positives on legitimate scoping: %s" % (hits,)
    return "quiet on closures, defaults, comprehensions, except-as, imports"


def main():
    rc = 0
    for fn in (t_the_checker_catches_the_defect_it_was_written_for,
               t_the_checker_is_quiet_on_legitimate_shapes,
               t_track_t_tools_have_no_out_of_scope_names):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("tool scoping OK" if rc == 0 else "tool scoping BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
