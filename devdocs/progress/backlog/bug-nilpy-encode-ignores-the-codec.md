---
track: N
prio: 30
type: bug
---

# NilPy: str.encode / bytes.decode ignore the codec argument

Landed knowingly 2026-07-20 for the uforth drive.

NilPy strings ARE byte strings (AnsiString), so `.encode(enc)` is a byte-for-
byte copy and `.decode(enc)` is its inverse. That is EXACT for latin-1, which
is 9 of uforth's 10 encode sites and all 4 decode sites.

It is wrong for the one `\.encode("utf-8", errors="replace")` site whenever a
character is >= 128: real UTF-8 would emit two bytes, this emits one. The
`errors=` argument is likewise accepted and dropped — harmless for latin-1,
which cannot fail, but not for a codec that can.

The encode arguments are SKIPPED at parse time rather than evaluated (see the
-4 case in PyParseStrMethod), because `errors="replace"` is a keyword argument
and NilPy has no keyword arguments on str methods.

## Fix when picked up

Needs a code-point model, or at least a real UTF-8 encoder over the byte
string, plus a decision about what a "character" is in NilPy. Worth pairing
with any wider Unicode work rather than doing alone.
