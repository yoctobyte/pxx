---
slug: bug-a-a-one-char-string-literal-in-a-frozen-concat-folds-to-integer-addition
title: "A one-char string literal on the right of a frozen concat folds to integer addition"
track: A
prio: 70
type: bug
status: done
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

## FIXED — the -O1 imm-fold arm named ONE of the two string result kinds (frankB, 2026-09-03)

Not a typing bug and not the parser. **The AST is correct in both spellings**
(`PXXDBG=a.ast` gives the identical BINOP tk=tyString / right tk=tyChar for
`s + c` and `s + 'q'`; only the right child's node kind differs, load vs
const), and **`-O0` is correct while `-O1`, `-O2` and `-O3` are wrong** — which
is the tell that says optimiser, and which the original report missed because
it never varied `-O`.

`compiler/ir_codegen.inc`, the `-O1 imm-fold` arm: a constant right operand
folds into the instruction's immediate and `Exit`s past everything below,
including both concat arms. Its guard read

```
not TypeIsFloat(IntToTypeKind(IRTk[node])) and
(IntToTypeKind(IRTk[node]) <> tyAnsiString) and
```

and its own comment said *"Excludes float / tyAnsiString results (concat +
ucomisd paths)"*. **There are TWO string result kinds and it named one.** A
concat also results in a frozen tyString, which is exactly what
`-uPXX_MANAGED_STRING` makes `s + 'q'` produce, so the arm claimed it and
emitted `add rax, $71`. Now excludes `TypeIsFrozenString` as well — the
exclusion follows the CONCEPT (a string-typed result is never integer
arithmetic) rather than enumerating kinds, so tyShortString and tyFixedString
come along.

**Why only that one spelling.** A `Char` VARIABLE is an IR_LOAD_SYM, not an
IR_CONST_INT, so it never reached the arm; a two-character literal is not an
ordinal at all. The one-char literal is the only operand shape that is both a
string concat operand and an integer constant.

Rows `onechar` and `loop1` added to `test/test_shortstring_concat.pas`.
Positive control, measured: fix reverted (compiler `2f9096bb2bd4`) → the two
`-uPXX_MANAGED_STRING` rows print `onechar  [zzzzzzzzzz] 10` / `loop1 10 zz`
at the default `-O` and are CORRECT at `-O0`, while the two default-mode rows
are unchanged. Restored → `2965c25fe0a6`. **These two rows are the only ones
in that file that need the default `-O` to stay meaningful.**

Verified 16 configurations (4 modes x -O0/-O1/-O2/-O3) byte-identical on
x86-64, and both byte-prefix modes on i386, arm32 and aarch64 — same output.
The arm is x86-64-only (see `IRValueKind`'s note in ir.inc, which describes
the same arm catching a different defect first). `gate.sh quick` GREEN.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
