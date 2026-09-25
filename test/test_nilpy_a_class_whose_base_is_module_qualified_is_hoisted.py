# The base is spelled `mod.Root`: the class header sweep resolves the
# qualified name so Base is hoisted, and a late-bound self.hook() in Base
# reaches Sub's definition.
import nilpy_qualbase_mod
class Base(nilpy_qualbase_mod.Root):
    def go(self):
        self.hook()
        return self.ident()
class Sub(Base):
    def hook(self):
        print("hook root", self.x)
s = Sub()
print(s.go())
print(isinstance(s, nilpy_qualbase_mod.Root))
