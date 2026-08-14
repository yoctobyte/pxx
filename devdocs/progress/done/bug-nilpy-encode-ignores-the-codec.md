---
track: N
prio: 30
type: bug
status: done
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

## Resolution (2026-08-15) — duplicate, already fixed

This is the same defect as `bug-n-str-encode-and-bytes-decode-ignore-the-encoding`,
which landed the real codec layer (`PyEncNormalize`/`PyEncCode`/`PyEncRequire`,
`PyCpToUtf8`/`PyUtf8CpAt`, `pystr_encode_enc`/`pystr_encode_enc_err`, and the
rewritten `TPyBytes.decode`), plus the `wantArgs = -11` mode in
`PyParseStrMethod` that evaluates the encoding argument instead of skipping it
and strips the `encoding=`/`errors=` keyword forms.

Verified against CPython at pin v308 — byte-identical:

```
5 [99, 97, 102, 195, 169]
café
4 [99, 97, 102, 233]
b'caf?'
```

which is exactly the case this ticket says is wrong: `"café".encode("utf-8")`
is 5 bytes with the two-byte sequence, and `errors="replace"` on ascii is
honoured rather than dropped. Closing as a duplicate; see the other ticket for
the implementation and the codec-subset note in
`devdocs/dev/nilpy-semantics-divergences.md`.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
