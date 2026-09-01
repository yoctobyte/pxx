---
slug: bug-p-a-cast-to-a-string-alias-silently-drops-a-following-index
title: "`TAlias(s)[1]` yields the WHOLE STRING, no diagnostic — FPC yields the character"
track: P
prio: 60
type: bug
status: backlog
found: 2026-09-01
found-by: frankH
owner: ""
blocked-by: []
summary: "`TAlias(s)[1]` where `TAlias = AnsiString` returns the whole string instead of the character, with NO error: pxx prints `hello` where FPC prints `h` (oracle-confirmed). The `[1]` is not misparsed, it is DROPPED — the cast arm never runs the postfix selector tail, so the rest of the expression is left in the token stream and whatever follows swallows it. Same cause, three different faces by position: silently wrong value (assignment), `expected ')' before '['` (parenthesised or argument position), and `SetLength expects a string variable in IR codegen` (lvalue). The wrong-value face is the dangerous one and is why this is 60 rather than 45 like its already-closed siblings. Root cause is [[refactor-p-one-lvalue-path-for-statements-and-expressions]]. Found attempting feature-embed-pascal-script: it is 2 of the 3 walls RemObjects Pascal Script hits."
---

# A cast to a string alias silently drops a following index

## Repro — and the oracle disagrees, silently

```pascal
program t;
type TAlias = AnsiString;
var s, r: AnsiString;
begin
  s := 'hello';
  r := TAlias(s)[1];        { must be 'h' }
  writeln('got [', r, ']  len=', Length(r));
end.
```

| | output |
| --- | --- |
| FPC 3.2.2 | `got [h]  len=1` |
| pxx (`59f487e7ca7c`, commit `97a166f35`) | `got [hello]  len=5` |

**No error, no warning.** This is the class CLAUDE.md names as the expensive
one: a plausible wrong value, far from the cause.

## The three faces, and they are ONE bug

The `[1]` is not misparsed — it is **left in the token stream**, because the
cast arm returns without running the postfix selector tail. What happens next
depends only on what is standing there to absorb it, which is why this looks
like three unrelated defects:

| position | what you see |
| --- | --- |
| `r := TAlias(s)[1];` | **compiles, wrong value** — the index vanishes |
| `b := TAlias(s)[1] = 'h';` | `incompatible types: cannot assign AnsiString to Boolean` — note the `= 'h'` never parsed either |
| `WriteLn(TAlias(s)[1]);` | `expected ')' before '['` |
| `SetLength(TAlias(p^.s), 8);` | `SetLength expects a string variable in IR codegen` |

The last row is the same bug reached through the lvalue path, confirmed with a
control: **drop the cast and it works.** `SetLength(p^.s, 4)` compiles and
runs; `SetLength(tbtstring(p^.s), 8)` does not. The cast is the only variable.

## Boundary — varied rather than assumed

Every row below was run. `TAlias = AnsiString`, `PArr = ^array[0..3] of Integer`.

| shape | |
| --- | --- |
| `TakeC(s[1])` — plain var indexed, argument position | PARSES |
| `Take(pa^[0], 4)` — deref indexed | PARSES |
| `Take(PArr(pa)^[0], 4)` — cast to a POINTER type, deref, index | PARSES |
| `TakeC(Copy(s,1,3)[1])` — call result indexed | PARSES |
| `TakeC((s)[1])` — parenthesised expr indexed | PARSES |
| `TakeC(TAlias(s)[1])` — **cast to a string alias, indexed** | **FAILS** |

So it is not parentheses, not argument position, and not indexing a temporary.
It is specifically **a value cast to a non-pointer type not being transparent
to the postfix tail.** A pointer cast is transparent because it builds an
`AN_PTR_CAST` node that the tail already walks.

## Why it is filed rather than fixed

The family is already mapped and the root cause already has a ticket:
[[refactor-p-one-lvalue-path-for-statements-and-expressions]] — *"Two lvalue
parsers, and the statement one keeps missing what the expression one learned."*
Two siblings are in `done/`, and the closer of the two,
[[bug-p-a-record-cast-as-an-assignment-target-cannot-be-indexed]], reports the
identical mechanism one level over: *"the statement-level cast-as-lvalue arm
hand-rolls its own postfix walker, and that walker knows `^` and `.field` but
not `[`."*

That is now **four instances of one design flaw**, which by
`root-cause-over-microfix.md`'s own count ("two is a smell, three is a design
flaw") means the microfix here is the wrong shape of change. Patching the
r-value cast arm to walk `[` would make a fifth hand-rolled walker. **Whoever
takes the refactor should take this as one of its acceptance rows**, and the
row to use is the wrong-VALUE one, not a parse error — a parse error announces
itself and this does not.

## Provenance

Found attempting [[feature-embed-pascal-script]] — the first real third-party
Object Pascal codebase this compiler has been pointed at from that ticket.
RemObjects Pascal Script's `uPSCompiler.pas` hits it at line 1930
(`tbtwidestring(p^.twidestring)[1]` as a call argument, 13 occurrences of the
shape in that file alone) and again at 2753 (`SetLength(tbtstring(vari^.tstring),
n)`). Those are **two of the three walls** that stop that unit compiling; the
third was a missing `PByteArray`, fixed separately.

---

## 2026-09-01 (frankH) — does anything currently pass BECAUSE of the swallow? Measured: no

frankA's caution, and it is the right one to raise: *"a leftover token that
changes three faces by position is the shape that has silent dependents."* A
token that is swallowed rather than misparsed can be load-bearing somewhere, and
the refactor would then break a green test for a good reason and look like a
regression.

**Swept the tree for the shape and there are none.** 122 occurrences of
`Ident(...)[` across `compiler/ lib/ test/ examples/ apps/`, reduced to the 36
distinct leading identifiers, cross-checked against declared type names. Only
four are types, and two of those (`f`, `F`) are false hits on an unrelated
`f = ...`. **The other two are `PByte` and `PUInt8` — POINTER casts, which are
already transparent and are NOT affected.** Zero casts to a string or array type
followed by an index exist in our own sources.

So nothing in the tree depends on the swallow, and the refactor cannot break a
passing test through this path.

### The positive control the refactor DOES need, and it is live

The pointer-cast-then-index shape must keep working, and it is not hypothetical
— `lib/rtl/typinfo.pas` uses it at 700, 807, 867, 904 and 920, all
`@PUInt8(instance)[p^.GetRef]`. **Verified live rather than assumed present:**

```
propinfo ok, GetRef=8 GetKind=0
GetOrdProp=5
after SetOrdProp: o.N=41
```

Both the read and the write path go through it, so a refactor that unified the
walkers and lost the pointer arm would fail this in under a second. Use it as
the second acceptance row beside the wrong-value one.

### One thing checked and deliberately NOT filed

While building that control I passed a string literal where a `PPropInfo` was
expected. pxx compiles it and segfaults; FPC refuses it
(*"Incompatible type for arg no. 1: Got \"Constant String\", expected \"PRec\""*).
That is **not a defect by CLAUDE.md's rules** and is recorded here only so the
next person does not re-find it and file it: accepting what FPC rejects is not a
defect, and `F('literal')` into a typed-pointer parameter is reachable only by
code the programmer already got wrong. It is `rejected/` territory, not compat.
It is mentioned at all because the crash is loud enough to look like a lead.
