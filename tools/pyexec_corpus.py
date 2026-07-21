#!/usr/bin/env python3
"""Extract + categorize the PYTHON-block corpus a uforth checkout ships.

Pins the contract for feature-lib-pyexec (the exec() / pyeval engine): what the
Python-subset tree-walker must parse and evaluate, and which host (vm.*) members
the reflection bridge must reach. Reads a uforth source tree; nothing from
uforth is vendored into this repo — run it against a local checkout.

Usage:  tools/pyexec_corpus.py [UFORTH_DIR] [--json OUT]
        (UFORTH_DIR defaults to ~/projects/uforth)
"""
import re, sys, os, json, glob

def extract(text):
    """Each PYTHON-block source: a "..." string immediately followed (past
    whitespace) by the PYTHON / 🐍 marker, matching uforth's tokenizer."""
    i, n, blocks = 0, len(text), []
    while i < n:
        if text[i] == '"':
            j = text.find('"', i + 1)
            if j == -1:
                break
            k = j + 1
            while k < n and text[k] in ' \t\r\n':
                k += 1
            m = re.match(r'(PYTHON|🐍)\b', text[k:])
            if m:
                blocks.append(text[i + 1:j])
                i = k + len(m.group(0))
                continue
            i = j + 1
        else:
            i += 1
    return blocks

VM_MEMBER = re.compile(r'\bvm\.([A-Za-z_]\w*)\s*(\()?')
FEAT = {
    'call_builtin': re.compile(r'\b(len|int|str|chr|ord|abs|range)\s*\('),
    'bitops':    re.compile(r'>>|<<|[&|^~]'),
    'ternary':   re.compile(r'\bif\b.*\belse\b'),
    'augassign': re.compile(r'[-+*/|&^%]=|<<=|>>='),
    'slice':     re.compile(r'\[[^]]*:[^]]*\]'),
    'floordiv':  re.compile(r'//'),
    'for':       re.compile(r'\bfor\b'),
    'while':     re.compile(r'\bwhile\b'),
    'fstring':   re.compile(r'f["\']'),
    'if_stmt':   re.compile(r'(^|;)\s*if\b'),
}

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    ufo_dir = args[0] if args else os.path.expanduser("~/projects/uforth")
    out = None
    if '--json' in sys.argv:
        out = sys.argv[sys.argv.index('--json') + 1]

    blocks, fields, methods = [], {}, {}
    featcount = {k: 0 for k in FEAT}
    pure_stack = 0
    for path in sorted(glob.glob(os.path.join(ufo_dir, "*.UFO"))):
        text = open(path, encoding='utf-8').read()
        for b in extract(text):
            fs, ms = set(), set()
            for m in VM_MEMBER.finditer(b):
                (ms if m.group(2) else fs).add(m.group(1))
            for f in fs: fields[f] = fields.get(f, 0) + 1
            for m in ms: methods[m] = methods.get(m, 0) + 1
            for k, rx in FEAT.items():
                if rx.search(b): featcount[k] += 1
            if not fs and not ms:
                pure_stack += 1
            blocks.append({'file': os.path.basename(path), 'src': b,
                           'fields': sorted(fs), 'methods': sorted(ms)})

    print(f"blocks: {len(blocks)}   pure-stack (no vm.*): {pure_stack}   "
          f"vm-accessing: {len(blocks) - pure_stack}")
    print("\nvm FIELDS (name: #blocks):")
    for k, v in sorted(fields.items(), key=lambda kv: -kv[1]):
        print(f"  {k}: {v}")
    print("\nvm METHODS (name: #blocks):")
    for k, v in sorted(methods.items(), key=lambda kv: -kv[1]):
        print(f"  {k}: {v}")
    print("\nlanguage features (name: #blocks):")
    for k, v in sorted(featcount.items(), key=lambda kv: -kv[1]):
        print(f"  {k}: {v}")
    if out:
        json.dump(blocks, open(out, 'w'), indent=1, ensure_ascii=False)
        print(f"\nwrote {len(blocks)} blocks -> {out}")

if __name__ == '__main__':
    main()
