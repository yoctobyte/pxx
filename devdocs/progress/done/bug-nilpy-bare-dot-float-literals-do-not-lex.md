---
track: N
prio: 35
type: bug
summary: "`.5` and `5.` do not lex — the shared number scanner requires a digit on BOTH sides of the dot, which is right for Pascal and wrong for Python"
status: done
owner: claude-AN
---

# `.5` and `5.` are not accepted as float literals

- **Type:** bug / missing lexical form (NilPy) — **Track N**, but the fix lands
  in Track A's shared lexer (see below).
- **Found:** 2026-08-02, sweeping literal syntax vs CPython.
- **Loud**: `.5` gives "expected expression", `5.` gives "unexpected token".

```python
print(.5)      # CPython 0.5
print(5.)      # CPython 5.0
```

## Everything else in the literal grammar is CLEAN

Measured in the same sweep, all byte-identical to CPython — worth recording so
nobody re-sweeps this surface:

```python
1_000_000            0x1F  0o17  0b1010        1e3  1E3  1.5e-3
"\x41\x42"           "\101" (octal escape)     r"raw\nnot"
"a" "b"  (implicit concatenation)              len("\0abc") == 4
'''triple'''  and  """triple"""                "\\" "\'" "\""
```

So this ticket is the entire remaining gap in NilPy literal syntax.

## Why it is not a two-line lexer tweak

`compiler/lexer.inc`'s number scanner makes a float only when a `.` is followed
by a digit, and only ever starts on a digit. Both restrictions are **correct for
Pascal** and are load-bearing there:

- `5.` would otherwise swallow the first dot of `5..10` (a subrange) and of
  `5.Field` — sometimes.
- `.5` never starts a token scan at all, because scanning begins on a digit.

And the lexer has **no NilPy awareness whatsoever** — `grep isNilPy
compiler/lexer.inc` returns nothing. So there is no existing flag to gate on;
the fix needs a lexer mode plumbed in first.

That makes this a **Track A change to the shared lexer**, with the Pascal
frontend in the blast radius and the self-host gate behind it, in exchange for
two convenience spellings. The cost/benefit is why it is prio 35 rather than
being fixed on sight.

## If it is taken

1. plumb a NilPy mode flag into the lexer (useful beyond this ticket — the
   lexer currently cannot distinguish the two languages at all)
2. under that flag only: allow a leading `.` when followed by a digit, and a
   trailing `.` when NOT followed by another `.` or an identifier character
3. leave Pascal's scanner byte-identical, and prove it: the self-host fixedpoint
   is exactly the test, since the compiler is Pascal source

The second condition is the subtle one — `5.` must still not eat the dot in
`5..10`, and NilPy has no subranges, so under the flag the only lookahead that
matters is "not another dot".

## Gate

A `.npy` diffed against CPython covering `.5`, `5.`, `.5e3`, `5.e3`, `x[.5]`-ish
contexts and arithmetic on both; plus a `.pas` regression asserting `5..10` and
`5.Field` still lex, and the self-host fixedpoint staying byte-identical.

## Fixed 2026-08-03 — and it was NOT a Track A change

The ticket's core premise was wrong, in the direction that makes this cheap:
**NilPy does not lex through `compiler/lexer.inc` at all.** It has its own
scanner, `compiler/pylexer.inc` (`PyLexAll`, its own number branch around the
`0x`/`0o`/`0b` prefix handling), which is Track N's own file. So there is no
lexer mode to plumb, no Pascal blast radius, and nothing in the shared lexer
was touched — `git diff` on `lexer.inc` is empty.

The premise was checked the expensive way first: the change was written into
`lexer.inc` exactly as this ticket specified, gated on `isNilPy`, and `print(.5)`
STILL failed — which is what pointed at the second scanner. Recorded so the next
person reading "the lexer has no NilPy awareness whatsoever" knows the sentence
is true and irrelevant.

### What landed (pylexer.inc only)

- the number branch now also starts on a `.` followed by a digit, so `.5`
  reaches the existing dot-then-digit float path unchanged;
- `PyTrailingDotFloat(P)` decides whether a dot ending a digit run belongs to
  the number: yes when it terminates the literal (`5.`, `5.)`, `5. * 2`) or
  introduces an exponent (`5.e3`, `5.e-3`), no before an identifier character
  (`5.real` stays an integer and a selector) or another dot.

Pascal's `5..10` and `5.Field` never enter this code, so the subtle lookahead
the ticket worried about costs Pascal nothing.

### Verified

`test/test_nilpy_dot_edge_float_literals.npy` (new, registered in both
`test-nilpy` Makefile sites): `.5`, `5.`, `.25 + 1`, `5. * 2`, `.5e3`, `5.e3`,
`5.e-3`, `-.5`, a list literal, a dict KEY, a default-free float parameter, and
the ordinary `0.5`/`5.0`/`1e3` spellings — all 15 lines byte-identical to
CPython. Separately checked unaffected: f-string format specs (`f"{v:.2f}"`,
`f"{v:8.3f}"`), `%`-formatting, slices, `1_000.`, `0x10`, `//`. The corpus's
`d1.items`-shaped hits (identifier ending in a digit, then a dot) enter the
IDENTIFIER branch and never reach this code.

`tools/gate.sh quick` GREEN (self-host fixedpoint + `--tier quick` + FPC seed
canary).

## Log
- 2026-08-03 — resolved, commit PENDING-COMMIT.
