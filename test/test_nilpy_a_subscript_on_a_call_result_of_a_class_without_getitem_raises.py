# SPDX-License-Identifier: 0BSD
# `mk()[0]` on a class with no __getitem__ printed the instance ADDRESS; the
# named receiver always raised. Expected is CPython 3.
import socket


class P:
    pass


def mk():
    return P()


def sock():
    return socket.socket()


try:
    print(mk()[0])
except TypeError as e:
    print("TypeError:", e)
try:
    print(sock()[0])
except TypeError as e:
    print("TypeError:", e)
p = mk()
try:
    print(p[0])
except TypeError as e:
    print("TypeError:", e)
try:
    mk()[0] = 1
except TypeError as e:
    print("TypeError:", e)
try:
    mk()[0] += 1
except TypeError as e:
    print("TypeError:", e)


class G:
    def __getitem__(self, k):
        return k * 2


def mkg():
    return G()


print(mkg()[21])
