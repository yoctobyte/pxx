# bug: case-insensitivity incomplete — builtins + function calls still case-sensitive

- **Type:** bug (Track A — parser / symbol resolution)
- **Status:** backlog
- **Found:** 2026-06-23, differential probe vs FPC (Track B)
- **Severity:** medium-high (breaks mixed-case FPC source broadly)
- **Relation:** continues `bug-keywords-case-sensitive` (DONE 7d5b18d) and
  `bug-builtin-write-case-sensitive` (DONE 3de5d05) — those fixed keywords and
  Write/Read/WriteLn/ReadLn; the rest of the builtins and all unit-function
  calls were not converted.

## Symptom

pascal26 is meant to be case-insensitive for user code (defs.inc "standard
case-insensitive Pascal"); variables and type names already are
(`Foo`/`foo`/`FOO` resolve, `INTEGER` works). But two classes of identifier
still match case-sensitively:

### 1. Builtin intrinsics other than Write/Read

```pascal
var s: string; begin s := 'hi'; writeln(Length(s)); end.   { ok: 2 }
var s: string; begin s := 'hi'; writeln(LENGTH(s)); end.   { error: undefined variable }
```

Likely affects `SetLength`, `High`, `Low`, `Inc`, `Dec`, `Copy`, `Ord`, `Chr`,
`Trunc`, `Round`, … — matched by hardcoded exact-case string compares rather
than `CaseEqual`. Concrete locus, e.g. `compiler/parser.inc:6973`:

```
else if (name = 'SetLength') or (name = 'setlength') then   { only two spellings }
```

so `SETLENGTH` / `SetLENGTH` fall through.

### 2. Unit / RTL function calls

```pascal
uses sysutils; begin writeln(IntToStr(123)); end.   { ok: 123 }
uses sysutils; begin writeln(inttostr(123)); end.   { error: no overload of inttostr matches }
```

Same for `UpperCase` / `LowerCase` / `Trim` / `StrToInt` (sysutils) and `Sqrt` /
`Min` / `Max` / `Power` (math): the exact-case spelling resolves, any other case
fails. Unit function symbols are looked up case-sensitively even though local
variables are not.

(Probed with `-Fulib/rtl` and the proper-case control passing, so this is name
resolution, not a missing unit/function.)

## Expected

All identifier resolution — builtins, unit functions, methods — uses the same
case-insensitive matcher as variables (respecting `{$CASESENSITIVE ON}`, under
which the compiler's own source still matches exactly for byte-identical
self-host). Route the builtin string compares through `CaseEqual` and make
imported-symbol lookup case-insensitive.

## Repro / regression

`tools/fpc_diff_probe.sh` — proper-case probes pass, mixed-case fail. Keyword
mixed-case (`BEGIN`) also still fails against the pinned v38 (that fix, 7d5b18d,
post-dates the pin → also wants a re-pin, see `chore-repin-new-intrinsics`).
