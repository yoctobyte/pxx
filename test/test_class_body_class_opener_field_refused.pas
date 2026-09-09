program test_class_body_class_opener_field_refused;
{ `class <name>: <type>;` in a class body. This COMPILED until the class-body
  `class` opener landed, and it compiled as a plain INSTANCE field: no arm
  matched, so the member loop's terminus stepped over the `class` and the
  field parser took what was left. The class-ness was discarded silently --
  one shared slot per class became one slot per instance, and nothing said so.

  Kept as a fixture rather than deleted because the harm is INVISIBLE: a
  revert of the opener does not crash here, it produces a working program with
  the wrong storage model. Only a row that demands the REFUSAL can see that.
  bug-p-the-class-body-class-opener-is-a-hand-maintained-lookahead-list }
type
  TC = class
    class wibble: LongInt;
  end;
begin
end.
