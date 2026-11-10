# `cls.species(it)` inside a @classmethod reaches the class's own @staticmethod
# even when another class declares a static of the same name (two carriers
# made the run-time arm give up: "'type' object has no attribute"). Expected = python3.
# bug-n-a-staticmethod-called-through-cls-raises-attributeerror
class Chart:
    @staticmethod
    def species(it):
        return "chart"


class Plot:
    @classmethod
    def bucket(cls, items):
        out = ""
        for it in items:
            out = out + cls.species(it) + " "
        return out

    @staticmethod
    def species(it):
        return "tree" + str(it)


print(Plot.bucket([1, 2]))
class Solo:
    @classmethod
    def go(cls, n):
        return cls.twice(n) + cls.thrice(n)
    @staticmethod
    def twice(n):
        return n * 2
    @classmethod
    def thrice(cls, n):
        return n * 3
print(Solo.go(5))
