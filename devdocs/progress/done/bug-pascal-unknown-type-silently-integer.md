---
prio: 65
---

# An UNKNOWN type name silently becomes a 4-byte Integer (pointers truncate)

- **Type:** bug (correctness — silent wrong code, no diagnostic)
- **Track:** P — Pascal frontend (shared `parser.inc`, so Track A file-lane)
- **Status:** done — CLOSED 2026-07-13.

## Symptom
`ParseTypeKind`'s final fallback is `Result := tyInteger` — meant for enum names, but an
**unknown** name lands there too. So a typo compiles:

```pascal
var x: Integr;      { typo for Integer — compiles, becomes a 4-byte Integer }
```

and, far worse, a pointer type the source never declared becomes a 32-bit int, so every
address stored through it is **TRUNCATED**:

```pascal
var p: PSomethingUndeclared;   { silently a 4-byte Integer }
p := GetMem(64);
```
```
heap-addr = 131751131217928
via-p     = 18446744072423997448     <- corrupted, no diagnostic
```

## This hole has bitten before
`bug-tobject-param-truncated-32bit` was exactly this: `Sender: TObject` fell through to
tyInteger and truncated. That fix special-cased TObject. **It patched the symptom, not the
hole** — and the hole then swallowed `TClass` (a class reference, truncated) and
`Int8`/`Int16`/`Int32` (all silently 4 bytes) until 2026-07-13, when those were fixed the
same one-at-a-time way. The next missing name will do it again.

## Confirmed symptoms so far
Each was found and fixed one at a time, and each came through THIS hole:
- `Sender: TObject` truncated to 32 bits ([[bug-tobject-param-truncated-32bit]]);
- `TClass` truncated — a class reference in a 4-byte int;
- `Int8` / `Int16` silently 4 bytes (and `Int32` right only by luck);
- **`absolute` silently IGNORED** — the var-section's qualifier skipper handed `absolute`
  AND its target name to ParseTypeKind, where both became Integers, so the overlay never
  happened and the variable got its own storage (b265).

The hole keeps manufacturing these. It is worth closing.

## Why it is not closed yet — what is VERIFIED, and what is not
Making it an error is a one-line change, and **the compiler still self-hosts with it on.**
`make test` then fails in exactly ONE place: the flagship fgl-compiles test, with
`unknown type: TPoint`. Everything else in the suite passes.

### Verified facts (do not re-derive)
- `TPoint` IS properly declared: under the lax build `SizeOf(TPoint) = 8` (the two Longints
  from `rtl/inc/typshrdh.inc`). The include RESOLVES.
- A missing include inside a unit is ALREADY a hard error — so it could not have been
  silently skipped.
- A record's NAME is registered (`AddUClass`) BEFORE its body is parsed, and a
  self-reference through a pointer (`next: ^TR`) resolves fine.
- **`VER3` IS defined under `--mimic-fpc`.** So typshrdh.inc's `{$ifdef VER3}` block is
  ACTIVE, and TPoint's declaration really does contain `public` and
  `constructor Create(apt: TPoint); overload;` — an advanced record, which pxx cannot parse
  ([[feature-pascal-advanced-records]]).

### What is NOT known
**Which construct actually trips it.** Line numbers are useless here: the error reports
"line 19", which is a COMMENT in typshrdh.inc and a `{$modeswitch}` in types.pp — they do
not track across includes. Two hypotheses were tried and BOTH were wrong (an unresolved
include; then a self-referencing type). Do not guess a third.

### The diagnostic is now IN, and it found the construct
Every Error now prints the `near:` token window (2026-07-13). With the strict error
re-applied, it says:

```
pascal26:19: error: unknown type (TPoint)
  near: dupError   PPoint   >>> TPoint  TPoint
```

So the failing token is the `TPoint` in **`PPoint = ^TPoint;`** — `typshrdh.inc` line 90.
TPoint itself is declared at line 62 of the same file, i.e. BEFORE it. So the question is
not "where" any more, it is:

**Why is TPoint not registered by the time `PPoint = ^TPoint` is parsed, given it is
declared 28 lines earlier?**

The likely answer: TPoint is a full ADVANCED RECORD — `public`, `constructor Create`,
`class function`, `class operator` — and pxx cannot parse any of that
([[feature-pascal-advanced-records]]). A minimal advanced record fails outright under the
LAX compiler too (`Expected: :, but got: function`), yet the real one somehow survives and
`SizeOf(TPoint) = 8` with `p.X` working — so something about that declaration is being
partially skipped rather than parsed, and the name never lands in the record table even
though the type ends up usable. THAT is the thing to understand.

### Instrumented — and the answer is ORDER, not the record
Done 2026-07-13. `AddUClass` DOES run for TPoint and `ParseRecordFields` DOES complete:

```
DBG unknown TPoint: IsRecordType=0 alias=-1 UClsCount=4 TypeSectionDepth=0
DBG named-record branch for TPoint, ci=4
DBG TPoint fields done; IsRecordType=20
```

Read the order. The **unknown-TPoint hit comes FIRST**, while the record table is still
empty for it (`IsRecordType=0`, `UClsCount=4`) — and TPoint's record declaration is
processed AFTERWARDS. So `PPoint = ^TPoint` is being parsed BEFORE `TPoint = record`, even
though TPoint is declared 28 lines EARLIER in the file.

**Declarations are not reaching the parser in source order.** That is the actual bug to
chase — not advanced records, and not the include. The advanced-record body is presumably
why TPoint's declaration gets deferred/re-walked, but the failure itself is an ordering
one.

This also explains something that should have been suspicious all along: forward pointer
refs (`PNode = ^TNode;` before TNode) currently WORK. If a pointer alias can be parsed
before its element type exists, then the unknown-name fallback is what is silently
absorbing that case too — which means closing the hole may require the forward-pointer
path to be made explicit (a real forward declaration + fixup), not just an error.

Next: find why the declaration order is not source order here (the decl pre-scan /
excision machinery is the place to look), and how forward pointer aliases are meant to
resolve their element type.

Advanced-record support is the likely prerequisite either way, since that declaration
cannot currently be parsed as written.

## Old notes (superseded)
## Why it was not simply made an error
Tried 2026-07-13 (one line: error instead of `Result := tyInteger`). It does NOT break
forward references — the declaration pre-scan registers the type section up front. It DOES
break the **flagship fgl-compiles test** with `unknown type: TPoint`.

### A wrong lead, recorded so nobody re-walks it
My first hypothesis was that FPC's `types.pp` declares `TPoint` via `{$i typshrdh.inc}`
and that we fail to resolve that include. **That is WRONG.** Checked directly:

```
uses types;         -> SizeOf(TPoint) = 8   (the record from the include: two Longints)
uses fgl;           -> SizeOf(TPoint) = 8   (transitively, same)
uses fgl, types;    -> SizeOf(TPoint) = 8
```

The include IS found and TPoint IS registered — and a missing include in a unit is already
a hard error (verified), so it could not have been silently skipped anyway. So the
"headline FPC-compat leans on this bug" claim in the first draft of this ticket was
**false**; ignore it.

What the strict error's true source is has NOT been isolated. Something in the `fgl` ->
`types` chain references a type name that is unknown AT THAT POINT, and today it quietly
becomes an Integer. Note that `typshrdh.inc`'s TPoint is an ADVANCED RECORD (methods,
`public`, a self-referencing `constructor Create(apt: TPoint)`), and pxx does not parse a
record with a `public constructor` at all — so how much of that declaration actually lands
is worth checking first.

## How to pick this up
1. Re-apply the one-line strict error in ParseTypeKind's final `else`.
2. Compile `test/test_fgl_use.pas --mimic-fpc -Fu/usr/share/fpcsrc/3.2.2/rtl/objpas` and
   find WHICH name is unknown and where. Do not assume it is the include.
3. Fix that, then keep the error.

The truncation hole is the prize and it is worth the dig: it is a silent wrong-code bug,
and it has already produced two shipped symptoms (TObject, then TClass/Int8/Int16).

## Gate
`make test` + self-host byte-identical + cross. The fgl-compiles test is the one to watch.


## CLOSED 2026-07-13

The insight was that the fallback was only ever legitimately needed in **one** place: the
ELEMENT of a `^`. `PNode = ^TNode;` before TNode is a legal forward reference, and
`ResolvePendingPointerAliases` already fixes the element up afterwards BY NAME — the
fallback was just the placeholder that let the parse get that far. Everywhere else it was
pure hazard.

So: a `PtrElemDepth` counter is raised around both `^`-element parses, an unknown name is
tolerated only while it is > 0, and everywhere else it is now `Error('unknown type: ...')`.

Two more name tables had to be consulted first, because they hold names that ARE declared
and simply were not reachable from ParseTypeKind:
- named dynamic-array types (`TByteArray = array of Byte`) live in their own table;
- C-imported typedefs (`typedef void* PGtkWidget;`) live in the C typedef table
  (needed a forward decl, since cparser.inc is included after parser.inc).

### What the strict check immediately caught
- **`AnsiChar` was never a recognised type name** — `Char` is a lexer TOKEN, so its FPC
  synonym fell through and became a 4-BYTE INTEGER where a 1-byte char belongs. Fixed.
- **The GTK tests were storing a 64-bit pointer in a 4-byte int.** `PGtkWidget` is never
  declared by the real `gtk.h` those tests import (it is a pxx-ism from a different
  header), so it was silently an Integer. The tests PASSED anyway — the truncated pointer
  was still non-nil. They now use `Pointer`, which is what `gtk_window_new` (a `void*`)
  actually returns. That is the bug this ticket describes, found live in green tests.

### Gate
`make test` green, self-host byte-identical, `testmgr --tier full` GREEN. Regression b266:
the POSITIVE half (forward `^` refs, named dyn-array types, AnsiChar/Int16 widths) in the
test file, and the NEGATIVE half (a typo'd name must FAIL to compile) in the Makefile,
since it must not compile at all.
