---
slug: bug-a-xtensa-cannot-widen-a-forward-jump-so-the-compiler-still-will-not-build
track: A+S
prio: 55
type: bug
status: new
found: 2026-08-31
found-by: frankA
owner: ""
blocked-by: []
summary: "The BACKWARD half of the J reach wall is closed (a jump to an already-placed label widens to a long jump automatically, at zero cost to anything in range). A FORWARD one cannot be: EmitXtensaJumpToLabel reserves three bytes before the label exists, so the fixup can only refuse. Measured on the compiler itself: `the forward jump at code offset 4040104 cannot reach its label at 4231481` -- 187 KB against J's 128 KB. This is the LAST wall between xtensa and building the compiler; the other five cross targets already do."
---

# An xtensa forward jump over 128 KiB still cannot be built

Sibling of [[bug-a-xtensa-cannot-widen-a-forward-call-so-a-big-image-still-refuses-to-build]]
— same asymmetry, one level down: that one is CALL0's 512 KiB, this is J's 128 KiB.

## Measured

```
$ compiler/pascal26 --target=xtensa --platform=posix compiler/compiler.pas /tmp/out
pascal26:2922: error: target xtensa: the forward jump at code offset 4040104
  cannot reach its label at 4231481 (J reaches +-128 KiB). A BACKWARD jump this
  far is widened automatically; a forward one cannot be, because the three-byte
  slot was sized before the label existed
```

Reached only after the frame wall
([[bug-a-xtensa-frame-larger-than-32kb-needs-more-than-one-addmi]]) and the
backward half of this one were cleared, so it is what xtensa hits **next**.

## Why the backward half was free and this one is not

A backward jump knows its target when it is emitted, so `EmitXtensaJumpToCode`
picks the form there: everything in range still emits the same three bytes and
only an out-of-reach jump pays ~26. A forward jump reserved three bytes before
the label existed. Widening it means reserving the long form's ~26 bytes at
**every forward jump in every xtensa program** — every `if`, `while` exit and
`case` arm — which is a large size cost on the target where size matters most.
riscv32 took exactly that trade in
[[bug-a-riscv32-cannot-reach-a-far-call-so-the-compiler-will-not-link]] because
there it is 4 bytes against 8. Here it is 3 against 26, and that is the whole
difference.

## The two candidate fixes, neither yet measured

- **Relaxation.** Emit the body, and if any forward fixup is out of range,
  rewind and re-emit with wide slots for those labels only. Free for every
  program that does not need it; the work is that the body's emission also
  appends to `CallFix`, `DynCall`, `IramCallFix` and the relocation lists, so a
  rewind has to restore those counters as well as `CodeLen`. This is the
  standard assembler answer and is probably the right one.
- **A veneer pool.** Patch the 3-byte slot to a short `j` to a long jump
  appended after the body. Cheap, and **does not work here**: the veneer would
  sit past the label, ≥187 KB from the slot, so it is out of J's reach too. Ruled
  out by the same number that reports the bug.

## Not to be confused with

The 3-byte slot is not the only xtensa-specific hazard here: `XtensaAlignCode4`
pads code to 4 and these slots are multiples of 3, so changing a reservation
moves the padding of everything after it (frankS, from the frame work). The
self-host fixedpoint does not see it — the compiler still builds. The cross
differential rows do.

## Gate

`pascal26 --target=xtensa --platform=posix compiler/compiler.pas` must produce an
artifact, plus `make test-xtensa` (every branch in the target goes through the
changed sequence) and the size cost measured with
`tools/count_bytes.py` / `--emit-obj` + `readelf -S`, not the page-quantised
`code=` line.
