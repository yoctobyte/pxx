#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Which backends still REFUSE a thing, against the state of the ticket they cite.

THE DEFECT THIS EXISTS FOR, three instances on 2026-09-02 alone:

  1. bug-a-a-function-returning-a-dynamic-array-is-refused-on-every-cross-target
     -- title said "every", fixed four, left xtensa. lib/rtl/sysutils.pas itself
     would not build for xtensa as a result.
  2. the concat-ownership fix -- "fixed the four cross backends", never listed
     xtensa, "the seventh backend that a grep for the common spelling does not
     return".
  3. feature-cross-virtual-indirect-hidden-dest -- title says "cross backends",
     body names i386/arm32/aarch64 and delivered exactly those three. Its error
     strings stayed compiled into riscv32 and xtensa for weeks, and jsondemo
     would not build for either.

Every one is the same instrument failing: a REFUSAL cites a ticket slug, someone
implements the feature on the backends they were looking at, the ticket closes,
and the citation in the backends they were NOT looking at goes on pointing at a
ticket marked done. Anyone who hits the error follows the slug, lands in done/,
and has to read the whole body to learn it was about other targets. The
reference is correct about something else.

"Cross backends" is not a number. THE POPULATION IS SEVEN: x86-64, i386, arm32,
aarch64, riscv32, xtensa, wasm32.

WHAT THIS REPORTS, and it is deliberately only the one question a grep cannot
answer on its own: for each ticket slug cited by a live refusal in the emitters,
is that ticket OPEN or CLOSED, and which backends still carry it. A slug cited
by a live refusal while its ticket sits in done/ or rejected/ is the defect --
either the ticket closed over a subset, or the refusal is stale and should have
been deleted with the fix. BOTH are real and this cannot tell them apart; it
tells you WHERE TO LOOK, which is the part that was missing.

NOT A CORRECTNESS GATE. A refusal is often the right answer for a target -- see
xtensa's 33 deliberate PAL refusals, or ParamStr, which an ESP image genuinely
cannot answer. Those cite no ticket slug and so do not appear here. The exit
code is about the AUDIT, not about the compiler: 0 when every cited slug is
open, 1 when at least one closed ticket is still being cited.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The emitters, by the backend each one speaks for. Named rather than globbed:
# a glob would silently pick up a new file and silently miss a renamed one, and
# the whole point here is that the population is enumerated.
EMITTERS = {
    'x86-64':  'compiler/ir_codegen.inc',
    'i386':    'compiler/ir_codegen386.inc',
    'arm32':   'compiler/ir_codegen_arm32.inc',
    'aarch64': 'compiler/ir_codegen_aarch64.inc',
    'riscv32': 'compiler/ir_codegen_riscv32.inc',
    'xtensa':  'compiler/ir_codegen_xtensa.inc',
    'wasm32':  'compiler/ir_codegen_wasm32.inc',
}

TICKET_DIRS = ['devdocs/progress']
CLOSED = ('done', 'rejected', 'decided')

# A slug inside an Error(...) string literal. Slugs are kebab-case and long;
# the length floor keeps ordinary parenthesised prose out.
SLUG_IN_ERROR = re.compile(r"Error\('([^']*)'", re.S)
SLUG = re.compile(r'\b((?:bug|feature|refactor|chore|idea|decide|regression|meta|umbrella)-[a-z0-9-]{12,})\b')


def find_tickets():
    """slug -> the status folder it lives in. Last one wins; collisions are
    reported by the caller rather than hidden, because a slug in two folders is
    itself a finding."""
    where = {}
    for base in TICKET_DIRS:
        for dirpath, _dirs, files in os.walk(os.path.join(ROOT, base)):
            folder = os.path.basename(dirpath)
            for fn in files:
                if fn.endswith('.md'):
                    where.setdefault(fn[:-3], set()).add(folder)
    return where


def cited_slugs():
    """slug -> {backend: [refusal text, ...]} for every slug named inside an
    Error() call in an emitter."""
    out = {}
    for backend, rel in EMITTERS.items():
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            print('MISSING EMITTER %-8s %s -- the population list is stale, '
                  'which is the exact failure this tool is about' % (backend, rel))
            continue
        src = open(path, encoding='utf-8', errors='replace').read()
        for msg in SLUG_IN_ERROR.findall(src):
            for slug in set(SLUG.findall(msg)):
                out.setdefault(slug, {}).setdefault(backend, []).append(
                    ' '.join(msg.split())[:110])
    return out


def selftest():
    """The tool reports CLEAN when the tree is clean and CLEAN when its own
    pattern has stopped matching, and those two look identical from the outside.
    This is the case it must reject, built rather than found so it does not
    depend on the repo still containing an instance -- the repo's only one was
    fixed by the commit that added this file, which is exactly how a guard ends
    up permanently unable to fail.

    Drawn from the right population: the string below is the real refusal that
    was compiled into ir_codegen_riscv32.inc until a0b9eeb9a, character for
    character, and the slug is the real ticket, which is really in done/."""
    real = ("Error('target riscv32: aggregate/frozen-string result via an "
            "indirect call is not yet supported "
            "(feature-cross-virtual-indirect-hidden-dest)');")
    msgs = SLUG_IN_ERROR.findall(real)
    if not msgs:
        print('SELFTEST FAIL: SLUG_IN_ERROR did not match a real Error() call')
        return 1
    slugs = SLUG.findall(msgs[0])
    if 'feature-cross-virtual-indirect-hidden-dest' not in slugs:
        print('SELFTEST FAIL: SLUG did not find the slug in %r' % msgs[0])
        return 1
    where = find_tickets()
    if 'feature-cross-virtual-indirect-hidden-dest' not in where:
        print('SELFTEST FAIL: find_tickets() cannot see a ticket that exists')
        return 1
    folders = where['feature-cross-virtual-indirect-hidden-dest']
    if not folders.issubset(set(CLOSED)):
        # Not a tool failure: someone reopened it. Say so rather than fail.
        print('SELFTEST SKIP: the control ticket is no longer closed (%s). '
              'Pick another closed slug for the control.' % '/'.join(sorted(folders)))
        return 0
    # And the negative half: prose that merely mentions a slug is not a refusal.
    if SLUG_IN_ERROR.findall("{ see feature-cross-virtual-indirect-hidden-dest }"):
        print('SELFTEST FAIL: a comment mentioning a slug was read as a refusal')
        return 1
    print('selftest ok: the pattern finds a real refusal, resolves its ticket as '
          'closed, and does not fire on prose')
    return 0


def main():
    # DEFAULT RUNS BOTH, because tools-devtest invokes every guard with no
    # arguments and a guard whose instrument is untested is the thing this file
    # is about. --selftest and --audit-only exist for reading one of them alone.
    if '--selftest' in sys.argv[1:]:
        return selftest()
    if '--audit-only' not in sys.argv[1:]:
        rc = selftest()
        if rc:
            return rc
    where = find_tickets()
    cited = cited_slugs()
    bad = 0
    if not cited:
        # A tool that finds nothing because its pattern stopped matching reports
        # exactly what a clean tree reports. Say which it is.
        print('no ticket slug is cited by any refusal in %d emitters -- if that '
              'is a surprise, the pattern is what changed' % len(EMITTERS))
        return 0
    print('%d ticket slug(s) cited by refusals across %d emitters\n'
          % (len(cited), len(EMITTERS)))
    for slug in sorted(cited):
        folders = where.get(slug, set())
        closed = folders and folders.issubset(set(CLOSED))
        backends = sorted(cited[slug])
        if not folders:
            state = 'NO SUCH TICKET'
        elif closed:
            state = 'CLOSED in %s' % '/'.join(sorted(folders))
        else:
            state = 'open in %s' % '/'.join(sorted(folders))
        flag = '  ' if (folders and not closed) else '!!'
        if flag == '!!':
            bad += 1
        print('%s %s' % (flag, slug))
        print('     %s' % state)
        print('     still refused by: %s' % ', '.join(backends))
        if closed:
            missing = [b for b in EMITTERS if b not in cited[slug]]
            print('     NOT refused by:   %s' % (', '.join(missing) or '(none)'))
            print('     -> a closed ticket is still being cited. Either it closed over a')
            print('        SUBSET and these backends were never in scope, or the refusal is')
            print('        stale and should have been deleted with the fix. Read the ticket')
            print('        body: the three 2026-09-02 instances were all the former.')
        print()
    if bad:
        print('%d slug(s) cited by a live refusal while CLOSED. See above.' % bad)
        return 1
    print('every cited slug is open. No refusal points at a closed ticket.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
