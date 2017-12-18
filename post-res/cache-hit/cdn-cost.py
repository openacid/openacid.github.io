#!/usr/bin/env python
# coding: utf-8

import math

# ugcbsy.qq.com     space: 5.39M      num: 1
# lmbsy.qq.com      space: 728.7T     num: 29.5M
# ltsbsy.qq.com     space: 970.2T     num: 43.0M
#
# total: 1698 TB / 72.5 million files
# cdn:   9 server/cluster: serve 188 TB/server, 8.0 million/server
# cdn:   x TB * 70% * 10 drives
#       4T: 28TB / N.O. file: 8.0 / 188 * 28 = 1.19 million
#       6T: 42TB / N.O. file: 8.0 / 188 * 42 = 1.78 million
#

# 2018 Mar 05 12:00 - 15:00 的数据
#
# lt-heilongjiang-mudanjiang-1-221-206-136-14 2T 133.9 / 1785 = 7.50%
# lt-heilongjiang-mudanjiang-1-221-206-136-13 3T  84.8 / 1752 = 4.84%
# lt-heilongjiang-mudanjiang-1-221-206-136-15 4T  73.9 / 1714 = 4.31%
# lt-heilongjiang-mudanjiang-1-221-206-136-16 4T  75.2 / 1731 = 4.34%
# lt-heilongjiang-mudanjiang-1-221-206-136-17 5T  66.7 / 1644 = 4.06%
# lt-heilongjiang-mudanjiang-1-221-206-136-18 6T  63.4 / 1680 = 3.77%
# lt-heilongjiang-mudanjiang-1-221-206-136-19 6T  66.8 / 1726 = 3.87%
# lt-heilongjiang-mudanjiang-1-221-206-136-21 6T  66.0 / 1714 = 3.85%
# lt-heilongjiang-mudanjiang-1-221-206-136-22 6T  63.3 / 1700 = 3.72%

backratio = {
        # '4t': 4.33*0.01, # s1
        # '6t': 3.70*0.01, # s2
        # another setup:
        '4t': 6.21*0.01, # s1
        '6t': 5.00*0.01, # s2
}

cdncapa = {
        '4t': 1.19 * (10**6), # b1
        '6t': 1.78 * (10**6), # b2
}

total_size = 1698.0 * (1024 ** 2) # MB
total_no = 72.5 * 1000 * 1000
avg_fsize = total_size / total_no # MB/file

# total N.O. files per cdn server
n = 8.0 * (10**6)


def calc_backratio_by_cdncapa_and_total(s, n):
    s = float(s)
    n = float(n)

    return (s**(a+1) - n**(a+1)) / (1-n**(a+1))


# s[2]^(a+1) - s[1]^(a+1)
# ----------------------- = b[1] - b[2]
#       n^(a+1) - 1
def find_a_by_2_samples(n, s1, s2, b1, b2):

    def _q(a):
        return (s1**(a+1) - s2**(a+1)) / (1 - n**(a+1))

    db = b1 - b2

    aa = (-2.0, -1.00000000001)
    while True:

        mid = (aa[0] + aa[1]) / 2

        rl = _q(aa[0])
        rm = _q(mid)
        rr = _q(aa[1])

        # print '======'
        # print aa[0], mid, aa[1]
        # print rl, rm, rr, rm - db

        if abs(rm - db) < 0.00000001:
            return mid

        if rm > db:
            aa = (aa[0], mid)
        else:
            aa = (mid, aa[1])

a = find_a_by_2_samples(n,
                        cdncapa['4t'],
                        cdncapa['6t'],
                        backratio['4t'],
                        backratio['6t'],
)
newfile_backratio = backratio['4t'] - calc_backratio_by_cdncapa_and_total(cdncapa['4t'], n)

print '- a=', a
print '- cache-miss 回源率(4T):', '{0:>8.2%}'.format(calc_backratio_by_cdncapa_and_total(cdncapa['4t'], n))
print '- cache-miss 回源率(6T):', '{0:>8.2%}'.format(calc_backratio_by_cdncapa_and_total(cdncapa['6t'], n))
print '- 新文件     回源率    :', '{0:>8.2%}'.format(newfile_backratio)
print

print '| 磁盘大小 | cdn节点容量/总容量 | 回源率=cache-miss回源+新文件回源 |'
print '| --: | --: | --: |'

k = 0.01
while k < .20:
    k += 0.01
    s = k * n
    b = calc_backratio_by_cdncapa_and_total(s, n)
    drive_size = s / cdncapa['4t'] * 4.0
    cost_sto = k / 0.1 * 4
    cost_sto = 4
    cost_bw =  b / 0.1 * 6
    # fmt = '| {drive_size:>4.1f}T | {k:>8.2%} | {bsum:>8.2%} = {b:>6.2%} + {newfile_backratio:>6.2%} | {cs:>8.2f}百万 | {cbw:>8.2f}百万 | {tt:>8.2f}百万 | {dec:>8.2f}百万 |'.format(
    fmt = '| {drive_size:>4.1f}T | {k:>8.2%} | {bsum:>8.2%} = {b:>6.2%} + {newfile_backratio:>6.2%} |'
    print fmt.format(
            drive_size=drive_size,
            k=k,
            bsum=b+newfile_backratio,
            b=b,
            newfile_backratio=newfile_backratio,
            cs=cost_sto,
            cbw=cost_bw,
            tt=cost_sto + cost_bw,
            dec=cost_sto + cost_bw - 10.0
    )


def calc_b(s, n, k):
    s = float(s)
    n = float(n)

    return (s**(a+1) - n**(a+1)) / (k**(a+1)-n**(a+1))

for node_cnt in range(1, 20):
    node_fcnt = 6 * 1024 * 1024 * 0.7 * 10 / avg_fsize
    serv_fcnt = total_no / node_cnt

    k = float(n)/serv_fcnt

    # b = calc_b(node_fcnt, serv_fcnt, 1)
    b = calc_b(1.78 * 1000 * 1000 / 9 *  node_cnt, n, 1)

    print '| {node_cnt:>3} | {serv_fcnt:>8.2f} mi | {k:>.3f} | {b:>8.2%} |'.format(
        node_cnt=node_cnt,
            serv_fcnt=serv_fcnt / (10**6),
            k=k,
            b=b,
    )

