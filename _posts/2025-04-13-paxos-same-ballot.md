---
title:      "Paxos 中 Ballot number 的重用机制"
authors:
    - xp
categories:
    - algo
tags:
    - distributed
    - 分布式
    - paxos

refs:
    - x: y

disabled_article:
    image: /post-res/linearizable/linearizable-banner-big.png

mathjax: false
toc: true
toc_label: 本文目录
toc_sticky: true
excerpt: "本文探讨 Paxos 协议中 Ballot number 的重用机制，分析何时可重复使用，以及为何只能使用系统中已存在的值而非提议新值"
---

![](/post-res/paxos-same-ballot/f3c38ebb6fbef4c9-paxos-same-ballot-banner.webp)

欢迎各位读者探讨 Paxos 的深层机制。在我此前发表的 [Paxos 的直观解释](https://zhuanlan.zhihu.com/p/145044486) 文章后，它作为一个完整的介绍 Paxos 文章, 收到了不少读者提出的深入问题，这些问题我已在 [Paxos 的读者答疑](https://github.com/openacid/openacid.github.io/discussions/31) 中详细回应。考虑到分布式共识算法的复杂性，我决定通过一系列 回答 Paxos 的特定问题 形式的文章来作为补充，本文是该系列的第一篇。希望这些分析能帮助你解决疑惑，从不同角度理解 Paxos，帮助自己在分布式系统领域构建更加完整的思维框架。

## 问：是否可以用同样的 Ballot number（rnd）运行 Paxos？

简短回答是：可以，但**不能**在这种情况下提议任何新的值；也就是说，若要用相同的 Ballot number 来重新运行 Paxos，则只能使用系统中**已经存在的值**，继续进行 phase-2（Accept 阶段）以完成提交。原因在于，若此时选择新的值，很可能会导致与现有已被接受的值产生冲突，进而导致不一致（脑裂）的情况。

Paxos 算法要求当我们用相同的 Ballot number 发起提案时，其流程不能从头开始选新值，否则会破坏 Paxos 的一致性。相反，我们只能“沿用”系统已存在、且在之前某一轮中被 Accept 过的值来继续完成提交。

---

## 示例

让我们通过一个时间线示意图来说明不同的时间点和 Paxos 状态。下面的图表展示了一个分布式系统中三个 Acceptor 节点在不同时间点的状态变化：

我们假设系统中已经发生了以下事件：

1.  第一个 Proposer 使用 Ballot number = 1：

    -   在 Acceptor-1 和 Acceptor-2 上完成了 phase-1（Prepare 阶段）
    -   然后在 Acceptor-1 上完成了 phase-2（Accept 阶段），写入了值 X

1.  第二个 Proposer 使用 Ballot number = 2：

    -   在 Acceptor-2 和 Acceptor-3 上完成了 phase-1（Prepare 阶段）
    -   然后在 Acceptor-1 和 Acceptor-2 上完成了 phase-2（Accept 阶段），提交了值 Y

![](/post-res/paxos-same-ballot/5abd75633aa50198-paxos-same-ballot-0.x.svg)

> 图中的事件以这种格式表示: `<phase><ballot_number>(<value>)`:
> 
> -   `phase` 可以是 P 或 A:
>     -   **P** 表示 Prepare 阶段（phase-1），
>     -   **A** 表示 Accept 阶段（phase-2），
> 
> -   `ballot_number` 表示投票轮次（也有些文章中使用 round number），
> -   `value` 表示在 Accept 阶段要提交的值（例如 `X`、`Y`）。但是他只对 A 表示的 accept 的 phase 有效
> 
> 例如 `P1` 指的是使用 **Ballot=1** 进行 Prepare，`A1(X)` 则指的是使用 **Ballot=1** 接受值 **X**。


### 不同时间下使用同一个 Ballot number 重新运行 Paxos 的效果示例

在上面的例子中, 我们将分析在几个不同的时刻(t1, t2, t3, t4, t5)分别使用相同的 Ballot number = 1 重新运行 Paxos 时会发生什么情况, 并详细描述每种场景下的具体行为和结果.

#### 场景 1：t1 时刻 - 无历史值场景

在时间点 t1，如果我们再次用同样的 Ballot number = 1 发起 Paxos，它可以完成 phase-1, 因为 Acceptor 总是接受同样的 Ballot number 的请求(Prepare 或 Accept). 但这次完成（Prepare）之后，并不会看到任何已存在的值。而前面我们说过, 用相同的 Ballot number 重复运行时也不能 propose 任何值. “无值”情况下也就无法运行 phase-2（Accept 阶段），所以协议会结束，等同于没有做任何更改。

![](/post-res/paxos-same-ballot/9c06b2c3e814b3ae-paxos-same-ballot-1.x.svg)

#### 场景 2：t2 时刻 - 部分节点存在历史值

与 t1 情况相似。如果此时系统只观测到部分 Acceptor(Acceptor-1 和 2)（它并不知道已有 `A1(X)` 的存在），那么结果与 t1 一样，无法提交新的值。

![](/post-res/paxos-same-ballot/a17787ad9c3273b8-paxos-same-ballot-2.x.svg)

#### 场景 3：t3 时刻 - 多数派存在历史值（关键场景）

在 t3 时，如果发起同样的 Ballot number = 1 的 Paxos，但访问到包含 `A1(X)` 的多数派（例如 Acceptor-1、Acceptor-2），phase-1 结束后会“得知”之前已经有值 `X` 被 Accept 过。Paxos 允许**继续使用已存在的值**，所以这时可以在 phase-2 中，使用 `X` 来完成提交。也就是说，用**同一个** Ballot number = 1 依然可以帮助把 `X` 提交到 Acceptor 的一个 majority 上，从而达成共识完成提交。

示意图如下所示，`P1'` 表示重复使用同一个 Ballot=1 进行再次 Prepare 且成功完成；在 Acceptor-1 上看到了值 `X`，然后在 `t3'` 时刻完成 phase-2 Accept 阶段，成功将值 `X` 提交到多数派。这次 Paxos 的运行可以视为修复了之前 `A1(X)` 未完成的提交（该值仅写入了 Acceptor-1 但未达到多数派共识）。

![](/post-res/paxos-same-ballot/56f61d3f1f71e0fd-paxos-same-ballot-3.x.svg)

#### 场景 4：t4 时刻 - 更高 Ballot 存在（被拒绝场景）

如果在时间点 t4 用 Ballot number = 1 去 Prepare，因为这时系统中已经出现了更新的提案（使用 Ballot=2 的提案），那么 Acceptor-2 会拒绝较小的 Ballot number 1 的 Prepare。这意味着 Paxos 提议会在第一阶段就被否定，不能往下进行 phase-2 的 Accept 阶段。

![](/post-res/paxos-same-ballot/321be959bc05288a-paxos-same-ballot-4.x.svg)

#### 场景 5：t5 时刻及之后 - 完全被新 Ballot 覆盖

在 t5 或之后的任何时刻，系统上已经有一个 Quorum 接受了 Ballot=2（甚至更高的 ballot）的 phase-1 Prepare，这会导致 **Ballot=1** 的 Prepare 请求无处不被拒绝。无法完成任何提交。

---

## 总结

-   **可以** 用重复的 Ballot number 来重新运行 Paxos 一次或多次，但前提是 **只能使用系统中已经存在、曾被 Accept 的值** ，不能引入任何新的值。
-   用同一个 Ballot number 重复运行 Paxos 可以看做是一个 **修复** 动作，它能够将未完成的提交（未达到多数派）推进至完成状态，但绝对不会破坏已有的提交或引入不一致。
-   一个直观理解：可以将 Paxos 中的 ballot number 视为"逻辑时间戳"。用同一个 Ballot number 重复运行 Paxos，相当于在同一个逻辑时间点上重放事件，但遵循"不能改变历史"的原则 — 如果在这个时间点上已经有了被接受的值，就必须沿用该值；如果没有，也不能随意引入新值。这种机制确保了即使在分布式环境中重复执行，系统状态也会收敛到一致。
-   且一个推论是: 如果不 propose 新的值, 那么用任意 Ballot number 去运行一次 Paxos, 都不会破坏系统的共识!

如果你对 Paxos 或一致性协议还有其他问题，欢迎进一步探讨！



Reference:

- paxos的读者答疑 : [https://github.com/openacid/openacid.github.io/discussions/31](https://github.com/openacid/openacid.github.io/discussions/31)

- 可靠分布式系统-paxos的直观解释 : [https://zhuanlan.zhihu.com/p/145044486](https://zhuanlan.zhihu.com/p/145044486)


[discuss-paxos]: https://github.com/openacid/openacid.github.io/discussions/31 paxos的读者答疑
[post-paxos]: https://zhuanlan.zhihu.com/p/145044486 "可靠分布式系统-paxos的直观解释"