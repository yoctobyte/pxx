#!/usr/bin/env python3
"""Flag hand-written literal short-jump displacements whose span is emitted by
code that can change size.

Two failure classes for a rel8 displacement. CheckRel8 guards the first:
too large, hard error, cannot ship. This is the second one -- in range, wrong
target. The span between the jump and its intended landing place grew or
shrank, the displacement is still a legal rel8, and it now points into the
middle of an instruction. It assembles, links, runs, and corrupts a value.
No symbol, relocation or size number moves.

Measured 2026-09-02: three such sites converted to PatchRel8, and TWO of them
were already wrong on master --

    ir_codegen.inc  jle 35 over five emitters that emit 27
        WriteLn(s:2, '|') for a ShortString 'abcdef' printed `|`; FPC prints
        `abcdef|`.
    symtab.inc      jns 10 over one MovRaxImm(0) that emits 2 (xor eax,eax)
        LoadFile into a ShortString reported Length(s) = 0 for a 21-byte file.

Both overshot by exactly 8 bytes into the NEXT emitter, so they corrupted a
value instead of faulting. The third site, whose span was all fixed-size
EmitB, was byte-identical -- which is the rule this check enforces:

    A LITERAL DISPLACEMENT MAY ONLY SPAN EMISSIONS OF FIXED SIZE.

Spanning EmitB/EmitI32 is fine: the bytes are on the page, and a reader adding
one is looking straight at the count. Spanning MovRaxImm, EmitSyscall,
EmitDataRef, EmitGlobRef or any other emitter that picks an encoding is not:
its size is decided elsewhere, by someone with no reason to look for a jump
across their edit. Use PatchRel8, which computes the displacement from the
emitted positions and range-checks it.

FINDING THE SITES. `EmitB($7x); EmitB(<literal>);` also matches ModRM and SIB
bytes and the second byte of a two-byte opcode -- EmitB($0F); EmitB($7E);
EmitB($C0) is `movq rax, xmm0`, and EmitB($4C); EmitB($89); EmitB($77);
EmitB($20) is `mov [rdi+32], r14`. A naive grep of that shape reports ~130
sites and roughly two thirds are not jumps; both an earlier count of 142 and a
peer's "about 25" came out of it. The discriminator here is POSITION: these
files emit one instruction per line, so a jump opcode is the FIRST byte
emitted on its line and a ModRM byte never is. Checked against the independent
comment-mnemonic classification over the whole commented population on
2026-09-02: 108 sites, 108 agreements, 0 disagreements. It also classifies the
23 sites that carry no comment, which the comment rule cannot.

--selftest asserts the check REJECTS both shapes it was built from and ACCEPTS
the fixed-size one, because a check that cannot fail prints PASS.
"""
import re, sys, glob, os

OPCODE = r'\$(7[0-9A-Fa-f]|EB|E3)'
SITE = re.compile(r'EmitB\(\s*' + OPCODE + r'\s*\)\s*;\s*'
                  r'EmitB\(\s*(\$[0-9A-Fa-f]+|\d+|Byte\(\s*-?\d+\s*\))\s*\)\s*;')
EMITB_LITERAL = re.compile(r'EmitB\(\s*(\$?[0-9A-Fa-f]+|Byte\(\s*-?\d+\s*\))\s*\)')
CALL = re.compile(r'([A-Za-z_][A-Za-z0-9_]*)\s*\(')
EMITTERISH = ('Emit', 'Mov', 'Patch', 'Check', 'Xtensa', 'x86', 'X386', 'IREmit')
# calls inside a span that emit nothing, or a fixed number of bytes
FIXED = {'EmitB': 1, 'EmitI32': 4}
NO_BYTES = {'Patch32', 'PatchRel8', 'CheckRel8', 'EmitRel8Target'}
SPAN_LOOKAHEAD = 40


def strip_comment(s):
    return re.sub(r'\{[^}]*\}', '', s)


def disp_value(tok):
    m = re.match(r'Byte\(\s*(-?\d+)\s*\)', tok)
    if m:
        return int(m.group(1)) & 0xFF
    return int(tok[1:], 16) if tok.startswith('$') else int(tok)


def scan_text(name, text):
    """Yield (line_no, opcode, disp, fixed_bytes_counted, [variable emitters])."""
    lines = text.split('\n')
    out = []
    for n, line in enumerate(lines, 1):
        code = strip_comment(line)
        for m in SITE.finditer(code):
            # POSITION RULE: a jump opcode is the first byte emitted on its line.
            head = code[:m.start()]
            if 'EmitB(' in head or 'EmitI32(' in head:
                continue                      # a ModRM, SIB or immediate byte
            disp = disp_value(m.group(2))
            if disp > 127:
                continue                      # backward: the span is above the site
            acc, variable, done = 0, [], False
            chunks = [code[m.end():]] + [strip_comment(l) for l in lines[n:n + SPAN_LOOKAHEAD]]
            for ch in chunks:
                for tok in CALL.finditer(ch):
                    fn = tok.group(1)
                    if not fn.startswith(EMITTERISH):
                        continue
                    if fn == 'EmitB' and EMITB_LITERAL.match(ch[tok.start():]):
                        acc += 1
                    elif fn == 'EmitB':
                        acc += 1              # a computed byte is still one byte
                    elif fn in FIXED:
                        acc += FIXED[fn]
                    elif fn in NO_BYTES:
                        pass
                    else:
                        variable.append(fn)
                    if acc >= disp:
                        done = True
                        break
                if done:
                    break
            out.append((n, m.group(1), disp, acc, variable))
    return out


def scan_tree(root):
    findings, total = [], 0
    files = sorted(glob.glob(os.path.join(root, 'compiler', '*.inc')) +
                   glob.glob(os.path.join(root, 'compiler', '*.pas')))
    for f in files:
        for n, op, disp, acc, variable in scan_text(f, open(f, errors='replace').read()):
            total += 1
            if variable:
                findings.append((f, n, op, disp, sorted(set(variable))))
    return total, findings


FIXTURE_BAD_WIDTH = """
            EmitB($48); EmitB($29); EmitB($C8);
            EmitB($7E); EmitB(35);
            EmitB($48); EmitB($BE); EmitDataRef(SpacesOffset);
            EmitB($48); EmitB($89); EmitB($C2);
            MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
"""
FIXTURE_BAD_CLAMP = """
  EmitB($48); EmitB($85); EmitB($C0);
  EmitB($79); EmitB($0A);
  MovRaxImm(0);
  EmitStoreStrLen(dstIdx);
"""
FIXTURE_GOOD = """
            EmitB($48); EmitB($85); EmitB($C9);
            EmitB($74); EmitB(15);
            EmitB($8A); EmitB($16);
            EmitB($88); EmitB($17);
            EmitB($48); EmitB($FF); EmitB($C6);
            EmitB($48); EmitB($FF); EmitB($C7);
            EmitB($48); EmitB($FF); EmitB($C9);
"""
FIXTURE_MODRM = """
            EmitB($4C); EmitB($89); EmitB($77); EmitB($20);
            EmitB($48); EmitB($8D); EmitB($70); EmitB($08);
            MovRaxImm(0); EmitSyscall;
"""


def selftest():
    fails = []

    def flagged(text):
        return [r for r in scan_text('<fixture>', text) if r[4]]

    def seen(text):
        return scan_text('<fixture>', text)

    if not flagged(FIXTURE_BAD_WIDTH):
        fails.append('the shipped `jle 35` width-pad shape was NOT flagged')
    if not flagged(FIXTURE_BAD_CLAMP):
        fails.append('the shipped `jns 10` LoadFile clamp shape was NOT flagged')
    if flagged(FIXTURE_GOOD):
        fails.append('an all-literal span WAS flagged (false positive)')
    if not seen(FIXTURE_GOOD):
        fails.append('the all-literal span was not detected as a jump site at all '
                     '-- the ACCEPT above would then be vacuous')
    if seen(FIXTURE_MODRM):
        fails.append('a ModRM/SIB byte was read as a jump opcode -- the position '
                     'rule is not doing its job')
    for f in fails:
        print('rel8-literal-span: SELFTEST FAIL: ' + f)
    if fails:
        return 1
    print('rel8-literal-span: selftest OK '
          '(2 known-bad shapes rejected, 1 good shape accepted and detected, '
          '1 ModRM line correctly not a jump)')
    return 0


def main():
    root = '.'
    args = [a for a in sys.argv[1:]]
    if '--selftest' in args:
        args.remove('--selftest')
        rc = selftest()
        if rc or not args:
            return rc
    if args:
        root = args[0]
    total, findings = scan_tree(root)
    if not findings:
        print('rel8-literal-span: OK — %d literal short jumps, every span is '
              'fixed-size emission' % total)
        return 0
    print('rel8-literal-span: %d of %d literal short jumps span an emitter '
          'whose size is not fixed' % (len(findings), total))
    for f, n, op, disp, variable in findings:
        print('  %s:%d  op=$%s disp=%d  spans %s' % (f, n, op, disp, ', '.join(variable)))
    print('  Convert these to PatchRel8: record `p := CodeLen; EmitB(0);` at the')
    print('  jump and call `PatchRel8(p)` at the landing site. See')
    print('  devdocs/progress/*/bug-a-hand-written-literal-short-jumps-'
          'span-emitters-that-can-grow.md')
    return 1


if __name__ == '__main__':
    sys.exit(main())
