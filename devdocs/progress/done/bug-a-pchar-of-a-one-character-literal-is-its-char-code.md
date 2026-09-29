---
track: A
prio: 10
type: bug
blocked-by: []
status: done
found-by: frankd-23 on v451 (`sprintf(buf, '%s', PChar('x'))` segfaults), via frankuser
tags: [pascal, pchar, literal, cross-target, silently-wrong]
summary: "`PChar('x')` gave the character code 120 as the pointer, where fpc 3.2.2 gives a pointer to a NUL-terminated \"x\". A one-character literal (also `#65` and a named `const K = 'x'`) parses as an ordinal Char node, and the PChar/PAnsiChar adapter reinterpreted that value. A constant Char is now rewritten to the one-character string literal, the path `PChar('xy')` already took. A non-constant Char (a variable or typed const) is refused with fpc's own message."
owner: ""
---

# PChar of a one-character literal is its char code

```pascal
p := PChar('x');
writeln(PtrUInt(p));   { pxx: 120; fpc 3.2.2: an address, p^ = 'x', p[1] = #0 }
```

The factor parser makes a one-character literal an AN_INT_LIT tagged tyChar,
which is right in every ordinal context. The PChar cast (sentinel -2) lowers
to its operand, so the code became the pointer. A named `const KC = 'k'` gives
the same node with LastExprTk left at something other than tyChar, so the arm
asks the node's kind as well.

fpc 3.2.2 on `PChar(c)` for a Char variable or a typed const Char:
`Illegal type conversion: "Char" to "PChar"`. pxx now gives the same
refusal instead of making the char value an address.

PWideChar('w') is still behind PXX_WIDE_PAYLOAD. That refusal is unchanged,
and chore-a-decide-whether-widestring-can-come-out-from-behind-pxx-wide-payload
tracks it.

## Tests

- test_pchar_of_a_one_character_literal: covers a literal, PAnsiChar, a named
  const, `#65`, a two-character control, a direct argument, `^` and `[0]`.
  The expected output is fpc 3.2.2's. It passes on six targets. The v451
  compiler segfaults on it.
- test_pchar_of_a_char_variable_is_refused: the refusal row, with fpc's
  message.
