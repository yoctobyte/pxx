---
track: B
prio: 55
type: bug
status: open
found: 2026-08-31
found-by: frank-user
owner: ""
blocked-by: []
summary: "lib/pcl/gtk3.pas PC() writes past its buffer with no length check at all. CBuf is 4096 bytes as four 1024-byte slots; a 1024-char string at slot 3 writes CBuf[4096], one past the array, and anything longer overruns further. At slots 0-2 a long string silently corrupts the NEXT slot, which a caller may still be holding. Single-threaded, no GTK misuse required. THE STATIC BUFFER IS NOT THE BUG AND MUST NOT BE 'FIXED': the owner ruled 2026-08-31 that it stays -- GTK is main-thread-only by contract (same as Win32), and PC() returns BEFORE the C call happens, so any allocating alternative needs a lifetime scheme with no good answer. The fix is a bounds check with deterministic truncation, keeping the static ring exactly as it is."
---

# `PC()` writes past its buffer on a long string

`lib/pcl/gtk3.pas`:

```pascal
CBuf: array[0..4095] of Char;   { four 1024-byte slots }
base := CBufSlot * 1024;         { slot 3 -> base 3072 }
for i := 1 to Length(s) do CBuf[base + i-1] := s[i];
CBuf[base + Length(s)] := #0;    { no bounds check anywhere }
```

Nothing tests `Length(s)`.

- `Length(s) = 1024` at slot 3 writes the NUL at `CBuf[4096]` — one past the end.
- Longer strings at slot 3 run off the array proper.
- At slots 0-2 a long string silently overwrites the **next slot**, which exists
  precisely so a caller can hold two transient strings at once (a `"%s"` format
  plus its argument). So the corruption target is a live buffer.

No threading and no GTK misuse required — a single-threaded program with a long
label does it.

## What NOT to change — owner's ruling, 2026-08-31

The static buffer is deliberate and **stays**:

- **GTK is main-thread-only by contract** (all calls from the thread that called
  `gtk_init`, as on Win32), so a shared static is not a thread-safety hole in a
  program that obeys the toolkit.
- **`PC()` returns before the C call happens**, so an allocating version has no
  moment at which it can free — *"the alternative is that we get a memory
  management hell."*

Do not replace this with heap allocation, refcounting, or a caller-frees
contract. That is the change this ticket exists to prevent as much as the
overflow.

## The fix

Bounds-check against the slot size and **truncate deterministically** when a
string does not fit. Static ring unchanged, no allocation, no ownership
question. A truncated GTK label is a visible cosmetic bug; the current behaviour
is silent memory corruption.

Worth deciding while there: whether an over-long string should also be visible
some other way, or truncation alone is enough. Truncation alone is probably
right for a binding — a label is not a place to raise.

## Also stale, same file

The comment argues *"one shared static buffer reused per call is safe (calls are
sequential)"* while the code has a **four-slot ring**, and rests the safety on
*"GTK copies title/label strings immediately"* — true of labels, not a general
property of every function this could be passed to. Fix the comment with the
bug, and say which functions the copy-immediately claim actually covers.
