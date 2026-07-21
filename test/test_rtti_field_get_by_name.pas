{ Field get/set by name over ANY field (not just published) — the reflection
  foundation for the exec()/getattr host bridge (feature-rtti-field-reflection).
  Exercises mixed field kinds and the VMT-8 instance->RTTI backlink. }
program test_rtti_field_get_by_name;

uses typinfo;

type
  TInner = record
    a, b: Int64;
  end;

  TThing = class
    Count: Integer;
    Tag: Int64;
    Buddy: TThing;
    Inner: TInner;
  end;

var
  t: TThing;
  cls: PClassRTTI;
  p: Pointer;
  k: Int64;
begin
  t := TThing.Create;
  t.Count := 42;
  t.Tag := 99;
  t.Buddy := t;          { self-reference: a non-nil object field }
  t.Inner.a := 7;
  t.Inner.b := 8;

  cls := GetInstanceRTTI(t);
  if cls = nil then begin writeln('FAIL: no instance RTTI'); halt(1); end;
  writeln('class=', GetClassName(cls));

  { integer field }
  p := GetFieldPtr(t, cls, 'Count', k);
  if p = nil then begin writeln('FAIL: no Count'); halt(1); end;
  writeln('Count=', PInteger(p)^, ' kind=', k);

  { int64 field — read AND write through the reflected pointer }
  p := GetFieldPtr(t, cls, 'Tag', k);
  if p = nil then begin writeln('FAIL: no Tag'); halt(1); end;
  writeln('Tag=', PInt64(p)^, ' kind=', k);
  PInt64(p)^ := 123;
  writeln('Tag(after set)=', t.Tag);

  { object field — the reflected pointer holds the instance pointer }
  p := GetFieldPtr(t, cls, 'Buddy', k);
  if p = nil then begin writeln('FAIL: no Buddy'); halt(1); end;
  if PPointer(p)^ = Pointer(t) then writeln('Buddy=self kind=', k)
  else writeln('FAIL: Buddy not self');

  { record field — reflected pointer addresses the embedded aggregate }
  p := GetFieldPtr(t, cls, 'Inner', k);
  if p = nil then begin writeln('FAIL: no Inner'); halt(1); end;
  writeln('Inner.a=', PInt64(p)^, ' kind=', k);

  { a name that does not exist -> nil }
  p := GetFieldPtr(t, cls, 'Nope', k);
  if p = nil then writeln('absent=ok') else writeln('FAIL: found phantom field');

  writeln('DONE');
end.
