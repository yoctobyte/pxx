---
track: A
prio: 45
type: feature
blocked-by: [decide-a-what-is-a-plain-frozen-strings-capacity-255-or-eight-megabytes]
summary: "PREMISE REFUTED 2026-09-03: the stride IS known and it is 8388616 bytes -- STRING_CAP + 8, taken from the ARRAY VARIABLE's storage class, which is a category error for a dynamic array whose elements live on the heap. Only x86-64 refuses; i386/aarch64/arm32/riscv32 ACCEPT it, match FPC 3.2.2 on three elements and SIGSEGV at 1000, all reproducible on pin v401 -- so x86-64's refusal is the only honest behaviour of the six and this is not a missing implementation. Now blocked on [[decide-a-what-is-a-plain-frozen-strings-capacity-255-or-eight-megabytes]], because the element stride IS that number: a plain frozen `string` is allocated at 8388616 (global) or 264 (local/field) and clamped at 255 in every one of them, by assignment as well as by concat. ORIGINAL TEXT, kept because it is what the ticket was filed on: In the FROZEN-string model (-uPXX_MANAGED_STRING, the self-host build), `array of string` is refused from SetLength up: the element is an inline fixed-capacity buffer and no path knows its stride. Delete/Insert refuse it downstream of that, which is why they carry a frozen-string exclusion."
status: working
owner: franka-29
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

## Re-measured 2026-09-03 (frankA) — the scope moved, in both directions

Still refused under `-uPXX_MANAGED_STRING` at HEAD. But the population it
refuses is not what this body describes, and the half that WAS the hard part is
already done.

| declaration | `-uPXX_MANAGED_STRING` |
| --- | --- |
| `array of string[10]` | **works** — 4 elements, values correct, no overlap |
| `array of string` | `SetLength: dynamic array of record/string not yet supported` |
| `array of AnsiString` | **same refusal** |

**THE CAPPED SPELLING NOW WORKS AND THIS TICKET DID NOT KNOW.** `array of
string[10]` allocates and strides correctly in all three modes (default,
`-u`, `-dPXX_SHORTSTRING`), asserted with four 10-char elements read back —
the shape that shows overlap if the stride is wrong. So "the element stride is
the declared capacity plus its header and that number is not what
`TypeSize(tyString)` answers" has been solved for every element that HAS a
declared capacity. What is left is the element that has none.

**AND `array of AnsiString` FAILS FOR THE SAME ONE REASON, WHICH THIS BODY
IMPLIES IT WOULD NOT.** It says "managed mode (`tyAnsiString` elements, the
default) is fine", which reads as though an explicitly-declared `AnsiString`
element stays managed under `-u`. It does not: **the flag freezes the whole
string family, not just bare `string`.** Measured — appending 'x' 300 times:

    default                 ansi=300  plain=300
    -uPXX_MANAGED_STRING    ansi=255  plain=255

So under `-u` an `AnsiString` is a 255-cap frozen buffer that truncates
silently, and `array of AnsiString` hits the same `ElemTk = tyString` guard.
One refusal, two spellings — not two gaps. (Whether the silent truncation of an
explicitly-declared `AnsiString` is chosen or a defect is a separate question
and not this ticket's; the mode's premise is "no heap strings", so it is at
least deliberate in direction.)

**WHAT IS ACTUALLY LEFT, AND IT IS A DECISION BEFORE IT IS A PATCH.** Both IR
paths are identical (`PXXDBG=a.ir`: the capped and uncapped spellings produce
byte-identical IR down to the `-102` call), so the whole difference is the
guard and the `elemSize` line beside it. Giving a plain frozen element the
stride it would have as a VARIABLE means `FrozenStrSlotSize(tyString,
DEFAULT_STR_CAP)` — **264 bytes per element**, so `SetLength(a, 1000)` is
264 KB. That is consistent with what a frozen `string` local costs and it is
still a number somebody should choose rather than inherit from a default,
which is why this was left rather than patched: the same `0`-means-unset
encoding is the subject of
[[bug-a-a-plain-frozen-string-records-capacity-zero-so-eleven-clamp-sites-cannot-say-unset]],
and deciding it there decides it here.

Not started for a second reason too: this is the `-uPXX_MANAGED_STRING` axis,
which the phase-4 byte-prefix flip does not touch, so it neither blocks the
flip nor is released by it.
