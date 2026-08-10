---
summary: "`Slot(i)^ := v` compiles clean and stores NOTHING — a call result used as an assignment TARGET is dropped. Reading `Slot(i)^` is fine, and so is `t := Slot(i); t^ := v`, so only one arm of the double case is broken. Silent wrong value, no diagnostic."
type: bug
track: A
prio: 60
found-by: claude-B
status: done
owner: claude-A
---

# Assignment through a pointer returned by a function call is silently dropped

- **Type:** bug (silent wrong value) — Track A (codegen / assignment lvalue)
- **Opened:** 2026-08-10
- **Found by:** Track B, writing crtl's `atexit`
  ([[feature-b-crtl-last-seven-unimplemented-declarations]]). The handler table
  stored every entry as 0 and the drain jumped to address 0.

## Repro

```pascal
program p4;
type PInt32 = ^Integer;
var buf: array[0..7] of Integer;
    base: Pointer;
function Slot(i: Integer): PInt32;
begin
  Slot := PInt32(NativeInt(base) + i * SizeOf(Integer));
end;
var t: PInt32;
begin
  base := @buf[0];
  Slot(0)^ := 111;                        { A: write through a call result }
  WriteLn('A buf[0]=', buf[0]);
  t := Slot(1); t^ := 222;                { B: via a variable }
  WriteLn('B buf[1]=', buf[1]);
  buf[2] := 333;
  WriteLn('C read through call result=', Slot(2)^);
end.
```

x86-64, `stable_linux_amd64/default/pinned` at v256:

```
A buf[0]=0            <- WRONG, expected 111
B buf[1]=222          <- ok
C read through call result=333   <- ok
```

FPC prints `A buf[0]=111`. No warning, no error — the store just does not happen.

## The boundary, measured

Three shapes over the same pointer; only the first is broken, which is the
`normalise-dont-special-case` smell exactly — one concept (deref an expression of
pointer type), and the *write* path has a case the *read* path does not.

| shape | result |
| --- | --- |
| `f(i)^ := v` — call result as assignment target | **silently no-op** |
| `f(i)^` in an expression — call result as read source | correct |
| `PCast(expr)^ := v` — cast expression as target | correct |
| `t := f(i); t^ := v` | correct |

So it is not "pointer arithmetic" and not "deref of a temporary" in general: the
read path handles the identical temporary. It is specifically **AN_CALL as the
base of a deref in lvalue position**. Worth checking the sibling shapes before
closing: `f(i)^.field := v`, `f(i)^[j] := v`, and a call result of a
pointer-to-record — 496396a2a ("indexing a call result dropped the .field
selector") was the same family on the read side, which suggests the lvalue path
has its own copy of that gap rather than sharing the fix.

## Why it rates a 60

It is the expensive kind: no crash at the mistake, a plausible wrong value far
away. In the crtl case the effect was a null jump three call frames later, and
the first hypothesis was a bad heap pointer — `PXXRealloc` was probed and cleared
before the store itself was suspected. Any code building a table through an
accessor helper hits this, and helpers like that are exactly what you write when
an array is variable-length.

## Track B's workaround, to be reverted when this closes

`lib/rtl/pxxcio.pas` inlines the slot-address cast at both use sites instead of
going through an `AtExitSlot(i)` helper, with a comment naming this ticket
(`devdocs/dev/track-b-workarounds.md` lifecycle). Restore the helper here when
this is fixed — it is the readable form.

## Log
- 2026-08-10 — resolved, commit PENDING-COMMIT.

## Resolution (2026-08-10)

Root cause was **parse-time, not codegen**: `ParseStatementAST`'s
call-result-selector branch (added by `bug-pascal-statement-call-result-selector`,
test `_b318`) recognised only `.` as the selector that makes a statement-leading
function call the *base* of a designator. With `^` and `[` it never fired, so the
bare `AN_CALL` was emitted and `^ := 111` fell into the default branch that skips
to the next `;` — no diagnostic, no store. `PXXDBG=a.ast` shows it directly: the
statement's whole AST is one `AN_CALL`, with no `AN_ASSIGN` anywhere.

That is why the read path was fine (the *expression* parser always handled the
full chain) and why `t := f(i); t^ := v` was fine — the double case's two arms
were a parser branch apart, exactly the `normalise-dont-special-case` shape the
ticket predicted.

Fix: `frDot` now tests `Tokens[...].Kind in [tkDot, tkCaret, tkLBrack]` at both
sites (bare callee, and after the matching `)`). All three sibling shapes the
ticket asked about — `f(i)^ := v`, `f(i)^.field := v`, `f(i)^[j] := v` — pass in
one change, plus `Slot(3)^ := Slot(0)^ + 1` with a call result on both sides.

Test `test/test_stmt_call_result_deref_b387.pas`, wired into `make test`,
byte-matched against FPC. Gate: `tools/gate.sh quick` GREEN (self-host
fixedpoint + testmgr quick).

**Track B follow-up (not done here — B owns the file):** `lib/rtl/pxxcio.pas`
still inlines the slot-address cast at both `atexit` sites instead of using an
`AtExitSlot(i)` helper. That workaround can now be reverted; see
`devdocs/dev/track-b-workarounds.md`.
