

- [内容简介]({{page.url}}#内容简介)
- [分布式系统的可靠性问题: 冗余和多副本]({{page.url}}#分布式系统的可靠性问题-冗余和多副本)
- [EC的基本原理]({{page.url}}#ec的基本原理)
    - [栗子🌰1: 实现k+1的冗余策略, 大概需要小学3年级的数学知识]({{page.url}}#栗子1-实现k1的冗余策略-大概需要小学3年级的数学知识)
    - [栗子🌰2: 实现k+m的冗余策略, 大概需要初中2年级的数学知识]({{page.url}}#栗子2-实现km的冗余策略-大概需要初中2年级的数学知识)
        - [增加1个校验块, 变成k+2]({{page.url}}#增加1个校验块-变成k2)
        - [实现k+m 的冗余]({{page.url}}#实现km-的冗余)
- [EC编码矩阵的几何解释]({{page.url}}#ec编码矩阵的几何解释)
    - [k=2, 为2个数据块生成冗余校验块]({{page.url}}#k2-为2个数据块生成冗余校验块)
    - [k=3, 4, 5...时的数据块的冗余]({{page.url}}#k3-4-5时的数据块的冗余)
        - [通过高次曲线生成冗余数据]({{page.url}}#通过高次曲线生成冗余数据)
        - [从曲线方程得到的系数矩阵]({{page.url}}#从曲线方程得到的系数矩阵)
- [EC解码过程: 求解n元一次方程组]({{page.url}}#ec解码过程-求解n元一次方程组)
    - [\[Vandermonde\] 矩阵保证方程组有解]({{page.url}}#vandermonde-矩阵保证方程组有解)

- [新世界: 伽罗华域 \[Galois-Field\] GF(7)]({{page.url}}#新世界-伽罗华域-galois-field-gf7)
    - [EC在计算机里的实现: 基于 伽罗华域 \[Galois-Field\]]({{page.url}}#ec在计算机里的实现-基于-伽罗华域-galois-field)
    - [栗子🌰3: 只有7个数字的新世界: GF(7)]({{page.url}}#栗子3-只有7个数字的新世界-gf7)
        - [模7新世界中的 **加法**]({{page.url}}#模7新世界中的-加法)
        - [模7新世界中的 **减法**]({{page.url}}#模7新世界中的-减法)
        - [模7新世界中的 **乘法** 和 **除法**]({{page.url}}#模7新世界中的-乘法-和-除法)
    - [栗子🌰4: 模7新世界直线方程-1]({{page.url}}#栗子4-模7新世界直线方程-1)
    - [栗子🌰5: 模7新世界直线方程-2]({{page.url}}#栗子5-模7新世界直线方程-2)
    - [栗子🌰6: 模7新世界中的二次曲线方程]({{page.url}}#栗子6-模7新世界中的二次曲线方程)
    - [模7新世界里的EC]({{page.url}}#模7新世界里的ec)

- [EC使用的新世界 \[Galois-Field\] GF(256)]({{page.url}}#ec使用的新世界-galois-field-gf256)
    - [模2的新世界: \[Galois-Field\] GF(2)]({{page.url}}#模2的新世界-galois-field-gf2)
    - [域的扩张 \[Field-Extension\]]({{page.url}}#域的扩张-field-extension)
        - [栗子🌰7: 实数到虚数的扩张]({{page.url}}#栗子7-实数到虚数的扩张)
    - [从2到256: 扩张 GF(2)]({{page.url}}#从2到256-扩张-gf2)
        - [栗子🌰8: GF(2) 下的质多项式]({{page.url}}#栗子8-gf2-下的质多项式)
        - [GF(2) 扩张成 GF(2^8)]({{page.url}}#gf2-扩张成-gf28)
- [实现]({{page.url}}#实现)
    - [标准EC的实现]({{page.url}}#标准ec的实现)
        - [EC编码: 校验数据生成]({{page.url}}#ec编码-校验数据生成)
        - [EC解码]({{page.url}}#ec解码)
        - [Vandermonde 矩阵的可逆性]({{page.url}}#vandermonde-矩阵的可逆性)
        - [GF256 下的 Vandermonde 矩阵的可逆性]({{page.url}}#gf256-下的-vandermonde-矩阵的可逆性)

    - [数据恢复IO优化: LRC: \[Local-Reconstruction-Code\]]({{page.url}}#数据恢复io优化-lrc-local-reconstruction-code)
        - [LRC 的校验块生成]({{page.url}}#lrc-的校验块生成)
        - [LRC 的数据恢复]({{page.url}}#lrc-的数据恢复)
    - [工程优化]({{page.url}}#工程优化)
- [分析]({{page.url}}#分析)
    - [可靠性分析]({{page.url}}#可靠性分析)
    - [IO消耗]({{page.url}}#io消耗)
- [参考]({{page.url}}#参考)




#   内容简介

[Erasure-Code], 简称 EC, 也叫做 **擦除码** 或 **纠删码**,
指使用 范德蒙([Vandermonde]) 矩阵的 里德-所罗门码([Reed-Solomon]) 擦除码算法.

**EC 本身是1组数据冗余和恢复的算法的统称**.

本文以 [Vandermonde] 矩阵的 [Reed-Solomon] 来解释 EC 的原理.

术语定义:

-   $d_j$ 表示数据块.
-   $y_i$ 表示通过数据块计算得来的, 作为数据冗余的校验块.
-   $u_j$ 表示丢失的, 需要恢复的数据块.
-   k 表示数据块的数量.
-   m 表示校验块的数量.


<!--more-->

本文内容包括:

-   第1节 [分布式系统的可靠性问题: 冗余和多副本]({{page.url}}#ec-ncopy)
    提出EC需要解决的问题.

-   希望对分布式存储领域增加了解的同学,
    可以只阅读 [EC的基本原理]({{page.url}}#ec-basic) 部分.

    这部分会用到1些中学的数学知识,
    逐步用举栗子🌰的方式给出了EC算法的直观解释.

    它和真正实现层面的EC原理是一致的, 但不深入到太多数学层面的内容.

-   已经对EC工作方式有些了解, 希望更深入了解其数学原理的读者, 可以直接从
    [EC编码矩阵的几何解释]({{page.url}}#ec-matrix) 开始阅读.

    这部分解释了EC的编码矩阵的原理和含义,
    但不包括更底层数学的讨论.

    [伽罗华域GF(7)]({{page.url}}#ec-gf7) 和 [伽罗华域GF(256)]({{page.url}}#ec-gf256) 开始介绍如何将EC应用到计算机上的方法,
    从这部分开始EC会用到1些抽象代数中的知识.

-   需要动手扣腚解决分布式存储问题的猿, 如果对数学原理不感兴趣,
    但对工程实践方面有兴趣的话, 可以参考 [实现]({{page.url}}#ec-impl).

-   需要对存储策略规划的架构师, 可以直接参考数值分析部分 [分析]({{page.url}}#ec-analysis).


<a name="ec-ncopy"></a>




<a name="ec-gf7"></a>





## 数据恢复IO优化: LRC: [Local-Reconstruction-Code]

当 EC 进行数据恢复的时候, 需要k个块参与数据恢复, 直观上,
每个数据块损坏都需要k倍的IO消耗.

为了缓解这个问题, 一种略微提高冗余度, 但可以大大降低恢复IO的算法被提出:
[Local-Reconstruction-Code], 简称 LRC.

LRC的思路很简单, 在原来的 EC 的基础上,
对所有的数据块分组对每组在做1次 $ k' + 1 $ 的 EC.
k' 是二次分组的每组的数据块的数量.



### LRC 的校验块生成

$$
\begin{aligned}
\overbrace{d_1 + d_2 + d_3}^{y_{1,1}} + \overbrace{d_4 + d_5 + d_6}^{y_{1,2}} & = y_1 \\
d_1 + 2d_2 + 2^2d_3 + 2^3d_4 + 2^4d_5 + 2^5d_6                                & = y_2 \\
d_1 + 3d_2 + 3^2d_3 + 3^3d_4 + 3^4d_5 + 3^5d_6                                & = y_3
\end{aligned}
$$

最终保存的块是所有的数据块: $ d_1, d_2, d_3, d_4, d_5, d_6 $,
和校验块 $ y_{1,1}, y_{1,2}, y_2, y_3 $.

这里不需要保存 $ y_1 $ 因为 $ y_1 = y_{1,1} + y_{1,2} $

对于 LRC的EC来说, 它的生成矩阵前k行不变,
去掉了标准EC的第k+1行, 多出2个局部的校验行:

$$
\begin{bmatrix}
1 & 0 & 0 & 0 & 0 & 0 \\
0 & 1 & 0 & 0 & 0 & 0 \\
0 & 0 & 1 & 0 & 0 & 0 \\
0 & 0 & 0 & 1 & 0 & 0 \\
0 & 0 & 0 & 0 & 1 & 0 \\
0 & 0 & 0 & 0 & 0 & 1 \\
\hline \\
1 & 1 & 1 & 0 & 0 & 0 \\
0 & 0 & 0 & 1 & 1 & 1 \\
\hline \\
1 & 2 & 2^2 & 2^3 & 2^4 & 2^5 \\
1 & 3 & 3^2 & 3^3 & 3^4 & 3^5 \\
\end{bmatrix}
\times
\begin{bmatrix}
d_1 \\
d_2 \\
d_3 \\
d_4 \\
d_5 \\
d_6
\end{bmatrix} =
\begin{bmatrix}
d_1 \\
d_2 \\
d_3 \\
d_4 \\
d_5 \\
d_6 \\
y_{1,1} \\
y_{1,2} \\
y_2 \\
y_3 \\
\end{bmatrix}
$$



### LRC 的数据恢复

LRC 的数据恢复和标准的EC类似, 除了2点不同:

-   在选择校验块的行生成解码矩阵的时候,
    如果某第k+i行没有覆盖到任何损坏的数据的话,
    是无法提供有效性信息, 需要跳过的.

    例如 $ d_4 $ 损坏时, 不能像标准EC那样选择第7行 `1 1 1 0 0 0`
    这行作为补充的校验行生成解码矩阵, 必须略过第7行, 使用第8行.

-   不是所有的情况下, m个数据损坏都可以通过加入m个校验行来恢复.
    因为LRC的生成矩阵没有遵循 [Vandermonde] 矩阵的规则,
    不能保证任意k行都是满秩的.

<a name="ec-analysis"></a>




##  工程优化

插播一条广告:
徐同学的博客中给出了很好的EC工程实现的介绍,
推荐!: [实现高性能纠删码引擎](http://www.templex.xyz/blog/101/writers.html)



#   分析



##  可靠性分析

在可靠性方面, 假设 EC 的配置是k个数据块, m个校验块.
根据 EC 的定义,k+m个块中, 任意丢失m个都可以将其找回.
这个 EC 组的丢失数据的风险就是丢失m+1个块或更多的风险:

$$
\sum_{i=m+1}^{k+m} {k+m \choose i} p^{i} (1-p)^{k+m-i}
$$

这里p是单块数据丢失的风险,一般选择磁盘的日损坏率: 大约是`0.0001`.
p一般很小所以近似就只看第1项:

$$
{k+m \choose m+1} p^{m+1} (1-p)^{k-1}
$$

2个校验块和3副本的可靠性对比(取m=2):

| k   | m   | 丢数据风险                                                      |
| :-- | :-- | :--                                                             |
| 1   | 2   | $ 1 \times 10^{-12} $ (1个数据块+2个校验块 可靠性 和 3副本等价) |
| 2   | 2   | $ 3 \times 10^{-12} $                                           |
| 3   | 2   | $ 9 \times 10^{-12} $                                           |
| 10  | 2   | $ 2 \times 10^{-10} $ (10+2 和 12盘服务器的 [RAID-6] 等价)      |
| 32  | 2   | $ 5 \times 10^{-9} $                                            |
| 64  | 2   | $ 4 \times 10^{-8} $                                            |

3个校验块和4副本的可靠性对比(取m=3):

| k   | m   | 丢数据风险                                                      |
| :-- | :-- | :--                                                             |
| 1   | 3   | $ 1 \times 10^{-16} $ (1个数据块+3个校验块 可靠性 和 4副本等价) |
| 2   | 3   | $ 5 \times 10^{-16} $                                           |
| 3   | 3   | $ 2 \times 10^{-15} $                                           |
| 10  | 3   | $ 7 \times 10^{-14} $                                           |
| 32  | 3   | $ 5 \times 10^{-12} $                                           |
| 64  | 3   | $ 7 \times 10^{-11} $                                           |

4个校验块和5副本的可靠性对比(取m=4):

| k   | m   | 丢数据风险                                                      |
| :-- | :-- | :--                                                             |
| 1   | 4   | $ 1 \times 10^{-20} $ (1个数据块+4个校验块 可靠性 和 5副本等价) |
| 2   | 4   | $ 6 \times 10^{-20} $                                           |
| 3   | 4   | $ 2 \times 10^{-19} $                                           |
| 10  | 4   | $ 2 \times 10^{-17} $                                           |
| 32  | 4   | $ 4 \times 10^{-15} $                                           |
| 64  | 4   | $ 1 \times 10^{-13} $                                           |



## IO消耗

以一个 EC 组来分析,
1个块损坏的概率是 $ p $, 这个组中有块损坏的概率是:
$ 1 - (1-p)^{k+m} \approx (k+m)p $

每次数据损坏都需要读取全组的数据进行恢复.
不论1块损坏还是多块损坏, 数据恢复都是读取1次, 输出1或多次.
恢复数据的输出比较小, 1般是1, 所以可以忽略.

每存储一个字节一天数据恢复产生的传输量是(blocksize是一个数据块或校验块的大小):

$$
\frac{(k+m)p \times (k+m) \times blocksize}
{(k+m) \times blocksize} = (k+m)p
$$

也就是说, 使用 EC 每存储`1TB`的数据,
每天(因为我们取的数据损坏概率是按天计算的)用于数据恢复而产生的IO是
`k * 0.1GB / TB`

磁盘的IO大致上也等同于网络流量, 因为大部分实现必须将数据分布到不同的服务器上.

> NOTE:<br/>
> 随着 `k`的增加, 整体成本虽然会下降(`1+m/k`),
> 但数据恢复的IO开销也会随着k(近似于)线性的增长.

例如:

假设`k+m = 12`:

如果整个集群有 `100PB` 数据,
每天用于恢复数据的网络传输是 `100TB`.

假设单台存储服务器的容量是`30TB`,
每台服务器每天用于数据恢复的数据输出量是 `30GB`,
如果数据恢复能平均到每天的每1秒, 最低的带宽消耗是:
`30GB / 86400 sec/day = 3.0Mbps`.

但一般来说数据恢复不会在时间上很均匀的分布,
这个带宽消耗需要预估10倍到100倍.

---



# 参考

-   [Vandermonde]
-   [范德蒙矩阵][Vandermonde]
-   [Cauchy]
-   [RAID-5]
-   [RAID-6]
-   [Finite-Field]
-   [Galois-Field]
-   [伽罗华域][Galois-Field]
-   [Reed-Solomon]
-   [里德-所罗门码][Reed-Solomon]
-   [Erasure-Code]
-   [Prime-Polynomial]
-   [Field-Extension]
-   [Complex-Number]
-   [Hamming-7-4]
-   [Generator-Matrix]

---

-   [实现高性能纠删码引擎](http://www.templex.xyz/blog/101/writers.html)

---

[Vandermonde]:      https://en.wikipedia.org/wiki/Vandermonde_matrix                     "Vandermonde matrix"
[Cauchy]:           https://en.wikipedia.org/wiki/Cauchy_matrix                          "Cauchy matrix"
[failure-rate]:     https://www.backblaze.com/blog/hard-drive-reliability-stats-q1-2016/ "HDD Failure Rate"
[RAID-5]:           https://zh.wikipedia.org/wiki/RAID#RAID_5                            "RAID-5"
[RAID-6]:           https://zh.wikipedia.org/wiki/RAID#RAID_6                            "RAID-6"
[Finite-Field]:     https://en.wikipedia.org/wiki/Finite_field                           "Finite-Field"
[Galois-Field]:     https://en.wikipedia.org/wiki/Finite_field                           "Galois-Field"
[Reed-Solomon]:     https://en.wikipedia.org/wiki/Reed%E2%80%93Solomon_error_correction  "Reed-Solomon error correction"
[Erasure-Code]:     https://en.wikipedia.org/wiki/Erasure_code                           "Erasure-Code"
[Prime-Polynomial]: https://en.wikipedia.org/wiki/Irreducible_polynomial                 "Prime-Polynomial"
[Field-Extension]:  https://en.wikipedia.org/wiki/Field_extension                        "Field-Extension"
[Complex-Number]:   https://en.wikipedia.org/wiki/Irreducible_polynomial#Field_extension "Complex-Number"
[Hamming-7-4]:      https://en.wikipedia.org/wiki/Hamming(7,4)                           "Hamming(7, 4)"
[Generator-Matrix]: https://en.wikipedia.org/wiki/Generator_matrix                       "Generator-Matrix"


