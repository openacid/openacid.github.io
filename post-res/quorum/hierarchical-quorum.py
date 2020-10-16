#!/usr/bin/env python
# coding: utf-8

def factorial(n):
    if n == 0:
        return 1
    return n*factorial(n-1)

def c(m, n):
    return factorial(m) / factorial(n) / factorial(m-n)

def failure_rate(p, n):

    total = 0
    for i in range(n//2+1, n+1):
        fi = c(n, i) * (p**i) * ((1-p)**(n-i))
        total += fi

    return total


p = 0.01

print("failure-rate:")

fm3 = failure_rate(p, 3)
print("  majority of 3 nodes:        {:.2e}".format(fm3))

fm7 = failure_rate(p, 7)
print("  majority of 7 nodes:        {:.2e}".format(fm7))

fm9 = failure_rate(p, 9)
print("  majority of 9 nodes:        {:.2e}".format(fm9))

f3x3 = failure_rate(fm3, 3) # 3x3
print("  hierarchical quorum of 3x3: {:.2e}".format(f3x3))
