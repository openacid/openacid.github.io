# 《Raft 的直观解释》正确性 review

Review 对象: [2026-08-08-raft-intuitive-cn.md](./2026-08-08-raft-intuitive-cn.md)

## 结论

当前版本需要 major revision 后再发布.

把所有可能出现过的历史表示成一棵只增长的树, 可以作为作者自定义的理解模型.但文章目前把这个模型进一步表述成 Raft 和 Paxos 的实际结构或直接等价模型, 因而产生了多处事实性错误.最严重的问题集中在 Raft election, `(term, node_id)`, commit 规则, Paxos prepare/accept 和 membership configuration.

以下行号以本次 review 时的原文为准.

## Blocker

### 1. consensus 不能定义为 monotonic

位置: 42–58.

文章把 distributed consensus 概括成“某个东西不变”以及“一致就是 monotonic”.这不是 consensus 的定义.Paxos 的核心 safety 要求是只能选择被提议的值, 只能选择一个值, learner 不能学到一个实际上没有被选择的值; replicated state machine 还要求所有 replica 按相同顺序执行相同 command.状态或历史的 monotonic growth 最多是某种表示方式的性质, 不能替代 agreement, validity 和 liveness.

修改方向: 先用 agreement 和 replicated command sequence 定义 consensus, 再把 monotonic tree 明确引入为本文使用的辅助模型.

依据: [Paxos Made Simple, §2.1 和 §3](https://www.microsoft.com/en-us/research/uploads/prod/2016/12/paxos-simple-Copy.pdf), [Raft extended paper, §2](https://raft.github.io/raft.pdf).

### 2. “Raft 实际上存储一棵只增不删的树”与协议不符

位置: 64–76, 90–120, 351–376.

Raft 的每个 replica 实际存储线性 log.只有 leader 具有 append-only property; follower 收到冲突 entry 时会删除冲突 entry 及其后缀, snapshot 也会丢弃已经压缩的 log prefix.未 committed 的 entry 可以在 leader change 后被覆盖, 所以“所有状态都不会丢失”和“数据也不会丢失”只对 committed state 才能成立.

树模型仍然可以保留, 但必须定义成“观察者保存的所有历史分支的概念性并集”, 并明确它不是 Raft replica 的实际持久化状态.

依据: [Raft extended paper, Figure 2, Figure 3, §5.3, §5.4 和 §7](https://raft.github.io/raft.pdf).

### 3. Raft 不会选择 `(term, node_id)` 最大的 candidate

位置: 247, 263–267, 307–337.

`RequestVote` 虽然携带 `term` 和 `candidateId`, 但 voter 不会对 `(term, node_id)` 做大小比较.Raft 在同一个 term 内按先到先得的方式至多投一票, 同时要求 candidate 的 log 至少与 voter 的 log 一样 up-to-date; log freshness 比较的是 `(lastLogTerm, lastLogIndex)`.因此“只允许 `(term, node_id)` 最大的 replica 成为 leader”以及“较小的 replica 放弃 election”都不属于 Raft.

修改方向: 删除以 node ID 打破同 term candidate 顺序的映射, 改为 term, one-vote-per-term, majority 和 log freshness 四个条件.

依据: [Raft extended paper, Figure 2, §5.2 和 §5.4.1](https://raft.github.io/raft.pdf).

### 4. `(term, node_id)` 不能同时充当每个 log entry 的 TimePoint

位置: 263–267, 307–315, 349.

同一个 leader 可以在同一个 term 内创建多个 log entry, 因此这些 entry 具有相同的 `(term, node_id)`.这个 tuple 可以标识某个 term 中的 candidate 身份, 却不能唯一标识 log entry.Raft log entry 的协议位置由 `index` 和 `term` 描述; Figure 2 的 `RequestVote` 也分别传递 `candidateId`, `lastLogIndex` 和 `lastLogTerm`.

修改方向: 把 election identity 和 log entry identity 拆成两个概念.如果 TimePoint 表示 log entry, 不能再把它直接等同于 `(term, node_id)`.

依据: [Raft extended paper, Figure 2, §5.2 和 §5.3](https://raft.github.io/raft.pdf).

### 5. Raft election 不是 Paxos prepare 的直接实现

位置: 257–267, 325–337.

Paxos prepare 会让 acceptor 对更小 BallotNumber 作出 promise, 并返回自己已经 accept 的最高编号 proposal.Raft `RequestVote` 返回的是 vote, 不会把已接受的 value 或完整 log 读回 candidate; 它通过 one-vote-per-term 和 log freshness restriction 保证新 leader 包含 committed entries.二者承担了部分相似的 safety 职责, 但消息语义和状态转换并不等价.

修改方向: 将“直接对应”降级为“作用上的类比”, 然后分别说明两种协议实际检查和返回的字段.

依据: [Paxos Made Simple, §2.2](https://www.microsoft.com/en-us/research/uploads/prod/2016/12/paxos-simple-Copy.pdf), [Raft extended paper, Figure 2 和 §5.4.1](https://raft.github.io/raft.pdf).

### 6. 文中的 commit 条件不是 Raft 或 Paxos 的 commit 条件

位置: 143–157, 223–245, 277–297, 368.

“TimePoint 大于所有 leaf TimePoint, 再写入 `WriteQuorum`”可以是本文自定义模型的规则, 但不是三个系统共同使用的 commit 定义.Raft leader 通过把当前 term 的 entry 复制到 majority 来直接 commit 它, 更早 term 的 entry 随之被间接 commit.Paxos 中 value 在某个 proposal 被 majority accept 时 chosen.两者都不执行一次对全局所有 leaf 的最大值检查.

修改方向: 分别定义“本文模型中的 committed”, “Paxos chosen”和“Raft committed”, 再证明模型映射, 不能直接宣称三者条件相同.

依据: [Raft extended paper, §5.3 和 §5.4.2](https://raft.github.io/raft.pdf), [Paxos Made Simple, §2.2](https://www.microsoft.com/en-us/research/uploads/prod/2016/12/paxos-simple-Copy.pdf).

### 7. 四个约束不足以构成一个完整 consensus protocol

位置: 148–183, 249–297, 301–303.

当前框架没有完整说明 failure model, quorum family 的交集条件, promise 是否持久化, crash recovery, retry/idempotency 和 liveness, 因而不能据此得出“完整,可以工作”或“Paxos 和 Raft 的 superset”.还有三个直接的内部缺口:

1. phase 0 禁止“不大于”当前 TimePoint 的写入, 包括相同 TimePoint; 如果 phase 3 使用同一个 TimePoint, replica 也会拒绝当前 writer 自己的写入或 retry, 除非另行定义 owner exception.
2. 一次 `ReadQuorum` 只能看到与它相交的已完成写入, 不能直接证明当前 TimePoint 大于系统中所有可能存在的 leaf.
3. 对 command tree 取 union 只保证集合不覆盖, 不会自动产生所有 replica 都能按同一顺序执行的 command sequence.

修改方向: 把这部分降级为 design sketch, 或补充状态变量, transition, quorum intersection, durable promise 和 safety/liveness proof.

### 8. Paxos acceptor state 和 v-BallotNumber 的映射不正确

位置: 341–345.

Paxos acceptor 至少需要持久化已经响应过的最高 prepare number, 以及已经 accepted 的最高编号 proposal `(BallotNumber, value)`.v-BallotNumber 是 accepted proposal 的编号, 不是“TimePoint 再加上节点内容”.文章描述的 root-star tree 是作者模型, 不是 Paxos 的实际数据结构.

修改方向: 先准确列出 promised BallotNumber 和 accepted `(BallotNumber, value)`, 再单独说明如何把这些状态投影到树模型.

依据: [Paxos Made Simple, §2.2 和 §2.5](https://www.microsoft.com/en-us/research/uploads/prod/2016/12/paxos-simple-Copy.pdf).

## Major

### 9. quorum 的核心交集条件没有写出来

位置: 130–139, 211–213.

“`WriteQuorum` 和 `ReadQuorum` 相互约束”不够精确.至少要明确任意合法 `ReadQuorum` 都与任意合法 `WriteQuorum` 相交.如果模型还要串行化并发写入, 则必须说明 write/write 如何相交或由其他机制排斥.

四 replica 下 `WriteQuorum = 1`, `ReadQuorum = 4` 的确满足 read/write intersection, 但任何一个 replica 不可用都会导致 read 无法完成, 而且它本身不解决并发 writer 冲突.文章应明确这是安全性与可用性的极端取舍, 不是通常意义上的 fault-tolerant 配置.

依据: [Weighted Voting for Replicated Data](https://www.andrew.cmu.edu/course/15-440/assets/READINGS/gifford79.pdf).

### 10. replicated log 与 application state machine 被混在一起

位置: 46–58, 68–72, 82–94.

Raft 中可能分叉的是尚未收敛的 replica log; application state machine 只按顺序执行 committed entry.不同 replica 的 raw log 在恢复完成前不一定互为前缀, 但已经 applied 的 command 必须满足 State Machine Safety.文章目前把 log, tree, state machine state 和所有历史分支当作同一个对象, 后续很多“不会丢失”和“取 union”的推论因此失去明确对象.

修改方向: 全文固定区分 conceptual history tree, per-replica log, committed log prefix 和 application state.

依据: [Raft extended paper, §2, Figure 3 和 §5.3](https://raft.github.io/raft.pdf).

### 11. “Paxos 是单值, Raft 是多值”缺少 single-decree 限定

位置: 30–36.

Basic/single-decree Paxos 决定一个值; Paxos replicated state machine 通过一系列 Paxos instance 决定 command sequence, 通常称为 Multi-Paxos.Raft 论文明确将 Raft 与 `(multi-)Paxos` 比较.当前写法容易让读者误以为完整 Paxos 只能决定一个值.

修改方向: 把此处的 Paxos 明确写成 single-decree Paxos, 并在后文映射前说明 Multi-Paxos.

依据: [Paxos Made Simple, §3](https://www.microsoft.com/en-us/research/uploads/prod/2016/12/paxos-simple-Copy.pdf), [Raft extended paper, Abstract 和 §3](https://raft.github.io/raft.pdf).

### 12. Raft write phase 不只检查 term

位置: 357–366.

`AppendEntries` 的确会拒绝小于 `currentTerm` 的请求, 但这只是第一项检查.它还必须验证 `prevLogIndex` 和 `prevLogTerm`; 遇到冲突时删除 follower 的冲突 suffix, 再追加新 entry.只写“判断 term, 检查通过后直接记录”遗漏了维持 Log Matching Property 的核心步骤.

依据: [Raft extended paper, Figure 2 和 §5.3](https://raft.github.io/raft.pdf).

### 13. membership configuration 不能简化成相邻 read/write quorum 相交

位置: 378–397.

Raft 论文中的安全目标是切换期间不能形成两个能够独立决策的 majority.其 joint consensus 同时包含 old 和 new configuration, election 与 commit 都分别要求 old majority 和 new majority; joint configuration committed 后才进入 new configuration.此外, replica 一旦把 configuration entry 加入 log, 就立即按最新 configuration 作决策, 并不是等该 entry committed 才开始使用.

相邻 quorum intersection 是解释的一部分, 但不足以替代 joint consensus 的规则.“完全正交”以及“只跟 read quorum 和 write quorum 相关”也过强, 因为 configuration entry, leader election, log replication 和 commit rule 都参与安全性.

依据: [Raft extended paper, §6](https://raft.github.io/raft.pdf).

### 14. snapshot 不是“发送整棵树”的普通优化

位置: 370–376.

Raft snapshot 的首要作用是 log compaction: 保存 application state 与最后包含的 index/term, 然后丢弃对应 log prefix.`InstallSnapshot` 可以把 snapshot 传给落后的 follower, 但不能把 snapshot 简化成发送概念性 history tree.

依据: [Raft extended paper, §7](https://raft.github.io/raft.pdf).

## Minor

### 15. 阶段编号前后不一致

位置: 269–297, 317–325.

正文标题依次是“第 0 阶段”“第一个阶段”“第三步”, 后文列表却是第 0,第 2,第 3 阶段.应先选定一套编号, 否则 Paxos Phase 1/2 与本文阶段无法稳定映射.

### 16. 一处对象名疑似写错

位置: 283.

“选择一个相同或不同的 Raft”按上下文应当是“选择一个相同或不同的 `ReadQuorum`”.

## 可以保留的核心思路

以下内容可以继续发展, 但要明确它们属于解释模型, 不是协议原始定义:

1. 把所有曾出现过的未 committed 分支保存在一棵概念性 history tree 中.
2. 用 TimePoint 表示历史事件, 用 partial order 描述部分事件的先后关系.
3. 用 quorum intersection 解释为什么新一轮操作能够接触到先前 committed state.
4. 把 Raft 的线性 committed log 解释成从多条候选历史中保留下来的单一可见历史.

建议重写时先完整定义这个抽象模型并证明它的 safety, 再分别建立到 Paxos 和 Raft 的映射.不要在模型尚未定义完时使用“就是”“完全对应”“完整形态”或“superset”这类等价性结论.
