# counts its own executions in a module both spellings share
from .counter import COUNT
COUNT[0] += 1
X = 5


class K:
    pass
