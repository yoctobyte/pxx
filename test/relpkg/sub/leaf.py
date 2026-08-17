# `..` climbs to the PARENT package; `.` stays here. Both spellings appear so
# the test fails if the level is ignored in either direction.
from ..constants import TOP
from .peer import NEAR

VAL = TOP + NEAR
