---
slug: bug-a-xtensa-variant-record-arms-start-at-different-offsets
track: A
prio: 45
type: bug
status: new
created: 2026-09-18
found-by: frankH
owner: ""
summary: "On xtensa the arms of a record's variant part do not share a start offset: `record Tag: Integer; case Integer of 0: (A: Int64); 1: (L, H: Integer); end` puts A at 8 and L at 4, so writing one arm and reading the other returns the wrong bytes -- the variant record's whole point. x86-64 (8/8) and i386 (4/4) are consistent. Measured 2026-09-18 with HEAD 316bbefd65cd, reading @r.A - @r and @r.L - @r under --platform=posix. Probable mechanism, NOT verified: the arm-start alignment and the Int64 field placement consult different alignment answers on xtensa (Int64 is 8-aligned in field placement there -- see the same record's size 16 vs i386's 12)."
---

# xtensa variant-record arms start at different offsets

```pascal
program VO;
type TVar = record Tag: Integer; case Integer of 0: (A: Int64); 1: (L, H: Integer); end;
var r: TVar;
begin
  WriteLn('A@', PtrUInt(@r.A) - PtrUInt(@r), ' L@', PtrUInt(@r.L) - PtrUInt(@r), ' size=', SizeOf(r));
end.
```

| target | output |
| --- | --- |
| x86-64 | `A@8 L@8 size=16` |
| i386 | `A@4 L@4 size=12` |
| **xtensa** (`--platform=posix --xtensa-soft-mulhigh`) | **`A@8 L@4 size=16`** |

Every arm of a variant part must begin at the same offset. On xtensa, a value
stored through `A` and read through `L`/`H` (or the reverse) reads the wrong
bytes. Programs overlay variant arms on purpose, so this produces wrong values.

Found while differentially checking typed-const record baking
(bug-a-a-typed-const-record-is-built-by-startup-code-not-stored-as-data): the
baked image was right and matched the layout table. The layout table itself is
what differs.

Test to add with the fix: assert the RELATION `@r.A = @r.L` rather than a
per-target offset, so the row carries no expected width.
