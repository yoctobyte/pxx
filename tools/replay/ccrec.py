#!/usr/bin/env python3
"""ccrec.py -- record a build's compiles as compile_commands.json (what `bear`
does), for build systems that do not write one (autotools, plain make).

    CCREC_LOG=/abs/rec.jsonl CC=/abs/tools/replay/ccrec.py ./configure ...
    CCREC_LOG=/abs/rec.jsonl make
    tools/replay/ccrec.py --merge /abs/rec.jsonl > compile_commands.json

As CC it appends one JSON line per compile (`-c` with a C source) to
$CCREC_LOG and then runs the real compiler ($CCREC_CC, default gcc) with the
same arguments, so the build is the ordinary gcc build -- the reference the
replay is compared with. Link steps, configure probes that do not compile a
file, and preprocessor-only runs (-E/-M without -c) are passed through
unrecorded. Configure probes (conftest.c, zlib's ztest$$.c) are dropped at
merge: their sources are deleted again, so an entry whose file is gone is one.
--merge keeps the LAST entry per (directory, file, output): a rebuild
replaces, it does not duplicate. The output is what tools/replay/compdb.py
reads (`units`). feature-tools-a-generic-compdb-replay
"""
import fcntl
import json
import os
import sys

SRC_EXT = ('.c', '.S', '.s')   # asm recorded too: compdb.py reports it as skipped


def record(argv):
    log = os.environ.get('CCREC_LOG')
    real = os.environ.get('CCREC_CC', 'gcc')
    if log and '-c' in argv:
        srcs = [a for a in argv if a.endswith(SRC_EXT) and not a.startswith('-')]
        out = None
        for i, a in enumerate(argv):
            if a == '-o' and i + 1 < len(argv):
                out = argv[i + 1]
            elif a.startswith('-o') and len(a) > 2:
                out = a[2:]
        if len(srcs) == 1:
            e = {'directory': os.getcwd(), 'arguments': [real] + argv,
                 'file': srcs[0]}
            if out:
                e['output'] = out
            with open(log, 'a') as f:
                fcntl.flock(f, fcntl.LOCK_EX)
                f.write(json.dumps(e) + '\n')
    os.execvp(real, [real] + argv)


def merge(path):
    seen = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            e = json.loads(line)
            # configure probes: autoconf's conftest.c, zlib's ztest$$.c, ...
            # -- all deleted again, so a source that no longer exists is one
            if not os.path.exists(os.path.join(e['directory'], e['file'])):
                continue
            seen[(e['directory'], e['file'], e.get('output'))] = e
    json.dump(list(seen.values()), sys.stdout, indent=1)
    sys.stdout.write('\n')


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--merge':
        merge(sys.argv[2])
    else:
        record(sys.argv[1:])
