---
track: B
prio: 55
type: bug
status: open
found: 2026-08-31
found-by: frank-user
owner: ""
blocked-by: []
summary: "TWO bugs in lib/pcl/gtk3.pas PC(). (1) No length check: a 1024-char string at slot 3 writes one past CBuf; at slots 0-2 a long string corrupts the next live slot. (2) The four-slot ring is arbitrary and unenforced, so a call taking FIVE PChar parameters reuses a slot the caller still holds -- no long string needed. PC() IS NOT DELETABLE, owner 2026-08-31: @s[1] of an EMPTY string is a nil pointer, and NULL is not the same argument as a pointer to \"\" -- PC() always writes a NUL and returns a valid pointer, which is a real job. (NilPy hit this and answered it by making empty strings carry a valid pointer; whether that representation is general is measurement 1.) THREE MEASUREMENTS IN ORDER: (1) is an empty AnsiString nil or a valid pointer, and is Pascal the same as NilPy; (2) do RUNTIME-built strings reserve len+1 for the NUL, or only literals (confirmed for literals: elfwriter.inc:1003, and ir_codegen_riscv32.inc:3001 already skips the prefix for a frozen string); (3) only if both are favourable does the copy go. Likely outcome: PC() survives with a bounds check and deterministic truncation, maybe a non-empty fast path. Owner ruling unchanged: no allocation, no ownership scheme."
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

## THE COPY IS PROBABLY THE REAL BUG — owner, 2026-08-31

*"issues arise if any function call takes more than one pchar parameter. and
that's likely the real bug - we are copying - where the caller already has a
string allocated. and i sortof do recall us specifying ansistring as always
allocating 1 byte more than the string length, to be filled by #0, exactly for
pchar compatibility."*

Two things follow, and the second is a **second bug** the ticket above missed.

### The ring depth is arbitrary and unenforced

`PC()` cycles four slots. A call taking **five** PChar parameters silently reuses
slot 0 while the caller still holds it — and unlike the overflow, this needs no
long string at all. Nothing anywhere states or checks the limit. `SignalConnect`
takes one, so it has never bitten; a `gtk_*` call with several string arguments
would.

### The recollection is CORRECT FOR LITERALS, and that is the load-bearing gap

Confirmed: `elfwriter.inc:1003` — *"PXXStrFromLit NUL-terminates it (the length
and refcount live BELOW...)"*. And a codegen path already exploits it,
`ir_codegen_riscv32.inc:3001`:

```
{ External C call: a Pascal string literal is stored as an 8-byte length
  prefix + NUL-terminated chars; pass the char data so the callee sees a
  const char*. }
if ProcExternal[procIdx] and TypeIsFrozenString(...) then
  <skip the 8-byte prefix>
```

Note the guard: `TypeIsFrozenString` — **literal**. The comment says *literal*
too, twice.

**NOT established, and it decides the fix:** whether a **runtime-built** string
(concat, `SetLength`, a computed name) also reserves `len+1` and stores the NUL.
A grep of `builtin.pas` for a `+1` on the allocation path found nothing. If
runtime strings carry the NUL, `PC()` can be **deleted** — return a pointer to
the char data, no buffer, no ring, no overflow, no slot limit, and both bugs
above vanish. If only literals do, `PC()` must stay for computed strings and can
merely shortcut the literal case.

**So the first job on this ticket is that one measurement**, not the bounds
check. Read the allocation path (`builtin.pas`), confirm or refute `len+1`, and
say which in the ticket. The bounds check is the fallback if the answer is "only
literals" — and even then the ring-depth bug still needs an answer.

The owner's design ruling above is unaffected either way: no allocation, no
ownership scheme. Deleting the copy is the *opposite* of introducing one.

## CORRECTION — `PC()` is NOT deletable. The empty string is why. (owner, 2026-08-31)

*"the only issue is with possible empty strings (nil pointer) ... vs pchar and
nil references etc.. so, the PC() function is likely not obsolete, since we
cannot simply do `string s=""; pointer p=s[1]; callsome(PChar(p))`."*

The section above proposed deleting `PC()` if runtime strings carry the NUL.
**That is wrong on its own, and this is the constraint that breaks it:** taking
`@s[1]` of an **empty** string yields a nil pointer, and `NULL` is not the same
argument as a pointer to `""`. Many GTK/GLib functions treat them differently —
some accept `NULL` as "unset", others crash. A pass-through would silently turn
`SetTitle('')` into `SetTitle(NULL)`.

`PC()` handles this today by construction: it always writes a NUL and returns a
pointer to it, so an empty string arrives as a valid empty C string. **That is a
real job and it survives every other change proposed here.**

Prior art the owner cites, and it should be checked before anything is designed:
**NilPy hit the same problem, and the answer there was to make an empty string
still carry a valid pointer.** If that representation is general rather than
NilPy-specific, the pass-through becomes safe after all — which is why it is a
measurement and not an assumption.

## The three measurements, in order

1. **Is an empty AnsiString a nil pointer, or a valid pointer to a NUL?** And is
   the answer the same for Pascal and NilPy strings, or did the NilPy fix apply
   only there? This gates everything else.
2. **Do runtime-built strings (concat, `SetLength`, computed) reserve `len+1`
   and store the NUL,** or only literals? Confirmed for literals only so far.
3. Only if 1 and 2 both come back favourable does the copy go away. Otherwise
   `PC()` stays and gets a bounds check plus an answer for the ring depth.

**Most likely outcome, stated so nobody over-reads the section above:** `PC()`
survives, gains a length check with deterministic truncation, and *may* gain a
fast path that passes char data straight through for a non-empty string whose
NUL is guaranteed. The empty case goes through the buffer regardless.
