---
slug: bug-a-assigning-nil-to-a-method-pointer-segfaults
track: A
prio: 65
type: bug
blocked-by: []
summary: "`ev := nil` where `ev: procedure(x: Integer) of object` SEGFAULTS at the assignment. Not at the call — at the store. Reproduced on pinned and at HEAD, with and without --no-nil-check, in a 12-line program. A method pointer is a 16-byte {Code,Data} record, so `:= nil` almost certainly lowers as a record COPY from address 0."
status: done
owner: claude-A
---

# `ev := nil` on a method pointer segfaults

## Repro — 12 lines, no RTL beyond the default

```pascal
program n5;
type
  TEv = procedure(x: Integer) of object;
  TC = class
    procedure Hit(x: Integer);
  end;
procedure TC.Hit(x: Integer); begin writeln('hit ', x); end;
var ev: TEv;
begin
  writeln('start');
  ev := nil;              { <-- SIGSEGV HERE }
  writeln('assigned nil ok');
end.
```

```
start
Segmentation fault (core dumped)   exit 139
```

`start` prints; the line after `ev := nil` does not. The fault is at the
**store**, with no call anywhere in the program.

- Reproduced on `pinned` (so it is not a recent regression) and at HEAD.
- Unaffected by `--no-nil-check`, so it is nothing to do with
  [[feature-a-emitted-nil-checks]] — it was found there and is in that
  feature's way, which is why it is filed rather than folded in.
- `Assigned(ev)` on an untouched `ev` answers `FALSE` and does not fault, so
  reading the variable is fine; it is specifically the nil STORE.

## Where to look

A method pointer is the 16-byte `{Code@0, Data@8}` record `MethodPtrRecId`
describes (`defs.inc:2207`), and its declared type kind is `tyRecord`
(`pasparser_lval.inc:71` keys the call path off exactly that). So `ev := nil`
reaches `AN_ASSIGN` with `lhsTk = tyRecord` and a nil RHS, and the record arm
copies `RecSize` bytes **from the source address** — which for `nil` is 0.
A 16-byte read from address 0 is precisely this fault.

The machinery to do it right is already there and one arm over: the
`AN_DEFAULT` path in the same `AN_ASSIGN` case emits `IR_DEFAULT_MEM`, which
zero-fills a record of exactly this size and already handles managed fields.
`ev := Default(TEv)` should be checked first — if that works, the fix is to
normalise `nil` into the same path rather than to grow a second one
(`devdocs/dev/normalise-dont-special-case.md`).

**Grep for the sibling before closing:** the same shape is reachable for any
record-valued nil-comparable type. Check at least `ev := nil` as an *argument*,
as a *field* (`obj.OnHit := nil`, which is the form real event-handler code
actually uses and is probably how this ships in an app), as an *array element*,
and the `nil`-RHS of a `var`/`out` parameter. A fix that only covers the simple
variable store leaves the common case broken.

## FPC

FPC accepts `ev := nil` on a method pointer and nils both fields; `Assigned(ev)`
is then False. That is the behaviour to match.

## Why the priority is not lower

It is a segfault on a two-word program with no unsafe construct in it, in the
type every GUI/event-driven Pascal program uses for callbacks — `OnClick := nil`
is how you *detach* a handler. Anything in `lib/pcl` or `examples/**` that does
that is dead on the spot.

## Gate

`make compiler/pascal26` (fixedpoint) + a test covering the four shapes in the
grep-for-the-sibling list above, each asserting `Assigned(x)` is False after,
plus the existing method-pointer call tests still green. `tools/gate.sh quick`.

---

## Resolution (2026-08-21)

### Confirmed by disassembly, not by reading

```
Program received signal SIGSEGV
  ev := nil;
  ...
  movabs $0x10,%rcx
=> rep movsb (%rsi),(%rdi)
```

16 bytes, `rep movsb`, source `%rsi`. Exactly the record copy the ticket
predicted, from a null source.

### The sibling was one `if` away

`ir.inc`'s `AN_ASSIGN` / `lhsTk = tyRecord` block already had this fixed **for
interfaces**, with a comment that states the whole bug:

> *interface := nil — zero the whole fat pointer {nil, nil}. The RHS is a
> pointer/ordinal nil, not a class or interface, so it never reaches the
> record-copy path (which would dereference a bogus source).*

The method-pointer arm sits in the same block, is the same 16-byte record, takes
the same nil, and was never checked. `devdocs/dev/normalise-dont-special-case.md`
names this exactly — and the arm that stayed broken is the one people write.

### Fix

One arm beside the interface one: a record-shaped destination assigned a nil
POINTER LITERAL is `IR_DEFAULT_MEM` (zero-fill of `RecSize`), not a copy.

Matched precisely — `AN_INT_LIT` + value 0 + `tyPointer`, which is exactly what
`tkNil` produces (`pasparser_expr.inc:370`) — rather than by the interface arm's
broader "RHS is not a class and not a record". The broader condition is arguably
the real normalisation and would also catch `r := 5`, but that changes behaviour
for shapes no test covers, and there was no evidence to spend. The narrow form
cannot make anything worse: every input it catches is a program that segfaulted.

Zero-fill is right rather than merely non-crashing: nil for a method pointer
means both fields nil, which is what FPC stores and what `Assigned()` then
reports.

### Four shapes, because the simple one is not the one that ships

`test/test_methodptr_nil_assign.pas`: a variable, a **field** (`c.OnHit := nil`
— what event-handler code actually does), an **array element**, and a `var`
parameter nilled by the callee, plus a loop. Each slot is armed and **called**
before it is cleared, so `Assigned()` is reading a real value and not answering
False by default.

`pinned` segfaults on this program after the first `hit 1`. Clean negative
control.

### Checked for collateral

Every interface test in the tree runs green (`test_interface_arc`, `_arc_exc`,
`_as_cast_retains`, `_ascast_dead_branch_temp`, `_ascast_temp_lifetime`,
`test_dynarray_of_interfaces_assign`, `test_getinterface_guid_b257`,
`test_interfaces`, `test_interface_byval_param_no_leak`) plus
`test_record_copy` — the arm above mine and the arm below it.

### Unblocks

[[feature-a-emitted-nil-checks]] arm 1's method-pointer half, which could not be
tested at all: `ev := nil; ev(2)` now reports
`caught methptr: Access violation (nil reference)` and the program continues.

### One residue, filed separately

`Take(nil)` where `Take(e: TEv)` is REFUSED — *"no overload of Take matches
these arguments: (Pointer)"*. FPC accepts it. Not a crash and not this bug (the
store is fixed; this is argument type-matching), so it is
[[bug-a-nil-is-not-accepted-as-a-method-pointer-argument]] rather than scope
creep here.

### Gate

`make compiler/pascal26` (byte-identical fixedpoint, 1 round) + the four shapes
+ the interface/record neighbours + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-21 — resolved, commit a90ad49ef.
