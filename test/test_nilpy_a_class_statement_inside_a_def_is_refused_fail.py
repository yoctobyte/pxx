# A class statement inside a def is refused by name (it said "expected expression").
# feature-n-a-class-statement-inside-a-def-is-refused
def make():
    class P:
        def __init__(self, v):
            self.v = v
    return P(3)
print(make().v)
