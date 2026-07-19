---
track: N
prio: 55
type: feature
claimed: claude-n-uforth
---

# NilPy lexer: hex/octal/binary int literals, triple-quoted strings, string line counting

Part of [[feature-nilpy-corpus-uforth]] milestone 1 (first parse blockers in
uforth.py, file order).

## Bugs/gaps

1. **Hex literals silently misparse**: `SYS_DATA_START = 0x10000` lexes as
   integer `0` followed by identifier `x10000` — no error, wrong value.
   uforth.py's memory map (lines 40-55) is all hex. Add `0x`/`0X`, `0o`/`0O`,
   `0b`/`0B` prefixes + `_` digit separators (also in decimal/float).
2. **Triple-quoted strings**: `"""docstring"""` currently lexes as empty
   string + runaway single-quote string swallowing the docstring body.
   Add real `'''`/`"""` handling (multi-line, no escape of the quote run).
3. **SrcLine not incremented inside string literals** — every newline
   consumed inside a string body drifts all subsequent error line numbers
   (observed: uforth.py line 61 reported as 50).

## Gate

test-nilpy green (+ new regression test_nilpy_literals.npy), self-host
byte-identical, testmgr quick.
