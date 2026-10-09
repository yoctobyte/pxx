# A relative, parenthesised import WITH `as` -- PyParseOneImport took no
# parens and failed with "expected ]/} before as".
from .ephem import (Ephem as Eph,
    epoch as ep)
