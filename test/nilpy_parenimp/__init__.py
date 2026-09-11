# The PARENTHESISED relative from-import, which is what a package with more
# submodules than fit on one line writes. The bare form is exercised by
# nilpy_relpkg; this one bound NOTHING AND SAID NOTHING before 2026-09-11,
# because PyParseImportRun's name loop is `while CurTok.Kind = tkIdent` and a
# '(' matched no arm at all.
#
# A trailing comma is included deliberately: it is legal inside the brackets and
# leaves the parser on ')' rather than on an identifier, which is the one place
# an off-by-one in the new arm would show.
from . import (one, two,
               three, four,)


def joined():
    return one.VALUE + "-" + two.VALUE + "-" + three.VALUE + "-" + four.VALUE
