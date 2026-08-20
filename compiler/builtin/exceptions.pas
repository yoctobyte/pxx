{ SPDX-License-Identifier: Zlib }
{ NAMED exceptions, and the CLASS is named ExceptionBase — neither name is
  arbitrary, and the reasoning is the whole design.

  Two exception hierarchies exist in this compiler and both are right to exist:
  sysutils' `Exception` (a Pascal library's design choice, in a language that
  also offers plain runtime errors) and pylib's `Exception` (a LANGUAGE builtin
  — Python's). They used to be one class wearing two hats, and that cost real
  things: pylib could not add a member sysutils lacked, an `except Exception:`
  needed a bridge in the frontend to catch both trees, and a layout guard had to
  assert `msg` stayed the first field in two files that no rule kept in step.

  So: ONE root here, and each unit declares its OWN class named `Exception`
  descending from it.

      unit sysutils;                     unit pylib;
      uses exceptions;                   uses exceptions;
      type                               type
        Exception = class(ExceptionBase)   Exception = class(ExceptionBase)
          constructor CreateFmt(...);        constructor Create(m: Variant);
        end;                               end;
        EConvertError = class(Exception)   ValueError = class(Exception) end;

  Two classes named `Exception`, siblings under one root. `ClassName` reports
  the DECLARED name, so BOTH answer `Exception` — which is what makes Python's
  `repr(e)` and `type(e).__name__` right without the frontend renaming anything.

  Why not one shared class re-exported under two names? Measured and rejected
  (see feature-a-one-exception-class-in-a-shared-unit): `CreateFmt` cannot merge
  — pylib's does minimal substitution because it must not drag sysutils into
  every .npy, sysutils' calls the real Format and PADS, and FPC parity says the
  padding wins. Siblings let each unit keep its own body with no hook.

  Why is the root NOT named `Exception`? Because then sysutils' descendant could
  not also be `Exception` — two rows, one name, first-match wins, and
  `Exception.CreateFmt` resolves to the root and fails. That was the original
  bug wearing a new hat.

  Anything that must be reachable on a caught exception REGARDLESS of which tree
  it came from belongs HERE, at one offset for every descendant. That is why
  `argsv` is on the root and untyped. }
unit exceptions;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
interface

type
  ExceptionBase = class
  public
    { THE message. A FIELD, not a property, and it must stay one: NilPy's
      `print(e)` reads this storage directly (the frontend synthesises the
      access), so a property over some other field loses the message on the
      read path. Message/FMessage below are VIEWS on it — one storage. }
    msg: AnsiString;
    FHelpContext: Integer;
    { Python's `e.args` payload, declared as the ROOT `TObject` on purpose.

      It cannot be `TPyList`: that type lives in pylib, and this unit is used by
      sysutils, which must not pull pylib into every Pascal program. So the slot
      is untyped here and cast inside pylib, which is the only code that puts
      anything in it.

      It lives on the ROOT rather than on pylib's descendant so that the offset
      is the same for every exception in either tree. A NilPy `except Exception:`
      catches RTL exceptions too, and reading `e.args` on one must find a
      defined slot — it reads nil, which is the honest answer, instead of
      whatever a shorter object has at that address. Eight bytes on every
      exception ever raised, spent deliberately. }
    argsv: TObject;
    constructor Create(const m: AnsiString);
    property FMessage: AnsiString read msg write msg;
    property Message: AnsiString read msg write msg;
    property HelpContext: Integer read FHelpContext write FHelpContext;
  end;

implementation

constructor ExceptionBase.Create(const m: AnsiString);
begin
  msg := m;
  FHelpContext := 0;
  argsv := nil;
end;

end.
