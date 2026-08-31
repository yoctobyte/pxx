#!/usr/bin/env python3
"""Fail if IROpName does not name every IR op declared in defs.inc.

IROpName has exactly one load-bearing caller: the `unsupported node in IR
codegen` error every backend raises for an op it has no arm for. So an op the
function does not name reports itself as **`unknown`**, on every target, and the
only way to learn which op is missing is to edit the backend and self-compile.

That is not hypothetical. Seven ops were unnamed until 2026-08-31 --
IR_PROCADDR, IR_CLASSREF, IR_VMTADDR, IR_IMTADDR, IR_SET_SIGNAL, IR_IO_LOCK,
IR_IO_UNLOCK -- and IR_CLASSREF was found the expensive way, on xtensa, at the
cost of a build.

The gap could open because nothing counted. The count that found it was a
parser someone ran once by hand; this is that parser, wired, so the eighth gap
cannot open silently.
bug-a-iropname-has-no-entry-for-seven-ir-ops-so-a-missing-arm-reports-unknown

Run: tools/iropname_lint.py [--list] [--selftest]
"""
import os, re, sys

OP_DECL = re.compile(r'\b(IR_[A-Z0-9_]+)\s*=\s*(\d+)\s*;')
FUNC    = re.compile(r'function IROpName.*?\n(.*?)\nend;', re.S)


def strip_comments(text):
    """Blank out { } and (* *) comments and // tails.

    NOT optional, and the reason is on the nose: IROpName's own body carries a
    comment naming IR_CLASSREF, so a scan that reads comments counts an op as
    named because the PROSE mentions it. Caught by the real-tree control below
    -- deleting the IR_CLASSREF arm left this tool reporting clean.

    That is the identical defect this tool's sibling was written to replace:
    abi.inc's review grep ended up matching one line in the tree, a comment
    quoting the rule. A checker satisfied by prose is the house failure mode,
    and writing a careful comment is what triggers it."""
    out, i, n = list(text), 0, len(text)
    while i < n:
        if text[i] == '{':
            j = text.find('}', i); j = n if j < 0 else j
            for k in range(i, min(j + 1, n)):
                if out[k] != '\n':
                    out[k] = ' '
            i = j + 1
        elif text.startswith('(*', i):
            j = text.find('*)', i); j = n if j < 0 else j + 1
            for k in range(i, min(j + 1, n)):
                if out[k] != '\n':
                    out[k] = ' '
            i = j + 1
        elif text.startswith('//', i):
            j = text.find('\n', i); j = n if j < 0 else j
            for k in range(i, j):
                out[k] = ' '
            i = j
        else:
            i += 1
    return ''.join(out)


def analyse(defs_text, ir_text):
    """-> (ops, unnamed). ops maps name -> ordinal."""
    ops = {m.group(1): int(m.group(2)) for m in OP_DECL.finditer(defs_text)}
    m = FUNC.search(ir_text)
    if not m:
        return ops, None                      # cannot find the function at all
    named = set(re.findall(r'\b(IR_[A-Z0-9_]+)\b', strip_comments(m.group(1))))
    return ops, sorted(set(ops) - named, key=lambda k: ops[k])


def selftest():
    """A check that cannot fail is not a check. Both directions asserted."""
    ok = True
    defs = 'IR_NOP = 0;\nIR_CALL = 1;\nIR_GHOST = 2;\n'
    complete = ("function IROpName(kind: Integer): AnsiString;\nbegin\n  case kind of\n"
                "    IR_NOP: Result := 'nop';\n    IR_CALL: Result := 'call';\n"
                "    IR_GHOST: Result := 'ghost';\n  else\n    Result := 'unknown';\n  end;\nend;\n")
    partial = complete.replace("    IR_GHOST: Result := 'ghost';\n", '')
    cases = (
        ('complete', defs, complete, []),
        # THE control: an unnamed op must be reported. Without this the linter
        # is the hand-run parser again -- correct and never consulted.
        ('one_gap',  defs, partial,  ['IR_GHOST']),
        # An op named only in a COMMENT is NOT named. This is the control that
        # caught the tool counting its own prose as coverage.
        ('comment_only', defs,
         partial.replace('  case kind of\n',
                         "  case kind of\n    { IR_GHOST is handled elsewhere }\n"),
         ['IR_GHOST']),
    )
    for name, d, i, want in cases:
        _ops, missing = analyse(d, i)
        good = (missing == want)
        ok = ok and good
        print(f'  selftest {name}: expected {want}, got {missing} -- '
              f'{"ok" if good else "FAILED"}')
    # A missing/renamed IROpName must be an ERROR, not an empty pass: that is how
    # this check would silently die if the function is ever restructured.
    _ops, missing = analyse(defs, 'function SomethingElse; begin end;\n')
    good = missing is None
    ok = ok and good
    print(f'  selftest no_function: expected None (hard error), got {missing} -- '
          f'{"ok" if good else "FAILED"}')
    return ok


def main():
    args = sys.argv[1:]
    if '--selftest' in args:
        sys.exit(0 if selftest() else 1)

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    defs_text = open(os.path.join(root, 'compiler', 'defs.inc'),
                     encoding='utf-8', errors='replace').read()
    ir_text = open(os.path.join(root, 'compiler', 'ir.inc'),
                   encoding='utf-8', errors='replace').read()
    ops, missing = analyse(defs_text, ir_text)

    if missing is None:
        print('iropname-lint: could NOT find `function IROpName` in ir.inc.\n'
              '  That is a failure, not a pass -- if the function moved or was\n'
              '  renamed, update this tool; do not let it report a silent zero.')
        return 1

    if missing:
        print(f'iropname-lint: {len(missing)} of {len(ops)} IR ops are unnamed by '
              f'IROpName.\nEach reports itself as `unknown` in the "unsupported node '
              f'in IR codegen"\nerror on EVERY target, so a backend gap in one cannot '
              f'be identified\nwithout editing the backend and self-compiling:\n')
        for k in missing:
            print(f'  {k}({ops[k]})')
        print('\nAdd an arm to IROpName in compiler/ir.inc, lowercase without the '
              'IR_ prefix.')
        return 1

    if '--list' in args:
        for k in sorted(ops, key=lambda k: ops[k]):
            print(f'  {ops[k]:3}  {k}')
    print(f'iropname-lint: clean -- IROpName names all {len(ops)} declared IR ops.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
