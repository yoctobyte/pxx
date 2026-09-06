---
slug: decide-where-the-string-delete-and-insert-routines-should-live
track: U
prio: 35
type: decide
status: backlog
created: 2026-09-06
found-by: frankD
owner: ""
blocked-by: []
summary: "lib/rtl/sysutils.pas declares `Delete(var s: AnsiString; index, count)` and `Insert(const src: AnsiString; var dst: AnsiString; index)` -- two routines fpc keeps in `system` and not in sysutils -- and both bodies are byte-for-byte what the __pxxStrDelete/__pxxStrInsert intrinsic already does. Their only effect is to shadow the intrinsic, which cost dyn-array Delete/Insert for every program that uses sysutils (fixed narrowly at f5ad23c32; the non-bare spellings are still closed). Deleting them removes the cause at the source -- but the builtin unit is not compiled for ESP, so on ESP the string spelling would go from working to `Delete: string helper unavailable`. The fork is which of those two costs we keep, and it needs a Track B/S reader, not a P one."
---

# Where should the string Delete and Insert live?

- **Track U** (decision). Files if it goes ahead: `lib/rtl/sysutils.pas`,
  possibly `compiler/builtin/builtin.pas` and whatever ESP builds instead.
- Found closing the fcl-passrc rung-7 wall at `pscanner.pp:5025` / `:5033`.
  **Recorded as a decide row and not left inside the P ticket** because a fork
  written into a P ticket is read by whoever picks up the P ticket, which is by
  construction not a B or S seat (frank-coordinator's point, and it is right).

## The fork

`lib/rtl/sysutils.pas:782` and `:786` declare, and `:3624` / `:3633` define:

```pascal
procedure Delete(var s: AnsiString; index, count: Integer);
procedure Insert(const src: AnsiString; var dst: AnsiString; index: Integer);
```

fpc's sysutils declares neither — they are `system` intrinsics there. Ours are
line-for-line the behaviour of `__pxxStrDelete` / `__pxxStrInsert` in
`compiler/builtin/builtin.pas:2166` / `:2173`: same clamping, same no-op cases.
Compared 2026-09-06; the only textual difference is `__pxxStrInsert` lacking an
`if src = '' then Exit` fast path, which changes no result.

So on a hosted target they are pure duplication whose ONLY observable effect is
to shadow the intrinsic.

**Option A — delete them from sysutils.**
- Removes the whole defect class at the source: `Delete(obj.Items, i, 1)` and
  every other non-bare dyn-array spelling start working with no parser change,
  and the fourteen other `SoftIntrinsicOpen` call sites lose one shadow each.
- **Breaks ESP.** `TargetIsEspClass` blocks the automatic `uses builtin`
  (`compiler/pasparser_prog.inc:1517`), so `FindProc('__pxxStrDelete') < 0` and
  the intrinsic's own arm raises `Delete: string helper unavailable (needs the
  builtin unit; not on ESP)`. A working string spelling becomes a compile
  error on xtensa and riscv32.
- Unmeasured: whether any ESP-target source in this tree actually calls
  `Delete`/`Insert` on a string. **That measurement would collapse the fork**
  and is the first thing to do if this is picked up.

**Option B — keep them, keep narrowing the parser.**
- What f5ad23c32 did. Costs a token probe per intrinsic and leaves the
  non-bare spellings closed
  ([[bug-p-a-shadowed-soft-intrinsic-is-closed-without-consulting-the-arguments]]).

**Option C — make the ESP build carry the two helpers.**
- Whatever ESP uses in place of the builtin unit grows `__pxxStrDelete` /
  `__pxxStrInsert`, then Option A applies with no ESP cost. This is the one
  that needs an S reader: I do not know what the ESP-side equivalent is or
  whether adding to it is cheap.

## Recommendation

**C if the ESP side is cheap, else A gated on the measurement** (does any
ESP-target source call string `Delete`/`Insert`?). B is what ships today and is
correct; it is only the more expensive place to keep paying.

Note the same question exists in miniature for `Copy`, `UpCase` and `Pos`,
which sysutils also re-declares. Those were probed 2026-09-06 and do NOT
diverge — dyn-array `Copy(a)`, `Copy(a,i,n)` and `Concat(a,a)` all match fpc
with sysutils in scope, because they resolve on a different path in the
expression parser. Same duplication, no observable cost, so they are not part
of this fork; they would only come along for tidiness.
