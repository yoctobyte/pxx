"""The arm the program actually selects: innermost guard, `else` clause.

It is LEXICALLY LAST of the four arms on purpose -- a unit alias is first-wins,
so an arm that is wrongly kept alive beats this one by position and the program
answers the dead module. That is why this fixture asserts a VALUE and not a
compile."""

WHO = "deep-hit"
SYM_DEEP_HIT = "sym-deep-hit"
