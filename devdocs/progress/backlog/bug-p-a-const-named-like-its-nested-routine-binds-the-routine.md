---
summary: "a local const whose name matches its own NESTED routine resolves to the routine's mangled name — `procedure Inner; const inner: integer = 0;` fails with `undefined variable (Inner$13)`"
type: bug
prio: 30
track: P
---

# A const named like its own nested routine binds the routine

- **Type:** bug (name resolution — Track P, shared `parser.inc`/`symtab.inc`).
- **Status:** backlog. **Pre-existing** — reproduces identically on the pinned
  binary, so it is not fallout from the static-local-const work that found it.
- **Found:** 2026-08-16, writing the regression test for
  [[bug-p-a-routine-local-typed-const-is-reinitialised-on-every-call]]; the test
  named its inner const after the routine holding it and hit this instead.

## Repro

```pascal
program nst3;
procedure Outer;
const outer: integer = 100;
  procedure Inner;
  const inner: integer = 0;                { same name as the routine }
  begin Inc(inner); write('i', inner, ' '); end;
begin Inc(outer); write('o', outer, ' '); Inner; Inner; end;
begin Outer; Outer; writeln; end.
```

```
pascal26:6: error: undefined variable (Inner$13)
```

FPC compiles and runs it: `o101 i1 i2 o102 i3 i4`.

## Boundary (measured)

| shape | result |
| --- | --- |
| const `inner` inside nested `Inner` | **fails** — binds `Inner$13` |
| const `icount` inside nested `Inner` | ok, matches FPC |
| const `foo` inside NON-nested `Foo` | ok |
| local `var` of the same name inside a nested routine | untested — **check this first** |

So it is specific to a **nested** routine: the mangled name (`Inner$13`) is what
the const's name resolves to, meaning the nested routine's own registration wins
over a const declared inside it. The non-nested case is fine, which says the
mangling — not the shadowing rule in general — is where the two names meet.

## Before closing

Grep the sibling shapes, because a resolution rule fixed on one arm here is
famously still broken on the others
([[project_pascal_name_resolution_has_six_tables]] is the tally): a local `var`
of the same name, a `type`, and a parameter. If they take different paths, that
is the second path that stays broken.

## Gate

The repro above matching `fpc -O- -Mobjfpc` byte for byte, plus whichever
sibling shapes the grep turns up; `gate.sh quick`; self-host fixedpoint.
