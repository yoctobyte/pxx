---
slug: decide-one-managed-string-kind-with-an-element-width-or-a-second-kind
title: "DECIDE: one managed-string kind carrying an element width, or a second kind — 636 sites say it matters"
track: U
prio: 60
type: decide
status: open
created: 2026-08-30
found-by: frank-coordinator
summary: "RULED 2026-08-31 (owner): option B, one managed-string kind carrying an element width. Ruled BY CONSTRUCTION — the measurement that was in flight came back YES (ASTStrElemTk exists at defs.inc:4495 with 27 readers, plus ProcRetStrElemTk/UFldPtrElemStrTk follow-ons), tyWideString has zero references left, and pasparser_decl.inc:464 already broke the alias the B way. The 636-site audit never has to happen. Carried forward: the runtime header ALREADY reserves an encoding enum (PXX_ENC_BYTES/UTF8/UCS2/UCS4 at builtinheap.pas:289) that nothing stamps or reads — see feature-a-stamp-and-read-the-managed-string-encoding-field."
---

# The fork

The owner asked, when raising string types on 2026-08-30:

> "all (dynamic) strings can use the same ansistring work… if all is well, **we can just tag
> the type**, and the rest should more or less be library/track B work. so, implementing new
> string types is **(almost) free**, give or take some conversion helpers where needed.
> **or do i overlook a something?**"

**636 is the answer to that question.** It was overlooked, and it was overlooked by the
coordinator too — the resolution that picked a distinct kind was written before anyone
counted.

## What was measured, by frankwasm, at HEAD in `compiler/*.inc`

| | count |
| --- | --- |
| `tyAnsiString` mentions, all | 824 |
| …code-level kind **tests** | **636** |
| …the `(x = tyAnsiString) or (x = tyString)` any-string shape | 97 |
| `TypeIsManagedStr` — the predicate that exists to normalise exactly this | **5 call sites** |
| `tyWideChar`, for contrast (a scalar that DID take its own ordinal) | 19 |

The last two rows are the finding. A chokepoint **exists** — `symtab.inc:3157
TypeIsManagedStr`, whose entire body is `Result := (tk = tyAnsiString)` — and it is
essentially unadopted: five calls against 636 direct tests.

## Option A — `tyWideString` as a distinct kind (as currently decided)

Matches the `tyWideChar` precedent. Explicit at every use. **Costs:** every one of those 636
tests that means *"is this a string"* rather than *"is this specifically an AnsiString"*
needs a third arm, added individually, with no way to find the missed ones except the bug
they cause. **A miss does not fail loudly** — it treats a wide string as not-a-string, which
is a leak or a silent wrong value. This is `normalise-dont-special-case.md`'s exact failure
mode at 636x.

## Option B — ONE managed-string kind carrying an ELEMENT WIDTH (recommended)

`tyAnsiString` stays *the* managed string kind; the element is `tyChar` or `tyWideChar`. All
636 sites keep working untouched, because a wide string genuinely **is** a managed string.
Only width-sensitive sites change: `Length` (>>1), indexing (stride 2), literal encoding,
`Write`, the transcode boundary.

**Three independent supports:**

1. **The runtime half is already built this way.** It needed no second block shape, no second
   refcount path, no second free path — because the difference was never the kind, it was the
   element width, and the header stayed a byte count. Modelling in the type system a
   distinction the runtime does not make is how the two drift.
2. **`TTypeRef` already carries `Kind` + `ElemTk`/`PtrDepth`/`DynDepth`** for precisely the
   "same kind, different shape" case. A wide string is `Kind = tyAnsiString, ElemTk =
   tyWideChar` — an existing field doing its existing job. B adds zero new mechanisms.
3. **FPC's own RTTI collapses the two spellings**: `TypeInfo(WideString)^.Kind` and
   `TypeInfo(UnicodeString)^.Kind` are **both 24 (`tkUString`)** on Linux, measured on
   fpc 3.2.2 rather than recalled.

The five real lockstep sites under A — `FieldIsManaged` (`rtti_emit.inc:24`) and four
finalizer/member-kind sites (:1337/:1367/:1456/:1490) — are each a **leak if missed** under A
and **change not at all** under B. That is the argument in miniature.

## The measurement that decides it — IN FLIGHT

Under B the element width must ride on an **expression** node, not only a symbol, because the
wall is `WideChar(u1) + WideChar(u2)` and that `+` result has no declaration to hang a width
on. `ASTTk` carries one kind per node.

frankwasm is measuring whether a node-level element slot already exists, starting from how
`s1 + s2` on two `tyAnsiString`s already knows its element size is 1. Outcomes:

- **slot exists** → B strictly cheaper, no fork, proceed
- **no slot, adding one is bounded and additive** (as `tyWideString` was) → still B
- **no slot and adding one is invasive** → **genuine fork, this ticket is live**

## State — nothing is half-done

The alias is **not** broken. `tyWideString` is landed additive and readers-free
(`ce693b1d5120`); the runtime half is landed and tested (surrogate pairs, lone surrogates,
truncated leads); `WideString` still resolves to `tyAnsiString`/`tyString` exactly as before.
Under B the ordinal-32 kind is deleted or repurposed at zero cost. Under A work resumes in
place.

## Carried regardless of the outcome

Both resolver sites are guarded by `PasDefineExists('PXX_MANAGED_STRING')`, and **both arms
build today** and both match fpc 3.2.2 for ASCII. Whichever option wins, the acceptance test
must **name the arm it ran under and run both** — a one-arm green lets the change land in one
configuration and silently miss the other. Same shape as
`bug-a-the-cdecl-soundness-reject-still-has-its-argument-shaped-door-on-four-targets`, one
level down: the untested axis is the build configuration instead of the target.

sysutils' `WideString`/`UnicodeString` identity functions are **documented** as the identity;
the moment the alias breaks, that documentation becomes wrong rather than stale. Same commit.

## The measurement that should decide it: **6 findable vs 636 unfindable**

Not "636 versus a 5-call chokepoint" — that names the count, and the count is
not the property that matters. The decision turns on **findability**:

- Option B's cost is **6 per-backend COW guards**, all spelling
  `(IRTk[left] = Ord(tyAnsiString)) and (elemSize = 1)`. One exact grep, one
  shape, found in a single command. A miss is impossible to hide.
- Option A's cost is **636 `tyAnsiString` kind tests** that are NOT mechanically
  separable into "means any string" (needs a third arm) and "means specifically
  AnsiString" (must not get one). Each must be judged individually, and a miss
  is invisible until it produces a wrong value.

**A large mechanically-enumerable set is cheap; a small set that must be judged
one site at a time is not.**

Evidence that A's unfindable misses are real rather than theoretical, found
while measuring and from a direction nobody had counted: under A, `Length` on a
wide string **returns garbage**. Every backend's Length path tests
`IRTk = tyAnsiString`; under A that test fails for a wide string, so Length
falls through to the dyn-array catch-all and reads the wrong word. Not a compile
error, not a leak — a wrong number from the most-called string operation in the
language. That is the third independent instance of A's silent-failure mode, and
it was found by accident, which is the point.

Under B that same test still passes and returns the byte count, so the halving
is a frontend shift and no backend changes at all.
— frankwasm, 2026-08-30

---

## RULED 2026-08-31 (owner) — option B, and it was already built

### The measurement that was "IN FLIGHT" came back YES

This ticket's own decision table said:

> - **slot exists** → B strictly cheaper, no fork, proceed

The slot exists. `compiler/defs.inc:4495` declares `ASTStrElemTk` — the element
TypeKind of a managed-string-typed *expression* — allocated in `ast_arena.inc`,
copied by the AST deep-copy, read through `ASTStrElemTkOf()`, **27 references
across the compiler**. Three follow-ons landed on top of it: `ProcRetStrElemTk`
(a managed-string result keeps its width), `UFldPtrElemStrTk` (a record field's
pointee), and pointer-to-managed-string width.

Its own comment names the property that dissolves the 636-site problem:

> `0` means NARROW, which is correct for every string expression that exists
> today and for every frontend that cannot produce a wide string at all. Sites
> do not need to be found…

**Option A is not merely unchosen, it is gone.** `grep -c tyWideString
compiler/*.inc` returns **zero** — the distinct kind landed additive at
`ce693b1d5120` has been fully backed out — and `pasparser_decl.inc:464` reads
*"THE ALIAS BREAK. WideString/UnicodeString keep the same KIND as…"*, which is
B's shape. The 636-site audit never has to happen, and A's worst measured
consequence (`Length` on a wide string returning garbage, because every
backend's Length path tests `IRTk = tyAnsiString`) is moot for the same reason
that test still passes.

**So this ticket sat at prio 60 in `backlog/` advertising a live fork to every
idle Track U reader while the code had already answered it.** Third instance
this week of the same shape (see the `-O0` pruning and Track R branch
rulings): *the fork dissolved before anyone had to rule on it.* Worth noticing
as a pattern — a `decide-*` whose resolution depends on a measurement should
carry the measurement's owner and be re-checked before it is offered, because a
stale fork costs a reader a full read plus a wrong model.

### What the owner added, and it is the more interesting half

Raised while ruling: the runtime header has spare bits, so record the element
width there and cover UCS-2 *and* UCS-4 without escaping to a variable-width
encoding, letting any library function read the tag instead of being written per
type.

**Checked, and the field is already reserved — by the same person, earlier.**
`compiler/builtin/builtinheap.pas:289`:

```pascal
{ KindData0, bits 16-23: text encoding. A small enum, NOT a codepage —
  CP_UTF8 (65001) would not fit, and this is the field pxx actually wants. }
PXX_ENC_BYTES = 0;  PXX_ENC_UTF8 = 1;  PXX_ENC_UCS2 = 2;  PXX_ENC_UCS4 = 3;
PXX_ENC_SHIFT = 16;
```

The header is `[meta:8][rc:8][len:8][data][nul]`, handle = base + 24. The meta
slot is 8 bytes; the highest bit in use is 12 (`MSTR_FLAG_ASCII_KNOWN`). The
encoding enum sits at 16-23 with four values defined and 252 free, the accessors
exist (`PXXHdrMeta`, `PXXHdrSetMeta`), and a test already pins the meta word
(`test_managed_block_meta`). **UCS-4 was anticipated in the original design.**
The codepage question was also already ruled, against, with the reason recorded
in that comment — a small enum rather than a codepage, because `CP_UTF8`
(65001) does not fit in a byte and an encoding is the field pxx actually wants.

**An ENCODING field is a better shape than a width field**, and that is the
design's, not this ruling's: `BYTES` and `UTF8` are both one byte per character
and differ in *meaning*; width (1/1/2/4) falls out of the encoding rather than
being the primary fact. A pure width field could not tell those two apart.

**This does not reopen the fork — it settles it harder.** The static model
(`ASTStrElemTk`) tells the COMPILER what to emit: no branch, no load. The
runtime tag tells a CALLEE THAT NEVER SAW THE DECLARATION — a library routine
taking a bare handle, `Write`, RTTI, variants, a debugger, and an assertion in a
checked build. They are complementary, and a runtime tag removes option A's
entire reason for existing, which was making the distinction visible.

### The gap, and it is narrow

Nothing stamps the field and nothing reads it: every managed string in the
system, of any width, is `KIND_LEGACY` with enc bits 0 = `BYTES`. Split out as
**`feature-a-stamp-and-read-the-managed-string-encoding-field`** (Track A).

### Carried from the original ticket, still binding

The acceptance test must **name the arm it ran under and run both**
`PXX_MANAGED_STRING` arms. A one-arm green lets a change land in one
configuration and silently miss the other.
