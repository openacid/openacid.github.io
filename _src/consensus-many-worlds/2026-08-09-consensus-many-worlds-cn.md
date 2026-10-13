---
title:      "分布式共识与量子多世界：结构对应与研究方向"
authors:
    - xp
categories:
    - algo
tags:
    - consensus
    - distributed
    - quantum
    - physics

refs:
    - "time-clocks":          https://lamport.azurewebsites.net/pubs/time-clocks.pdf                  "Time, Clocks, and the Ordering of Events in a Distributed System"
    - "mwi":                  https://plato.stanford.edu/entries/qm-manyworlds/                       "Many-Worlds Interpretation of Quantum Mechanics (SEP)"
    - "everett-1957":         https://journals.aps.org/rmp/abstract/10.1103/RevModPhys.29.454         "'Relative State' Formulation of Quantum Mechanics (Everett, 1957)"
    - "decoherence":          https://plato.stanford.edu/entries/qm-decoherence/                      "The Role of Decoherence in Quantum Mechanics (SEP)"
    - "quantum-darwinism":    https://arxiv.org/abs/0903.5082                                         "Quantum Darwinism (Zurek, 2009)"
    - "no-cloning":           https://www.nature.com/articles/299802a0                                "A single quantum cannot be cloned (Wootters & Zurek, 1982)"
    - "causal-set":           https://journals.aps.org/prl/abstract/10.1103/PhysRevLett.59.521        "Space-time as a causal set (Bombelli, Lee, Meyer, Sorkin, 1987)"
    - "sequential-growth":    https://arxiv.org/abs/gr-qc/9904062                                     "A classical sequential growth dynamics for causal sets (Rideout & Sorkin, 1999)"
    - "consistent-histories": https://plato.stanford.edu/entries/qm-consistent-histories/             "The Consistent Histories Approach to Quantum Mechanics (SEP)"
    - "wolfram-physics":      https://www.wolframphysics.org/                                         "The Wolfram Physics Project"
    - "quantum-byzantine":    https://dl.acm.org/doi/10.1145/1060590.1060662                          "Fast quantum Byzantine agreement (Ben-Or & Hassidim, 2005)"

mathjax: false
toc: true
toc_label: 本文目录
toc_sticky: true
excerpt: "多历史共识模型与量子力学的多世界诠释共享同一个信息骨架: grow-only 分支, 局部视图, 冗余复制定义客观性. 本文整理四条结构对应, 物理学中已有的同构研究纲领, 以及三个对不上的缺口——它们构成一组明确的研究问题."
---

这篇文章记录一个观察: 《重新理解分布式共识: Raft 与 Paxos 的共同结构》里建立的多历史共识模型, 与量子力学的[多世界诠释][mwi] (Many-Worlds Interpretation, MWI) 共享同一个结构骨架. 这个重叠不是修辞——物理学里已经有正经的研究纲领在用几乎相同的形式结构描述现实; 而两者对不上的地方, 恰好构成一组明确的研究问题. 本文把对应关系, 已有纲领和缺口整理成一份研究方向清单.

需要的背景只有一段. 多历史模型把 state machine 定义为一棵只增不删的树 (`cm1-history-tree`, `cm2-grow-only`), 树上每个节点是一个全局唯一的 TimePoint (`cm3-unique-timepoint`); 写入把新 TimePoint 复制到一个 `WriteQuorum`, 读取合并一个 `ReadQuorum` 的视图, 任何两者必有交集 (`cm4-quorum-intersection`), 写满一个 `WriteQuorum` 即 commit. 树上允许多条历史分支同时生长; 单历史算法 (Paxos/Raft) 是在此之上追加约束 (`cs1-global-max` 等), 强制所有观察者沿同一条分支延伸.

四条对应先列成表, 每条下文单独展开:

| 共识模型                        | 物理                        | 共享的性质                               |
| ------------------------------- | --------------------------- | ---------------------------------------- |
| grow-only 历史树                | MWI 的分支波函数            | 分支只增不删, "删除"只是局部不可见       |
| commit (写满一个 `WriteQuorum`) | 退相干 + quantum Darwinism  | 客观性 = 记录被冗余复制, 且实际不可逆    |
| TimePoint 偏序                  | 狭义相对论的因果序          | 并发/类空的事件没有先后                  |
| 多历史框架 + 单历史约束         | 幺正演化 + 经典体验         | "唯一的历史"是观察者协议的产物           |

## 对应一: grow-only 历史树 ↔ 分支的波函数

MWI 的宇宙态就是一棵 grow-only 树. [MWI][everett-1957] 的主张是: 宇宙波函数只做幺正演化, 从不坍缩; 所谓"测量", 是观察者与被测系统纠缠, [退相干][decoherence]使不同结果对应的分量彼此失去干涉, 成为互不作用的分支; 所有分支同样真实. 分支只增不删——这正是 `cm1-history-tree` 加 `cm2-grow-only`.

对应最锋利的一点在"删除"的处理上. 共识模型为了保住 `cm2-grow-only`, 把 Raft 的 log 截断解释为: 被截断的分支在全局树 (所有 replica 本地树的并集) 中仍然存在, 只是不再存于这个 replica, 变得不可见. MWI 对"坍缩"的处理一字不差: 坍缩只是分支内观察者的视角表象, 全局波函数中没有任何东西消失.

## 对应二: commit ↔ 退相干与 quantum Darwinism

这是四条对应里最深的一条: 两边对"一件事客观地发生了"给出了同一个定义——**信息被冗余复制到足够多的载体, 使任何未来观察者都必然读到一致的结果**.

共识侧: 写入复制到一个 `WriteQuorum` 即 commit; 由 `cm4-quorum-intersection`, 任何 `ReadQuorum` 都与它相交, 未来所有读取必然看到这个写入.

物理侧: Zurek 的 [quantum Darwinism][quantum-darwinism] 纲领回答"经典的客观事实从哪来": 测量结果之所以客观, 是因为它的记录被冗余地复制进环境的大量片段 (散射的光子, 空气分子...), 多个观察者各自读取互不相交的环境片段, 仍得到同一个答案. 把"环境片段"读作 replica, 这就是 quorum read.

连不可逆性的结构都相同. committed 的写入无法撤销, 因为撤销要求收回已扩散到多个 replica 的记录; 退相干实际不可逆, 因为恢复相干要求收回已扩散进环境的全部记录. 两边都是 "for all practical purposes" 的不可逆——信息扩散造成的热力学式单向性, 而非逻辑上的不可能.

## 对应三: TimePoint 偏序 ↔ 相对论的因果序

这一条不是新发现, 而是分布式系统这门学科的出身: Lamport 1978 年提出逻辑时钟的[论文][time-clocks]明确说明灵感来自狭义相对论——类空间隔的两个事件没有客观先后, 事件的顺序只能由"消息可能从谁传到谁"定义. 多历史模型里 TimePoint 的偏序 (并发的 TimePoint 互不可比) 就是这个因果偏序的离散版本. 换句话说, 共识与物理之间的这条通道四十多年前就已打开, 当时的方向是从物理流向计算机.

## 对应四: 多/单历史拆分 ↔ 量子/经典分层

多历史模型分两层: 多历史框架 (所有分支共存) 加单历史约束 (强制选出一条). 物理里对应的分层是: 幺正量子力学 (所有历史都在) 加经典体验 (每个观察者只经历一条).

但这里有一个诚实的差别, 而且这个差别本身有研究价值. MWI 里没有 `cs1-global-max`, 也没有 `cs3-write-fence`——不存在任何全局机制把其他分支孤立掉, 每条分支里的观察者都以为自己是唯一历史. 共识里的单历史则是观察者共同遵守的读取协议的产物: 所有 reader 都执行"选择最大 leaf 所在的分支", 于是全体观察者的经验收敛到同一条历史. 这给"为什么我们只经历一个世界"提供了一种协议式表述: 唯一的历史不必是本体层面的事实, 只需是所有观察者运行同一个选择规则的结果.

## 已有的研究纲领

"用这类形式系统描述现实"不是空想, 已经有人在下注:

- **Causal set theory** ([Bombelli, Lee, Meyer, Sorkin 1987][causal-set]): 量子引力的一个方向, 假设时空的本体就是一个局部有限的偏序集. [Rideout–Sorkin][sequential-growth] 的 classical sequential growth 动力学一次添加一个元素, 且不得违反已有的因果序——严格就是"grow-only 偏序结构作为现实本体". 未解决的核心问题是恢复连续时空与广义相对论.
- **Consistent histories** ([Griffiths; Gell-Mann–Hartle][consistent-histories]): 把量子力学直接表述为"历史的集合 + 一致性条件": 只有当粗粒化历史之间的干涉被退相干消除时, 才能对历史赋予经典概率. 连"历史族"这个词都与本文的用法重合.
- **Quantum Darwinism** ([Zurek][quantum-darwinism]): 见对应二, 是把"客观性 = 冗余复制"做成定量纲领的工作.
- **Wolfram 的 multiway system** ([Wolfram Physics Project][wolfram-physics]): 所有可能演化构成的分支图, 与多历史树形式同构, 并声称量子力学在其 "branchial space" 中涌现. 形式结构可作参考, 但其物理主张未被主流学界接受.

## 缺口, 也就是研究方向

对应到此为止; 对不上的部分恰好是三个可以研究的问题.

**问题一: 振幅与干涉.** 量子分支带复振幅, 分支之间会干涉; 分支结构本身是退相干选出的涌现近似 (哪组基底算"分支"由环境决定), 不是公理. 共识树没有振幅, 分支严格独立, `cm2-grow-only` 是精确公理而非热力学近似. 研究方向: 给多历史树的分支挂上振幅并允许干涉, union merge 在什么条件下失效? 得到的结构与 path integral, 与 multiway graph 各是什么关系?

**问题二: Born 规则没有对应物.** 物理侧, "观察者以多大概率发现自己在哪条分支"由 Born 规则 (按 |ψ|² 加权) 给出, 而 MWI 内部如何推导出 Born 规则至今没有公认答案 (Deutsch–Wallace 的决策论推导, Zurek 的 envariance, 均有争议). 共识侧, 分支的胜负由 fencing 和消息时序对抗性地决定, 根本没有测度. 研究方向: 对抗性选择与概率测度之间有没有桥? 例如把网络调度建模为随机而非对抗的, 分支的存活率会不会出现自然的测度?

**问题三: no-cloning 是边界.** 整套 quorum 机制建立在"记录可复制"之上——`cm2-grow-only` 与 `cm4-quorum-intersection` 的每一步都在复制信息. 而 [no-cloning 定理][no-cloning]禁止复制未知量子态; 能被复制的只有 (近似) 正交的经典信息. Zurek 的回答恰好把这条边界变成了定义: **能被冗余复制的那部分信息, 就是"经典"**. 因此结论可以说得很精确: 共识式的形式系统能描述的是退相干之后的经典骨架, 描述不了量子内核; 可复制性就是分界线. 研究方向: 在"记录不可复制"的世界里, 哪些共识结论仍然成立? 这个方向已有入口——[quantum Byzantine agreement][quantum-byzantine] 等量子分布式计算工作是从计算机一侧挖的隧道; 从"用共识形式系统刻画经典性如何涌现"一侧挖的隧道, 目前要少得多.

## 为什么重叠得这么好

两个领域重叠并不神秘. 分布式系统理论和诠释层面的量子力学是同一类理论: 研究嵌在系统内部, 只能通过局部交互获得局部视图的观察者, 能知道什么, 能就什么达成一致. 它们共享信息的运动学——事件, 因果偏序, 观察即复制记录, 客观性即冗余一致; 只是动力学不同——一边是幺正演化与振幅, 一边是协议与对抗时序. 骨架相同, 血肉不同; 而血肉对不上的地方, 就是上一节的三个问题.
