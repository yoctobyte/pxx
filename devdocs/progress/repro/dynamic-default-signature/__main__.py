from .early import Sampler
from .late import Grid


def main():
    s = Sampler(Grid())
    print("C1 cross-module, name shared with a pylib container ->", s.march(1, 2))
    print("C2 cross-module, unique name                        ->", s.march_named(1, 2))


main()
