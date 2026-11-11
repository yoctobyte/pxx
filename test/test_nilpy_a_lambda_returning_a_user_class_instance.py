# bug-n-a-lambda-returning-a-user-class-instance-yields-none
class V3:
    def __init__(self, x=0.0):
        self.x = x

    def __repr__(self):
        return "V3(%.2f)" % self.x


def call(fn):
    return fn()


def d_obj():
    return v


v = V3(7.0)
f_obj = lambda: v
f_new = lambda: V3(9.0)
f_num = lambda: 22.0
f_str = lambda: "hello"
f_lst = lambda: [1, 2]

print("L1 lambda -> obj, called direct  ->", f_obj())
print("L2 lambda -> obj, through param  ->", call(f_obj))
print("L3 lambda -> new obj, thru param ->", call(f_new))
print("L4 lambda -> float, thru param   ->", call(f_num))
print("L5 lambda -> str, thru param     ->", call(f_str))
print("L6 lambda -> list, thru param    ->", call(f_lst))
print("L7 def    -> obj, thru param     ->", call(d_obj))
print("L8 inline lambda, thru param     ->", call(lambda: v))
