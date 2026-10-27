from .ca import A
from .cb import C


def go(o):
    o.r(5, b=7)
    o.r(6, a=8, b=9)
    o.r(7)


def run():
    for o in [A(), C()]:
        go(o)
