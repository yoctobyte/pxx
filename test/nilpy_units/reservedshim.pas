{ The SHIM half of bug-n-a-module-member-named-like-a-pascal-keyword-is-
  uncallable, and the population that bug's fix could have broken.

  Pascal cannot declare a constant called END or a routine called SET, so a
  library that has to expose those Python attribute names declares END_ and
  set_, and PyMapReservedMember maps the application's spelling onto them. That
  convention had NO test anywhere when the fix landed -- the fix narrowed the
  mapping to fire only when the underscored spelling really exists in the target
  unit, and nothing in the suite would have noticed it being narrowed to never.

  So this unit exists to be reached by its UNDERSCORED names through their PLAIN
  spellings. Do not add a plainly-spelled sibling: that is the other test's job
  and it would make this one pass for the wrong reason. }
unit reservedshim;

interface

const
  END_  = 'shim-end';
  TEXT_ = 'shim-text';

function set_(x: Integer): Integer;
function type_(x: Integer): Integer;

implementation

function set_(x: Integer): Integer;
begin
  set_ := x * 10 + 1;
end;

function type_(x: Integer): Integer;
begin
  type_ := x * 10 + 2;
end;

end.
