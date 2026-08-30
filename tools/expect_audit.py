#!/usr/bin/env python3
"""Classify Makefile test expectations as DERIVED or likely CAPTURED.

An expectation that was CAPTURED -- someone ran the program, looked at the
output and pasted it in -- records whatever the compiler did that day, bugs
included, and then defends that behaviour after the fix. See
chore-t-audit-which-test-expectations-were-captured-from-output-rather-than-derived.

The signal this tool uses is deliberately narrow and mechanical: **does the
expected text appear literally in the test's own source?** A test that prints
`writeln('looped 3')` and is checked against `looped 3` is derived by
inspection -- a reader can confirm it without running anything. A test checked
against a value that appears nowhere in its source is a COMPUTED result, and a
computed result is where capture happens.

This is a triage tool, not a verdict. It cannot know that `15511210043330985984000000`
is 25!, and it will flag it. What it does is turn 3101 expectations into a
ranked reading list, so the judgement is spent where capture is possible at all.

Usage: tools/expect_audit.py [--bucket high|med|low] [--limit N]
"""
import re, sys, os, collections

MAKEFILE = 'Makefile'
EXPECT = re.compile(r'expect_same\.sh\s+([A-Za-z0-9_./-]+)\s+(".*")\s*$')
# a compile line naming a source we can read
SRC = re.compile(r'\b(test/[A-Za-z0-9_./-]+\.(?:pas|npy|c|zig|rs))\b')

def split_args(s):
    """Split a trailing `"cmd" "expected"` pair, respecting escaped quotes."""
    parts, cur, q, i = [], [], False, 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            cur.append(s[i:i+2]); i += 2; continue
        if c == '"':
            if q: parts.append(''.join(cur)); cur = []; q = False
            else: q = True
            i += 1; continue
        if q: cur.append(c)
        i += 1
    return parts

def tokens(expected):
    """Content tokens worth looking for in the source."""
    e = expected
    e = re.sub(r'\$\$\(printf\s+', ' ', e)
    e = re.sub(r"%b|\\n|\\t|'", ' ', e)
    toks = re.findall(r"[A-Za-z_][A-Za-z0-9_]{2,}|-?\d+(?:\.\d+)?", e)
    # drop make/shell plumbing that is never test content
    drop = {'TESTTMP','printf','grep','head','tail','sort','uniq','wc','sed','awk','tr'}
    return [t for t in toks if t not in drop]

def main():
    lines = open(MAKEFILE, errors='replace').read().split('\n')
    src_cache = {}
    rows = []
    last_src = None
    for i, ln in enumerate(lines):
        m = SRC.search(ln)
        if m and 'expect_same' not in ln:
            last_src = m.group(1)
        m = EXPECT.search(ln)
        if not m:
            continue
        name = m.group(1)
        args = split_args(m.group(2))
        expected = args[-1] if args else ''
        src = last_src
        body = ''
        if src and os.path.exists(src):
            if src not in src_cache:
                src_cache[src] = open(src, errors='replace').read()
            body = src_cache[src]
        toks = tokens(expected)
        if not toks:
            hit = 1.0
        else:
            found = sum(1 for t in toks if t in body)
            hit = found / len(toks)
        if not body:
            bucket = 'nosrc'
        elif hit >= 0.85:
            bucket = 'low'
        elif hit >= 0.4:
            bucket = 'med'
        else:
            bucket = 'high'
        rows.append((bucket, round(hit, 2), name, src or '-', expected[:100], i + 1))
    want = None
    limit = 40
    a = sys.argv[1:]
    if '--bucket' in a: want = a[a.index('--bucket') + 1]
    if '--limit' in a: limit = int(a[a.index('--limit') + 1])
    counts = collections.Counter(r[0] for r in rows)
    print("expectations: %d   low(derivable-by-inspection)=%d  med=%d  HIGH(computed)=%d  no-source=%d"
          % (len(rows), counts['low'], counts['med'], counts['high'], counts['nosrc']))
    if want:
        sel = [r for r in rows if r[0] == want]
        sel.sort(key=lambda r: r[1])
        print("\n-- bucket %s: %d rows (showing %d), lowest literal-overlap first --"
              % (want, len(sel), min(limit, len(sel))))
        for b, h, n, s, e, ln in sel[:limit]:
            print("  Makefile:%-6s %-34s %-38s hit=%.2f  %s" % (ln, n[:34], s[:38], h, e[:60]))

if not any(f in sys.argv for f in ('--files','--oracle','--oracle-c','--oracle-pas')):
    main()

# ---------------------------------------------------------------------------
# Second population: the test/**/*.expected corpus.
#
# A .expected file is a transcript by idiom -- the usual way one comes into
# existence is redirecting a program's output into it. That makes this corpus
# the place captured expectations actually live, and it is four times the size
# of the Makefile's inline literals. Same signal as above: how much of the
# expected text appears literally in the test's own source.
# ---------------------------------------------------------------------------

def audit_expected_files(limit=40, want=None):
    import glob
    files = sorted(glob.glob('test/**/*.expected', recursive=True))
    mk = open(MAKEFILE, errors='replace').read()
    rows = []
    for f in files:
        stem = f[:-len('.expected')]
        src = None
        for ext in ('.pas', '.npy', '.c', '.zig', '.rs'):
            if os.path.exists(stem + ext):
                src = stem + ext; break
        exp = open(f, errors='replace').read()
        wired = os.path.basename(f) in mk or f in mk
        if src is None:
            rows.append(('nosrc', 0.0, f, '-', wired, len(exp))); continue
        body = open(src, errors='replace').read()
        toks = tokens(exp)
        hit = 1.0 if not toks else sum(1 for t in toks if t in body) / len(toks)
        bucket = 'low' if hit >= 0.85 else ('med' if hit >= 0.4 else 'high')
        rows.append((bucket, round(hit, 2), f, src, wired, len(exp)))
    c = collections.Counter(r[0] for r in rows)
    print("\n.expected files: %d   low=%d  med=%d  HIGH(computed)=%d  no-source=%d   unwired=%d"
          % (len(rows), c['low'], c['med'], c['high'], c['nosrc'],
             sum(1 for r in rows if not r[4])))
    if want:
        sel = [r for r in rows if r[0] == want]
        sel.sort(key=lambda r: (r[1], -r[5]))
        print("-- bucket %s: %d rows (showing %d), lowest literal-overlap first --"
              % (want, len(sel), min(limit, len(sel))))
        for b, h, f, s, w, n in sel[:limit]:
            print("  hit=%.2f %6dB %-52s src=%-30s %s" % (h, n, f[:52], os.path.basename(s)[:30],
                                                          '' if w else 'UNWIRED'))
    return rows

if '--files' in sys.argv:
    a = sys.argv
    audit_expected_files(limit=int(a[a.index('--limit')+1]) if '--limit' in a else 40,
                         want=a[a.index('--bucket')+1] if '--bucket' in a else None)


# ---------------------------------------------------------------------------
# --oracle: the strong form of the question, for the one population that has an
# independent oracle.
#
# A NilPy test is a Python program. CPython can run it. So for every
# test_nilpy_*.npy with a .expected, "is this expectation derived?" has a real
# answer rather than a heuristic one: run it under CPython and compare. An
# expectation CPython reproduces byte for byte is reproducible without running
# the implementation under test -- which is this audit's whole criterion.
#
# Everything that does NOT agree must be listed in test/nilpy_transcripts.txt
# with a reason. This check enforces that registry in BOTH directions, so it
# cannot quietly grow (a newly-disagreeing test is reported) or quietly rot (an
# entry that starts agreeing is reported as stale).
#
# Exit 1 on any drift, so it can gate.
# ---------------------------------------------------------------------------

REGISTRY = 'test/nilpy_transcripts.txt'


def oracle():
    import glob, subprocess
    listed = set()
    if os.path.exists(REGISTRY):
        for ln in open(REGISTRY, errors='replace'):
            ln = ln.split('#')[0].strip()
            if ln:
                listed.add(ln)
    agree, disagree = set(), {}
    pairs = []
    for e in sorted(glob.glob('test/**/*.expected', recursive=True)):
        npy = e[:-len('.expected')] + '.npy'
        if os.path.exists(npy):
            pairs.append((npy, e))
    for npy, e in pairs:
        name = os.path.basename(npy)[:-4]
        want = open(e, errors='replace').read().rstrip('\n')
        try:
            p = subprocess.run(['python3', npy], capture_output=True, text=True, errors='replace', timeout=15)
        except subprocess.TimeoutExpired:
            disagree[name] = 'cpython timeout'; continue
        if p.returncode != 0:
            disagree[name] = 'cpython: ' + (p.stderr.strip().split('\n')[-1] if p.stderr else 'error')[:70]
        elif p.stdout.rstrip('\n') == want:
            agree.add(name)
        else:
            disagree[name] = 'output differs from CPython'
    print("NilPy expectations with a CPython oracle: %d" % len(pairs))
    print("  DERIVED  (CPython reproduces the .expected) : %d" % len(agree))
    print("  transcripts (cannot be confirmed)           : %d" % len(disagree))
    unlisted = sorted(set(disagree) - listed)
    stale = sorted(listed & agree)
    for n in unlisted:
        print("  NEW TRANSCRIPT (not in %s): %s -- %s" % (REGISTRY, n, disagree[n]))
    for n in stale:
        print("  STALE ENTRY (now agrees with CPython, drop it from %s): %s" % (REGISTRY, n))
    missing = sorted(listed - set(disagree) - agree)
    for n in missing:
        print("  REGISTRY NAMES A TEST THAT NO LONGER EXISTS: %s" % n)
    ok = not (unlisted or stale or missing)
    print("  registry: %s" % ("in sync" if ok else "OUT OF SYNC"))
    return 0 if ok else 1


# ---------------------------------------------------------------------------
# --oracle-c: the same strong check for the C corpus, with gcc as the oracle.
#
# The instrument here is NOT a reimplementation of the comparison. It runs the
# Makefile's own recipe line, with `tools/expect_same.sh` doing the comparing,
# against a TESTTMP populated with gcc-built binaries instead of pxx-built ones.
# That matters: the first version of this DID reimplement it, and reported 321
# of 362 expectations as disagreeing. They were lines of the shape
#
#     $(TESTTMP)/prog; tools/expect_same.sh prog-rc "$$?" "89"
#
# where the assertion is the exit code of a binary the reimplementation never
# ran, so it compared 0 against 89 every time. A 321/362 disagreement rate is
# not a finding, it is a broken harness -- and running the real recipe line
# removes the entire class, because there is no second implementation of the
# semantics to get wrong.
#
# Two populations have no native gcc oracle and are counted, not judged:
# sources gcc rejects (pxx C extensions), and cross-target rows that go through
# tools/run_target.sh -- qemu correctly refuses a natively-built ELF.
# ---------------------------------------------------------------------------

def oracle_c(tmp=None):
    import subprocess, tempfile, collections as _c
    tmp = tmp or tempfile.mkdtemp(prefix='expect_audit_c_')
    mk = open(MAKEFILE, errors='replace').read().split('\n')
    CMAP = re.compile(r'\$\(COMPILER\)[^\n]*?\b(test/[A-Za-z0-9_./-]+\.c)\s+\$\(TESTTMP\)/([A-Za-z0-9_.-]+)')
    b2s = {}
    for l in mk:
        for m in CMAP.finditer(l):
            b2s.setdefault(m.group(2), m.group(1))
    E2 = re.compile(r'expect_same\.sh\s+([A-Za-z0-9_./-]+)\s+(".*")\s*$')
    BIN = re.compile(r'\$\(TESTTMP\)/([A-Za-z0-9_.-]+)')
    OTHER = re.compile(r'\$\((?!TESTTMP\))[A-Za-z_]+\)')
    rows = []
    for i, l in enumerate(mk):
        if not E2.search(l):
            continue
        names = set(BIN.findall(l)) & set(b2s)
        if len(names) == 1:
            rows.append((next(iter(names)), E2.search(l).group(1), l, i + 1))
    built, rej = set(), 0
    for b in sorted({r[0] for r in rows}):
        p = subprocess.run(['gcc', '-w', '-I', 'test', '-o', os.path.join(tmp, b), b2s[b]],
                           capture_output=True, text=True, errors='replace', timeout=90)
        if p.returncode == 0: built.add(b)
        else: rej += 1
    res = _c.Counter(); bad = []
    for b, name, line, ln in rows:
        if b not in built:
            res['no oracle: gcc rejects the source'] += 1; continue
        recipe = line.lstrip('\t').lstrip()
        while recipe[:1] in ('@', '-', '+'): recipe = recipe[1:]
        if 'run_target.sh' in recipe:
            res['no oracle: cross-target row'] += 1; continue
        if OTHER.search(recipe):
            res['skipped: other make variable'] += 1; continue
        sh = recipe.replace('$$', '$').replace('$(TESTTMP)', '$TESTTMP')
        try:
            p = subprocess.run(['bash', '-c', 'export TESTTMP=%s\n%s\n' % (tmp, sh)],
                               capture_output=True, text=True, errors='replace', timeout=40)
        except subprocess.TimeoutExpired:
            res['timeout'] += 1; continue
        if p.returncode == 0: res['DERIVED (gcc reproduces it)'] += 1
        else:
            res['DISAGREES WITH GCC'] += 1
            bad.append((name, ln, (p.stdout + p.stderr)[:200]))
    print("C expectations tied to exactly one gcc-buildable binary: %d rows, %d binaries built of %d"
          % (len(rows), len(built), len(built) + rej))
    for k, v in res.most_common():
        print("  %-36s %d" % (k, v))
    for n, ln, d in bad:
        print("  DISAGREES: %s (Makefile:%d)\n    %s" % (n, ln, d.replace('\n', '\n    ')[:200]))
    return 1 if bad else 0


# ---------------------------------------------------------------------------
# --oracle-pas: FPC as the oracle for the Pascal corpus.
#
# Weaker than the other two, and the difference is the point. CPython IS the
# definition of what a .npy should do and gcc IS the definition for portable C,
# so a disagreement there is a finding. FPC is only the reference for the subset
# of the dialect pxx shares with it -- a test written for a pxx extension may
# compile under FPC and legitimately behave differently. So here:
#
#   FPC agrees  -> the expectation is DERIVED, full stop. That direction is
#                  sound: an independent implementation reproduced the value.
#   FPC differs -> NOT a finding on its own. It is a candidate: either a
#                  deliberate dialect divergence or a captured expectation, and
#                  only reading tells them apart.
#
# Flags are the project's canonical ones (tools/fpc_diff_probe.sh): -Mobjfpc -vw.
# ---------------------------------------------------------------------------

def oracle_pas(limit=None):
    import subprocess, tempfile, collections as _c
    tmp = tempfile.mkdtemp(prefix='expect_audit_pas_')
    units = os.path.join(tmp, 'u'); os.makedirs(units, exist_ok=True)
    mk = open(MAKEFILE, errors='replace').read().split('\n')
    CMAP = re.compile(r'\$\(COMPILER\)[^\n]*?\b(test/[A-Za-z0-9_./-]+\.pas)\s+\$\(TESTTMP\)/([A-Za-z0-9_.-]+)')
    b2s = {}
    for l in mk:
        for m in CMAP.finditer(l):
            b2s.setdefault(m.group(2), m.group(1))
    E2 = re.compile(r'expect_same\.sh\s+([A-Za-z0-9_./-]+)\s+(".*")\s*$')
    BIN = re.compile(r'\$\(TESTTMP\)/([A-Za-z0-9_.-]+)')
    OTHER = re.compile(r'\$\((?!TESTTMP\))[A-Za-z_]+\)')
    rows = []
    for i, l in enumerate(mk):
        if not E2.search(l):
            continue
        names = set(BIN.findall(l)) & set(b2s)
        if len(names) == 1:
            rows.append((next(iter(names)), E2.search(l).group(1), l, i + 1))
    if limit:
        rows = rows[:limit]
    built = set()
    nbuild = 0
    for b in sorted({r[0] for r in rows}):
        try:
            p = subprocess.run(['fpc', '-Mobjfpc', '-vw', '-FU' + units,
                                '-o' + os.path.join(tmp, b), b2s[b]],
                               capture_output=True, text=True, errors='replace', timeout=90)
        except subprocess.TimeoutExpired:
            continue
        nbuild += 1
        if p.returncode == 0 and os.path.exists(os.path.join(tmp, b)):
            built.add(b)
    res = _c.Counter(); cand = []
    for b, name, line, ln in rows:
        if b not in built:
            res['no oracle: fpc cannot build it'] += 1; continue
        recipe = line.lstrip('\t').lstrip()
        while recipe[:1] in ('@', '-', '+'): recipe = recipe[1:]
        if 'run_target.sh' in recipe:
            res['no oracle: cross-target row'] += 1; continue
        if OTHER.search(recipe):
            res['skipped: other make variable'] += 1; continue
        sh = recipe.replace('$$', '$').replace('$(TESTTMP)', '$TESTTMP')
        try:
            p = subprocess.run(['bash', '-c', 'export TESTTMP=%s\n%s\n' % (tmp, sh)],
                               capture_output=True, text=True, errors='replace', timeout=40)
        except subprocess.TimeoutExpired:
            res['timeout'] += 1; continue
        if p.returncode == 0:
            res['DERIVED (fpc reproduces it)'] += 1
        else:
            res['candidate: fpc differs (read it)'] += 1
            cand.append((name, ln))
    print("Pascal expectations tied to one .pas-built binary: %d rows, fpc built %d of %d binaries"
          % (len(rows), len(built), nbuild))
    for k, v in res.most_common():
        print("  %-38s %d" % (k, v))
    if cand:
        print("\n  candidates to read (fpc differs -- dialect divergence OR capture):")
        # No cap. A truncated list in an audit tool reads as "that is all of
        # them", and the whole point of this pass is that the remainder is the
        # reading queue -- an elided tail is the part nobody then reads.
        for n, ln in cand:
            print("    Makefile:%-7d %s" % (ln, n))
    return 0


if '--oracle' in sys.argv:
    sys.exit(oracle())
if '--oracle-c' in sys.argv:
    sys.exit(oracle_c())
if '--oracle-pas' in sys.argv:
    a = sys.argv
    sys.exit(oracle_pas(limit=int(a[a.index('--limit')+1]) if '--limit' in a else None))
