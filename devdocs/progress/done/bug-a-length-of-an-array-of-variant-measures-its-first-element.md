---
track: A
prio: 10
type: bug
blocked-by: []
status: done
found-by: borg native tier at a69c18a (two NEW-REDs, test_open_array_of_variant and test_a_bracket_argument_reaches_the_same_door_at_every_call_path), via frankuser; bisected by frankH to c65fc287f6
tags: [pascal, variant, length, array, regression, silently-wrong]
summary: "c65fc287f6 taught Length a Variant arm, which measures the string the Variant holds, and keyed it on the node's type kind alone. An array's kind is its element kind, so an open, dynamic or field `array of Variant` also read tyVariant. Length and High of the array then measured element 0's string: 30/1 where 35/7 was right, 33 for 66. The arm now also requires the node not to be a whole array (ASTNodeIsWholeArray) and to have dyn depth 0."
owner: ""
---

# Length of an array of Variant measures its first element

Introduced by c65fc287f6 (fix(A): Length, UpCase and Copy of a Variant work
on the string it holds). Bisected: c65fc287f6^ prints 35 7 9 and c65fc287f6
prints 30 1 9 on test_open_array_of_variant.

The Variant arm in the Length argument lowering (ir.inc) asked
`ASTTk[arg] = tyVariant`. Arrays carry their element kind, so it could not
tell `Length(v)` from `Length(arrOfVariant)`. The same lesson is recorded on
ASTNodeIsWholeArray, for interfaces. The arm now asks that predicate and
NodeDynDepth as well.

test_length_of_an_array_of_variant covers a dynamic, open (from dyn, static
and bracket arguments), field and static array; Copy of an array of Variant;
and the Variant string ops the original commit added. Its expected output is
fpc 3.2.2's, built with cwstring. On c65fc287f6, five of its eight lines are
wrong. It passes on six targets. The fixture from the original commit,
test_length_of_a_variant, still passes, and so does the NilPy row.

The quick gate runs neither borg row, which is how this got past it.
