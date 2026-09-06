{ Both member loops used to end in a bare `else Next;` -- a catch-all that
  discarded ANY token it did not recognise, with no diagnostic. A class body
  containing `42 43 44;`, `+ - * ;` or `'oops';` compiled and ran, and so did a
  record body containing `42 43;`. fpc 3.2.2 refuses all four on the exact line.

  It failed OPEN, which is the part worth a test: an unsupported construct was
  not reported as unsupported, it was dropped, and the type was built as though
  the member had never been written. That is how a property's `default <value>`
  operand disappeared for as long as it did -- `default 16` looked like working
  support for a clause that was never parsed, because the 16 came here.

  THE FIX IS A NARROWING AND THE TWO ALLOW-LISTS DIFFER ON PURPOSE. Censused
  over 2276 files before touching either arm: the class loop fired 6287 times
  (6283 tkSemicolon, 4 tkVar) and the record loop 11 (8 tkVar, 3 tkClass, no
  semicolons at all). So `class` is legal in a record body's skip list and NOT
  in the class body's -- a class body has real arms for class members, so
  `class` arriving at the terminus means one of them failed.

  This file only asserts the REFUSAL. The traffic that must keep working -- the
  `var` and `class var` sections -- is covered by the files the census named,
  test_record_nested_type_section and
  test_nested_pointer_alias_is_scoped_to_its_owner among them, which is why
  they are not duplicated here.
  bug-p-a-class-or-record-body-silently-swallows-any-token-it-does-not-recognise }
program test_a_stray_token_in_a_class_or_record_body_is_refused;
type
  TThing = class
    FX: Integer;
    42 43 44;
  end;
begin
  WriteLn('unreachable: the stray literals above must not compile');
end.
