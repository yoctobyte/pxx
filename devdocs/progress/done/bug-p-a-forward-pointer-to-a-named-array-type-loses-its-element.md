---
slug: bug-p-a-forward-pointer-to-a-named-array-type-loses-its-element
title: "`PArr = ^TArr` above `TArr = array[..] of T` loses the pointee's element — refused two ways, and silent through a class field"
track: P
prio: 55
type: bug
status: done
owner: frankB
created: 2026-09-05
found-by: frankB
blocked-by: []
summary: "FIXED. A pointer alias naming an array type declared BELOW it kept no element shape, so `p^[i].f` was refused with `a value of this type has no members`, `with p^[i] do f` was refused differently with `Integer has no members`, and through a CLASS FIELD the same shape did not refuse at all — it compiled, exited 0, and read 0 where fpc reads 42. The identical declarations in the other ORDER always worked. ParseTypeKind's `^T` arm had recorded the gap in its own comment and called it a stride fallback; it was not. Fixed in ResolvePendingPointerAliases, which exists to run after the type section. Found by walking FPC's compiler sources, where it was the last PARSER wall: `cclasses` and the three units behind it stopped at `undefined variable (StrIndex)`."
---

# The shape

```pascal
type
  PHashItemList = ^THashItemList;                     { cclasses.pas:182 }
  THashItemList = array[0..N] of THashItem;           { :183 }
...
  with FHashList^[Index] do
    if StrIndex >= 0 then ...                         { :1274 — refused }
```

Ordinary Pascal, and the spelling FPC's own compiler uses.

# Three voices, one cause

| spelling | before |
| --- | --- |
| `p^[i].f` (read or write) | `a value of this type has no members` |
| `with p^[i] do f` | `with needs a record, class or interface — Integer has no members` |
| `fld^[i].f`, `fld` a CLASS FIELD | **compiles, exits 0, reads 0** |

Same missing fact, and the third one does not announce itself. A ticket written
from either of the first two would have been ranked as a diagnostic problem.

The **declaration order** is the discriminator and the whole argument: every
failing row has an in-order twin (`TArr` first, `PArr` second) that has always
worked. A declaration order changing whether a program parses is the tell the
pointer-to-pointer arm of the same routine already names in its own header.

# Where it was, and why the comment undersold it

`ParseTypeKind`'s `^T` arm asks `FindArrayType` and takes the element shape from
the ArrType entry. Its comment already said:

> *(A FORWARD `PA = ^TA` ahead of TA's own declaration is not covered — the
> entry does not exist yet — and falls back to the old default.)*

**"Falls back to the old default" reads as a stride approximation.** What it
actually costs is `AliasElemRec`, and without the element record the construct
is not approximated — it is refused, or silently zero.

`ResolvePendingPointerAliases` is the pass that exists for exactly this: it
already repairs a forward pointee that is a class/record declaration, a pointer
alias, or a plain type alias. A named ARRAY type lives in the ArrType table
rather than the alias table, so `FindTypeAlias` answered -1 and **no arm fired
at all** — the fourth pointee shape, in a routine whose other three were each
added when someone hit them.

# The march

Re-run under `--mimic-fpc-compiler` against `/usr/share/fpcsrc/3.2.2/compiler`:

| unit | before | after |
| --- | --- | --- |
| `cutils` `globtype` `constexp` `version` `cstreams` | OK | OK |
| `cclasses` `comphook` `finput` `cfileutl` | `cclasses.pas:1274 undefined variable (StrIndex)` | `cclasses.pas:1561 undefined variable (prefetch)` |
| `cmsgs` | `an object type cannot have a constructor` | unchanged — DECIDED, not a gap |

`prefetch` is `procedure Prefetch(const mem)` — an FPC compiler intrinsic
declared in `systemh.inc`, semantically a cache hint, so the next wall is an
RTL/builtin gap and not a parser one.

Note the wall before this one was `TFPCHeapStatus`, closed the same day by
`f6ddab6ef`. Two walls in one session, each revealed only by removing the one in
front of it, which is the argument for walking a corpus rather than triaging a
backlog.
