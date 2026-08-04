# write/writeln to a Text FILE rejects a Char (stdout accepts one)

- **Type:** bug — Track P (Pascal frontend) / Track A (builtin lowering)
- **Status:** backlog
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
