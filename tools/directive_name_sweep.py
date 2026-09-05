#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Which compiler directive NAMES does pxx warn about that FPC accepts?

A spurious `unknown compiler directive` warning cannot fail any PASS/FAIL
instrument in this repo -- it exits 0 -- and under -Werror it stops valid code
from compiling.  bug-p-a-spurious-unknown-directive-warning-cannot-fail-any-
test-we-have.  This is the instrument that can see it.

TWO THINGS MAKE IT AN INSTRUMENT RATHER THAN A GREP.

1. It RUNS every candidate through both compilers instead of diffing against
   PAS_INERT_DIRECTIVES.  A misreading of our own list can then neither invent
   a finding nor hide one.

2. THE VERDICT IS WHAT FPC SAYS ABOUT THE NAME, NEVER THE EXIT CODE.  fpc
   answering `Illegal compiler directive "$X"` means fpc does not know the name
   either, so our warning is correct.  Anything else -- a note, a target-
   specific warning, or an error about the VALUE -- means fpc knows the name
   and ours was a false positive.  A bare `{$X}` probe makes a value-requiring
   directive error under fpc, so on exit code alone $ASMCPU is indistinguishable
   from a name fpc rejects; that is the case that forced this rule.

POSITIVE CONTROL, asserted rather than described: two invented names must warn
under BOTH compilers.  If they do not, the run aborts instead of reporting a
clean sweep -- a directive probe that never reaches the classifier reads
exactly like a corpus with nothing wrong in it.

CHOOSE THE CORPUS FOR WHAT IT CAN CONTAIN THAT THE LAST ONE COULD NOT.  Runs so
far, each finding what its predecessor structurally could not see:

  this tree (2166 sources, frankD)   -> clean; present-tense only, and a name
                                        absent HERE is invisible to it
  /usr/share/fpcsrc/3.2.2            -> 7 false positives; compiler, rtl and
                                        packages, and NOT the testsuite
  library_candidates/ (2501 sources) -> 2 more, both from the 9 names that
                                        appear in FPC's testsuite and nowhere
                                        in fpcsrc

Still unswept, for want of a corpus on this box: Delphi-only sources, vendor
units, FPC 3.3+.

Usage:  tools/directive_name_sweep.py <corpus dir> [<corpus dir> ...]
        tools/directive_name_sweep.py --only <name> [<name> ...]
        PXX=stable_linux_amd64/default/pinned tools/directive_name_sweep.py ...
"""
import collections
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(os.path.dirname(__file__)))
# $PXX points it at another compiler -- the pin, say. That is how the REPORTING
# path gets its own control: once a false positive is fixed, the only binary
# that still shows one is an older one, and a tool whose finding path has never
# been seen to fire is a tool that always prints "clean".
PXX = os.environ.get('PXX') or os.path.join(HERE, 'compiler', 'pascal26')
# `{$NAME` and `(*$NAME` -- the directive name is the word right after the $.
DIRECTIVE = re.compile(r'(?:\{|\(\*)\$([A-Za-z_][A-Za-z0-9_]*)')
SOURCE_EXT = ('.pas', '.pp', '.inc', '.dpr', '.lpr', '.p', '.dpk')
CONTROL_NAMES = ['zzznotadirectiveatall', 'pxxinventedcontrolname']


def census(roots):
    """name -> (occurrences, first path).  Aborts rather than measuring nothing.

    A CORPUS THAT IS NOT ON DISK MEASURES CLEAN AND DOES NOT ERROR, and on this
    box that is not hypothetical: `library_candidates/` is in .gitignore, so it
    never arrives by pull.  Counted 2026-09-06 by frank-coordinator across the
    checkouts here: 10 have it and 9 do not, live sessions on both sides, and
    nothing about a checkout announces which side it is on.  The same sweep run
    by two agents then returns two different answers and neither one errors.

    So the file count is printed with the verdict -- a corpus-derived number
    without its corpus root and size is not reportable -- and an absent root or
    an empty walk is a hard stop.
    bug-t-a-ticket-citing-a-corpus-file-is-only-reproducible-by-whoever-has-that-corpus
    """
    missing = [r for r in roots if not os.path.isdir(r)]
    if missing:
        sys.exit('corpus root(s) not on disk: %s\n'
                 'This tool would otherwise walk nothing and print "clean".\n'
                 'library_candidates/ is gitignored and never arrives by pull.'
                 % ', '.join(missing))
    seen = collections.Counter()
    where = {}
    files = 0
    for root in roots:
        for dirpath, _, filenames in os.walk(root):
            for fn in filenames:
                if not fn.lower().endswith(SOURCE_EXT):
                    continue
                files += 1
                path = os.path.join(dirpath, fn)
                try:
                    text = open(path, errors='replace').read()
                except OSError:
                    continue
                for m in DIRECTIVE.finditer(text):
                    name = m.group(1).lower()
                    seen[name] += 1
                    where.setdefault(name, path)
    if not seen:
        sys.exit('walked %d source file(s) under %s and found NO directive at '
                 'all.\nThat is a corpus this tool cannot say anything about, '
                 'not a clean sweep.' % (files, ', '.join(roots)))
    return seen, where, files


def probe(name, workdir):
    """(pxx warns about the name, fpc calls the name illegal, fpc's first word)."""
    src = os.path.join(workdir, 'p_%s.pas' % name)
    with open(src, 'w') as f:
        f.write('program p_%s;\n{$%s}\nbegin\nend.\n' % (name, name))
    pxx = subprocess.run([PXX, src, os.path.join(workdir, 'o_%s' % name)],
                         capture_output=True, text=True, cwd=workdir)
    fpc = subprocess.run(['fpc', '-FE' + workdir, src],
                         capture_output=True, text=True, cwd=workdir)
    pxx_out = pxx.stdout + pxx.stderr
    fpc_out = fpc.stdout + fpc.stderr
    says = ''
    for line in fpc_out.splitlines():
        if re.search(r'\b(Warning|Note|Hint|Error|Fatal)\b', line):
            says = re.sub(r'^[^)]*\) ', '', line).strip()
            break
    return ('unknown compiler directive' in pxx_out,
            'Illegal compiler directive' in fpc_out,
            says)


def main(argv):
    if not os.path.exists(PXX):
        sys.exit('no %s -- run `make compiler/pascal26` first' % PXX)

    with tempfile.TemporaryDirectory(prefix='dirsweep-') as workdir:
        # The control runs FIRST and aborts the sweep, because a clean result
        # from a probe that never reached the classifier is the failure this
        # whole file exists to avoid.
        for control in CONTROL_NAMES:
            warns, illegal, _ = probe(control, workdir)
            if not (warns and illegal):
                sys.exit('CONTROL FAILED: invented name %r gave pxx_warns=%s '
                         'fpc_illegal=%s -- expected both true. The probe is '
                         'not reaching the classifier; no verdict is possible.'
                         % (control, warns, illegal))
        print('control ok: an invented name warns under both compilers')

        if argv and argv[0] == '--only':
            names = [n.lower() for n in argv[1:]]
            if not names:
                sys.exit('--only needs at least one directive name')
            counts, where = collections.Counter(), {}
        else:
            counts, where, files = census(argv)
            names = sorted(counts)
            print('corpus: %s -- %d source files, %d distinct directive names'
                  % (', '.join(argv), files, len(names)))

        bad = []
        for name in names:
            warns, illegal, says = probe(name, workdir)
            if warns and not illegal:
                bad.append((name, counts.get(name, 0), where.get(name, ''), says))

        if not bad:
            print('no false positive: every name pxx warns about, fpc rejects too')
            return 0
        print('\n%d FALSE POSITIVE(S) -- fpc knows the name, pxx warns:' % len(bad))
        for name, n, path, says in bad:
            print('  {$%s}  uses=%d  %s' % (name, n, path))
            print('      fpc: %s' % (says or '(accepted silently)'))
        return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
