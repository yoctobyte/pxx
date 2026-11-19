#!/usr/bin/env python3
"""help_coverage.py [--list] [--self-check] -- is every long option the
compiler ACCEPTS printed by `pascal26 --help` or documented in
docs/reference/cli.md?

Enumerated from the ARGUMENT PARSER, not from a grep of the docs: the docs are
the citing source, and the question is what the artefact accepts. A flag
nobody can find reads as "that flag does not exist", and the next move is to
correct a true reference on the strength of an incomplete list.
bug-a-help-does-not-advertise-flags-the-compiler-accepts

--help is curated on purpose (it ends by naming cli.md as the full list), so
the contract is help UNION cli.md, not help alone. Measured when this was
written: 99 accepted, 35 in --help, 10 in neither.

Accepted = every `'--name'` / `'--name='` literal compared against `option`
in compiler.pas, plus `Copy(option, 1, n) = '--name='` prefixes. A floor on
that count catches the pattern rotting into matching nothing. --self-check is
the positive control: an injected accepted flag that neither lists must be
flagged. Exit 0 = covered; 1 names each missing flag."""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FLOOR = 90


def accepted_flags(src):
    acc = set()
    for m in re.finditer(r"option\s*=\s*'(--[a-z0-9][a-z0-9-]*=?)", src):
        acc.add(m.group(1).rstrip('='))
    for m in re.finditer(r"Copy\(option,\s*1,\s*\d+\)\s*=\s*'(--[a-z0-9][a-z0-9-]*)=?'", src):
        acc.add(m.group(1))
    return acc


def listed(text):
    return set(re.findall(r'(--[a-z0-9][a-z0-9-]*)', text))


def main():
    src = open(os.path.join(ROOT, 'compiler', 'compiler.pas'), encoding='latin-1').read()
    acc = accepted_flags(src)
    if '--self-check' in sys.argv:
        acc.add('--pxx-help-coverage-self-check-probe')
    if len(acc) < FLOOR:
        print('help_coverage: only %d accepted flags found (floor %d) -- the parser '
              'pattern no longer matches compiler.pas; fix the checker' % (len(acc), FLOOR))
        return 1
    out = subprocess.run([os.path.join(ROOT, 'compiler', 'pascal26'), '--help'],
                         capture_output=True, text=True, errors='replace')
    helptext = out.stdout + out.stderr
    if 'docs/reference/cli.md' not in helptext:
        print('help_coverage: --help no longer names docs/reference/cli.md as the full list')
        return 1
    inhelp = listed(helptext)
    indoc = listed(open(os.path.join(ROOT, 'docs', 'reference', 'cli.md')).read())
    missing = sorted(acc - inhelp - indoc)
    if '--list' in sys.argv:
        print('accepted %d: in --help %d, in cli.md only %d, in neither %d'
              % (len(acc), len(acc & inhelp), len((acc & indoc) - inhelp), len(missing)))
    if '--self-check' in sys.argv:
        if missing == ['--pxx-help-coverage-self-check-probe']:
            print('help_coverage: self-check OK -- the injected flag was flagged, nothing else missing')
            return 0
        print('help_coverage: self-check FAILED -- expected only the probe, got %s' % missing)
        return 1
    for f in missing:
        print('help_coverage: accepted but in neither --help nor docs/reference/cli.md: ' + f)
    if missing:
        print('help_coverage: %d flag(s) undiscoverable. Document each in '
              'docs/reference/cli.md (or print it in --help).' % len(missing))
        return 1
    print('help_coverage: OK -- all %d accepted flags are in --help or cli.md' % len(acc))
    return 0


sys.exit(main())
