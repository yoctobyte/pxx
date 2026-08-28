#!/usr/bin/env python3
"""Flag a call FPC cannot resolve: a routine used before it is declared.

pxx resolves names across a whole unit; FPC resolves them in SOURCE ORDER. So
a file can self-host perfectly and still break the bootstrap seed, silently,
and nothing in the per-fix loop looks — `make compiler/pascal26` compiles with
pxx. It has happened twice in ir_codegen_wasm32.inc, both times found only by
`gate.sh quick`'s FPC canary, which runs once at the end of a phase.

This asks FPC's question directly: it expands compiler.pas's {$include} chain
in order, exactly as FPC sees it, and reports any call to a routine whose
declaration — definition or `forward;` — comes later in that stream.

The include expansion is the whole point and the first version did without it.
That version reported SEVENTEEN failures on a tree that builds clean under FPC,
because this repo declares cross-file forwards in dedicated files
(forwards.inc, pyforwards.inc) pulled in at the right point in the chain, and a
per-file view cannot see them. A check that cries wolf is worse than no check;
it would have been suppressed within a day.

Deliberately narrow even so. A name is reported only when it is DECLARED
somewhere in the stream (so an RTL or unit routine is never reported), used
before that declaration, and not inside a comment or a string literal. The
failure mode chosen is a MISS, not a false alarm — the gate's real FPC build
stays the backstop either way.
"""
import os
import re
import sys

DEF = re.compile(r'^\s*(?:function|procedure)\s+([A-Za-z_]\w*)', re.I)
FWD = re.compile(r'\bforward\s*;', re.I)
INC = re.compile(r'\{\$i(?:nclude)?\s+([^}]+?)\s*\}', re.I)
# A conditional wrapped around a declaration on ONE line: this repo writes
# `{$ifndef PXX_NO_ARM32}procedure EmitSignalRuntimeArm32; forward;{$endif}`,
# and a declaration regex anchored at ^ cannot see past the directive.
DIRECTIVE = re.compile(r'\{\$[^}]*\}')
IDENT = re.compile(r'[A-Za-z_]\w*')

# Names FPC's own system/sysutils units export. A use of one of these BEFORE
# this codebase's own definition is not a build failure — FPC resolves it to
# ITS routine and compiles — so it is reported as a NOTE rather than a FAIL.
#
# It is still worth printing. The seed build and the self-hosted build then run
# DIFFERENT implementations of that name for every call before the definition,
# and nothing anywhere says so. That is a real divergence, just not the one
# this check exists to gate.
#
# Curated, therefore incomplete, and incompleteness here can only cause a FALSE
# ALARM — the opposite of this file's chosen failure mode. Every entry was
# added because it actually fired on a tree FPC builds clean.
FPC_SYSTEM = {
    'lowercase', 'uppercase', 'copy', 'pos', 'length', 'setlength', 'insert',
    'delete', 'trim', 'val', 'str', 'inttostr', 'strtoint', 'abs', 'odd',
    'chr', 'ord', 'round', 'trunc', 'frac', 'int', 'sqr', 'sqrt', 'exp', 'ln',
    'assigned', 'high', 'low', 'inc', 'dec', 'writeln', 'write', 'readln',
    'halt', 'exit', 'move', 'fillchar', 'getmem', 'freemem', 'reallocmem',
    'comparestr', 'stringofchar', 'format', 'floattostr', 'strtofloat',
}


def strip(line, depth):
    """Remove comments and 'string' literals; return (code, brace depth).

    Braces NEST here. Standard Pascal says the first `}` closes, and both pxx
    and FPC accept `{ ... span_{nd-1} ... }` as one comment — measured, with a
    six-line program, after this scanner ended a comment early and reported a
    name that appears only in the prose. A tokenizer that disagrees with both
    compilers about where a comment ends is not a check, it is a generator of
    plausible-looking failures.

    A {$...} directive is a comment to Pascal but not to the include scanner,
    so directives are returned intact at depth 0 and filtered by the caller.
    """
    out, i, n = [], 0, len(line)
    while i < n:
        if depth > 0:
            c = line[i]
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
            i += 1
            continue
        c = line[i]
        if c == '{':
            if line.startswith('{$', i):
                j = line.find('}', i)
                if j < 0:
                    return ''.join(out), 1
                out.append(line[i:j + 1])
                i = j + 1
                continue
            depth = 1
            i += 1
        elif c == '(' and i + 1 < n and line[i + 1] == '*':
            j = line.find('*)', i + 2)
            if j < 0:
                return ''.join(out), 0     # (* *) does not nest; rare here
            i = j + 2
        elif c == "'":
            j = i + 1
            while j < n and line[j] != "'":
                j += 1
            i = j + 1
        elif c == '/' and i + 1 < n and line[i + 1] == '/':
            break
        else:
            out.append(c)
            i += 1
    return ''.join(out), depth


def expand(path, root, seen, out):
    """Append (file, lineno, stripped-source) for path and everything it includes."""
    real = os.path.realpath(path)
    if real in seen:
        return
    seen.add(real)
    try:
        raw = open(path, encoding='utf-8', errors='replace').read().split('\n')
    except OSError:
        return
    depth = 0
    for ln, line in enumerate(raw, 1):
        code, depth = strip(line, depth)
        m = INC.search(code)
        if m:
            name = m.group(1).strip().strip("'\"")
            if not name.startswith('%'):        # {$i %DATE%} and friends
                expand(os.path.join(root, name), root, seen, out)
                continue
        out.append((path, ln, DIRECTIVE.sub('', INC.sub('', code))))


def analyse(stream):
    """Two passes: collect every declaration, then find uses that precede one.

    The second pass lowercases each LINE once rather than each identifier, and
    drops a name the moment it has been reported — 210k lines is enough for
    either detail to show up in the wall clock.
    """
    declared, decl_lines = {}, set()
    for pos, (_path, _ln, code) in enumerate(stream):
        m = DEF.match(code)
        if m:
            declared.setdefault(m.group(1).lower(), pos)
            decl_lines.add(pos)

    bad, notes, seen = [], [], set()
    for pos, (path, ln, code) in enumerate(stream):
        if pos in decl_lines:
            continue
        low = code.lower()
        for um in IDENT.finditer(low):
            name = um.group(0)
            if name in seen:
                continue
            d = declared.get(name)
            if d is None or pos >= d:
                continue
            seen.add(name)
            row = (path, ln, code[um.start():um.end()],
                   stream[d][0], stream[d][1])
            if name in FPC_SYSTEM:
                notes.append(row)
            else:
                bad.append(row)
    return bad, notes


def main(argv):
    entry = argv[1] if len(argv) > 1 else 'compiler/compiler.pas'
    root = os.path.dirname(os.path.realpath(entry))
    stream = []
    expand(entry, root, set(), stream)
    bad, notes = analyse(stream)
    for path, ln, name, dpath, dln in notes:
        print(f'note {path}:{ln}: uses {name} before this codebase declares it '
              f'at {dpath}:{dln} — FPC resolves it to its OWN system-unit '
              f'routine, so the seed build and the self-hosted build run '
              f'different implementations here. Builds either way.')
    for path, ln, name, dpath, dln in bad:
        print(f'FAIL {path}:{ln}: calls {name}, declared at '
              f'{dpath}:{dln}, which FPC has not seen yet')
    if bad:
        print('     pxx resolves across the unit and FPC resolves in source')
        print('     order, so this self-hosts and breaks the bootstrap seed.')
        print('     Add a `forward;` — near the top of the same file, or in')
        print('     forwards.inc / the frontend`s own forwards file.')
        return 1
    print(f'ok  no use-before-declaration in the FPC include stream '
          f'({len(stream)} lines from {entry})')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
