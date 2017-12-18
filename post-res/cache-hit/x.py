#!/usr/bin/env python
# coding: utf-8


# 228 39 1.38 0.0353846 avg fsize: 1.52MB fcnt: 149 million
# 385 43 1.60 0.0372093 avg fsize: 1.39MB fcnt: 278 million
# 391 30 1.27 0.0423333

# total fcnt: 370 billion
# total fsize: 556 PB
# uncached:


# solve (149000000^(x+1)-1)/(1-0.0353846) = (278000000^(x+1)-1)/(1-0.0372093)


# https://www.wolframalpha.com/input/?i=solve+(149000000%5E(x%2B1)-1)%2F(1-0.0353846)+%3D+(278000000%5E(x%2B1)-1)%2F(1-0.0372093)

# a = -1.00304
# a+1 = -0.00304


a = -1.00304
n = 370*1024**3
fsize = 1.5*1024**2

a1 = a+1
N = n**a1-1

s1=149*1024**2
s2=278*1024**2
b1 = 628*1024**2 / 8
# PB
cached = 9.36 * 1024**5
cachedfcnt = cached / fsize

bcnt1 = b1/fsize
def get_b(s):
    S = s**a1-1
    b = 1-S/N
    return b

def not_cached_fn(s):
    S = s**a1-1
    return N-S


S1 = s1**a1
c= bcnt1/(n**a1-S1) * a1

print cachedfcnt

nocache_acc = (n**a1-cachedfcnt**a1) * c/a1
# per second
print nocache_acc



