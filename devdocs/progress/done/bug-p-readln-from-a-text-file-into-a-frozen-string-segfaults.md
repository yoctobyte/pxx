---
track: P
prio: 80
type: bug
summary: "FIXED 2026-09-06 (7a79ff1d2) -- `ReadLn(f, s)` where `f: Text` and `s: ShortString` (or any `string[N]`) SEGFAULTS. A plain `s: string` in the same program on the same line works, which is the whole discriminator: the target's declared type decides between a correct read and a crash. Cause: ParseTextReadRest routed every string-ish target to `TextReadStrTo(var f: Text; var s: AnsiString)`, handing an inline `[len][chars]` slot to a routine that writes an 8-byte managed handle through it. Reproduces at HEAD AND on pin v405, so it is not a regression from the sized-boolean work it was found beside. Fixed at the AST level -- read into an AnsiString temp, then AN_ASSIGN into the frozen target -- so the truncation-to-capacity comes free and all six backends are covered by one change."
status: done
---

# ReadLn from a text file into a frozen string segfaults

`var f: Text; s: ShortString; ... ReadLn(f, s);` → SIGSEGV. Change `s` to
`string` and the identical program reads the line correctly.

**The working half is the finding.** A crash on a construct nobody uses is a
gap; a crash on the *frozen* spelling while the *managed* spelling on the same
line works is a routing bug, and it says where to look without a debugger.

## Cause

`ParseTextReadRest` had one string arm, and it emitted a call to

```pascal
procedure TextReadStrTo(var f: Text; var s: AnsiString);
```

for every target whose kind was string-ish. For `tyAnsiString` the `var`
parameter is a pointer to an 8-byte managed handle and that is what the callee
writes. For `tyShortString` / `tyFixedString` / `tyString` the same pointer
addresses an **inline** `[len][chars…]` slot, so the callee's handle store
lands on the length prefix and the first characters, and the subsequent
dereference of the "handle" it reads back walks a pointer made of text.

`TypeIsFrozenString(tk)` is the predicate that separates the two — it covers
`tyString`, `tyShortString` and `tyFixedString`, i.e. exactly the kinds whose
storage is inline.

## Fix

A new `TypeIsFrozenString` arm in `ParseTextReadRest`, **before** the generic
string arm: allocate an `AllocVar('', tyAnsiString)` temp, read into that, then
emit `AN_ASSIGN destNode := temp`. The existing AnsiString→frozen assignment
path already clamps to the target's capacity, so `string[4]` now truncates
exactly as fpc does rather than overrunning.

Done at the **AST** level deliberately: one change covers x86-64 and every
cross backend, instead of six copies of a prefix-width special case in codegen.

## Scope of the pre-existing claim

Measured on `compiler/pascal26` at HEAD *and* on the pinned compiler from
v405. Neither is a regression from the semantic-identity work
(`decide-how-a-type-carries-an-identity-its-kind-cannot-hold`) that was in
flight when this was found — it was found *because* a test for that work read a
`ShortString`, not caused by it.

Sibling, same session, same shape at the other door:
`bug-p-read-into-a-frozen-string-uses-the-wrong-prefix-width`. Fixed one arm of
a double case, grepped for the sibling, found it.

Test: `test/test_read_into_a_frozen_string_from_stdin_and_a_file.pas`,
`.expected` copied from fpc's own output, wired into the Makefile.

Fixed in `7a79ff1d2`.
