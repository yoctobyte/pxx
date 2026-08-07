---
prio: 35
type: bug
track: N
summary: "PyParseClass's `only pass is supported as a one-line class body` branch is unreachable — the lexer now normalises every one-line suite, so `class C: x = 1` compiles and matches CPython. The behaviour is BETTER than documented; the comments describing the restraint and calling the def half open are false, and they are what produced a stale five-site patch plan."
status: done
owner: claude-AN
---

# The one-line class body restraint is no longer enforced, and its comments now lie

- **Type:** bug (false comments / dead branch) — **Track N**
- **Filed:** 2026-08-04, from Track A+N overnight work resolving
  [[bug-nilpy-one-line-def-and-class-bodies-do-not-parse]].
- **No behaviour is broken.** Filed because the stale comments here already
  cost one session a wrong plan, and this file's comments are the interface
  between passes.

## Measured (HEAD bd16f4b1c, self-hosted fixedpoint)

```python
class C: x = 1
print(C.x)
class D: pass
d = D()
class E: y = 5
print(E.y)
```

pxx and CPython both print `1` / `5`. No error.

But `compiler/pyparser.inc:18961-18965` still says:

```pascal
if not PyIsIdent('pass') then
  Error('Nil Python: only `pass` is supported as a one-line class body — '
        + 'put the body on its own indented line');
```

That branch cannot be reached for `class`/`def`. `a843c17d4` made the LEXER
synthesise `NEWLINE INDENT` after the header colon whenever real code follows
(`pylexer.inc:1022-1036`), so `CurTok.Kind` at `18961` is always `tkNewline` and
control takes the ordinary indented path — which handles a real body correctly,
as the measurement shows.

## What is actually wrong

Three comment blocks describe a world that no longer exists, and all three
assert that the one-line DEF half is still open — the claim that generated this
ticket's parent's stale five-site plan:

1. `pyparser.inc:18948-18960` — "Only `pass` is accepted, deliberately... which
   is what makes this slice separable from the one-line DEF half of that ticket,
   where two scanners infer 'is this name bound inside a def?' from indent depth
   alone and would harvest a one-line def's locals as module globals." The def
   half shipped 2026-08-03; the harvest was measured NOT to happen (a one-line
   def's local is reported as an ordinary compile-time `undefined variable`, not
   widened to a module global).
2. `pyparser.inc:18832-18843` — `PyRegisterClassFieldsPrepass`'s "decide from
   what FOLLOWS the colon whether there is an indented body at all". Still
   correct as defensive code, but its framing implies the no-INDENT case is
   live. It is not, for `def`/`class`.
3. `pyparser.inc:15640-15642` — `PyParseDefHeader`'s contract should name the
   lexer as the reason `: NEWLINE INDENT` is always present, so the next reader
   does not conclude the header is the bug. Two independent recon agents read
   exactly this and proposed patching it.

## Proposed fix

Comment-only, plus one decision:

- Rewrite the three blocks to say the lexer normalises the inline suite, so
  these branches are unreachable defensive fallbacks for `def`/`class`.
- **Keep the branches.** `18870-18871`'s empty member span is what keeps a class
  SIZED and its VMT emitted, and `18863` records that skipping the call outright
  crashed every construction. Deleting them to "clean up" would re-open
  `a0cf42cb6`.
- Decide what the now-dead `only pass` error should be. It cannot fire today;
  either drop it with a comment saying why, or keep it as an assertion whose
  message says "unreachable — the lexer normalises this" rather than describing
  a restriction users can hit.

## Why prio is low but not zero

Nothing misbehaves, and the accidental outcome (a one-line class body with real
content works, matching CPython) is the outcome we want. The cost is entirely in
the record: this file's comments are load-bearing documentation for a frontend
whose passes communicate through token spans, and a false one here already
produced a 200-line patch plan against already-correct code.

## Gate

`make test-nilpy` + self-host byte-identical. Comment-only changes should be
byte-identical output; if the `only pass` error is removed, add a row to
`test/test_nilpy_one_line_class_body.npy` pinning `class C: x = 1` against
CPython so the accidental capability becomes an intended one.

## 2026-08-07 — DONE

Re-measured first: `class C: x = 1` / `class E: y = 5` compile and match CPython,
so the ticket's finding still holds at HEAD.

All three comment blocks rewritten to describe the world that exists:

1. **`PyParseClass`'s one-line branch** — now says the lexer's synthesised
   `NEWLINE INDENT` makes it unreachable for a body with content, that a
   one-line body with content works and matches CPython, and that the branch is
   KEPT because its empty member span is what keeps a class sized and its VMT
   emitted (`a0cf42cb6`). The false claims — that only `pass` is accepted
   "deliberately", and that the one-line DEF half is still open because
   indent-keyed scanners would harvest a def's locals as module globals — are
   struck, with a note that they are what cost a session a 200-line patch plan.
2. **`PyRegisterClassFieldsPrepass`'s colon scan** — kept (it is real defence
   against the `unresolved forward: G.create` mis-attribution) but reframed:
   the only shape that still arrives without an INDENT is a genuinely empty
   body, and the check is not evidence that content is unsupported.
3. **`PyParseDefHeader`** — given the contract header it lacked, naming the
   lexer as the reason `: NEWLINE INDENT` is always present. That is the exact
   sentence two recon sessions needed and did not find.

### The `only pass` error — decided

Kept as an ASSERTION rather than deleted. It cannot fire today, but the lexer
rule behind that guarantee is load-bearing and undocumented as such elsewhere
(see [[bug-nilpy-def-body-scans-run-on-when-no-indent-is-found]]), so a future
narrowing of it should report itself here rather than silently mis-attribute a
body. Its message no longer describes a restriction users can hit — it says the
lexer normalises this shape and reaching the parser without the INDENT is a bug
to report.

### Test

`test/test_nilpy_one_line_class_body.npy` gained the rows the Gate line asked
for — a one-line class with a field, with a `pass` body used as a real class,
and two on one — pinning the accidental capability as an intended one. The whole
file's output is byte-identical to CPython's; `.expected` regenerated.

`tools/gate.sh quick` GREEN, self-host byte-identical.

## Log
- 2026-08-07 — resolved, commit 1178b04b3.
