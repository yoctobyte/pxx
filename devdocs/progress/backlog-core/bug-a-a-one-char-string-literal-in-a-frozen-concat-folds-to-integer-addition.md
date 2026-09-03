---
slug: bug-a-a-one-char-string-literal-in-a-frozen-concat-folds-to-integer-addition
title: "A one-char string literal on the right of a frozen concat folds to integer addition"
track: A
prio: 70
type: bug
status: backlog
owner: ""
created: 2026-09-03
summary: Under -uPXX_MANAGED_STRING, `u := s + 'q'` on frozen strings emits `lea rax,[s];
  add rax,$71` — address plus Ord('q') — and prints an empty string.
---

# A one-char string literal on the right of a frozen concat becomes integer addition

`-uPXX_MANAGED_STRING` makes bare `string` frozen. In that build a `+` whose
right operand is a ONE-CHARACTER string literal is not typed as a concat at
all: it takes the generic integer arm and adds the character's ordinal to the
string's address.

## Repro

```pascal
program cc;
var s, u: string[10]; c: Char;
begin
  s := 'a'; c := 'q';
  u := s + c;   WriteLn('str+chr  [', u, '] ', Length(u));   { [aq] 2 — correct }
  u := s + 'q'; WriteLn('str+lit  [', u, '] ', Length(u));   { []   0 — WRONG   }
  u := s + 'qq';WriteLn('str+lit2 [', u, '] ', Length(u));   { [aqq] 3 — correct }
end.
```

`pascal26 -uPXX_MANAGED_STRING cc.pas cc26 && ./cc26`.

**Only the one-character literal is wrong.** A `Char` variable is fine, and a
two-character literal is fine — so it is the constant folder treating a
single-quoted single character as a Char CONSTANT and then folding
`string + charconst` as arithmetic, not the concat path being missing.

## The emitted code names the cause

For `g := g + 'q'` with a global `g: string[10]`, disassembled:

```
lea  rax, [g]
add  rax, 0x71          <- 0x71 = 113 = Ord('q'). This is pointer arithmetic.
push rax
lea  rdi, [g]
pop  rsi
mov  rcx, [rsi]         <- "length" read from g+113, i.e. whatever follows g
cmp  rcx, 10 / clamp / rep movsb
```

There is no call to any concat helper and no stack temp: the whole concat was
folded away before codegen saw it. So the fix is in typing/folding, not in a
backend.

## Scope, measured

- **Not the byte-prefix overhaul.** Identical output with and without
  `-dPXX_SHORTSTRING`, and identical under the PINNED compiler (which predates
  the byte-prefix layout entirely). Found while fixing
  `bug-a-string-concat-segfaults-on-x86-64-under-the-byte-prefix-mode` and
  explicitly excluded from it.
- **Needs `-uPXX_MANAGED_STRING`.** In the default build bare `string` is
  managed, the concat is tagged tyAnsiString and every spelling is correct.
  That is why no default-mode suite row sees it.
- Wrong for a local too, with a different shape: a local `s` prints stack
  garbage at length 10 (the capacity) rather than an empty string, because the
  bytes past the slot differ.

`test/test_shortstring_concat.pas` documents this in a comment and deliberately
uses a `Char` variable rather than a one-char literal, so that test stays a
test of concat widths rather than of this.
