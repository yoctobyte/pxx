#!/usr/bin/env python3
"""Pass-through AST kinds that IRLowerAST can VALUE but IRLowerAddress cannot ADDRESS.

A PASS-THROUGH node's value IS a child's value -- its arm ends
`Result := IRLowerAST(ASTLeft[node])` or `...ASTRight[node]`. Its ADDRESS is
therefore that child's address. If IRLowerAddress has no arm for it, a consumer
that needs an address gets the node's CONTENTS instead. That is not a
diagnostic; it is a wrong pointer.

MEASURED, twice, in one afternoon (b531be20a):
  AN_STR_FROM_CHAR is `Left = store into a hidden temp, Right = read of it`. It
  had a value arm and no address arm, and the variant-to-variant store -- which
  calls IRLowerAddress when its RHS is an lvalue -- copied 16 bytes from an
  8-byte load. `v := Variant(y)` crashed before its first WriteLn.

THE RAW SET DIFFERENCE IS NOT THE CENSUS. 83 kinds have a value arm and no
address arm and nearly every one is a statement or a literal, so a guard built
on it flags everything and means nothing (a filter that never says no is as
empty as one that never fires). The PASS-THROUGH property is what turns the gap
from a category into a defect.

TWO CONTROLS, both branched on:
  --self-check <pre-fix ir.inc>  must report AN_STR_FROM_CHAR. A filter that
      cannot name the case that motivated it is not measuring that case.
  the snapshot                   a kind not in ACCEPTED is a NEW pass-through
      that nobody gave an address arm, and that is what this exists to catch.

ACCEPTED is not a list of things that are fine -- it is a list of things whose
reachability was ASKED and not demonstrated. AN_COMMA was constructed against
gcc (`s = (i++, t);` for a 24-byte struct) and pxx matched, so its gap is not
reachable by that route; AN_AWAIT and AN_PARFOR were not constructed either way.
A missing guard is not a demonstrated defect, and neither is it a cleared one.
"""
import re, sys, os

ACCEPTED = {
    'AN_COMMA':  'C frontend only. `s = (i++, t);` for a 24-byte struct matches gcc.',
    'AN_AWAIT':  'stackful today: AN_AWAIT lowers straight to its operand. Not constructed.',
    'AN_PARFOR': 'a statement; its value arm exists for uniformity. Not constructed.',
}

def strip_comments(text):
    out = []; depth = 0
    for ln in text.split('\n'):
        r = ''
        for c in ln:
            if depth == 0 and c == '{': depth = 1
            elif depth == 1 and c == '}': depth = 0
            elif depth == 0: r += c
        out.append(r)
    return out

def body(L, name):
    for i, ln in enumerate(L):
        if re.match(r'^(function|procedure)\s+%s\b' % name, ln.strip()) and 'forward' not in ln:
            for j in range(i + 1, len(L)):
                if re.match(r'^(function|procedure)\s+[A-Za-z]', L[j]):
                    return i, j
    sys.exit('lowering_passthrough_census: no body for %s -- has it been renamed?' % name)

KINDS = re.compile(r'AN_[A-Z0-9_]+')
LABEL = re.compile(r'^\s{0,6}((?:AN_[A-Z0-9_]+\s*,\s*)*AN_[A-Z0-9_]+)\s*:\s*$')
RET   = re.compile(r'Result\s*:=\s*IRLowerAST\(AST(Right|Left)\[node\]\)\s*;')

def census(path):
    L = strip_comments(open(path).read())
    vlo, vhi = body(L, 'IRLowerAST')
    alo, ahi = body(L, 'IRLowerAddress')
    adr = set()
    for ln in L[alo:ahi]:
        adr.update(re.findall(r'ASTKind\[node\]\s*=\s*(AN_[A-Z0-9_]+)', ln))
        m = LABEL.match(ln)
        if m: adr.update(KINDS.findall(m.group(1)))
    arms = {}; cur = None; buf = []
    for i in range(vlo, vhi):
        m = LABEL.match(L[i])
        if m:
            if cur: arms[cur] = buf
            cur = tuple(KINDS.findall(m.group(1))); buf = []
        elif cur is not None:
            buf.append((i + 1, L[i]))
    if cur: arms[cur] = buf
    hits = []
    for ks, b in arms.items():
        lines = [(n, ln) for n, ln in b if RET.search(ln)]
        if not lines: continue
        side = RET.search(lines[0][1]).group(1)
        for k in ks:
            if k not in adr: hits.append((k, side, lines[0][0]))
    return sorted(hits), len(arms), len(adr)

def main():
    args = sys.argv[1:]
    if args and args[0] == '--self-check':
        if len(args) < 2:
            sys.exit('--self-check needs a pre-b531be20a compiler/ir.inc to read')
        hits, _, _ = census(args[1])
        names = [k for k, _, _ in hits]
        if 'AN_STR_FROM_CHAR' not in names:
            print('lowering_passthrough_census: SELF-CHECK FAILED — the filter does not '
                  'name AN_STR_FROM_CHAR in a tree where it had no address arm.')
            return 1
        print('lowering_passthrough_census: self-check OK — AN_STR_FROM_CHAR is reported '
              'in a pre-fix tree.')
        return 0
    hits, nval, nadr = census(os.environ.get('IRINC', 'compiler/ir.inc'))
    print('lowering_passthrough_census: %d value arms, %d address arms' % (nval, nadr))
    new = [h for h in hits if h[0] not in ACCEPTED]
    for k, side, n in hits:
        note = ACCEPTED.get(k, '*** NEW ***')
        print('  %-18s -> AST%s[node]  ir.inc:%-6d %s' % (k, side, n, note))
    if new:
        print('\nlowering_passthrough_census: %d NEW pass-through kind(s) with no arm in '
              'IRLowerAddress.' % len(new))
        print('A pass-through node\'s address is its RESULT\'s address. Give it an arm in '
              'IRLowerAddress (lower Left for its side effect, return '
              'IRLowerAddress(ASTRight[node])), or add it to ACCEPTED with the reachability '
              'you actually constructed.')
        return 1
    print('lowering_passthrough_census: OK — every pass-through kind is addressable or '
          'accounted for.')
    return 0

if __name__ == '__main__':
    sys.exit(main())
