# a subpackage importing ANOTHER subpackage -- the pervasive corpus shape
from mypkg.core.bus import Bus


class Node:
    def __init__(self, tag):
        self.tag = tag
        self.bus = Bus()

    def emit(self):
        return self.bus.send(self.tag)
