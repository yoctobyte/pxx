---
slug: bug-p-a-resourcestring-is-not-addressable
track: P
prio: 55
type: bug
status: backlog
blocked-by: []
summary: "`@SomeResourceString` is `error: undefined variable` — pxx parses a `resourcestring` section as a plain const section (pasparser_proc.inc:4783), and a const has no address. FPC makes resourcestrings addressable (they are runtime-replaceable variables), which is what `Exception.CreateRes(@SArgumentOutOfRange)` — the Delphi/FPC idiom, 3 sites in generics.defaults.pas — depends on."
---

# A `resourcestring` is not addressable

- **Track P** (Pascal frontend — `resourcestring` handling).
- Found 2026-08-28 by frankB while implementing
  [[feature-sysutils-delphi-exception-api-gaps-found-by-rtl-generics]].
  Measured against pin **v389** (`325b4479070a`).

## Repro

```pascal
program rs;
resourcestring
  SFoo = 'out of range';
var p: ^string;
begin
  p := @SFoo;          { pxx: error: undefined variable (SFoo)   fpc: fine }
  WriteLn(p^);
end.
```

## The boundary, measured — only resourcestring differs

| declaration | pxx `@` | fpc `@` |
| --- | --- | --- |
| `resourcestring SFoo = 'x'` | **error** | works |
| `const SFoo = 'x'` (untyped) | error | error |
| `const SFoo: string = 'x'` (typed) | works | works |
| `var SFoo: string = 'x'` | works | works |

Three of the four rows already agree, including the untyped-const row where
BOTH refuse — so this is not general laxness about addressing constants, and
the fix is not "let `@` take a const". It is one row.

## Cause

`compiler/pasparser_proc.inc:4783` routes a `resourcestring` section straight
into `ParseConstSection`, with the comment "`resourcestring` sections (FPC
rtlconsts et al) register as plain [consts]". That was the right call for
*reading* one — `WriteLn(SFoo)` works — and it is what makes vendored units
carrying `resourcestring` blocks compile at all. It only falls short where the
address is taken.

In FPC a resourcestring is not a constant: it is a runtime-replaceable variable,
which is the whole point of the construct (a translation layer rewrites it at
startup). That is why `@` works there and why the Delphi RTL idiom is built on
it.

## Why it matters

`Exception.CreateRes(ResString: PString)` is the Delphi/FPC resource-string
constructor, and every call site spells its argument `@SSomeResourceString`:

```pascal
raise EArgumentOutOfRangeException.CreateRes(@SArgumentOutOfRange);
```

Three such sites in `generics.defaults.pas` (many more in
`generics.collections`). `CreateRes` itself is Track B's and is implemented —
it takes a `PString`, dereferences it, and constructs. **The library side is
done; the call sites cannot be written until this lands.** No workaround was
added: the platonic spelling is the FPC one, and reshaping the consumer is not
available anyway since it is vendored.

## Fix sketch

Give a `resourcestring` section's entries storage — a typed string variable
initialised to the literal — rather than folding them as constants. Reading is
unchanged; `@` then works for free, and a future translation hook has somewhere
to write. The `ParseConstSection(-1, 0)` call is where the two paths currently
merge.

## Gate

The repro above prints `out of range`; the other three rows of the table are
unchanged (in particular an untyped `const` must STILL refuse `@`); `make test`
+ self-host fixedpoint.
