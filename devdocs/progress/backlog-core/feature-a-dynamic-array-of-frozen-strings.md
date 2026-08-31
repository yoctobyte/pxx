---
track: A
prio: 45
type: feature
summary: "In the FROZEN-string model (-uPXX_MANAGED_STRING, the self-host build), `array of string` is refused from SetLength up: the element is an inline fixed-capacity buffer and no path knows its stride. Delete/Insert refuse it downstream of that, which is why they carry a frozen-string exclusion."
---

# `array of string` is unsupported in the frozen-string model

- **Type:** feature (compiler core) — **Track A**
- **Opened:** 2026-08-21, split out of
  [[feature-dynarray-insert-delete-managed-elements]] while closing its last
  items.

## What happens

```pascal
program frz;
var a: array of string;
begin
  SetLength(a, 3);       { ok in the managed model }
end.
```

```
$ ./compiler/pascal26 -uPXX_MANAGED_STRING frz.pas out
pascal26:5: error: SetLength: dynamic array of record/string not yet supported
```

Managed mode (`tyAnsiString` elements, the default) is fine — the element is a
handle, one pointer wide. The **frozen** model stores the string INLINE, so the
element stride is the declared capacity plus its length header, and that number
is not what `TypeSize(tyString)` answers. `ir_codegen.inc`'s `specialId = 102`
arm refuses rather than striding by a wrong width, which is the right call:
the wrong stride here is not a crash, it is a buffer of silently overlapping
strings.

## Why this ticket exists separately

`feature-dynarray-insert-delete-managed-elements` carried "frozen-string
elements" as an open item on Delete/Insert. It is not their gap. They refuse it
because **nothing** supports it: a program cannot even `SetLength` such an array,
so Delete/Insert could never have been reached with one. Fixing it there would
have been a microfix on the symptom
(`devdocs/dev/root-cause-over-microfix.md`).

## Scope

1. Record the element's frozen capacity on the dyn-array symbol (the
   `SymTR[].ElemTk = tyString` case needs an `ElemStrCap` alongside it — the
   record arm already carries `ElemRec` for exactly this reason and computes
   `RecSize`).
2. Use it as the stride in every SetLength / index / copy path, per backend —
   the same list `SymDynElemRowLen` already threads through.
3. Then DELETE the frozen-string exclusions in the Delete/Insert parser gates
   (`pasparser_stmt.inc`, both spellings of "frozen-string element type not yet
   supported"), and add an `array of string` section to
   `test/test_dynarray_insert_delete.pas` that runs under
   `-uPXX_MANAGED_STRING`.

## Priority note

Low (30). The frozen model exists for the self-host build, and the compiler's
own source does not use `array of string` — it would have hit this. Ordinary
user code runs in the managed model, where the shape already works.
