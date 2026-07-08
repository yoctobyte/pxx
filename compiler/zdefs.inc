{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Zig frontend state (zparser.inc's globals) =====
  Declared here — right after defs.inc, far ahead of the parser includes —
  instead of at the top of zparser.inc, because the impl prescan rejects
  var sections in late-position includes with a spurious "global declared
  later" error (bug-impl-prescan-late-include-var-section, found by the
  Whitespace probe; wparser.inc hit the same wall and parked its state in
  defs.inc). Semantics of each block are documented at the point of use
  in zparser.inc. }

const
  Z_MAX_GENERIC_FNS = 64;

type
  { fn f(comptime T: type, ...) template: name, type-param name, token span }
  TZGenericFunc = record
    Name, ParamName: AnsiString;
    TokStart, TokCnt: Integer;
  end;

var
  { defer / errdefer: per-function stash, replayed at exits }
  ZDeferNode: array[0..31] of Integer;
  ZDeferIsErr: array[0..31] of Boolean;
  ZDeferCount: Integer;

  { optionals ?T: which UClasses are auto-registered __has+__val pairs }
  ZOptCi: array[0..MAX_UCLASS-1] of Boolean;

  { error unions !T: global error-slot symbol + name->code registry +
    which procs return !T }
  ZErrName: array[0..255] of AnsiString;
  ZErrCount: Integer;
  ZErrSlotSym: Integer;
  ZProcErrs: array[0..MAX_PROCS-1] of Boolean;

  { slices: which UClasses are auto-registered __ptr+__len views, and the
    element type each strides by }
  ZSliceCi: array[0..MAX_UCLASS-1] of Boolean;
  ZSliceElemTk: array[0..MAX_UCLASS-1] of TTypeKind;

  { comptime-generics: buffered fn templates }
  ZGenericFns: array[0..Z_MAX_GENERIC_FNS-1] of TZGenericFunc;
  ZGenericFnCount: Integer;
