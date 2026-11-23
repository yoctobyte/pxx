#!/usr/bin/env python3
"""The fixed aarch64 sequences of compiler/ir_codegen_a64_i128.inc, from their
assembly source.

snippets.s -> Pascal on stdout: one procedure per `// SNIP name` block, one
EmitI32 per word with its source line as the comment. Branches stay inside a
block, so the words are position independent. Needs clang (any version with
the aarch64 target) and llvm-objdump; set LLVM_OBJDUMP if yours is suffixed.

  python3 tools/a64_i128/gen.py > /tmp/words.pas

and paste the procedures over the ones in the .inc.
feature-c-int128-other-targets-float-and-narrow-modes"""
import subprocess, sys, re, os, tempfile
D = os.path.dirname(os.path.abspath(__file__))
OBJDUMP = os.environ.get('LLVM_OBJDUMP', 'llvm-objdump')
src = open(os.path.join(D, 'snippets.s')).read().split('\n')
T = tempfile.mkdtemp()
blocks, cur = [], None
for ln in src:
    m = re.match(r'\s*//\s*SNIP\s+(\w+)', ln)
    if m:
        cur = (m.group(1), []); blocks.append(cur); continue
    if cur is not None: cur[1].append(ln)
out = []
for name, lines in blocks:
    body = '\n'.join(lines)
    asm = os.path.join(T, name + '.s'); obj = os.path.join(T, name + '.o')
    open(asm, 'w').write('.text\n' + body + '\n')
    subprocess.check_call(['clang', '--target=aarch64-linux-gnu', '-c', asm, '-o', obj])
    dis = subprocess.check_output([OBJDUMP, '-d', '--no-show-raw-insn', obj]).decode()
    raw = subprocess.check_output([OBJDUMP, '-d', obj]).decode()
    words = []
    for l in raw.split('\n'):
        m = re.match(r'\s*[0-9a-f]+:\s+([0-9a-f]{8})\s+(.*)', l)
        if m:
            words.append(('$' + m.group(1).upper(), m.group(2).split('//')[0].strip()))
    # source comments: instruction lines of the body (labels kept as comments)
    srcl = [x.strip() for x in lines if x.strip() and not x.strip().startswith('//')]
    out.append('procedure %s;\nbegin' % name)
    si = 0
    for w, d in words:
        lab = ''
        while si < len(srcl) and srcl[si].endswith(':'):
            lab += srcl[si] + ' '; si += 1
        s = srcl[si] if si < len(srcl) else d
        si += 1
        out.append('  EmitI32(%s);  { %s%s }' % (w, lab, s.replace('{', '(').replace('}', ')')))
    out.append('end;\n')
print('\n'.join(out))
