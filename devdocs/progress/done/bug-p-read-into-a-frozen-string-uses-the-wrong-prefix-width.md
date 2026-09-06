---
track: P
prio: 80
type: bug
summary: "FIXED 2026-09-06 (7a79ff1d2) -- `ReadLn(s)` from stdin where `s: ShortString` silently stores the WRONG VALUE: a QWORD length is written at [rdi] and the characters at rdi+8, i.e. the word-prefix layout, into a byte-prefix slot. `Length(s)` came back right BY ACCIDENT (the low byte of the qword, little-endian only) while the characters sat at s[8..10], so the length agreed with the source and the text did not. A plain `s: string` works. No capacity clamp either. Reproduces at HEAD AND on pin v405. Sibling of bug-p-readln-from-a-text-file-into-a-frozen-string-segfaults -- same defect, other door, one crashes and one lies. Fixed at the AST level in ParseReadArgsAST (AnsiString temp in the ARG chain, AN_ASSIGN chained after), so all six backends are covered by one change."
status: done
---

# Read into a frozen string uses the wrong prefix width

`var s: ShortString; ReadLn(s);` from stdin stores a value that is wrong in a
way that survives the obvious check. `EmitReadVarParse`'s `tyString` arm writes
a **QWORD** length at `[rdi]` and the characters at `rdi+8` — the `tyFixedString`
word-prefix shape — into a byte-prefix `[len][chars…]` slot.

The bytes, reading `abc` into a `ShortString`, pxx vs fpc:

```
pxx   0 0 0 0 0 0 0 97 98 99 0 0
fpc  97 98 99 35 35 35 35 35 35 0 0 0     (35 = pre-filled '#')
```

**`Length(s)` was correct on both.** The qword length shares its low byte with
the byte prefix on a little-endian target, so the single field anyone spot-checks
agreed with the source while every character was six bytes off. That is the
reason this outlived the segfault it is a sibling of: the crashing door
announces itself and this one hands back a plausible length.

There was also no clamp to the declared capacity, so `s: string[4]` reading a
sixteen-character line wrote past the slot.

## Fix

`ParseReadArgsAST`: for a `TypeIsFrozenString` target, allocate an AnsiString
temp, put **the temp** in the ARG chain, and chain an `AN_ASSIGN dest := temp`
onto a `raHead`/`raTail` list; the whole read returns `GenMakeSeq(node, raHead)`
when any temps exist. The frozen-assignment path already truncates to capacity,
so `string[4]` now yields `over` / `long` exactly as fpc does.

At the **AST** level, not in codegen: the wrong-prefix arithmetic exists once
per backend, and normalising the read into "managed read + assign" removes all
six copies rather than correcting them.

## Pre-existing

Measured at HEAD and on the pinned compiler from v405. Not a regression from
the semantic-identity work in flight beside it.

Test: `test/test_read_into_a_frozen_string_from_stdin_and_a_file.pas`, fed
`printf 'abc\nlonger-than-four\n77\n'`, `.expected` copied from fpc.

Fixed in `7a79ff1d2`.
