---
slug: bug-a-assigning-nil-to-a-method-pointer-segfaults
track: A
prio: 65
type: bug
blocked-by: []
summary: "`ev := nil` where `ev: procedure(x: Integer) of object` SEGFAULTS at the assignment. Not at the call — at the store. Reproduced on pinned and at HEAD, with and without --no-nil-check, in a 12-line program. A method pointer is a 16-byte {Code,Data} record, so `:= nil` almost certainly lowers as a record COPY from address 0."
status: backlog
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
