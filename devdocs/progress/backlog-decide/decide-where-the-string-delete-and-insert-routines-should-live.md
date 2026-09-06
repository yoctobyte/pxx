---
slug: decide-where-the-string-delete-and-insert-routines-should-live
track: U
prio: 35
type: decide
status: resolved
created: 2026-09-06
found-by: frankD
owner: "frankH"
blocked-by: []
summary: "lib/rtl/sysutils.pas declares `Delete(var s: AnsiString; index, count)` and `Insert(const src: AnsiString; var dst: AnsiString; index)` -- two routines fpc keeps in `system` and not in sysutils -- and both bodies are byte-for-byte what the __pxxStrDelete/__pxxStrInsert intrinsic already does. Their only effect is to shadow the intrinsic, which cost dyn-array Delete/Insert for every program that uses sysutils (narrowed at f5ad23c32). RESOLVED SAME DAY AND THERE WAS NO FORK: the ESP cost I declined to trade against does not exist. frankH measured it at HEAD -- on the bare ESP profile `uses sysutils` does not compile AT ALL (sysutils drags lib/rtl/strings.pas, whose UpCase needs the same builtin unit), so nothing on ESP can reach these declarations, and the posix ESP profile HAS the builtin unit so the intrinsic works there. Removal owned by frankH."
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

## RESOLVED 2026-09-06 — the fork was not a fork

frankH measured the premise instead of reasoning about it, and it is FALSE at
HEAD. `compiler/pascal26`, `--target=xtensa --esp-profile=bare`:

```
uses sysutils; begin end.        -> UpCase: builtin helper unavailable
                                    (needs the builtin unit; not on ESP)
                                    in lib/rtl/strings.pas:146
Delete(s, 1, 6);  (no sysutils)  -> Delete: string helper unavailable
```

The first line is the discriminator: sysutils drags `lib/rtl/strings.pas`,
whose `UpCase` needs the same builtin unit, so **`uses sysutils` fails on bare
ESP before it can offer anybody a `Delete`.** Removing the declarations moves
bare ESP from "cannot compile `uses sysutils`" to "cannot compile `uses
sysutils`". The other ESP profile (`--platform=posix`) HAS the builtin unit, so
the intrinsic works there and the declaration carries nothing;
`EspBareBoot` is the sole exclusion in `pasparser_prog.inc`, so those two
profiles are the whole ESP population.

**What I got wrong, stated plainly, because the shape is reusable.** Declining
the placement half inside a P bug fix was right — it is a B/S trade and I would
have guessed the S half. Writing down the CONSEQUENCE as though it were
established was not. `TargetIsEspClass` blocks the builtin unit, therefore the
string spelling breaks on ESP: every step of that is true and the conclusion is
still false, because it never asks whether anything on ESP can reach the
declaration in the first place. **A cost inherited from a code path is not a
cost until something reaches that path**, and the reaching is the cheap half to
measure — two compiles. I reasoned about the consequence and routed the
reasoning; the measurement collapsed it in under an hour.

Third instance of the same cause, which is what settles that it is the
placement and not the predicate: `pasparser_expr.inc:5045` and
`pyparser.inc:47148` both carry a comment about `TStrings.SetValueFromIndex`'s
bare `Delete(Index)` binding `sysutils.Delete`, which broke `lib/rtl/classes.pas`
under NilPy while it compiled clean under Pascal
(`bug-a-the-import-escape-hatch-fails-on-classes-pas`), and `classes.pas:805`
and `:910` still carry `Self.` with the comment *"Delete is also a builtin"* —
workarounds for this declaration.

Option A, taken by frankH. The parser narrowing at f5ad23c32 stays and is
independent: it fixes the bare-name spelling for any USER-declared shadow,
which removing our own declaration does not address.
