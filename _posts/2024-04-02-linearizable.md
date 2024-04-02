---
title:      "分布式系统中的Linearizable事务:时间、通信与一致性"
authors:
    - xp
categories:
    - algo
tags:
    - distributed
    - 分布式

refs:
    - x: y

disabled_article:
    image: /post-res/linearizable/linearizable-banner-big.png

mathjax: false
toc: true
toc_label: 本文目录
toc_sticky: true
excerpt: "分布式系统中,Linearizable事务的实现需要解决事务间先后顺序的判断问题,本文深入探讨了这一难题,分析了其中的时间一致性挑战,并提出了几种解决方案和设计思路。"
---

![](/post-res/linearizable/ed2084df235602ac-linearizable-banner-47x20.jpg)

**Linearizable 事务的定义**: 对一个分布式系统S, 如果 txn2 在 txn1 commit之后发起, 那么 txn2 一定能看到 txn1 提交的数据.

那么, **怎么知道 txn2 是不是在 txn1 之后呢**?

例如可以这么做: 在 txn1 commit后看一眼表得到时间 t1 , 在 txn2 开始前看一眼表得到时间 t2 , 如果 `t2 > t1` , 那么就说 txn2 是在 txn1 之后.

那么, **怎么保证他俩看的这两块表的时间一致呢**?

相对论告诉我们对不同的观察者, `t2 > t1` 和 `t1 > t2` 可能在不同的参考系里分别被观察到.
因此看2块表决定先后的方法, 理论上在我们这个宇宙中就是无法实现的.

如下图, R₁ 惯性系相对 R₀ 惯性系以 v = sinθ 运动时, R₀ 中的 t=1 时刻在 R₁
看来发生在时刻 1 之后, 反之一样; 其中距离单位为1光秒, 所以以光速 C
运动的参考系是直线 x=t; 某个 R₁ 中的 t=1 的点在 R₀ 中的 t²-x²=1 的双曲线上:

![](/post-res/linearizable/d8f39bf1d645bdf2-linearizable-relativity.excalidraw.png)

因此, **要确定先后, txn1 和 txn2 就必须看同一块表**.

也就是说, **txn1 和 txn2 必须有一次通讯**(直接通讯, 或通过第三方, 即同一块表), 才能确认彼此先后.

也就是说, 要真正达成 Linearizable, txn1 commit 后必须有个 **写表** 的操作记录自己
commit 的 **时刻**, txn2 开始前必须有个 **读表** 的操作, 才能正确区分先后,
从而达成 Linearizable. 有些分布式系统本身就可以做表(虚拟时间), 例如 Paxos 的 `ballot` 就是表,
Raft 的 `(term, log_index)` 也是表.

当然, 你可以说我不用看表, 我的代码写的就是完成 txn1 后, 才发起的 txn2;
在这个情况下, 实际上是 **让 txn1 和 txn2 直接通讯了**, 这个情况下要达成
Linearizable, 应该直接把 t1 当做 txn2 的一部分提交到系统S, 告诉系统S, txn2 要在
t1 前 commit 的事务都执行完之后再执行.

即:

-   如果一个线程内的2个 txn, 那么这个线程应该负责保证自己需要的 Linearizable;
-   2个线程中的2个 txn:
    -   如果彼此不知道对方, 则不需要保证 Linearizable;
    -   如果 txn2 知道 txn1 , 那么说明他们通过某种途径进行了通讯,
        那么应该由这个通讯的路径(可能是通过某表)来保证 Linearizable. 而不是把麻烦不分职责的丢给系统S让它做表.

各种解决分布式 Linearizable 的文章讨论的, 就是在解决怎么把 t1 告诉 txn2 的问题:
或者让系统S本身做表, 或者找一个第三方发号器做表.

有不少的 Linearizable  看起来是在绑起双手解决问题, 例如 Raft 中
Linearizable-read 的实现, 是让系统S自己做表的例子: txn2 做 read 时,
要等待系统中所有 log 都 apply 才进行 read, 不论这些 log 是否跟这个 read 操作相关.

在我看来, 更好的设计应该是, Raft 给每个 write 操作返回它的 log 的对应 id, 后面的
read 操作如果依赖之前某个 write 的结果, 那么就把这个 log id
交给 Raft 使之知道至少 apply 到哪个 log 为止才能被 read.

log id 在 Raft 系统中就是这个表的时间.



Reference:

