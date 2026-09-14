---
track: B
prio: 35
type: bug
status: resolved
found: 2026-08-31
found-by: frank-user
owner: ""
resolved: 2026-09-14
blocked-by: []
summary: "FIXED 2026-09-14. Both gating measurements came back favourable, so the COPY went and PC() survives as a pass-through: `PC := PChar(s)`. (1) Runtime-built strings DO reserve the NUL -- builtinheap.pas:2386 allocates PXX_HDR_SIZE + newLen + 1 for every managed string, not only for literals; swept 0..4096 x SetLength/concat/Copy, zero failures. (2) An empty AnsiString's handle IS nil, as the owner said -- but PChar() of one routes through PXXPCharOf onto a shared read-only #0 (builtinheap.pas:1076), so the empty string arrives as a pointer to \"\" and never as NULL. That was PC()'s one irreplaceable job and the language already does it. Deleting the ring deletes BOTH filed bugs at once (the 1024-char overflow and the arbitrary four-slot depth) and makes PC() reentrant and thread-safe as a side effect. Owner's ruling honoured exactly: no allocation, no ownership scheme -- deleting a copy introduces neither. Regression test test/test_gtk3_pc_pchar_conversion.pas, wired into test-core, three rows, TWO of them RED against the old ring."
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

## RESOLVED 2026-09-14 — the copy went, `PC()` stayed

The ticket said the first job was the measurement and not the bounds check.
Both measurements were run, and both came back the way that deletes the copy.

### Measurement 2 — runtime strings DO carry the NUL

`compiler/builtin/builtinheap.pas:2386`:

```pascal
need := PXX_HDR_SIZE + newLen + 1;          { +1 = nul terminator }
```

That is the grow/allocate path for **every managed string**, not a literal-only
property. The owner's recollection — *"i sortof do recall us specifying
ansistring as always allocating 1 byte more than the string length, to be
filled by #0, exactly for pchar compatibility"* — is correct and it is general.
The earlier grep of `builtin.pas` that "found nothing" was looking in the wrong
unit.

Measured as well as read, because a single `+1` in the source is one instrument:
lengths **0..4096**, three construction routes (`SetLength`+fill, chunk-by-chunk
concat, `Copy`), `byte[Length(s)]` read back through the handle each time.

| route | lengths swept | not NUL-terminated |
| --- | --- | --- |
| `SetLength` + fill | 0..4096 | **0** |
| concat, one char at a time | 0..4096 | **0** |
| `Copy` | 0..4096 | **0** |

Non-empty strings with a nil handle: **0**.

### Measurement 1 — the empty string is nil, and `PChar()` already answers it

The owner's constraint is real and it is why `PC()` is not deletable outright:

```
empty     : len=0 handle=NIL
literal   : len=5 handle=non-nil byte[len]=0  NUL-TERMINATED
concat    : len=11 handle=non-nil byte[len]=0  NUL-TERMINATED
SetLength : len=7 handle=non-nil byte[len]=0  NUL-TERMINATED
PChar(empty) = non-nil, byte[0]=0
```

The last row is the one that decides it. An empty AnsiString's handle IS nil, so
`@s[1]` really would hand a C callee `NULL` — but `PChar(s)` is not `@s[1]`. The
cast lowers through `PXXPCharOf` (`compiler/ir.inc:11025`), which substitutes a
**shared read-only `#0` byte** (`builtinheap.pas:1076`) for a nil handle. So the
empty string arrives as a valid pointer to `""`, which is exactly the job the
copy was doing, done by the language, with no buffer.

### The fix

```pascal
function PC(const s: AnsiString): Pointer;
begin
  PC := PChar(s);
end;
```

The 4096-byte `CBuf` and `CBufSlot` are gone. This is the *opposite* of
introducing an allocation or an ownership scheme, so the owner's design ruling
of 2026-08-31 is honoured rather than merely worked around. It also picks up the
`-dPXX_SHORTSTRING` prefix-skip and every other thing the centralised conversion
knows, for free — `PC()` was the last straggler outside
`refactor-centralize-managed-string-pchar-conversion`.

### The regression test, and its positive control

`test/test_gtk3_pc_pchar_conversion.pas` (+ `.expected`), wired into `test-core`
beside the other gtk rows. No display, no `gtk_init`: the rows go through
`snprintf`/`strlen`, so they assert the CONVERSION and nothing about GTK.

Run against the **pre-fix unit** (`git show HEAD:lib/pcl/gtk3.pas` into a
scratch `-Fu` root) — two of the three rows are RED, which is what makes them
evidence:

```
MANY FAIL: one,two,three,%s,%s,%s,%s,%s,one
LONG FAIL: strlen=2048
EMPTY ok
```

and at HEAD:

```
MANY ok
LONG ok
EMPTY ok
```

`MANY` is the owner's own statement of the defect — six conversions live across
one call (a `"%s,%s,%s,%s,%s"` format plus five arguments) against a ring four
deep. Note **what** it corrupted: the format string's own slot, so the callee
printed `%s` literally. Single-threaded, no long string, no GTK.

`LONG` is the filed overflow: 4096 chars, `strlen` reads **2048**.

`EMPTY` passes on BOTH sides deliberately. It is not there to catch the bug; it
is there so that nobody can "simplify" `PC()` into `@s[1]` later. It guards the
property that must survive, which is the half of this ticket the owner had to
write in twice.

### What was checked, and what was not

- `lib/pcl/gtk3widgets.pas:1339` (`g_markup_escape_text(PC(AText), -1)`) and
  both `SignalConnect*` are the in-tree callers; all build.
- **17 of 18 `test/gui/*.pas` build.** `test_pcl_tabbar.pas` fails identically
  before and after (an overload with a `ShortString` argument) — pre-existing,
  not this.
- Three of the five gtk3 examples build clean. `mandelbrot_gui.pas` and
  `gl/triangle.pas` fail identically before and after, for unrelated reasons
  (`--threadsafe` and a derived `libgl_c.so` soname respectively).
- `lib/pcl/historic/gtk3.pas` still carries the ring. It is the archived copy
  and was deliberately left alone.
- **No sibling of this pattern exists.** Swept `lib/pcl/` and `lib/rtl/` for a
  file-scope `array[0..N] of Char` used as a conversion buffer: the only other
  hit, `dns_libc.pas:220`, is a routine LOCAL and therefore per-call.
