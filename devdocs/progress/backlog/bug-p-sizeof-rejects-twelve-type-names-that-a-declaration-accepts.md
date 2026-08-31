---
slug: bug-p-sizeof-rejects-twelve-type-names-that-a-declaration-accepts
track: P
type: bug
prio: 40
status: backlog
found: 2026-08-31
found-by: frank-rust
owner: unassigned
blocked-by: []
summary: "A PATTERN, not a site: a builtin type name is settled against the builtin TABLE rather than against the PROGRAM. Two instances so far in different functions with different callers -- SizeOf (fixed: the builtin table was consulted before the record/alias/array/enum/variable tables, so after the tables were merged `type Currency = record` measured 8 instead of 12, a Boolean named `longbool` measured 4 instead of 1, and a ten-byte array named `tdatetime` measured 8 instead of 10, all confirmed against FPC 3.2.2) and ParseTypeKind (open: bug-p-a-user-type-whose-name-shadows-a-builtin-is-unusable, which also drives the const-eval SizeOf). ORDERING IS NECESSARY AND NOT SUFFICIENT -- frankwasm hit the same family at 19bb32f31 with the ordering already correct and it still refused a legal program, because the declaration had not been parsed yet when the check ran. The census of all 51 builtin names, the counter-example, and the control program are in the body; the twelve REJECTED names it opened on are fixed."
---

# `SizeOf(N)` rejects twelve builtin type names that `var v: N` accepts

## The census — all 51 builtin names, measured

For each name: compile `var v: N; WriteLn(SizeOf(v))` and `WriteLn(SizeOf(N))`.
Thirteen disagree; the other 38 agree exactly.

| name | `SizeOf(v)` | `SizeOf(N)` |
| --- | ---: | ---: |
| SizeUInt, ValReal, TDateTime, Currency | 8 | **rejected** |
| LongBool | 4 | **rejected** |
| WordBool | 2 | **rejected** |
| ByteBool | 1 | **rejected** |
| Comp, OleVariant | 8 / 16 | **rejected** |
| UTF8String, RawByteString, ShortString | 8 | **rejected** |
| Extended | 8 | **10** |

The error is `SizeOf: unknown type or variable`, with nothing hinting the type
itself is fine — the same no-diagnostic shape `BuiltinTypeNameTk`'s header says
it was created to end.

`Extended` is **not** part of this ticket: it needs a ruling on what `Extended`
IS, not a lookup, and it already has one —
[[bug-p-sizeof-extended-disagrees-with-the-storage-extended-gets]] [P p65].

This is the FOURTH ticket from one two-table split, after
[[bug-a-sizeof-real-disagrees-with-the-storage-real-actually-gets]], the
`Extended` one, and
[[bug-p-sizeof-string-disagrees-with-the-storage-string-actually-gets]].

## The obvious fix is wrong — built, measured, reverted

`BuiltinTypeNameTk` ends in `else Result := tyUnknown`. Chaining the declaration
path there (`else Result := BuiltinScalarTypeKind(nm)`) fixes twelve of the
thirteen in one line, keeps the fixedpoint, and passes the whole census. **It is
still wrong**, and the safety argument for it — *"every arm above still wins, so
this can only turn a REJECTION into an answer"* — is false:

```pascal
type Currency = record a, b, c: Integer; end;   { a USER type }
var longbool: Boolean; tdatetime: array[0..9] of Byte;
```

| | correct (pinned) | with the chain |
| --- | ---: | ---: |
| `SizeOf(Currency)` — the user's record | 12 | **8** |
| `SizeOf(longbool)` — a `Boolean` variable | 1 | **4** |
| `SizeOf(tdatetime)` — a 10-byte array | 10 | **8** |

`SizeOf`'s dispatch consults `BuiltinTypeNameTk` **first** and only reaches the
record/alias/array tables in its `else`. So a rejection there was never a
rejection — **it was the fallthrough into the user-type lookup**, which is
exactly what the table's own header warns about: *"Callers must consult a user
type alias FIRST where that matters: this answers what the name means as a
BUILTIN, not what the current scope binds it to."* SizeOf is a caller for which
it matters, and does not.

**Why the census could not see this**: every probe program declared no user
types, so `rejected` and `resolved by the user-type path` produce identical
output. The measurement was correct and answered a different question — a
negative result with two indistinguishable causes, and only the one I was
looking for in view.

## The real fix

Reorder `SizeOf`'s dispatch so the user tables (record, class, array alias,
type alias, enum) are consulted **before** `BuiltinTypeNameTk`, matching what
that header already tells callers to do; *then* the chain above is safe and
closes twelve rows. Note the reorder is a behaviour change in its own right —
today a user `type Integer = ...` loses to the builtin — so it wants its own
before/after census, with the shadowing program above as the positive control.

Possibly the same job as
[[refactor-p-five-dispatch-sites-for-one-named-type-cast]].

## Reproducing the census

Loop the 51 names, compiling the two one-line programs above for each, and diff
the columns. Roughly 100 sub-second compiles. **Include at least one user type
whose name collides with a builtin** — without that the run cannot distinguish
the two causes, and will report a clean fix for the change that regressed.
