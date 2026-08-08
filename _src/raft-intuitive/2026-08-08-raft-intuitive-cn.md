---
title:      "重新理解分布式共识：Raft 与 Paxos 的共同结构"
authors:
    - xp
categories:
    - algo
tags:
    - raft
    - consensus
    - distributed

refs:
    - x: y

mathjax: false
toc: true
toc_label: 本文目录
toc_sticky: true
excerpt: ""
---

<!-- Rethinking Distributed Consensus: A Unified View of Raft and Paxos -->

![](raft-intuitive-banner.png)

这篇文章尝试从一个比 Raft 和 Paxos 更抽象, 更通用的视角, 用一种直观, 可理解, 可感受的方式解释 distributed consensus.

之前我写过一篇直观解释 Paxos 的文章. 这篇文章不再从某个具体算法出发, 而是先建立一个通用的 distributed consensus 模型, 再用它解释 Raft 和 Paxos 的共同结构.

## Raft 和 Paxos 的简化方式

Raft 和 Paxos 不太一样, 但核心完全相同.

Raft 是一个多值的 distributed consensus, 而经典的 (single-decree) Paxos 是一个单值的 distributed consensus. Raft 和 Paxos 分别在不同方向对consensus问题做了简化, 以至于读者从paxos或raft中都无法窥见问题的全貌. 所以我们今天来解释解释: 到底在 distributed system 里, 什么叫作一致 consensus?

- Paxos 的简化方式是把consensus简化成单值, 让问题看起来更**易于描述**;

- Raft 的简化方式是面向实践, 对理论做了一些删减, 让问题看起来更**易于实现**.

这篇文章先讨论什么是"一致", 也就是通常所说的 consensus; 然后建立一个通用直观模型, 让读者对问题全貌有准确的把握, 最后再把它映射到 Raft 和 Paxos, 展示这两种算法各自做的取舍.

## 什么是 distributed consensus?

什么是分布式系统 Distributed System? 分布式系统是为了软件容灾设计的，它需要用多个副本(replica)来对同一个软件进行故障冗余。

但副本之间要保持它们互相之间都可以用作备份，也就是说要求它们都是一样的。这其实就是分布式共识（distributed consensus）最朴素的理解和定义. 即: 2个 replica 上的 state machine 一样.

但在软件工程中, 我们实际上要不断改变系统(state-machine)里的某些变量, 从而让系统状态不断向前推进.

因此, 在一个系统里, 我们所说的"一致", 是指这个系统 (也就是 state machine) 的多个 replica 都以相同的方式向前变化. 换句话说, 在多 replica 场景里, 一致就是 **monotonic**.

### replica 之间的 "一样"

distributed consensus 是通过让多个 replica 都运行一个独立的 state machine, 并要求所有 state machine 以相同的方式变化.

这里的"相同的变化"并不是指它们在某个时间点上完全相同, 而是指任意两个 state machine 的内部状态 sm1 和 sm2 有 **公共前缀**, 公共前缀部分就是 replica 之间提供的冗余, 一个 Distributed Consensus 的目的就是将 **公共前缀** 不停的扩大, 来完成 state machine 的推进. 因此, 在分布式系统里, replica 之间的 "一样" 是指:

- 2个 replica 上的 state machine 有公共前缀,
- 且公共前缀可以不断扩大.

然后我们来举个例子来说明这两点要求定义的"一样":

#### String state-machine

假设现在有一个简单的分布式系统, 它的 state 以 string 表示: state 最初是空字符串, 然后可以变成 a, 再变成 ab, 最后变成 abc, 这是一个单调变化 monotonic growth; 

- 如果2个 replica 上的state 分别为 `ab` , `abc`, 那么 `ab` 就是它们的 **公共前缀**, 也就是这2个replica达成一致的部分. 

- 如果2个 replica 上的state 分别为`ab` , `ax`, 那么`a`就是它们的**公共前缀**, 但剩下的部分, `ab` 和 `ax` 不再是前缀关系, 前缀不能再扩大了, 于是这2个replica产生了决定性的不一致, 无法维护一组互相备份的 state-machine了.

- 所以在这里例子里, **任意2个 replica之间要求一个是另一个的前缀**, 以满足replica之间的"一致"的要求.

注意 replica 之间的"一致" 还仅仅是 Consensus 的其中一个要求, Consensus 要求的一致还包括读写之间可见性的保证等, 我们后面继续说.

现在我们先讨论replica之间的一致性要求.

## monotonic growth 的核心形态

在软件实现中, 我们一般都把 state machine 对等定义为一些列操作日志 logs, 一个 log 序列对应一个唯一的 state machine 状态, 这也是 Raft 实现的理论基础, 通过复制 logs 的方式实现 state machine 的复制. 

在 distributed system 里, 我们无法直接保证每个 state machine 的 logs 都以 互为前缀的 的方式向前推进, 即 replica A 上的 log 可能是 `[x,y]`, replica B 上的 log 可能是 `[x,z]`, 因为分布式系统要求系统必须能在部分replica 宕机时也能工作, 所以理论上无法保证每个 replica 上经历的状态都是前缀关系. 这里注意, Raft 本身也没有保证这一点, 它只保证了 committed logs 的 monotonic growth, 而未 committed 的 log 是会发生回退的, 例如在leader切换时. 

所以我们不假设log的线性结构, 线性本身也不是问题的本来样子. 我们允许log是树形结构.

因此, distributed consensus 的核心是一个树形结构, 而这棵树会保持 monotonic growth.

### 树, 而不只是 log

这里提前说一下: Raft 做了一个简化: 它给人的印象是, 维护了一系列 log, log 像字符串一样向前线性增长. 但实际上, 它的内部隐藏形态是一棵树. 这棵树可以产生分支. 文章最后我们会讲到 Raft 隐藏的 grow-only tree 如何映射会线性 logs

这个grow-only tree 不仅是 Raft 内部的核心形态, 也是 distributed consensus 的核心形态: 我们可以把任何 distributed consensus 都想象成一个可以产生分支的树形结构.

TODO: 画一张包含三个 state machine 的树形图. 每个 state machine 内部存储一棵树; 这棵树可以添加不同的分支, 但只能添加, 不能删减.



>  更进一步 distributed consensus 的核心 state machine 可以被理解成一个 DAG 网状结构, 而不仅是一个 tree. 这个网状结构也是 grow-only 的, 不会删除节点和分支, 只会增加. 但我们本文只讨论 tree, 因为它已经足够可以来描述Paxos和Raft了.



## state machine 的定义

前面对 state-machine 做了直观地介绍, 现在来明确定义一下: 本文后面所提到的 state machine 内部是一棵树, 树有一个空的根节点, 树上其他节点包含一些修改 state 的 command, 所以我们本文中就认为 state machine 就是 这个 tree.

这是本文的第一个约束, **`cm1-history-tree`**: state machine 的状态是一棵树.

从这里开始, 我们把树上的每个节点称为一个 TimePoint. 严格地说, TimePoint 是tree 上节点的唯一标识.

之所以叫作 TimePoint, 是因为它不只表示节点在树上的位置, 还表示系统历史中的一个时刻. 后面会提到, 这种顺序定义了事件发生的先后关系, 因而也定义了系统中的虚拟时间.

我们对 state machine 进行修改的操作, 就是在 tree上添加一个分支并到达一个新的 TimePoint. 每个 TimePoint 对应的节点都可以包含与 state machine 业务相关的指令, 也就是 command.

TODO: 加图

### 只添加, 不删除

第二个约束, **`cm2-grow-only`**: state machine 只允许添加 TimePoint, 不能删除或修改已有的 TimePoint. 满足 `cm2-grow-only` 约束, 就可以保证replica 之间的公共部分逐渐增加, 进而完成系统冗余的推进.

TODO: 添加一张展示树形结构 replication 过程的图.



## TimePoint 必须全局唯一

在一个分布式环境里, 我们必须假设有多个写入者(writer) 正在试图向一个或多个replia写如新的状态(对 state machine 的 grow-only tree 增加一个新的分支和TimePoint节点), 因此这就要求每个writer必须不能产生同样的TimePoint 节点. 

例如, writer-1 对一个 replica 写入 `[a->b]`, writer-2 对另一个 replica 写入 `[x->y->b]`, 如果`b` 在这两次写入都用了相同的标识, 系统就产生了一个无法兼容的冲突, 后续任何在 `b` 后面追加的tree分支都没有公共部分, 就是说replica 无法互相作为可以替代的副本了. 

所以这里引入第三个约束, **`cm3-unique-timepoint`**: 每个 writer 尝试向 repclia 的 state machine 写入新数据时, 产生的 TimePoint (tree 上的vertex的id)都必须不同.

如果 TimePoint 相同, 就可能覆盖之前的数据或产生冲突. TimePoint 覆盖违背了前面提到的"state machine monotonic growth"原则.

因此, `cm3-unique-timepoint` 约束要求: 每个 TimePoint 都必须全局唯一.

TODO: 添加一张图, 展示 TimePoint 冲突如何造成状态覆盖, 从而违背树形结构 monotonic growth 的原则.

> - 在 Paxos 里, TimePoint 就是 ballotNumber, Paxos也要求BallotNumber全局唯一.
>
> - 在 Raft 里, TimePoint 对应 `(term, voted_for_node_id)`, 它也是全局唯一的.

现在我们定义好了数据结构, 接下来我们介绍读写流程.

## commit 的定义

### 从 fault tolerance 到 quorum

分布式系统要求整个系统具备一定的冗余, 也就是 fault tolerance 能力. 例如, 当一个由三个 replica 组成的系统中有一个 replica 发生故障时, 我们仍然能够读到数据. 为此, 我们需要引入 quorum 的概念, 进而引入 commit 的概念.

commit 的概念非常直接: 当writer按照**一定的约束**写入数据后, 以后的reader总能通过**特定的方法**读到这些数据, 即, 写后可读.

这里已经无须再讨论数据覆盖的问题, 因为 `cm2-grow-only` 和 `cm3-unique-timepoint` 约束保证了任何写入都不会覆盖已有数据. 我们只需要保证发生故障时——也就是reader无法看到系统全貌时——仍然能够读到想要的数据.

这要求读写之间存在一个约定, 这个约定就是 quorum write 和 quorum read:

1. writer 写入时, 必须写入某个指定的 replica 集合, 才能认为写入成功. 这个集合就是一个 `WriteQuorum`.
2. reader 读取时, 必须读取某个指定的 replica 集合, 才能认为一定能读到已写入的数据. 这个集合就是一个 `ReadQuorum`.

`WriteQuorum` 和 `ReadQuorum` 是一对相互约束的集合. 这第四个约束, **`cm4-quorum-intersection`**: 任何一个 `WriteQuorum` 都必须与任何一个 `ReadQuorum` 有交集; 交集中的 replica 保证写入的内容一定能被读到.

> - 最常见的配置是: 假设有三个 replica, 那么 `WriteQuorum` 是任意两个 replica, `ReadQuorum` 也是任意两个 replica.
> - 也存在一些不太常用的 quorum 配置. 例如, 假设 cluster 有四个 replica, `WriteQuorum` 可以是任意三个 replica, `ReadQuorum` 可以是任意两个 replica. 
> - 同样, 在四 replica 系统中, 也可以把 `WriteQuorum` 定义为一个 replica, 把 `ReadQuorum` 定义为四个 replica. 这些配置都满足 `cm4-quorum-intersection` 约束.

### 多历史 commit

有了 `cm4-quorum-intersection` 约束, commit 的定义也就自然出现了: 一个写入把新 TimePoint 写到一个 `WriteQuorum`, 就是 committed. 由 `cm4-quorum-intersection` 约束, 之后任何 `ReadQuorum` 的读取都一定能看到它.

注意, 这个定义对 TimePoint 的没有提任何要求: 树上的任何分支都可以继续生长, 任何写入只要写完一个 `WriteQuorum` 就不会丢失, 也一定能被读到. 我们把它称为**多历史 commit**, 到目前为止的系统就是一个**多历史consensus**——树上允许多条历史同时生长. 后文把系统约束到单一历史时, commit 会获得一个更强的形式.

TODO 加图

> 

## 完整的多历史 consensus 框架

### 四个约束

现在, 我们对整个系统有了四个基本约束:

1. `cm1-history-tree`: state machine 是一个树形结构.
2. `cm2-grow-only`: 树形结构只能添加 TimePoint, 不能删减.
3. `cm3-unique-timepoint`: 不同 replica 在树上产生的 TimePoint 不能冲突, 全局唯一.
4. `cm4-quorum-intersection`: 任何 `WriteQuorum` 与任何 `ReadQuorum` 都有交集; 写完一个 `WriteQuorum` 就是多历史 commit.

有了这四个约束, 我们其实已经得到了一个完整, 可行的多历史框架: 任何写入都不会丢失, committed 的写入一定能被读到. 后文把它约束成单历史之后, 就得到 Paxos 和 Raft 的抽象形态.

这个多历史框架比 Raft 和 Paxos 更通用, 也更简单. 但要求应用处理多分支历史. 它之所以简单, 也是因为它采用了多历史分支的结构. 相反复杂的地方都来自于线性logs的单历史 consensus.

所以 Paxos 和 Raft 看起来更复杂, 它们要求引入一个机制如何在多个历史分支中确定的选择一个作为当前状态, 多历史分支的 state machine 本身没有这个复杂性.

### 多历史 consensus 的一个具体的读写流程

下面给出一个可用的读写流程(但并不是唯一的), 具体步骤如下:

1. read phase: 选择一个 `ReadQuorum` replica 集合, 从中读取每个 replica 上的 grow-only tree 结构.
2. 合并与生成状态:
   1. 对所有读取结果取 union. 因为系统是 monotonic growth 的, 所以可以直接取 union, 不会产生任何数据覆盖.
   2. 把确定后的 union 作为系统的当前状态.
   3. 在合并后的数据结构上添加一个新的 TimePoint. 这个 TimePoint 对应的节点包含业务所需的数据, 例如要执行的 command, 并且必须满足 `cm3-unique-timepoint` 约束.
   4. 这时——假设它是单进程——在内存中维护并准备提交的状态.
3. write phase: 把新生成的状态写入一个 `WriteQuorum`. 由于 TimePoint 不会重复, 新状态不会覆盖各 replica 上的已有数据. 每个 replica 收到写入请求后, 直接合并本地的`tree`和接收到的`tree'`, 再将结果存储起来.

这是多历史框架的一套完整业务流程. 注意它不需要任何并发控制: 由 `cm2-grow-only` 和 `cm3-unique-timepoint` 约束, 并发 writer 各自追加各自的 TimePoint, union 合并永远不会冲突.

TODO: 添加几张图片和相应说明, 展示几种不同的读写并发执行流程.

## 现实中为什么不使用这种多历史模型?

现实中, 我们不会直接使用这个多历史框架进行业务读写, 因为它是一种抽象的数学结构, 实际使用起来不太方便.

### 多历史并存

这个模型不好用的原因是它采用了树形结构. 换句话说, 系统状态是多个状态叠加在一起的. 描述系统 state machine 的模型是一棵树, 每个分支都代表一段历史; 如果这棵树存在多个 leaf TimePoint, 它呈现的就是多段历史并存的状态.

> 也许这个多历史分支的模型其实能更好的描述我们的现实?

### 从多历史到单历史

这种结构的核心问题就是多历史并存. 如果我们容忍并允许使用这种数据结构描述系统, 就必须处理多段历史并存的状态. 这在工程上既不实用, 也不容易使用.

所以下一个问题是如何把它变成单历史的数据结构. 换句话说, 工程实现需要能够从中选择唯一的分支. 这是在前面讨论"一致"和 monotonic 的基础上引入的新问题. 后文把满足这个要求的系统称为**单历史框架**.

为了方便工程使用, 我们还需要让不同 replica 或者整个系统按照一种确定的方法, 选择某一段历史作为系统状态. 这样就可以避免整个系统呈现树形结构和多历史叠加的状态.

这有点像量子态的坍缩: 我们用一种方法观察系统, 然后确定它的当前状态. 在这种观测方法实施之前, 系统可以处在多历史叠加的状态.

我们把上面建立multi history的约束用`cm*-`命名, 后面是建立single history将引入的新的约束, 我们将用`cs*-`来命名.

## 确定地选择一条历史分支

前文说到, reader读取时, 我们会从由多个 replica 组成的 `ReadQuorum` 中读出多个数据状态, 再把它们合并成一个多分支的数据. 现在, 为了让所有 reader (以及一个reader的多次选择)面对同一个多分支tree时都能得到一个确定的结果, 才能保证读操作是确定的. 因为才单历史下, 选择一个分支就代表放弃其他分支作为系统的一部分, 如果两次选择不同, 呈现出来的结果就是数据丢失.

这说明, 对于任意2个分支 `a` 和 `b` , 任一个 reader 都确定的选择一个`a` 或`b`, 这说明`a`和`b`之间存在一个偏序关系, 即认为被选的较大, 没被选的较小.

#### 分支间是偏序关系而不是全序关系的原因:

这里最简单的想法是认为2个 分支之间是全序关系. 但这里还只要求分支之间只需是偏序关系, 因为如果`a`和`b`无法比较大小, 就无法选任何一个, 无法完成read操作, 那么也不会造成读到不一致的结果, 系统仍是正确的.

### TimePoint 之间形成 partial order

分支的先后关系定义了 TimePoint 的 partial order. 同一分支上的两个 TimePoint 一定可以比较先后(显然), 不同分支上的 leaf TimePoint 则可能彼此不可比.

现在reader可以确定的选择了, 那么写入`WriteQuarum`的一个分支就一定可被读到了. 但也引入了另外一个问题, 即如果写入的分支的TimePoint较小, 那么可能不被reader进程选择, 那么就想当于数据丢失了.

这是在单历史框架里, commit 所需要另一个更强的条件, **`cs1-global-max`**, 也是**单历史 commit** 的定义: 一个写入除了完成多历史 commit (写完一个 `WriteQuorum`), 它的 TimePoint 必须**全局最大**: 即必须大于所有replica上所有分支的 TimePoint. writer 无法直接观测全局; 后文的 `cs3-write-fence` 约束将保证: 视图之外的冲突写入要么自己无法完成, 要么会让当前写入在写入阶段被拒绝.

单历史 committed 的 TimePoint 必须与其他每个 leaf TimePoint 都可比大小(必须可以比较reader才能完成) 并且是整个 partial order 中唯一最大的 TimePoint.

注意, 这里的要求是: TimePoint 仍然可以是Partially ordered, 但是所有被用作树上节点的TimePoint必须是全序的, 或者说节点 TimePoint是一个Totally ordered子集, 而Partially ordered全集的定义还保留, 后面会用在 `cs3-write-fence` 里.

### 选择单历史带来的状态丢失

现在还有另一个问题, 因为我们只选择读到的树形结构中的一条分支作为系统的当前状态, 所以相当于抛弃了另外一些状态, 而我们的写入要求下次读取时一定选择我们写入的分支, 那么要保证之前committed的数据还被读到, 就要求写入时必须包含所有之前已经committed数据, 即写前需要进行一次quorum-read, 基于read选择的最大分支上进行追加新的TimePoint 节点.

### 在已经读到的分支上追加

这就是为单历史框架引入的第二个约束, **`cs2-extend-read-branch`**: 所有变更都必须在之前可能已经被读到的分支上追加. 这条约束就是 Paxos Made Simple 里的条件 P2c, 在 Raft 中体现为 Leader Completeness.

读取流程会先执行一次 quorum read, 得到一个合并的tree. 注意, 读取者无法直接判断哪个分支已经 committed——某个 leaf 分支的写入是否覆盖了完整的 `WriteQuorum`, 是发生在读取者视图之外的事件. 因此可执行的规则是: 选择最大 leaf 所在的那条分支. 最大 leaf 指与视图中其余每个 leaf 都可比且更大的 leaf, 存在则唯一. 这个规则不会选错: 若存在已经完成单历史 commit 的分支, 由 `cs1-global-max` 和 `cm4-quorum-intersection`, 它或它的后代必然就是任何合法视图中的最大 leaf, 所以按最大 leaf 选择永远不会丢掉 committed 的分支. 还有一种情况: 视图中不存在最大 leaf, 只有多个互不可比的极大 leaf (极大指没有其他 leaf 比它大, 偏序下可能同时有多个). 此时可以断定它们都还没有完成单历史 commit——committed 的 leaf 必然大于所有与它共存的 leaf——所以任选一个极大 leaf 的分支都不会丢失 committed 数据. Paxos 和 Raft 的实例中 leaf 是全序的, 最大 leaf 总是存在, 不会出现这种情况.

一个 read 操作会选择这个最大 leaf, 把它所在的分支作为当前的历史状态. 这个状态可能已经被读到, 所以下一次读取仍然必须选择最大 leaf, 才能保证前后两次读取结果一致.

之后, 只有在这个可能已经被看到的分支上继续追加历史, 再增加一个满足 `cs1-global-max` 约束的新 TimePoint (大于其他所有 leaf TimePoint), 才能完成单历史 commit, 并保证下次读取时不会发生状态丢失.

这就是 Raft 在 leader election 时必须先联系一个 quorum, 并且只允许持有最大 log 的 replica 成为 leader 的原因. 后文"读取的映射"一节会看到, "最大 log"比较的是分支的 leaf TimePoint, 它是对"读取并合并"这一步的简化.

## Atomic read-then-write

### 并发产生的问题

读者现在肯定已经看到了另一个问题. 这个方法在没有并发 writer 时是正确的, 但整个读写过程需要在 distributed system 中的多个 replica 上执行, 因而存在时间延迟. 在此期间, 其他读写者可能正在执行相同的操作.

也就是说, 我们读到了一个最大的分支, 但等到写入时, 这个最大分支可能已经发生了变化.

为了保证方法能够正确执行, 还需要增加单历史框架的第三个约束, **`cs3-write-fence`**: 

- writer 在读取之前先确定自己要写入的 TimePoint, write前的读取因此也带上了这个 TimePoint: `t₀`
- 读取之前, 必须让一个 `ReadQuorum` 中的每个 replica 先记录这个 TimePoint `t₀`, 并从此拒绝 TimePoint 不大于等于 `t₀` 的写入: 拒绝 `t: !(t >= t₀)`(注意这里TimePoint是偏序的, 所以不能简化成: 拒绝`t: t < t₀`; 随后这这个 replica 上进行一次读操作. 这样, "先读后写"在每个 replica 上和全局上都成为一个原子操作.

这个步骤对应 Paxos 的 prepare phase, 也就是第一阶段, 或者 Raft 的 RequestVote phase. 这两个步骤做的是同一件事: 把当前 writer 的 TimePoint 发送给一个 `ReadQuorum`, 再让 `ReadQuorum` 中的 replica 拒绝其他`!(t >= t₀)` 的 TimePoint 的写入(或: 拒绝小于`t₀`的写或无法比较的写).

### 单历史框架的三个新约束

至此, 在多历史框架的四个约束 (`cm1-history-tree`, `cm2-grow-only`, `cm3-unique-timepoint`, `cm4-quorum-intersection`) 之上, 单历史框架增加了三个约束:

1. `cs1-global-max`: 单历史 commit 除了写完一个 `WriteQuorum`, 新 TimePoint 还必须大于全局所有其他 leaf TimePoint.
2. `cs2-extend-read-branch`: 所有变更必须在之前可能已经被读到的分支上追加.
3. `cs3-write-fence`: 读取之前, 先让同一个 `ReadQuorum` 记录 writer 的 TimePoint 并拒绝其他 writer 不大于它的写入; 读取必须发生在这组 replica 记录禁写之后.

这七个约束合起来, 就是完整的单历史 distributed consensus, 也就是 Paxos 和 Raft 的抽象形态. 

### 完整的写流程

现在的读写流程一共包含 2 个阶段: 第 1 阶段在一个 `ReadQuorum` 上先设置 write fence, 保证读到的数据不再被更改, 然后在同一组 replica 上读取并合并; 第 2 阶段选择一个 `WriteQuorum`, 写入新的 history tree.

#### 第 1 阶段

第 1 阶段先选择当前 writer 的 TimePoint `t₀`. 这里不假设所有 TimePoint 具有 total order; 只有当后续步骤确认它满足 `cs1-global-max` 约束 (大于其他所有 leaf TimePoint) 时, 才能继续 commit.

然后选择一个 `ReadQuorum`, 让这个 `ReadQuorum` 中的每个 replica 记录 `t₀`. 后续必须拒绝 `t: !(t >= t₀)`写入, 包括更小, 相同或者与它不可比的写入. fence 记录本身需要两条维护规则: 每个 replica 只保留一个 fence TimePoint, 因为仅当新的 fence 请求带来严格更大的 TimePoint 时才替换并应答 即只接受`t: t >= t₀`; 并且 fence 记录必须持久化, 否则 replica 重启后保护消失. Raft 的 `currentTerm` 加 `votedFor` 正是这条规则的实现.

`ReadQuorum` 中的每个 replica 记录 fence 之后, 再读取它的 state machine tree, 然后reader合并所有读到的 tree. 接着根据已定义的 partial order, 选择最大 leaf 所在的分支作为待写入的分支.

此时还要比较将要写入的 TimePoint 与所有 leaf TimePoint:

1. 如果它大于其他所有 leaf TimePoint, 就可以继续追加.
2. 如果存在一个 leaf TimePoint 不小于它, 或者与它不可比, 就不能继续.

#### 第 2 阶段

第 2 阶段是把追加后的树形结构发送给选定的 `WriteQuorum`, 让它们接收.

1. 如果当前 TimePoint 满足 `cs1-global-max` 约束 (大于其他所有 leaf TimePoint), 并且一个 `WriteQuorum` 没有拒绝当前写入, 就认为写入成功, 完成单历史 commit. 之后的 read 一定能够看到它, 而且它是 partial order 中最大的 TimePoint, 所以这个分支一定会被看到.
2. 如果写入被拒绝, 就说明已经有另一个 writer 的 TimePoint 使当前写入不满足"大于其他所有 TimePoint"的条件. 另一个 TimePoint 可能更大, 也可能与当前 TimePoint 不可比. 当前写入可能会在下次读取时被忽略, 所以不能认为这次写入成功, 必须放弃. 放弃后, writer 可以取一个更大的新 TimePoint, 重新走一遍两个阶段.

两个阶段全部完成后, 新的数据结构就被认为是 committed, 也就是完成了一次 distributed read/write.





## 映射到 Paxos 和 Raft

这个单历史 consensus 实际上包含了 Paxos 和 Raft 的全部功能, 但不包括 Raft 的 membership configuration.

虽然它们看起来并不相同, 但我们可以通过概念映射, 直接把这个框架映射到 Paxos 和 Raft 上. 也就是说, 这里提出的 distributed consensus read/write 流程是 Paxos 和 Raft 的 superset.

### TimePoint 和虚拟时间

我们的 TimePoint 对应 Paxos 的 BallotNumber, 以及 Raft 的 `(term, node_id)`. TimePoint 被定义为全局不可重复, 与 Paxos 对 BallotNumber 的定义相同.

Raft 做了一些简化, 所以这一点不太容易看出来. 实际上, `(term, node_id)` 合在一起形成一个 candidate ID. 它是全局唯一的, 与我们的 TimePoint 完全对应. Raft 中的 `(term, node_id)` 比较是partially ordered, term不一样则由term决定大小, term一样时, `node_id` 相同表示相等, 不同表示不能比较. 

这里提出一个观点: 整个系统实际上是一段由事件组成的历史, 而事件之间的顺序就是时间.

在这个 distributed consensus 中, TimePoint 决定了tree上节点的顺序, 它是这个系统中的虚拟时间. TimePoint 对应 BallotNumber, 也对应 Raft 中的 `(term, node_id)`; 它定义了事件(log)之间的先后顺序.



同样我们也可以看到, 在 Raft 的 election phase, 它要求一个  `ReadQuorum`, 接收 `(term, node_id)`时, 同样, 使用的是Partially ordered 的比较: 

- 较小term的 VoteRequest会被拒绝,
- term相同时, 拒绝`node_id`不同的请求.

### 两个阶段的映射

我们的框架分为两个阶段:

- 第 1 个阶段: 先禁止写入, 再读取.
- 第 2 个阶段: 写入.

第 1 阶段对应 Paxos 的 prepare phase (Phase 1) 和 Raft 的 election phase. 当然, Raft 的 election phase 还完成了其他工作. 禁写和读取必须落在同一组 replica 上, 而且每个 replica 都要先记录禁写, 再被读取, 所以两者天然合并在同一条消息里: Paxos 的 prepare 应答就同时完成了记录 BallotNumber 和返回已 accept 值这两件事.

在我们的设计中, 第 1 阶段的禁写步骤禁止其他 writer 发起且 TimePoint 不大于当前 writer TimePoint 的写入, 也就是:

1. 禁止更小, 相同或不可比 TimePoint 的读写. Paxos 的 BallotNumber 具有 total order, 这个约束直接通过比较大小实现. Raft 的 `(term, node_id)` 是 partial order: 拒绝更小的 TimePoint 就是拒绝更小的 term, 拒绝不可比的 TimePoint 就是同一 term 内至多投一票.

可以看到, Raft 实际上使用并体现了它对虚拟时间的定义, 也就是 `(term, node_id)`. 它通过比较这个值来判断新的 leader 是否合法.

### 读取的映射

在我们的系统中, 第 1 阶段的 quorum read 对应 Paxos 对 prepare 的应答: 它把 `ReadQuorum` 中的值拿到本地, 然后进行比较.

Raft 没有把值读取回来, 而是用一个取巧的办法省掉了这次读取. 要解释它, 先把 Raft 简化一下: 我们不直接映射到完整的 Raft, 而是先映射到一个简化的 Raft——每个 term 里只有一条 log, leader 当选后只 propose 这一条 log 就结束生命周期, 要写入新数据必须重新选举. 真实 Raft 在一个 term 里连续写入多条 log, 可以看作对同一个 TimePoint 的细分; 先在"每 term 一条 log"的模型上建立映射, 再加回这个细分, 扩展是自然而直接的.

在简化的 Raft 里, 一个 replica 的整条 log 就是树上的一条分支, 它的 last log 就是这条分支的 leaf TimePoint. Raft 的 election 对应我们的第 1 阶段, 其中禁写和读取两个步骤比较的是不同的东西: 禁写步骤比较 writer 自己的 TimePoint, 也就是 candidate 的 `(term, node_id)`; 读取步骤比较的是双方已经持有的 leaf TimePoint, 也就是 last log.

读取步骤的取巧在于: candidate 不把每个 replica 上的分支读回来合并, 而是让每个 voter 拿 candidate 的 last log 与自己的 last log 比较, candidate 的更小就拒绝投票. 于是能凑齐 `ReadQuorum` 的 candidate, 本地 log 必然不小于 quorum 中每个 replica 的 log——它已经持有 quorum 视图中最大的分支, 读取与合并因此可以省去. 省去读取是安全的, 因为 commit 规则保证任何大于 committed leaf 的新 TimePoint 都只能追加在 committed 分支上, 所以持有最大 leaf 的 candidate 必然已持有全部 committed 数据. log 较小的 candidate 凑不齐 quorum, 效果上等于放弃 election, 最终由持有最大 log 的 replica 当选.

再看这个比较用的值. leaf TimePoint 完整写出来是 `(last log term, last log node_id, last log index)`: 前两项标识产生这条 log 的 leader, index 是同一 term 内的细分. 由于每个 term 至多选出一个 leader (majority 两两相交, 加上每个 replica 在一个 term 里至多接受一个 candidate), term 唯一确定了写这条 log 的 node, 中间的 node_id 可以省去. 省去之后, 剩下的就是 Raft 论文里 election 时比较的 `(last log term, last log index)`.

这也解释了 `RequestVote` 的参数为什么恰好是 `term, candidateId, lastLogTerm, lastLogIndex` 这四个字段: 前两个用于禁写步骤的 TimePoint 比较, 后两个用于读取步骤的 leaf 比较.

实际上, 终止 election 或者把状态读取回来合并, 这两种设计都是可以的; Raft 选择了前者.

### 映射到 Paxos

我们的系统使用树形结构, 但 Paxos 只允许每个 replica 保存一个 value 以及一个 v-BallotNumber, 也就是这个 value 对应的 BallotNumber.

对应到我们的数据结构, Paxos 做了一个简化: 它允许整棵树没有链式 TimePoint, 但可以存在多个 TimePoint. 也就是说, Paxos 只允许根节点连接到树上的其他一些 TimePoint, 而不允许 TimePoint 继续连接新的 TimePoint.

v-BallotNumber 就是树上的一个 TimePoint, 再加上这个 TimePoint 对应的节点所包含的内容. 还要注意, acceptor 接受更高 BallotNumber 的 accept 时会替换本地保存的 value; 这与 `cm2-grow-only` 并不冲突——和后文对 Raft log 截断的理解一样, 被替换的旧值在全局树中仍然存在, 只是不再存于这个 replica, 变得不可见.

### 映射到 Raft

在 Raft 中, 树上的一个 TimePoint 对应一段同 term 的 log, 而这个 TimePoint 对应的节点内容则对应这段 log 本身. 段内的每条 entry 由 index 区分, 是对这个 TimePoint 的细分——这就是把前文"每 term 一条 log"的简化 Raft 扩展回真实 Raft 的方式.

这里需要注意一点: 虽然 Raft 在工程设计上只有一条单链历史, 但我们可以把它理解为同样存储了一个树形结构, 只是那些不需要被读取的 TimePoint 直接变得不可见.

当我们认为 Raft 也存储了一棵树, 只是不允许其中一些 TimePoint 可见时, 它就与我们的系统直接对应起来了.

TODO: 添加一张图, 展示 Raft 在 leader election 过程中, 一次写入没有提交, 新 leader 出现并导致状态回退时, 实际上隐藏了一个 TimePoint 的过程.

### 写入阶段的映射

最后的写入阶段最简单.

写入时, 我们把新状态写到每个 replica 上, 再判断当前写入是否被标记为禁止:

1. Paxos 的第二阶段: 写入时比较 last BallotNumber, 检查 Paxos 的 accept 请求是否被禁止.
2. Raft: 判断 term. 如果 replica 存储的 term 大于请求中的 term, 就表示禁止写入.

这三个行为相互对应. 检查通过后, 直接把数据记录到系统中并应答成功.

同样, 三个系统都要求待写入的 TimePoint 满足 `cs1-global-max` 约束 (大于其他所有 leaf TimePoint), 并写入一个 `WriteQuorum`, 也就是完成单历史 commit.

## Raft 的其他工程设计

为了工程实现, Raft 还增加了一些设计.

在我们的系统中, writer 会把整棵树发送到每个存储 replica 上. Raft 不能这么做, 因为它假设 log 量非常大, 所以需要逐段发送.

逐段发送可以被理解为分段发送 tree 的过程. snapshot 也可以被理解为发送整棵树时采用的一种工程优化.

## membership configuration

Raft 还支持 membership configuration 变更.

在我看来, membership configuration 并不是 distributed consensus 的核心问题, 而是一个与上述流程完全正交的概念. 它只与 read quorum 和 write quorum 相关, 约定了如何设置 `ReadQuorum` 和 `WriteQuorum`, 从而保证相邻的两次读写能够彼此看到.

成员变更实际上比较简单: 一次写入使用某个 write quorum 后, 后续使用的 read quorum 必须与这个 write quorum 有交集.

注意: 这里要求这个 write quorum 与之后所有读取它的 read quorum 都有交集.

但是, 这会带来一个问题: 经过多次 membership configuration change 后, 我们不知道之前使用过哪些 write quorum, 也不知道之后会使用哪些 read quorum.

成员变更 (membership change) 实际上是把一组 read quorum 和 write quorum 对变成另一组.

为了解决这个问题, Raft 做了一个优化: 新的 write quorum 必须包含之前所有 write quorum 已经写入的内容. 这样, 我们只需要保证相邻两个 membership configuration 之间的 read quorum 和 write quorum 有交集.

也就是说, 在 Raft 的实现中, 前一个 membership configuration 必须 committed, 然后才能 propose 下一个 membership configuration.
