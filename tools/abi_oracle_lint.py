#!/usr/bin/env python3
"""Flag a backend that re-derives the parameter-passing convention from Syms[]
instead of asking the ABI oracle in compiler/abi.inc.

abi.inc states the invariant -- "backends consult the oracle and never re-derive
the convention from Syms[]" -- and then named its own enforcement: a review grep
for a `Syms[...].IsRef or` chain. That grep was calibrated to a SPELLING, not to
a shape. It matched nothing on real code for months while the convention was in
fact being re-derived longhand, spelled `and ... and not`. By 2026-08-31 it
matched exactly one line: a COMMENT in ir_codegen_wasm32.inc quoting the rule.
A reviewer who runs it opens the hit, finds prose, and concludes the tree is
clean -- which is worse than the zero it used to return.

So this asks the shape's question instead: does a single boolean condition in a
backend combine an ABI-carrying Syms[] field (IsRef / IsArray) with a type-kind
test? That is the re-derivation shape, however it is spelled.

Exit 1 if any unmarked site is found. A site that is a DELIBERATE per-target
divergence is silenced by putting

    { abi-divergence: <why this target must differ> }

in or immediately above the condition -- which is what abi.inc asks for, that
divergence be "deliberate and reviewable instead of accidental and invisible".
Silencing costs you a sentence; it cannot be done by accident.

## The baseline, and why it is not a suppression list

A site that is a KNOWN, FILED disagreement goes in `abi_oracle_lint.baseline`
with its ticket. The check then passes on exactly that set and fails on anything
new -- so it can be wired into a gate today, without marking the open aarch64
site as "not a finding" to manufacture a green.

The difference matters and is the whole design: a `{ abi-divergence: }` marker
says *this is not a finding*; a baseline entry says *this is a finding, it is
that one, and here is its ticket*. Only the second can fail later.

Two guards stop it decaying into the dead grep it replaces:

  * **A baseline entry that matches nothing is an ERROR, not silence.** The file
    cannot outlive its cause -- the day aarch64:2869 is fixed, this tells you to
    delete the line, rather than quietly passing forever the way the `IsRef or`
    grep did.
  * Entries are keyed on the CONDITION TEXT, not on a line number. Line numbers
    rot: three separate site coordinates in the ticket that prompted this tool
    were stale within four days, while their reasoning held.

Credit for the baseline design: frankwasm, who also supplied the argument for
wiring it -- an unwired check's result has to be READ, and reading is the step
that fails.

Run: tools/abi_oracle_lint.py [--list] [--selftest]
"""
import glob, os, re, sys

# The oracle's question is narrow, and the narrowness is the whole point:
# "does a PARAMETER's stack slot hold the ADDRESS OF THE VALUE?" So a condition
# is only re-deriving the convention if it is about a PARAMETER. Two shapes look
# similar and are NOT this, both verified by reading before being excluded:
#   * type dispatch in IR_STORE -- `TypeIsFrozenString(tk) and not IsArray`
#     picks a store lowering, it does not ask where a param lives;
#   * local finalisation -- `Kind = skLocal` blocks releasing managed locals.
# Including those made the first baseline 78, of which the large majority could
# never have been oracle calls. A linter whose hits are mostly noise gets muted,
# which is the same end state as one that cannot fire.
ABI_FIELD    = re.compile(r'Syms\[[^\]]+\]\.(IsRef|IsArray)\b')
TYPE_TEST    = re.compile(r'Syms\[[^\]]+\]\.TypeKind\b')
PARAM_SIGNAL = re.compile(r'Syms\[[^\]]+\]\.IsRef\b|\bskParam\b')
NOT_A_PARAM  = re.compile(r'\bskLocal\b')
MARKER    = re.compile(r'abi-divergence\s*:', re.I)
# Routine-scoped exemption: some whole routines ask a question the oracle does
# not answer (slot WIDTH and register class, rather than slot-holds-ADDRESS).
# One stated reason beats seventeen identical per-site markers -- and it expires
# on its own, because it is cleared by the next top-level routine header, so a
# new routine cannot inherit an exemption written for its neighbour.
REVIEWED  = re.compile(r'abi-oracle-reviewed\s*:', re.I)
ROUTINE   = re.compile(r'^(procedure|function)\s', re.I)
COND_HEAD = re.compile(r'\b(if|while)\b', re.I)


def strip_comments(text):
    """Blank out { } and (* *) comments and // tails, preserving line count and
    column positions so reported coordinates stay true."""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        if text[i] == '{':
            j = text.find('}', i)
            j = n if j < 0 else j
            for k in range(i, min(j + 1, n)):
                if out[k] != '\n':
                    out[k] = ' '
            i = j + 1
        elif text.startswith('(*', i):
            j = text.find('*)', i)
            j = n if j < 0 else j + 1
            for k in range(i, min(j + 1, n)):
                if out[k] != '\n':
                    out[k] = ' '
            i = j + 1
        elif text.startswith('//', i):
            j = text.find('\n', i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = ' '
            i = j
        elif text[i] == "'":                      # Pascal string literal
            j = i + 1
            while j < n and text[j] != "'":
                j += 1
            i = j + 1
        else:
            i += 1
    return ''.join(out)


def conditions(src):
    """Yield (line_no, condition_text) for each if/while condition, following it
    across lines to its `then`/`do` at paren depth 0. Multi-line is the point:
    the real chains wrap, which is half of why a line-oriented grep missed them."""
    lines = src.split('\n')
    for idx, line in enumerate(lines):
        for m in COND_HEAD.finditer(line):
            kw = m.group(1).lower()
            end_kw = 'then' if kw == 'if' else 'do'
            buf, depth, li, pos = [], 0, idx, m.end()
            while li < len(lines) and li < idx + 40:
                seg = lines[li][pos:]
                for ch in seg:
                    if ch == '(':
                        depth += 1
                    elif ch == ')':
                        depth -= 1
                buf.append(seg)
                joined = ' '.join(buf)
                mk = re.search(r'\b' + end_kw + r'\b', joined, re.I)
                if mk and depth <= 0:
                    yield idx + 1, joined[:mk.start()]
                    break
                li += 1
                pos = 0


def load_baseline(path):
    """-> [(file, condition, note)] ; blank lines and # comments ignored."""
    out = []
    if not os.path.exists(path):
        return out
    for line in open(path, encoding='utf-8'):
        line = line.rstrip('\n')
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        parts = [p.strip() for p in line.split('\t') if p.strip()]
        if len(parts) >= 2:
            out.append((parts[0], parts[1], parts[2] if len(parts) > 2 else ''))
    return out


def apply_baseline(hits, baseline):
    """-> (new_hits, stale_entries). Matching is on file + condition text, so an
    edit elsewhere in the file cannot silently retire an entry."""
    remaining = list(baseline)
    new = []
    for path, ln, cond in hits:
        base = os.path.basename(path)
        for i, (bf, bc, _note) in enumerate(remaining):
            if bf == base and bc == cond:
                remaining.pop(i)
                break
        else:
            new.append((path, ln, cond))
    return new, remaining


def scan(paths):
    hits = []
    for path in paths:
        raw = open(path, encoding='utf-8', errors='replace').read()
        src = strip_comments(raw)
        rawlines = raw.split('\n')
        striplines = src.split('\n')
        # Lines covered by a routine-scoped exemption.
        exempt, active = set(), False
        for i, l in enumerate(rawlines):
            if ROUTINE.match(l):
                active = False
            if REVIEWED.search(l):
                active = True
            if active:
                exempt.add(i + 1)
        for ln, cond in conditions(src):
            if ln in exempt:
                continue
            if not (ABI_FIELD.search(cond) and TYPE_TEST.search(cond)):
                continue
            if not PARAM_SIGNAL.search(cond):
                continue
            if NOT_A_PARAM.search(cond):
                continue
            # The marker may sit ANYWHERE in the contiguous comment block above
            # the condition, however long that block is. A fixed look-back
            # window silently fails to pick up a marker that a long
            # justification has pushed out of range -- measured by frankS, who
            # placed one correctly and had the site keep reporting. That failure
            # is safe (the site stays visible) but it is silent, which is the
            # property this tool exists to object to.
            #
            # A line is comment-only when it is non-blank in the raw source and
            # blank after comment stripping. Walk up over those and over blank
            # lines, stopping at the first line carrying code.
            top = ln - 1                        # 1-based ln -> index of line above
            while top > 0:
                rawl, stripl = rawlines[top - 1], striplines[top - 1]
                if rawl.strip() and stripl.strip():
                    break                       # real code: the block ends here
                top -= 1
            window = '\n'.join(rawlines[max(0, top - 1):ln + 6])
            if MARKER.search(window):
                continue
            hits.append((path, ln, ' '.join(cond.split())[:110]))
    return hits


def selftest():
    """A check that cannot fail is not a check. Both controls are asserted."""
    ok = True

    # POSITIVE: the shape, in the spelling the old grep could see.
    pos1 = "if Syms[si].IsRef or (Syms[si].TypeKind = tyAnsiString) then\n"
    # POSITIVE: the same shape in the spelling that defeated the old grep, wrapped
    # across lines -- this is riscv32's IR_LEA chain reduced to its skeleton.
    pos2 = ("else if (Syms[si].TypeKind = tyAnsiString) and not Syms[si].IsArray and\n"
            "        not ((Syms[si].Kind = skParam) and Syms[si].IsRef) then\n")
    # NEGATIVE: a real line from the tree -- abi.inc's own rule, quoted inside a
    # comment. The old grep's only 2026-08-31 hit. Must NOT be reported.
    neg1 = "  { note names the exact shape it exists to stop -- a `Syms[x].IsRef or`\n" \
           "    chain with a Syms[x].TypeKind test beside it }\n"
    # NEGATIVE: a marker at the TOP of a long comment block must still take.
    # 14 filler lines put it far outside any fixed 8-line look-back.
    neg6 = ("{ abi-divergence: stated at the top of a long justification }\n"
            + "{ filler }\n" * 14
            + "if Syms[si].IsRef and (Syms[si].TypeKind = tyAnsiString) then Foo;\n")
    # POSITIVE: but a marker separated from the condition by real CODE is not
    # this condition's marker, however close it is.
    pos4 = ("{ abi-divergence: belongs to the statement below, not the one after }\n"
            "Bar(1);\n"
            "if Syms[si].IsRef and (Syms[si].TypeKind = tyAnsiString) then Foo;\n")
    # NEGATIVE: a routine-scoped exemption covers the site below it...
    neg5 = ("procedure EmitSomething(p: Integer);\n"
            "{ abi-oracle-reviewed: asks slot width, not slot-holds-address }\n"
            "begin\n"
            "  if Syms[si].IsRef and (Syms[si].TypeKind = tyAnsiString) then Foo;\n")
    # POSITIVE: ...and it must NOT leak into the NEXT routine. Same body, but the
    # condition now sits past a new routine header. This is the control that
    # stops a broad exemption from quietly silencing the whole rest of a file.
    pos3 = neg5 + ("end;\n\nprocedure EmitOther(p: Integer);\nbegin\n"
                   "  if Syms[si].IsRef and (Syms[si].TypeKind = tyAnsiString) then Bar;\n")
    # NEGATIVE: a reviewed, deliberately-divergent site.
    neg2 = ("{ abi-divergence: this target passes it differently on purpose }\n"
            "if Syms[si].IsRef and (Syms[si].TypeKind = tyAnsiString) then\n")

    # NEGATIVE: IR_STORE type dispatch. Real line from ir_codegen.inc:6183.
    # Picks a store lowering; asks nothing about where a parameter lives.
    neg3 = "else if TypeIsFrozenString(Syms[symIdx].TypeKind) and not Syms[symIdx].IsArray then\n"
    # NEGATIVE: local finalisation. Real shape from ir_codegen.inc:11909.
    neg4 = ("if (Syms[i].Kind = skLocal) and (i <> retSymIdx) and\n"
            "   (Syms[i].TypeKind = tyAnsiString) and not Syms[i].IsArray then\n")

    import tempfile
    for name, body, want in (('pos1', pos1, 1), ('pos2', pos2, 1),
                             ('pos3', pos3, 1), ('pos4', pos4, 1),
                             ('neg6', neg6, 0),
                             ('neg1', neg1, 0), ('neg2', neg2, 0),
                             ('neg3', neg3, 0), ('neg4', neg4, 0),
                             ('neg5', neg5, 0)):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, 'ir_codegen_probe.inc')
            open(p, 'w').write(body)
            got = len(scan([p]))
        status = 'ok' if got == want else 'FAILED'
        if got != want:
            ok = False
        print(f'  selftest {name}: expected {want} hit(s), got {got} -- {status}')

    # --- baseline controls. A baseline is a suppression list unless it can fail.
    hit = ('compiler/ir_codegen_probe.inc', 42, 'Syms[si].IsRef and (Syms[si].TypeKind = tyAnsiString)')
    cases = (
        # exact match -> nothing new, nothing stale
        ('base_match',  [hit], [('ir_codegen_probe.inc', hit[2], 'tkt')], 0, 0),
        # a finding absent from the baseline must still be reported
        ('base_new',    [hit], [],                                        1, 0),
        # THE control that stops rot: an entry matching nothing is STALE, and
        # stale must be an error. Without this the file outlives its cause and
        # passes forever -- which is exactly how the grep it replaced behaved.
        ('base_stale',  [],    [('ir_codegen_probe.inc', 'Syms[x].IsRef and (Syms[x].TypeKind = tySet)', 'tkt')], 0, 1),
        # an entry must not match a DIFFERENT condition in the same file
        ('base_narrow', [hit], [('ir_codegen_probe.inc', 'Syms[q].IsRef and (Syms[q].TypeKind = tySet)', 'tkt')], 1, 1),
    )
    for name, hits_in, base_in, want_new, want_stale in cases:
        new, stale = apply_baseline(hits_in, base_in)
        good = (len(new) == want_new and len(stale) == want_stale)
        if not good:
            ok = False
        print(f'  selftest {name}: expected new={want_new} stale={want_stale}, '
              f'got new={len(new)} stale={len(stale)} -- {"ok" if good else "FAILED"}')
    return ok


def main():
    args = sys.argv[1:]
    if '--selftest' in args:
        sys.exit(0 if selftest() else 1)

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    paths = sorted(glob.glob(os.path.join(root, 'compiler', 'ir_codegen*.inc')))
    all_hits = scan(paths)

    bpath = os.path.join(root, 'tools', 'abi_oracle_lint.baseline')
    baseline = load_baseline(bpath)
    hits, stale = apply_baseline(all_hits, baseline)

    if stale:
        print('abi-oracle-lint: STALE BASELINE -- these entries matched nothing.\n'
              'A baseline entry that cannot fire is the dead grep this tool replaced.\n'
              'If the site was fixed, DELETE the line (and close its ticket):\n')
        for bf, bc, note in stale:
            print(f'  {bf}  {note}')
            print(f'    {bc[:100]}')
        return 1

    if not hits:
        n = len(baseline)
        print('abi-oracle-lint: clean -- no unmarked convention re-derivation'
              + (f' beyond {n} baselined site(s).' if n else '.'))
        print('  (if this is the FIRST run, that is not a pass: see --selftest)')
        return 0

    by_file = {}
    for path, ln, cond in hits:
        by_file.setdefault(os.path.basename(path), []).append((ln, cond))
    print(f'abi-oracle-lint: {len(hits)} unmarked site(s) re-deriving the '
          f'convention from Syms[] instead of asking abi.inc:\n')
    for f in sorted(by_file):
        print(f'  {f}  ({len(by_file[f])})')
        if '--list' in args:
            for ln, cond in by_file[f]:
                print(f'    :{ln}  {cond}')
    print('\nEach is either (a) asking a question ABIParamSlotHoldsValueAddr et al.\n'
          'already answer -- call the oracle -- or (b) a deliberate per-target\n'
          'divergence, which abi.inc wants stated: add { abi-divergence: <why> }.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
