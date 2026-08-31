struct Pair { int a; int b; };
int take_pair(struct Pair p) { return p.a * 100 + p.b; }
struct Pair make_pair(int a, int b) { struct Pair p; p.a = a; p.b = b; return p; }
