# `class Site` beside `def site()` — Python's commonest naming convention, and
# two different names because Python is case-sensitive. Our class lookup is not.
from dataclasses import dataclass


@dataclass
class Site:
    key: str
    lat: float


SITES = {"a": Site("a", 1.0)}


def site(key: str) -> Site:
    return SITES[key]


class Box:
    def __init__(self, n: int):
        self.n = n
