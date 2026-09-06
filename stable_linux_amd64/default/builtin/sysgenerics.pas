{ SPDX-License-Identifier: Zlib }
unit sysgenerics;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ THE GENERIC TYPES FPC DECLARES IN ITS **SYSTEM** UNIT, which pxx has no
  lib/rtl/system.pas to hold.

  Today that is exactly one type. The unit exists rather than a compiler-side
  registration because a template is a NAME plus a TOKEN RANGE (Templates[] in
  defs.inc), so registering one without source means synthesising tokens; a
  six-line unit is the same thing spelled in the language, and every mechanism
  that already imports a template from a unit works on it unchanged.

  Pulled AMBIENTLY -- ParseUsesUnitAmbient from ParseProgram's token pre-scan,
  the same door `math`, `builtinwide` and `softfloat` come through -- so a
  program naming TArray with no `uses` at all compiles, which is the whole
  point: FPC's is in System and therefore needs none.

  lib/rtl/sysutils.pas ALSO declares TArray<T> and KEEPS it. That is not an
  oversight and not a duplicate to be tidied away:

    - The pre-scan sees THE PROGRAM'S TOKENS AND NOTHING ELSE (the same scope
      limit builtinwide's note in pasparser_prog.inc records). A UNIT that names
      TArray while the program does not -- rtl-generics' Generics.Collections is
      the live case, `function ToArrayImpl(ACount: SizeInt): TArray<T>` --
      triggers nothing here and would break if SysUtils stopped supplying it.
    - Those two populations are disjoint and the split is structural, not luck:
      rtl-generics code uses generic COLLECTIONS and needs SysUtils anyway, so
      TArray arrives free there; fpc-testsuite files exercise TArray ITSELF and
      carry no more `uses` than the feature requires. Measured 2026-09-06: 7 of
      7 rtl-generics files naming TArray<> use SysUtils, and 0 of 6 testsuite
      files do.

  Two templates of the same name coexist -- verified, both spellings resolve and
  a value from either specialization is the same dynamic array -- because a
  specialization of `array of T` is a STRUCTURAL type, not a minted class, so it
  carries none of the identity trouble a duplicated generic CLASS would.
  bug-a-tarray-is-not-ambient-so-a-unit-that-names-it-without-uses-sysutils-is-refused }

interface

type
  { Spelled the way sysutils spells it, and the spelling is load-bearing: under
    {$MODE PXX} this one declaration serves BOTH consumer spellings -- objfpc's
    `specialize TArray<LongInt>` and Delphi's `TArray<LongInt>`. Writing it as
    `generic TArray<T> = array of T` instead compiles here and then refuses the
    Delphi spelling at the use site with `unknown type: TArray`. }
  TArray<T> = array of T;

implementation

end.
