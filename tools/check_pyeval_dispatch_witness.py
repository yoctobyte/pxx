#!/usr/bin/env python3
"""Fail if a runtime routine makes a callable VALUE without the DCE witness.

    tools/check_pyeval_dispatch_witness.py [builtin-dir]

DCE keeps NilPy's full callable dispatch (PyCallKey1, pyvar_callv0: ~314 KB on
riscv32) only when PyEvalDispatchMark is live, and every routine that makes a
callable value takes its address (pylib.pas, the comment on
PyEvalDispatchMark; dce.inc, DceCondRoots). A maker that does not would leave a
value that only the full dispatch can call in a program whose hooks were
re-aimed at the Lite stand-ins, which answer the wrong thing for it. So this
finds every routine that stamps a callable tag (8 bound pair, 9 closure,
10 bound-fn, 11 class, 13 builtin type), allocates a closure or bound-fn
object, builds a builtin method or sets a defaultdict factory, and requires
the witness in it. EXEMPT lists the ones that only re-tag or copy a value some
witness already made, each with the reason.

feature-nilpy-esp-code-size-blocks-dual-slot-ota
"""
import os
import re
import sys

MAKES = re.compile(
    r"VType\s*:=\s*(8|9|10|11|13|VT_PYCLOSURE|VT_BOUNDFN|VT_CLASSREF|VT_BTYPE)\b"
    r"|Magic\s*:=\s*@Py(Closure|BoundFn)MagicMarker"
    r"|TPyBuiltinMethod\.Create"
    r"|FHasFactory\s*:=\s*True")
HEADER = re.compile(r"(function|procedure|constructor)\s+([A-Za-z0-9_.]+)")
WITNESS = '@PyEvalDispatchMark'

EXEMPT = {
    'PyMakeClosure': 'its object comes from PyMakeClosureObj, a witness',
    'pyvar_of_callable': 're-tags an object a witness made, or a bare code address (Lite calls those)',
    'PyCallKey1': 'is the full dispatch itself',
    'TPyDict.copy': 'copies a factory pydefaultdict_new (a witness) set',
}


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', 'compiler', 'builtin')
    bad = 0
    found = 0
    for name in sorted(os.listdir(d)):
        if not name.endswith('.pas'):
            continue
        lines = open(os.path.join(d, name), encoding='latin-1').read().split('\n')
        heads = [i for i, l in enumerate(lines) if HEADER.match(l)]
        for k, st in enumerate(heads):
            end = heads[k + 1] if k + 1 < len(heads) else len(lines)
            body = lines[st:end]
            hits = [st + j + 1 for j, l in enumerate(body) if MAKES.search(l)]
            if not hits:
                continue
            routine = HEADER.match(lines[st]).group(2)
            found += 1
            if routine in EXEMPT or any(WITNESS in l for l in body):
                continue
            print('%s:%d: %s makes a callable value without `PyEvalDispatchWitness := @PyEvalDispatchMark;`'
                  % (name, hits[0], routine))
            bad += 1
    if found < 10:
        print('only %d makers found: the patterns no longer match the runtime' % found)
        return 1
    if bad:
        return 1
    print('callable-value makers all witnessed: %d routines' % found)
    return 0


if __name__ == '__main__':
    sys.exit(main())
