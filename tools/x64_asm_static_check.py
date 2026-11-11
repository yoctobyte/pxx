#!/usr/bin/env python3
"""x64_asm_static_check.py [--compiler PATH] [--keep DIR]

Assembles EVERY literal instruction line that the compiler source passes to
EmitAsmX64([...]), through the real text assembler (compiler/asmtext.inc +
x64enc.inc), using the mock environment of test/test_asm_emit_x64.pas.

Why it exists: converting raw EmitB codegen to EmitAsmX64 is checked by
compiling a corpus and comparing the output, which proves only the lines that
corpus reaches. On 2026-11-11 `push [rax+%]` sat on the C aggregate-argument
path. The corpus compiled no C and passed; test-nilpy's cpyext rows failed
with "push expects a register". This check does not depend on coverage. A line
the assembler cannot encode fails here, wherever it is.

Hole values are dummies (1 for every `%`, `%r64` and `@glob`). Only "does it
assemble" is checked, not the bytes. The bytes are what the corpus oracle and
the harness check. Labels, jumps and calls are left out because they need
their surrounding lines.

Exit 0 = every line assembles. Each failing line is printed with its file:line.
"""
import os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HARNESS = os.path.join(ROOT, 'test', 'test_asm_emit_x64.pas')


def pascal_strings(text):
    """Single-quoted Pascal string literals in text ('' is an escaped quote)."""
    return [m.group(1).replace("''", "'") for m in re.finditer(r"'((?:[^']|'')*)'", text)]


def calls(src):
    """(line_no, items_text) for each EmitAsmX64([ ... ]) call in src, with
    Pascal comments ({ }, (* *), //) removed from the items text."""
    out = []
    for m in re.finditer(r'EmitAsmX64\(\[', src):
        i = m.end(); depth = 1; q = False; buf = []
        while i < len(src) and depth:
            c = src[i]
            if q:
                buf.append(c)
                if c == "'": q = False
            elif c == "'": q = True; buf.append(c)
            elif c == '{':
                i = src.find('}', i); i = len(src) if i < 0 else i
            elif src.startswith('(*', i):
                i = src.find('*)', i) + 1; i = len(src) if i <= 0 else i
            elif src.startswith('//', i):
                i = src.find('\n', i); i = len(src) if i < 0 else i
            else:
                if c == '[': depth += 1
                elif c == ']': depth -= 1
                if depth: buf.append(c)
            i += 1
        out.append((src.count('\n', 0, m.start()) + 1, ''.join(buf)))
    return out


def plain(line):
    t = line.strip()
    if not t or t.endswith(':'): return False
    mn = t.split()[0].lower()
    return not (mn.startswith('j') or mn in ('call', 'loop', 'loope', 'loopne', 'jrcxz'))


def holes(line):
    return line.count('%') + len(re.findall(r'@(glob|data)\b', line))


def main():
    comp = os.path.join(ROOT, 'compiler', 'pascal26')
    if '--compiler' in sys.argv: comp = sys.argv[sys.argv.index('--compiler') + 1]
    lines = []   # (where, text)
    seen = set()
    cdir = os.path.join(ROOT, 'compiler')
    for f in sorted(os.listdir(cdir)):
        if not (f.endswith('.inc') or f.endswith('.pas')) or f.startswith('asmtext'): continue
        src = open(os.path.join(cdir, f), errors='replace').read()
        for ln, items in calls(src):
            for s in pascal_strings(items):
                if plain(s) and s not in seen:
                    seen.add(s); lines.append(('%s:%d' % (f, ln), s))
    h = open(HARNESS).read()
    cut = h.rindex('\nbegin\n')
    # Error must not halt: report, count, and abandon only the current line.
    head = h[:cut].replace("writeln(StdErr, 'ERROR: ', msg); Halt(1);",
                           "writeln('ASMERR ', CurWhere, ' :: ', msg); Inc(ErrN); raise EAbort.Create('');")
    head = head.replace('uses SysUtils;', 'uses SysUtils;\nvar CurWhere: AnsiString; ErrN: Integer = 0;', 1)
    body = ['\nbegin']
    for where, s in lines:
        lit = "'" + s.replace("'", "''") + "'"
        args = ''.join(', 1' for _ in range(holes(s)))
        body.append("  CurWhere := %s; ResetCode; try EmitAsmX64([%s%s]); except on EAbort do ; end;"
                    % ("'" + where + " " + s.replace("'", "''") + "'", lit, args))
    body.append("  writeln('STATIC_LINES=%d ERRORS=', ErrN);" % len(lines))
    body.append('  if ErrN > 0 then Halt(1);')
    body.append('end.')
    d = tempfile.mkdtemp()
    if '--keep' in sys.argv: d = sys.argv[sys.argv.index('--keep') + 1]; os.makedirs(d, exist_ok=True)
    # the harness includes ../compiler/*.inc relative to itself: generate beside it
    gen = os.path.join(ROOT, 'test', '.x64_asm_static_check_gen.pas')
    open(gen, 'w').write(head + '\n'.join(body) + '\n')
    try:
        r = subprocess.run([comp, '-Fu' + cdir, gen, os.path.join(d, 'chk')], capture_output=True, text=True)
        if r.returncode:
            print(r.stdout[-3000:] + r.stderr[-3000:]); print('x64-asm-static: BUILD FAILED'); return 2
        r = subprocess.run([os.path.join(d, 'chk')], capture_output=True, text=True)
        out = r.stdout
        bad = [l for l in out.split('\n') if l.startswith('ASMERR')]
        for l in bad: print(l)
        tail = [l for l in out.split('\n') if l.startswith('STATIC_LINES')]
        print(tail[0] if tail else 'x64-asm-static: no summary (rc=%d)\n%s' % (r.returncode, out[-2000:] + r.stderr[-2000:]))
        print('x64-asm-static: %s' % ('OK' if r.returncode == 0 and not bad else 'FAIL'))
        return 0 if r.returncode == 0 and not bad else 1
    finally:
        if '--keep' not in sys.argv:
            os.remove(gen)


sys.exit(main())
