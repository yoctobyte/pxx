# Bug: `case ... else <stmt1>; <stmt2>; ... end` (multi-statement else, no begin/end) fails to parse

- **Type:** bug — Track A (compiler internals, parser)
- **Status:** backlog
- **Opened:** 2026-07-01
- **Found by:** building the `-S` x86-64 disassembler (feature-asm-textual-emit-mode
  task #7) — `compiler/asmdisasm_x64.inc` self-compiled cleanly under FPC but
  failed to self-host (`pascal26` compiling `compiler.pas`) with a confusing
  `Expected: end, but got: Result` / `unexpected token ()` error, reported at
  a line that (after mapping the flattened line count back to source) turned
  out to be a `case` statement's closing `end;` — nowhere near where the real
  problem was.

## Repro (minimal, isolated)

```pascal
program ReproFFGroup2;
function Foo(x: Integer; var text: AnsiString): Integer;
begin
  case x of
    0: text := 'a';
    1: begin text := 'b'; Result := 1; Exit; end;
  else
    text := 'c'; Result := 4; Exit;
  end;
  Result := 5;
end;
var t: AnsiString;
begin
  writeln(Foo(0, t), ' ', t);
end.
```

Fails: `Expected: end, but got: Result` — the parser reads `text := 'c';` as
*the entire* else-branch (treating it like a normal `label: single-statement;`
case arm), then expects `end` immediately and chokes on the second statement
(`Result := 4;`). Standard Pascal (and FPC) treats a `case` statement's
`else` clause as taking an implicit statement *list* running up to `end`
(the same convention as a `try...except...end`'s exception-handler list, or
a bare `begin...end` block) — this compiler's parser apparently only reads
one statement after `else` before expecting `end`.

**Fix once wrapped in `begin...end`:**

```pascal
  else
  begin
    text := 'c'; Result := 4; Exit;
  end;
```

compiles and runs correctly (`Result=5`, i.e. control fell through — wait,
in the real repro the else branch's `Exit` fires and returns 4; confirmed
via the isolated test in the finding session).

## Impact

Silent nothing at first — it's a hard parse error, so any code hitting this
shape simply fails to compile, which is at least loud (unlike the sibling
open-array stack-copy bug filed alongside this one). The confusing part is
diagnostic quality: the reported error line/token give essentially no hint
that the real issue is an *earlier* unwrapped multi-statement `else` — a
future person hitting this will likely burn real time bisecting, as this
session did, unless they know to look for this specific pattern.

## Suggested fix

`case` statement parsing (`ParseStatementAST`'s `tkCase` handler or
equivalent, `compiler/parser.inc`) needs its `else`-clause parsing to consume
a statement *list* (repeatedly parse statements until it sees `end`), not a
single statement — matching every other implicit-statement-list context in
the language (`try/except`, `try/finally`, the top-level `begin...end` of a
routine body, etc.). Also worth a better diagnostic: if the parser is
*at* `end`-or-statement-list ambiguity inside a `case`, an error mentioning
"case else" specifically (not just a generic "expected end") would have
saved real debugging time here.

## Workaround used

Wrapped the one production instance of this pattern in `begin...end`
(`compiler/asmdisasm_x64.inc`'s FF-opcode-group decoder, the `case
mrm.RegField and 7 of ... else ... end;` block). Audited every other `case`
statement in the same new file for the same shape (grep for bare `else`
lines, checked each one's following statement count) — this was the only
instance. Not otherwise blocking; `case...else` with a single statement (the
overwhelmingly common case) is unaffected.

## Also worth checking while in there

- Is this specific to `else` inside `case`, or does a *bare `case`-label*
  arm (`label: stmt1; stmt2;` with no `begin/end`) have the same issue? Not
  observed in this session's repro attempts (every multi-statement case-label
  arm already used explicit `begin...end` in the code that triggered this),
  so unconfirmed either way — worth a quick isolated test.
- A `grep -rn "^\s*else\s*$" compiler/*.pas lib/**/*.pas` sweep, cross-checked
  for "is this else inside a case, and does its body have >1 statement before
  end/another case label" to gauge exposure elsewhere in the existing
  codebase (none found in a quick manual pass during this session, but a
  scripted sweep would be more thorough).
