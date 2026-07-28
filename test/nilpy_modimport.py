# A module whose FIRST line is an import: the pre-scan used to skip it (its
# "start of file" test assumed token 0), so the unit was compiled from the body
# parse instead — in the middle of accumulating this module's own statements,
# whose AST nodes a Pascal unit's compile then recycled.
import re

ALL = ['C', 'D']
PAT = re.compile(r'\d+')


def digits(s):
    return PAT.findall(s)
