---
track: N
prio: 45
type: bug
blocked-by: []
summary: "A backslash immediately before a newline INSIDE a string literal is emitted as a literal backslash plus newline instead of being consumed as a line continuation. Affects ordinary and triple-quoted literals alike. Silent wrong VALUE — found because webencodings/mklabels.py generated a file with a stray leading backslash line."
---

# `\` before a newline inside a string literal is not a line continuation

- **Type:** bug (Nil-Python frontend) — **Track N**.
- **Filed:** 2026-08-18 by frank3-b, found running the corpus caller named by
  [[feature-b-mimic-urllib-request-over-the-rtl-http-stack]].

## The bug

Python's lexer consumes `\` + newline inside a string literal, emitting
nothing. NilPy emits both characters literally.

## Repro

```python
s = '''\
AB
CD'''
print(repr(s))
t = "x\
y"
print(repr(t))
```

pxx (pinned, HEAD `df15ae3fe`) prints `'\\\nAB\nCD'` then `'x\\\ny'`.

CPython prints `'AB\nCD'` then `'xy'`.

Both literal forms are affected, so it is the escape handling in the string
scanner, not anything specific to triple quotes.

## Why it matters more than it looks

This is a **silent wrong value**, not an error. The string still builds, the
program still runs, and the damage is two extra characters in the middle of
text — the kind of thing that surfaces far from the cause, which
`devdocs/dev/debugging-playbook.md` calls the expensive case.

`'''\` at the start of a triple-quoted block is a *common* Python idiom
precisely because it lets the first line of the content start at column 0, so
this is not an exotic corner.

## How it was found — a worked example of the damage

`library_candidates/webencodings/webencodings/mklabels.py` is a code generator
that prints a Python module. Run under pxx and under CPython against the same
local HTTP endpoint, the two outputs differ by exactly one line: pxx's
generated file starts with a stray `\` line. Everything else — all the label
mappings, the alignment padding, the JSON decoding — is identical.

So the generated module would be a **syntax error** in the file it generates,
from a generator that ran without complaint. That is the whole failure mode in
one artifact.

Reproduce it with any local server:

```
sed 's|http://encoding.spec.whatwg.org/encodings.json|http://127.0.0.1:PORT/enc.json|' \
  library_candidates/webencodings/webencodings/mklabels.py > mklabels_local.py
pinned mklabels_local.py out && ./out > pxx.txt
python3 mklabels_local.py > cpy.txt
diff cpy.txt pxx.txt      # one line: a leading '\'
```

with `enc.json` holding the WHATWG shape, e.g.
`[{"encodings":[{"labels":["utf-8","utf8"],"name":"UTF-8"}],"heading":"x"}]`.

## Not a urllib bug

Worth stating because of where it was found: `urlopen` is not involved. The
generator's HTTP fetch, its `.read().decode('ascii')` and its `json.loads` all
produce byte-identical results to CPython — the diff is entirely in the literal
that the generator prints.
