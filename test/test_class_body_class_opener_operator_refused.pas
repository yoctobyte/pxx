program test_class_body_class_opener_operator_refused;
{ `class operator` is real Delphi/FPC and pxx implements it for RECORD types
  only -- ParseRecordFields has an arm that parses the signature and discards
  it; the class-body member loop has none.

  It gets its own message rather than the opener's list, because the list
  would read as "you mistyped" and the writer did not: they wrote a construct
  we do not support. Pin v407 refuses it too, as `expected ':' before <name>`
  -- the silent-absorption symptom, the `class` stepped over and `operator`
  read as a field name -- so this is a better message for the same refusal,
  never a narrowing.
  bug-p-the-class-body-class-opener-is-a-hand-maintained-lookahead-list }
type
  TC = class
    class operator Initialize(var a: TC);
  end;
begin
end.
