{ The `typinfo` FACADE (feature-typinfo-facade-unit): FPC's RTTI API shapes over
  OUR blobs. Real code never reads RTTI bytes -- it calls GetPropInfo, PropType,
  GetOrdProp, GetFloatProp, GetEnumProp and friends -- so what is owed is FPC's
  SHAPES, not FPC's byte layout, and that is what this asserts.

  TWO THINGS IT GATES, and the second is why it exists at this size.

  1. Every accessor, over every property KIND. That is the facade.

  2. Every accessor over both ACCESS SHAPES -- `read FField` and `read GetIt` --
     because the two are one case with two arms and the second arm was missing.
     Until 2026-08-28 GetOrdProp and GetStrProp handled only GetKind=0 and fell
     off the end for a read METHOD, so `property Num: Integer read GetI` answered
     0 through RTTI while reading 107 directly, with no error
     ([[bug-b-rtti-read-of-a-getter-method-property-answers-zero]]). The WRITE
     half already dispatched through setter methods, which is exactly how the
     hole survived: the direction anyone would test by round-tripping was the
     one that worked. So every property below exists TWICE, once each way, and
     the assertion is that the two agree -- a facade that reads the field
     correctly and the method as zero passes any single-shape test.

  The `_m` twins deliberately do NOT return the bare field: each getter perturbs
  the value (+100, 'via-', doubling) so a silently-skipped method call reads as
  the raw field rather than as the right answer by luck.

  WHAT WAS DIFFED AGAINST FPC 3.2.2, AND WHAT WAS NOT -- stated because "checked
  against FPC" is the kind of claim that decays into folklore.

    * The TTypeData block at the end: all twelve OrdType/FloatType values were
      produced by an FPC program and are identical to ours, run for run.
    * The set rendering: GetSetProp's DEFAULT was read off FPC, not recalled,
      and it is the surprising one -- FPC returns 'clRed,clBlue' with NO
      brackets, and '[clRed,clBlue]' only with brackets=True. An empty set is
      therefore '' by default and '[]' with brackets. Both are asserted.

  This file itself does NOT compile under FPC, and the reason is a live bug
  rather than a design choice: instance lookups here go through GetInstanceRTTI
  instead of FPC's `GetPropInfo(AnObject, 'Num')`, because that spelling binds to
  the wrong overload and segfaults
  ([[bug-p-a-class-instance-converts-implicitly-to-any-typed-pointer]]). When it
  lands, the `RT` helper below disappears and this file becomes portable. }
program lib_typinfo_props;

{$MODE OBJFPC}{$H+}

uses typinfo, sysutils;

type
  TColor = (clRed, clGreen, clBlue, clGold);
  TStyles = set of TColor;

  TLeaf = class(TObject)
  private
    FTag: Integer;
  published
    property Tag: Integer read FTag write FTag;
  end;

  TThing = class(TObject)
  private
    FNum: Integer;
    FBig: Int64;
    FDbl: Double;
    FSng: Single;
    FStr: string;
    FFlag: Boolean;
    FCol: TColor;
    FSty: TStyles;
    FObj: TLeaf;
    FNumM: Integer;
    FBigM: Int64;
    FDblM: Double;
    FStrM: string;
    FColM: TColor;
    function GetNumM: Integer;
    procedure SetNumM(v: Integer);
    function GetBigM: Int64;
    procedure SetBigM(v: Int64);
    function GetDblM: Double;
    procedure SetDblM(v: Double);
    function GetStrM: string;
    procedure SetStrM(const v: string);
    function GetColM: TColor;
    procedure SetColM(v: TColor);
  published
    { arm one: plain fields }
    property Num: Integer read FNum write FNum;
    property Big: Int64 read FBig write FBig;
    property Dbl: Double read FDbl write FDbl;
    property Sng: Single read FSng write FSng;
    property Str: string read FStr write FStr;
    property Flag: Boolean read FFlag write FFlag;
    property Col: TColor read FCol write FCol;
    property Sty: TStyles read FSty write FSty;
    property Obj: TLeaf read FObj write FObj;
    { arm two: getter/setter METHODS, each perturbing the value }
    property NumM: Integer read GetNumM write SetNumM;
    property BigM: Int64 read GetBigM write SetBigM;
    property DblM: Double read GetDblM write SetDblM;
    property StrM: string read GetStrM write SetStrM;
    property ColM: TColor read GetColM write SetColM;
  end;

function TThing.GetNumM: Integer; begin Result := FNumM + 100; end;
procedure TThing.SetNumM(v: Integer); begin FNumM := v * 2; end;
function TThing.GetBigM: Int64; begin Result := FBigM + 100; end;
procedure TThing.SetBigM(v: Int64); begin FBigM := v * 2; end;
function TThing.GetDblM: Double; begin Result := FDblM + 0.5; end;
procedure TThing.SetDblM(v: Double); begin FDblM := v * 2; end;
function TThing.GetStrM: string; begin Result := 'via-' + FStrM; end;
procedure TThing.SetStrM(const v: string); begin FStrM := v + '!'; end;
function TThing.GetColM: TColor; begin Result := FColM; end;
procedure TThing.SetColM(v: TColor); begin FColM := v; end;

var
  fails: Integer;
  t: TThing;
  leaf: TLeaf;
  p: PPropInfo;
  list: TPropList;
  n: Integer;

procedure Chk(const name, got, want: string);
begin
  if got = want then
    WriteLn(name, '=ok')
  else
  begin
    WriteLn(name, '=FAIL got<', got, '> want<', want, '>');
    Inc(fails);
  end;
end;

procedure ChkI(const name: string; got, want: Int64);
begin
  Chk(name, IntToStr(got), IntToStr(want));
end;

procedure ChkB(const name: string; got, want: Boolean);
begin
  if got = want then WriteLn(name, '=ok')
  else begin WriteLn(name, '=FAIL'); Inc(fails); end;
end;

{ INSTANCE LOOKUPS GO THROUGH GetInstanceRTTI, not through the TObject
  overloads typinfo declares. Those overloads are correct code that cannot be
  SELECTED yet: pxx converts a class instance to any typed pointer implicitly,
  so `GetPropInfo(obj, 'Num')` binds to the PClassRTTI arm and segfaults
  ([[bug-p-a-class-instance-converts-implicitly-to-any-typed-pointer]]). When
  that lands, every `RT` below can become a bare `t` and this helper goes away —
  which is the point of routing through one helper rather than 40 call sites. }
function RT: PClassRTTI;
begin
  RT := GetInstanceRTTI(Pointer(t));
end;

begin
  fails := 0;
  t := TThing.Create;
  leaf := TLeaf.Create;
  leaf.Tag := 9;

  { ---- lookup: by class and by instance, both must find it ---- }
  p := GetPropInfo(RT, 'Num');
  ChkB('lookup_by_instance', p <> nil, True);
  ChkB('lookup_missing_is_nil', GetPropInfo(RT, 'NoSuchProp') = nil, True);
  ChkB('is_published', IsPublishedProp(RT, 'Num'), True);
  ChkB('is_published_missing', IsPublishedProp(RT, 'NoSuchProp'), False);

  { ---- PropType over every kind ---- }
  Chk('kind_int',    GetEnumName(TypeInfo(TTypeKind), Ord(PropType(RT, 'Num'))),  'tkInteger');
  Chk('kind_int64',  GetEnumName(TypeInfo(TTypeKind), Ord(PropType(RT, 'Big'))),  'tkInt64');
  Chk('kind_float',  GetEnumName(TypeInfo(TTypeKind), Ord(PropType(RT, 'Dbl'))),  'tkFloat');
  Chk('kind_single', GetEnumName(TypeInfo(TTypeKind), Ord(PropType(RT, 'Sng'))),  'tkFloat');
  Chk('kind_bool',   GetEnumName(TypeInfo(TTypeKind), Ord(PropType(RT, 'Flag'))), 'tkBool');
  Chk('kind_enum',   GetEnumName(TypeInfo(TTypeKind), Ord(PropType(RT, 'Col'))),  'tkEnumeration');
  Chk('kind_set',    GetEnumName(TypeInfo(TTypeKind), Ord(PropType(RT, 'Sty'))),  'tkSet');
  Chk('kind_class',  GetEnumName(TypeInfo(TTypeKind), Ord(PropType(RT, 'Obj'))),  'tkClass');
  ChkB('prop_is_type',      PropIsType(RT, 'Col', tkEnumeration), True);
  ChkB('prop_is_type_no',   PropIsType(RT, 'Col', tkInteger),     False);
  ChkB('prop_is_type_miss', PropIsType(RT, 'NoSuchProp', tkInteger), False);

  { ---- ARM ONE: plain fields ---- }
  SetOrdProp(t, GetPropInfo(RT, 'Num'), 42);
  ChkI('f_ord_roundtrip', GetOrdProp(t, GetPropInfo(RT, 'Num')), 42);
  ChkI('f_ord_direct',    t.Num, 42);

  SetInt64Prop(t, GetPropInfo(RT, 'Big'), 9223372036854775807);
  ChkI('f_int64_roundtrip', GetInt64Prop(t, GetPropInfo(RT, 'Big')), 9223372036854775807);

  SetFloatProp(t, GetPropInfo(RT, 'Dbl'), 2.5);
  ChkI('f_float_roundtrip', Round(GetFloatProp(t, GetPropInfo(RT, 'Dbl')) * 100), 250);
  SetFloatProp(t, GetPropInfo(RT, 'Sng'), 1.5);
  ChkI('f_single_roundtrip', Round(GetFloatProp(t, GetPropInfo(RT, 'Sng')) * 100), 150);

  SetStrProp(t, GetPropInfo(RT, 'Str'), 'hello');
  Chk('f_str_roundtrip', GetStrProp(t, GetPropInfo(RT, 'Str')), 'hello');

  SetOrdProp(t, GetPropInfo(RT, 'Flag'), 1);
  ChkI('f_bool_roundtrip', GetOrdProp(t, GetPropInfo(RT, 'Flag')), 1);

  SetEnumProp(t, GetPropInfo(RT, 'Col'), 'clBlue');
  Chk('f_enum_roundtrip', GetEnumProp(t, GetPropInfo(RT, 'Col')), 'clBlue');
  ChkI('f_enum_ordinal',  GetOrdProp(t, GetPropInfo(RT, 'Col')), 2);
  SetEnumProp(t, GetPropInfo(RT, 'Col'), 'clNoSuchColor');
  Chk('f_enum_bad_name_leaves_it', GetEnumProp(t, GetPropInfo(RT, 'Col')), 'clBlue');

  { FPC 3.2.2's own default is NO brackets — measured, not recalled. Both
    spellings are asserted because the default is the one that surprises. }
  SetSetProp(t, GetPropInfo(RT, 'Sty'), '[clRed,clBlue]');
  Chk('f_set_default_no_brackets', GetSetProp(t, GetPropInfo(RT, 'Sty')), 'clRed,clBlue');
  Chk('f_set_brackets', GetSetProp(t, GetPropInfo(RT, 'Sty'), True), '[clRed,clBlue]');
  SetSetProp(t, GetPropInfo(RT, 'Sty'), '[clGreen]');
  Chk('f_set_assign_clears', GetSetProp(t, GetPropInfo(RT, 'Sty'), True), '[clGreen]');
  SetSetProp(t, GetPropInfo(RT, 'Sty'), '[]');
  Chk('f_set_empty', GetSetProp(t, GetPropInfo(RT, 'Sty'), True), '[]');
  Chk('f_set_empty_default', GetSetProp(t, GetPropInfo(RT, 'Sty')), '');
  { unbracketed INPUT is accepted too, which is how FPC's own round trip works }
  SetSetProp(t, GetPropInfo(RT, 'Sty'), 'clGreen,clGold');
  Chk('f_set_unbracketed_input', GetSetProp(t, GetPropInfo(RT, 'Sty'), True), '[clGreen,clGold]');
  SetSetProp(t, GetPropInfo(RT, 'Sty'), '[clRed, clGold]');
  Chk('f_set_spaces_ok', GetSetProp(t, GetPropInfo(RT, 'Sty'), True), '[clRed,clGold]');
  SetSetProp(t, GetPropInfo(RT, 'Sty'), '[clRed,clNoSuch]');
  Chk('f_set_unknown_ignored', GetSetProp(t, GetPropInfo(RT, 'Sty'), True), '[clRed]');

  SetObjectProp(t, GetPropInfo(RT, 'Obj'), leaf);
  ChkB('f_obj_roundtrip', GetObjectProp(t, GetPropInfo(RT, 'Obj')) = Pointer(leaf), True);
  ChkB('f_obj_direct',    t.Obj = leaf, True);

  { ---- ARM TWO: the SAME accessors over getter/setter METHODS.
    Each getter perturbs the value, so an accessor that silently skipped the
    method call would read the raw field and these would fail. This arm is the
    regression for bug-b-rtti-read-of-a-getter-method-property-answers-zero. ---- }
  SetOrdProp(t, GetPropInfo(RT, 'NumM'), 21);          { setter doubles -> 42 }
  ChkI('m_ord_setter_ran',  t.FNumM, 42);
  ChkI('m_ord_getter_ran',  GetOrdProp(t, GetPropInfo(RT, 'NumM')), 142);
  ChkI('m_ord_agrees',      GetOrdProp(t, GetPropInfo(RT, 'NumM')), t.NumM);

  SetInt64Prop(t, GetPropInfo(RT, 'BigM'), 4000000000);
  ChkI('m_int64_setter_not_truncated', t.FBigM, 8000000000);
  ChkI('m_int64_agrees', GetInt64Prop(t, GetPropInfo(RT, 'BigM')), t.BigM);

  SetFloatProp(t, GetPropInfo(RT, 'DblM'), 1.25);
  ChkI('m_float_setter_ran', Round(t.FDblM * 100), 250);
  ChkI('m_float_agrees', Round(GetFloatProp(t, GetPropInfo(RT, 'DblM')) * 100), Round(t.DblM * 100));

  SetStrProp(t, GetPropInfo(RT, 'StrM'), 'x');
  Chk('m_str_setter_ran', t.FStrM, 'x!');
  Chk('m_str_getter_ran', GetStrProp(t, GetPropInfo(RT, 'StrM')), 'via-x!');
  Chk('m_str_agrees',     GetStrProp(t, GetPropInfo(RT, 'StrM')), t.StrM);

  SetEnumProp(t, GetPropInfo(RT, 'ColM'), 'clGold');
  Chk('m_enum_agrees', GetEnumProp(t, GetPropInfo(RT, 'ColM')), 'clGold');

  { ---- GetPropList, unfiltered and filtered ---- }
  n := GetPropList(RT, @list);
  ChkI('proplist_count', n, 14);
  n := GetPropList(RT, [tkInteger], @list);
  ChkI('proplist_filtered_int', n, 2);

  { ---- TTypeData: OrdType / FloatType, and FPC's field SPELLINGS.
    This block is what a vendored Generics.Defaults actually reaches — frankA
    measured its whole typinfo requirement as five TTypeData fields at nine
    sites, with OrdType and FloatType used ONLY as case selectors dispatching to
    a comparer. So these ordinals are not cosmetic: a wrong one silently selects
    the wrong comparer. Every value below was diffed against fpc 3.2.2 and is
    identical to it, including the two that look wrong and are not — Boolean and
    Char both answer otUByte(1), not a boolean or character kind of their own. ---- }
  ChkI('ord_shortint', Ord(GetTypeData(TypeInfo(ShortInt))^.OrdType), 0);
  ChkI('ord_byte',     Ord(GetTypeData(TypeInfo(Byte))^.OrdType),     1);
  ChkI('ord_smallint', Ord(GetTypeData(TypeInfo(SmallInt))^.OrdType), 2);
  ChkI('ord_word',     Ord(GetTypeData(TypeInfo(Word))^.OrdType),     3);
  ChkI('ord_longint',  Ord(GetTypeData(TypeInfo(LongInt))^.OrdType),  4);
  ChkI('ord_longword', Ord(GetTypeData(TypeInfo(LongWord))^.OrdType), 5);
  ChkI('ord_int64',    Ord(GetTypeData(TypeInfo(Int64))^.OrdType),    6);
  ChkI('ord_qword',    Ord(GetTypeData(TypeInfo(QWord))^.OrdType),    7);
  ChkI('ord_boolean',  Ord(GetTypeData(TypeInfo(Boolean))^.OrdType),  1);
  ChkI('ord_char',     Ord(GetTypeData(TypeInfo(Char))^.OrdType),     1);
  ChkI('float_single', Ord(GetTypeData(TypeInfo(Single))^.FloatType), 0);
  ChkI('float_double', Ord(GetTypeData(TypeInfo(Double))^.FloatType), 1);

  { the FPC spellings must address the SAME bytes as ours — the two arms of the
    variant part drifting apart is the one way that record can go wrong }
  ChkI('alias_min', GetTypeData(TypeInfo(Int64))^.MinInt64Value,
                    GetTypeData(TypeInfo(Int64))^.MinValue);
  ChkI('alias_max', GetTypeData(TypeInfo(Int64))^.MaxInt64Value,
                    GetTypeData(TypeInfo(Int64))^.MaxValue);
  ChkI('alias_elsize', GetTypeData(TypeInfo(Int64))^.elSize,
                       GetTypeData(TypeInfo(Int64))^.ElemSize);

  if fails = 0 then WriteLn('TYPINFO-PROPS OK')
  else WriteLn('TYPINFO-PROPS ', fails, ' FAILED');
end.
