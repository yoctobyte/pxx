---
track: A
prio: 60
type: bug
blocked-by: []
summary: "`Take([...])` — an array CONSTRUCTOR passed to an open-array parameter — heap-allocates a dyn-array temp per call and never releases it. 64 bytes leaked per `Format('%d-%s', [i, 'x'])`; 2M Format calls reach 125 MB RSS. Element type is irrelevant (128 B/call for strings, 40 B/call for integers). The sibling arm — a fixed-array VARIABLE passed to the same parameter — was fixed in 2026-06 (bug-open-array-copy-temp-leak, 692db33) by replacing the heap temp with a frame buffer; the constructor arm still allocates. Same concept, two paths, fix landed on one."
status: new
owner: ""
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
