---
type: bug
track: A
prio: 85
status: open
summary: Under -dPXX_SHORTSTRING, a `const s: string[N]` parameter arrives with the
  correct Length and NUL data on every target; the same parameter by value is fine.
---

# A const shortstring parameter arrives as NUL bytes under the byte-prefix mode

**Silent, and on EVERY target** — unlike the ordering and concat blockers, which
are x86-64 only. `const` is the idiomatic way to pass a string one does not
intend to modify, so this hits ordinary code.

## Repro

```pascal
program cp;
procedure T(const n: string[12]); begin WriteLn('const param=[', n, '] len=', Length(n)); end;
procedure V(n: string[12]);       begin WriteLn('value param=[', n, '] len=', Length(n)); end;
begin T('hello'); V('hello'); end.
```

Measured at `45f6639f5`, compiler sha `a43276f1ce47`, exit 0 everywhere.

| | default | `-dPXX_SHORTSTRING` |
| --- | --- | --- |
| `const` param | `[hello] len=5` | **`[<NUL><NUL><NUL><NUL><NUL>] len=5`** |
| value param | `[hello] len=5` | `[hello] len=5` |

Confirmed identical on x86-64, i386, arm32, aarch64 and riscv32 (`cat -v` shows
`^@^@^@^@^@`; without `cat -v` the field looks like blanks, or like nothing at
all in a terminal).

**The LENGTH is right and the DATA is gone**, which is the same signature as the
array bug before it was fixed: the prefix is found and the payload is not.
By-value works, so the divergence is in how the `const` reference is passed or
dereferenced, not in the layout.

## Guard note

Printed normally, `[<NUL>*5]` renders as an empty-looking field that reads as a
formatting quirk. `cat -v` is what separates "prints nothing" from "prints five
NULs", and the two have different causes. **Any probe comparing printed output
of a string that might be NUL-filled needs `cat -v` or a byte comparison**, not
an eyeball.
