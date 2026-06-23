# bug: const section before constructor/destructor not terminated

- **Type:** bug (compiler / parser)
- **Status:** backlog
- **Track:** A (compiler)
- **Reported-by:** Track B (apps/ide/eliah designer.pas)
- **Opened:** 2026-06-23

## Symptom

A `const` (or presumably `var`/`type`) section in a unit **implementation**,
followed directly by a `constructor`/`destructor` method body, is misparsed: the
const-section loop does not treat `constructor` as a terminator, so it reads
`constructor` as the next const NAME and then expects `=`:

```
Expected: =, but got: TC (Kind: 1, Line: 11)
pascal26:11: error: unexpected token ()
```

`procedure`/`function` after the same const section parse fine — so the
section-terminator keyword set is missing `constructor` (and almost certainly
`destructor`, `class procedure`, `class function`, `operator`).

## Minimal repro

`u_ctor.pas`:
```pascal
unit u_ctor;
interface
type
  TC = class
    V: Integer;
    constructor Create;
  end;
implementation
const
  K = 7;
constructor TC.Create;   { <-- misparsed as a const name }
begin
  V := K;
end;
end.
```
`p_ctor.pas`: `program p_ctor; uses u_ctor; var c: TC; begin c := TC.Create; writeln(c.V); end.`

```
PXX -Fu<dir> -Fulib/rtl p_ctor.pas /tmp/p_ctor   # fails
```

Control (swap `constructor` for a plain `procedure`) compiles OK.

## Expected

`const`/`var`/`type` sections in implementation terminate on `constructor` and
`destructor` (and class methods / operator) exactly as they do on
`procedure`/`function`.

## Impact / Track B note

Blocks the natural arrangement (private render-constants in the implementation
section) in `apps/ide/eliah/designer.pas`. Track B moved those consts to the
interface section as a temporary, reversible placement (flagged in-file) to keep
M1 moving — revert to implementation consts once this lands.

## Log
- 2026-06-23 — filed from M1 designer work, with minimal repro.
