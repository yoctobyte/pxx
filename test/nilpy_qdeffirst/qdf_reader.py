import qdf_defs
class Holder:
    def __init__(self, details):
        self.details = details
    def fittings(self):
        t = self.details()
        return (t[0], t[1])
def three():
    return Holder(details=qdf_defs.r_three)
def tot():
    f = qdf_defs.total
    return f([1, 2, 3])
def run():
    f = qdf_defs.g
    print(f(4))
    h = qdf_defs.gs
    print(h("a"))
    k = qdf_defs.gl2
    print(k([1, 2, 3]))
