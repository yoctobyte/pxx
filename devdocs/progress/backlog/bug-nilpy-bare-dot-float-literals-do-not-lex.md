---
track: N
prio: 35
type: bug
summary: "`.5` and `5.` do not lex — the shared number scanner requires a digit on BOTH sides of the dot, which is right for Pascal and wrong for Python"
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
