---
owner: claude-A
---

# write/writeln to a Text FILE rejects a Char (stdout accepts one)

- **Type:** bug — Track P (Pascal frontend) / Track A (builtin lowering)
- **Status:** done
- **Opened:** 2026-08-04
- **Found by:** Track B, `tools/fpc_diff_probe.sh` `file-append` case.
- **prio:** 55

## Symptom

    error: write(Text): unsupported argument type (string/integer/float only)

for a `Char` argument to a Text file, while the identical write to **stdout**
compiles:

| written | to a Text file | to stdout |
| --- | --- | --- |
| `'ab'` (string literal) | OK | OK |
| **`'a'` (Char literal)** | **error** | OK |
| **`c: Char`** | **error** | OK |
| `s: string` | OK | OK |
| `42`, `True` | OK | OK |

FPC accepts all of them to either destination.

## Why it is easy to hit

In Pascal a **one-character literal is a `Char`**, not a string. So

    writeln(f, 'a');

— about the most ordinary line anyone writes — does not compile, while
`writeln(f, 'ab')` does. The error message reads as if strings were the problem,
which points away from the actual cause. Character-at-a-time file output
(delimiters, separators, building a line) is the natural case and it is exactly
what is blocked.

## Notes

- Hard error, not a silent wrong value, so it cannot corrupt data.
- The stdout path already handles `Char`, so the two write lowerings have
  diverging type tables; that comparison is likely the whole fix.
- Related theme, different defect, and much worse:
  `bug-p-string-char-relational-compares-lengths` (urgent) — there the Char/string
  mismatch produces silently wrong values instead of an error.

## Repro

```
printf "program q; var f: Text; begin Assign(f,'/tmp/z'); Rewrite(f); writeln(f,'a'); Close(f); end.\n" > /tmp/q.pas
./stable_linux_amd64/default/pinned /tmp/q.pas /tmp/q_o
```

## Resolution (2026-08-05)

`TextStrArg` (`compiler/parser.inc`) gates its ordinal arm on
`TypeIsOrdinal(tk) and (tk <> tyChar)`. The exclusion is **correct** — `StrInt`
would print a Char's ORDINAL (120 for `'x'`) — but no Char arm was ever added
beside it, so a Char fell straight through to the catch-all error. That is why
the message named "string/integer/float only" and pointed away from the cause:
strings were never the problem.

**Fix:** a Char arm routed through a new `StrChar(c: Char; width: Integer)` in
`compiler/builtin/builtin.pas`, mirroring the existing `StrInt` / `StrQWord` /
`StrFloat` shape including the width argument. The error text now reads
"string/Char/integer/float only", so the next person to hit an unsupported type
is not misled the same way.

**Verified byte-identical to FPC**, including width padding, over: a Char
literal, a Char variable, `c:4`, `'Z':3`, a `Chr()` result in a loop, and the
string/integer/float cases that already worked. Locked in as
`test/test_writeln_text_char.pas`, which also reads the file back so the test
proves the BYTES landed, not just that it compiled.

### Found while verifying: the read-side twin CRASHES

`read(f, c)` for a Char destination segfaults — `ParseTextReadRest` carries the
identical `(trTk <> tyChar)` exclusion, but there the fall-through hands the
one-byte Char slot to `TextReadLn`, whose second parameter is a
`var AnsiString`. A string handle is written into one byte. Pre-existing
(`pinned` segfaults too).

Filed as `bug-p-read-text-file-into-a-char-segfaults` rather than fixed here,
because it carries a design question this one does not: pxx's Text read is
line-oriented by construction, while FPC's `read(f, c)` consumes ONE character.
A Char arm that reads a line and takes `[1]` would fix the crash and match FPC
on the first read but return the wrong thing on the second — and a character
loop is the main reason to read a Char at all. That wants a `TextReadChar` with
pushback, not a quick arm, so it is tracked separately with both options
written out.

**Gate:** `testmgr --tier quick` green; `selfhost_fixedpoint.sh` converges and
agrees with `compiler/pascal26`.

## Log
- 2026-08-05 — resolved, commit PENDING-COMMIT.
