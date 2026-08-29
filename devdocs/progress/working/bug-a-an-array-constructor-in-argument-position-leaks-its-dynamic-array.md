---
track: A
prio: 60
type: bug
blocked-by: []
summary: "`Take([...])` — an array CONSTRUCTOR passed to an open-array parameter — heap-allocates a dyn-array temp per call and never releases it. 64 bytes leaked per `Format('%d-%s', [i, 'x'])`; 2M Format calls reach 125 MB RSS. Element type is irrelevant (128 B/call for strings, 40 B/call for integers). The sibling arm — a fixed-array VARIABLE passed to the same parameter — was fixed in 2026-06 (bug-open-array-copy-temp-leak, 692db33) by replacing the heap temp with a frame buffer; the constructor arm still allocates. Same concept, two paths, fix landed on one."
status: working
owner: frankA
---

# An array constructor in argument position leaks its dynamic array

- **Type:** bug (codegen / managed heap) — **Track A**.
- **Filed:** 2026-08-29 by the wasm32 lane, on `origin/master` at `7aba316be`.
  Target-independent; measured on native x86-64.
- **Impact: `Format` leaks 64 bytes per call**, which is what raises this above
  the usual temp-lifetime ticket. `Format(fmt, [args])` is the single most
  common way an array constructor appears in real Pascal, and every one of them
  leaks.

## Symptom

```pascal
program FmtRss;
uses SysUtils;
var i: Integer; s: string;
begin
  for i := 1 to 2000000 do s := Format('%d-%s', [i, 'x']);
  writeln('done ', Length(s));
end.
```

```
done 9
Maximum resident set size (kbytes): 125232
```

## Measurement

The instrument is arena advance between two `PXXAlloc(1024, 8)` probes, at two
iteration counts. 1024 is a size the loop never allocates and therefore never
frees, so every probe bumps the arena rather than popping a free list; a build
that releases everything gives the SAME number at both counts.

```pascal
procedure Take(const a: array of string);  begin if Length(a) = 0 then writeln('empty'); end;
procedure TakeI(const a: array of Integer); begin if Length(a) = 0 then writeln('empty'); end;
```

| loop body | n=1000 | n=9000 | per call |
| --- | --- | --- | --- |
| `Take(['x', 'y'])` | 129032 | 1153032 | **128 B** |
| `TakeI([1, 2])` | 41032 | 361032 | **40 B** |
| `Format('%d-%s', [i, 'x'])` | 65072 | 577072 | **64 B** |
| `Take(av)` — a named `array of string` variable | 1032 | 1032 | **0 B** |

The last row is the control and it is what makes the rest a leak rather than an
artefact of a bump allocator: the same parameter, the same callee, an argument
that is a variable instead of a constructor, and the advance is flat. The
release machinery works; the constructor path does not reach it.

Element type is irrelevant (strings and integers both leak, differing only by
element width), so this is the dyn-array temp itself, not per-element ARC.

## The sibling that was already fixed

`bug-open-array-copy-temp-leak` (done, 2026-06-23, `692db33`) is the same
defect on the other arm: passing a FIXED ARRAY to an open-array parameter
heap-allocated a dyn-array temp whose slot was re-nil'd per call, orphaning the
previous block — "~40-48 bytes PER CALL, a 2M-call loop reached ~78-94 MB RSS".
It was fixed by replacing the heap temp with a frame/BSS-local `[len:8][data]`
buffer, which is reused per call site and auto-frees.

The constructor arm was not covered by that change and still allocates. This is
`normalise-dont-special-case`'s stated failure mode — *"if you fix a bug on one
arm of a double case, grep for the sibling before closing the ticket"* — and
the numbers line up almost exactly (40-48 B/call then, 40-128 B/call now; ~78-94
MB then, 125 MB now), which is the tell that it is one concept and not two bugs.

**So the likely fix is not new work: apply the same frame-buffer treatment to
the constructor path.** Whether the buffer can be shared with the fixed-array
arm, or whether a constructor whose elements are managed needs per-element
release before reuse, is the part that needs deciding — a constructor of
`string` elements owns its element handles in a way a borrowed fixed array does
not, so the "managed element handles are borrowed bytes, no per-element ARC"
justification in the 2026-06 ticket does NOT carry over unexamined. That is the
one real design question here and it should be settled before coding.

## Not to be confused with

`bug-a-open-array-of-string-arg-spilled-through-a-managed-string-temp` (same
lane, same day, adjacent code). That one is a mistyped hidden temp and was
measured to leak NOTHING — its arena advance is identical before and after the
fix. This ticket is the leak that probe kept finding underneath it. Two
defects, one call shape; fixing the first does not touch this.

## Gate

Track A's: `make compiler/pascal26` (the byte-identical self-host fixedpoint)
plus the arena-advance table above reproduced flat, plus `tools/gate.sh quick`.
The control row must stay flat too — a "fix" that made every row equal by
making the variable case allocate would pass a slope test on the three leaking
rows alone.

---

# Diagnosis, frankA 2026-08-30 — one root cause, TWO leaking consequences

**Reproduced first:** `FmtRss` gives 124,720 KB here against the ticket's
125,232 KB. Confirmed at `origin/master`, native x86-64.

**Both lowerings are in `compiler/ir.inc`:** `AN_ARRAY_CTOR` at :5921 and
`AN_VARREC_ARRAY` at :6000. Each does exactly what the sibling ticket described
— `AllocDynArray(...)`, then `IR_DEFAULT_MEM` re-nils the handle slot per call,
then `SetLength`. Re-nilling without releasing orphans the previous block. Same
mechanism as `bug-open-array-copy-temp-leak`, on the other arm, as filed.

## Correction: "element type is irrelevant" is wrong, and it changes the fix

The ticket concludes:

> Element type is irrelevant (strings and integers both leak, differing only by
> element width), so this is the dyn-array temp itself, not per-element ARC.

Two numbers (128 B for two strings, 40 B for two integers) are consistent with
that reading, but they are also consistent with a second leak, so they do not
separate the hypotheses. Varying **element count** and **string length** does.

Instrument: RSS over a 2M-call loop. It is validated against the ticket's own
arena-probe instrument on all three overlapping rows — `Take(['x','y'])` 128 B,
`TakeI([1, 2])` 40 B, `Format('%d-%s', [i,'x'])` 64 B — so the two independent
methods agree where they overlap, and the new rows below can be trusted.

| loop body | RSS (KB) | B/call |
| --- | --- | --- |
| `Take(['x'])` — 1 string | 156 160 | 80.0 |
| `Take(['x','y'])` — 2 strings | 249 984 | 128.0 |
| `Take(['x','y','z'])` — 3 strings | 343 552 | 175.9 |
| `TakeI([1])` | 77 952 | 39.9 |
| `TakeI([1,2])` | 78 080 | 40.0 |
| `TakeI([1,2,3])` | 93 696 | 48.0 |

**Strings scale linearly with element count at ~48 B per element per call.
Integers do not** — 1 and 2 elements cost the same 40 B, and the step at 3 is an
allocator size class, not a slope. So element type is not irrelevant; it selects
whether a second leak exists at all.

Second axis, which settles what that per-element cost *is* — string **length**,
one element throughout:

| element | RSS (KB) | B/call |
| --- | --- | --- |
| `['x']` (1 char) | 156 160 | 80.0 |
| `['x'*32]` | 218 752 | 112.0 |
| `['x'*128]` | 406 016 | 207.9 |

~1 byte per character. **The string DATA is leaking, not merely a handle.** Each
call allocates a fresh copy of every string element and never releases it.

## So there are two leaking things, from one root cause

The orphaned block is the single cause; it has two consequences, because the
block *owns* what it points at:

| path | node | array block leaks | element data leaks |
| --- | --- | --- | --- |
| `Format(f, [i,'x'])` — `array of const` | `AN_VARREC_ARRAY` | yes, ~48–64 B/call | **no** |
| `Take(['x','y'])` — `array of string` | `AN_ARRAY_CTOR` | yes, ~40 B/call | **yes**, ~(len+40)/element |
| `TakeI([1,2])` — `array of Integer` | `AN_ARRAY_CTOR` | yes, ~40 B/call | n/a (unmanaged) |
| `Take(av)` — a named variable (control) | — | no | no |

`Format` is confirmed clean on the second axis: `%s` with a 1-char argument and
with a 128-char argument both cost **63.9 B/call**, flat. An `array of const`
element is a `TVarRec` holding a *reference*; it never copies the string. The
`AN_ARRAY_CTOR` path is different because it stores each element **through the
normal element-assign path, with managed-string ARC** (its own comment says so)
— those handles are freshly owned by the temp, and die with it.

## What this does to the proposed fix

The ticket proposes applying the sibling's frame-buffer remedy, and asks whether
a constructor of `string` elements needs per-element release. **Measurement
answers it: yes, and the element leak is already there today, independent of any
change.**

- For the **headline `Format` case the ticket is exactly right**: pure dyn-array
  temp, no element leak, and the frame-buffer swap fixes it completely. That is
  the highest-value half and it is the straightforward one.
- For **`AN_ARRAY_CTOR` with managed elements the sibling's justification does
  not carry over**, and the ticket was right to flag it. `bug-open-array-copy-temp-leak`
  could say *"managed handles are borrowed bytes (no per-element ARC)"* because
  it `IR_COPY_REC`'d raw bytes out of a caller-owned fixed array — the caller
  kept ownership. Here the temp **creates** the handles. A frame buffer that
  reuses storage without releasing the previous contents keeps leaking the
  elements: `Take(['x'])` would go from 80 B/call to roughly 40, not to 0.

So the constructor arm needs the buffer **plus** a release of the previous
contents' managed elements before reuse (or the elements stored as borrowed
rather than retained). That is a real design decision and it is now made against
numbers rather than against the sibling's precedent.

**A slope test on the three leaking rows alone would not catch this** — the same
warning the ticket's own Gate section makes about the control row. A fix that
addressed only the block would move every headline number and still leak
proportionally to string length, which no fixed-size probe sees.

## Status: blocked on file ownership, not on understanding

Both lowerings are in `compiler/ir.inc`, held by **frankC** (C-side array-shape
census). Diagnosis, instrument and the element-release decision are done and
recorded here; the edit itself is short once the file is free. Nothing else in
the Pascal frontend or codegen is involved — the parser side
(`pasparser_lval.inc:3285/3407`) only builds the node and needs no change.
