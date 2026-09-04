program test_rtti_reg;

type
  TBase = class
  published
    procedure Notify;
  end;

  TChild = class(TBase)
  published
    procedure Callback;
  end;

procedure TBase.Notify; begin end;
procedure TChild.Callback; begin end;

type
  { RTTI names are frozen, WORD-length-prefixed blobs (rtti_emit.inc points
    NamePtr at Strs[].Offset, and the interned-literal pool keeps its 8-byte
    NativeInt prefix). Under the managed-string default a name pointer must be a
    FROZEN string pointer to read the inline [len][chars] correctly — `^string`
    would treat the length word as a managed handle and crash.

    THE CAP IS 256 AND IT IS A KIND SELECTOR, NOT A LENGTH. `string[N]` for
    N <= 255 is tyShortString (one length byte, the FPC ABI); only N > 255 can
    be tyFixedString, because a byte cannot count past 255. The type is never
    instantiated — only `^TRttiStr` exists — so the number bounds nothing and
    names a layout. This mirrors lib/rtl/typinfo.pas, which says the same thing
    at greater length; the copy lives here because giving this test a `uses
    typinfo` would put typinfo's own published classes into the registry and
    change the Count line, which is the thing the test exists to watch.

    IT SAID 255 UNTIL 2026-09-04 AND THAT IS HOW IT BROKE. `string[255]` sat
    exactly on the boundary, so when phase 4 of the shortstring work re-typed
    N <= 255 to tyShortString this declaration silently started claiming a
    byte prefix over a word-prefixed blob. typinfo.pas was moved to 256 ahead
    of that commit for precisely this reason and predicted the symptom; this
    second copy was not moved with it, and no instrument connects the two.
    The failure was masked for a further day by a deref that dropped the kind
    entirely and fell back to the 8-byte reading — so the day THAT was fixed
    (a50671107), an unrelated-looking commit turned this test red. Do not
    "tidy" the 256 back to 255. }
  TRttiStr = string[256];   { COPY-OF lib/rtl/typinfo.pas TRttiStr }
  PString = ^TRttiStr;
  TRTTIEntry = record
    NamePtr: PString;
    RTTIPtr: Pointer;
  end;
  PRTTIEntry = ^TRTTIEntry;

  TRegistry = record
    Count: Int64;
    Dummy: TRTTIEntry;
  end;
  PRegistry = ^TRegistry;

var
  reg: PRegistry;
  entries: PRTTIEntry;
  i: Integer;
begin
  reg := __rttireg();
  if reg = nil then
  begin
    writeln('no RTTI registry found');
    Halt(1);
  end;

  { THE GUARD THAT WOULD HAVE CAUGHT THIS AS ITSELF. Above, the cap is prose;
    here it is an assertion. A byte-prefixed TRttiStr reads the length's LOW
    BYTE, which is correct for every name shorter than 256, then takes the
    chars from the prefix's own zero bytes -- so the names come out empty or
    truncated while the count stays right, and nothing says "wrong kind".
    SizeOf is the one place the kind is visible before any blob is read. }
  if SizeOf(TRttiStr) <> 264 then
  begin
    writeln('TRttiStr is not the word-prefixed kind: SizeOf=', SizeOf(TRttiStr),
            ' (want 264 = 8-byte length word + 256 chars). ',
            'string[N<=255] is tyShortString and CANNOT read an RTTI name.');
    Halt(1);
  end;

  writeln('Count: ', reg^.Count);
  
  { entries start immediately after Count }
  entries := @reg^.Dummy;

  for i := 0 to Integer(reg^.Count) - 1 do
  begin
    writeln('Class ', i, ': ', entries[i].NamePtr^);
  end;
end.
