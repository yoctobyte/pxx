typedef long myint;
typedef unsigned long mysize;
typedef struct _Opaque Opaque;

myint twice(myint x);
mysize passsize(mysize n, Opaque *handle);

myint twice(myint x) {
    return x + x;
}
mysize passsize(mysize n, Opaque *handle) {
    return n;
}
