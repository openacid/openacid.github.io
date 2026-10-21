---
title: "OpenRaft 自适应成员变更：新旧 quorum 相交时跳过 joint"
date: 2026-10-21
disabled_url: /distributed/raft-adaptive-config-change-cn/
draft: true
authors:
    - xp
categories:
    - distributed
tags:
    - raft
    - consensus
    - membership
mathjax: false
toc: true
toc_label: 本文目录
toc_sticky: true
description: "OpenRaft 的 change_membership() 现在只在新旧 config 不相交时才走 joint。joint config 的作用是把不相交的新旧 config 变成两个相交的步骤，新旧 config 本身相交时就不需要它。OpenRaft 用 maj(C0) + maj(C1) > |C0 ∪ C1| 精确判断两个多数派 config 是否相交，Raft 的“一次只变一个节点”是这个判断的简化版。"
---

![](raft-adaptive-config-change-banner-small.png)

OpenRaft 的 config change 按新旧 config 是否相交来选择变更路径。这里的相交指旧 config 的每个 quorum 都与新 config 的每个 quorum 至少共享一个节点。
- 相交时，`Raft::change_membership()` 只写一条新 config 日志；
- 不相交时，才经过 joint config，写两条日志。

这个做法基于两点。第一，joint config 的作用是把不相交的新旧 config 变成两个相交的步骤，新旧 config 本身相交时，就不需要 joint config。第二，OpenRaft 精确判断两个多数派 config 是否相交：两者相交，当且仅当两者的多数派大小之和大于两者并集的节点数，这个判断只需线性时间。Raft 的 [single-server change][ref-raft-dissertation]（下文称“一次只变一个节点”）是这个判断的简化版。

## 1. joint config 把不相交的 C0、C1 变成两个相交的步骤

下文把旧 config 记作 `C0`，新 config 记作 `C1`，joint config 记作 `C01 = [C0,C1]`，`C0` 与 `C1` 相交记作 `C0 ~ C1`。从 `C0` 直接切换到 `C1` 要求 `C0 ~ C1`，原因见[《Raft 成员变更：何时需要先提交 leader 的当前 term 日志》][post-raft-membership-log-barrier]（下文称上一篇）第 3 节。

**joint 变更由两次相交的切换组成，`C01` 是连接 `C0` 与 `C1` 的桥。** `C01` 的每个 quorum 都同时包含 `C0` 的一个 quorum 和 `C1` 的一个 quorum，所以即使 `C0` 与 `C1` 不相交，`C0 ~ C01` 和 `C01 ~ C1` 也总是成立。

```text
| joint 变更，两条日志：
|
|     C0 -----> C01 -----> C1
|        C0 ~ C01   C01 ~ C1
|
| C0 ~ C1 时，一条日志：
|
|     C0 ----------------> C1
```

`C0 ~ C1` 已经成立时，`C1` 自己就能完成连接，`C01` 只会多一条日志、多等一次提交。

跳过 joint 时，leader 还必须先提交一条自己 term 的日志，否则会出现[《Raft 成员变更上踩的坑》][post-raft-bug-cn]中的 bug，原因见[上一篇][post-raft-membership-log-barrier]。OpenRaft 本来就对所有成员变更这样要求：leader 当选后写下的第一条日志提交之前，成员变更会返回 `UncommittedLeaderLog` 错误。所以 OpenRaft 跳过 joint 时只需判断 `C0 ~ C1`。

## 2. C0 ~ C1 的精确判断：maj(C0) + maj(C1) > |C0 ∪ C1|

对两个多数派 config，记 `maj(C) = ⌊|C|/2⌋ + 1` 为 `C` 的多数派大小，则：

> **`C0 ~ C1` 当且仅当 `maj(C0) + maj(C1) > |C0 ∪ C1|`。**

计算只需要一次集合并，耗时与两个 config 的节点总数成正比。按定义检查则要枚举两边的全部 quorum，代价随节点数指数增长。

如果存在一对不相交的 quorum，它们互不重叠地落在 `C0 ∪ C1` 中，合计至少有 `maj(C0) + maj(C1)` 个节点，所以 `maj(C0) + maj(C1) ≤ |C0 ∪ C1|`。反过来，如果 `maj(C0) + maj(C1) ≤ |C0 ∪ C1|`，就能构造出一对不相交的 quorum：`C0` 的 quorum 先取只在 `C0` 中的节点，`C1` 的 quorum 先取只在 `C1` 中的节点，不够时再从两边共有的节点中取。这个不等式保证共有节点够两边分。

**Raft 的“一次只变一个节点”是精确判断的简化版。** 以增加一个节点为例，`C1` 就是两者的并集，`|C0 ∪ C1| = |C1| = |C0| + 1`。这时 `maj(C0) + maj(C1) = ⌊|C0|/2⌋ + ⌊(|C0|+1)/2⌋ + 2 = |C0| + 2`，大于 `|C0 ∪ C1|`，所以精确判断总是成立。删除一个节点时，交换 `C0` 与 `C1` 的位置，结论相同。反过来，精确判断还允许一部分一次变两个节点的变更：

| 变更                    | 精确判断                                                              | 一次只变一个节点 |
|---                      |---                                                                    |---|
| `{a,b,c} → {a,b,c,d}`   | 相交                                                                  | 允许 |
| `{a,b,c} → {b,c,d}`     | 不相交，`C0` 的 quorum `{a,b}` 与 `C1` 的 quorum `{c,d}` 没有共同节点 | 不允许 |
| `{a,b,c,d} → {a,b,c,e}` | 相交                                                                  | 不允许 |

精确判断比“一次只变一个节点”多允许的变更，只出现在两个 config 都有偶数个投票节点时。这样的变更共三种：替换一个 `{a,b,c,d} → {a,b,c,e}`，增加两个 `{a,b,c,d} → {a,b,c,d,e,f}`，删除两个 `{a,b,c,d} → {a,b}`。把两个 config 的节点数按奇偶分情况代入公式，就能验证只有这三种。生产集群通常有奇数个投票节点。在这些集群上，精确判断与“一次只变一个节点”允许的变更相同。

## 3. OpenRaft 的 change_membership() 只在 C0、C1 不相交时走 joint

[commit c90c6b53][commit-openraft-skip-joint] 之后，`Raft::change_membership()` 用 OpenRaft 依赖的 quorum 计算库 [quorum-set][repo-quorum-set] 0.3.0 中的 `bridge_to()` 选择下一条 config。当前 config 不是 joint config 时，`bridge_to()` 用第 2 节的精确判断。相交时，`bridge_to()` 返回目标 config，变更一条日志完成。不相交时，`bridge_to()` 返回 joint config `C01`，`change_membership()` 等它提交后再写目标 config。例如，3 节点集群一次替换全部节点 `{a,b,c} → {d,e,f}` 时，新旧 config 不相交，仍走 joint。

此前，只要投票节点有变化，`change_membership()` 就先写 joint config。现在，增加或删除一个投票节点只写一条日志，第 2 节中两个 config 都有偶数个投票节点时多出的三种变更也只写一条。

## 4. 其他 21 个 Raft 的 config change 实现

21 个 Raft 实现，它们分为三类。下面的代码链接固定在当时的 commit 上。

**6 个实现按变化的节点数决定是否跳过 joint：**

| 实现 | 跳过 joint 的条件 | 代码 |
|---|---|---|
| etcd-io/raft | 请求为 `ConfChangeTransitionAuto`，且只含一个变更 | [raftpb/confchange.go:85-91][code-etcd-raft-enter-joint] |
| tikv/raft-rs | 与 etcd 相同 | [proto/src/confchange.rs:134][code-raft-rs-enter-joint] |
| TiKV | 请求最多含一个变更，此时 TiKV 发送 `ConfChangeTransitionAuto` | [util.rs:982][code-tikv-conf-change-auto] |
| CockroachDB | 请求只含一个变更，且该变更不是把投票节点降级 | [replica_command.go:1978][code-cockroach-simple-conf-change] |
| braft | 增加与删除的节点数之和不超过 1 | [node.cpp:3296][code-braft-skip-joint] |
| Redpanda | 只在增加投票节点时跳过：每个 learner 单独提升为投票节点。删除投票节点时，即使只删一个也走 joint | [consensus.cc:550][code-redpanda-promote-voter]、[group_configuration.cc:1391][code-redpanda-remove-voter-joint] |

**6 个实现只要投票节点变化就走 joint：** [SOFAJRaft][code-sofajraft-conf-change-joint]、[Apache Ratis][code-ratis-conf-change-joint]、[LogCabin][code-logcabin-conf-change-joint]、[ScyllaDB][code-scylla-conf-change-joint]、[Zeebe（Camunda 的 Atomix Raft）][code-zeebe-conf-change-joint]、[RethinkDB][code-rethinkdb-conf-change-joint]。

**9 个实现没有 joint，只支持“一次只变一个节点”：** [hashicorp/raft][code-hashicorp-raft-single-change]、[Dragonboat][code-dragonboat-single-change]、[NuRaft][code-nuraft-single-change]、[canonical/raft][code-canonical-raft-single-change]、[RabbitMQ Ra][code-ra-single-change]、[Kafka KRaft][code-kraft-single-change]、[Kudu][code-kudu-single-change]、[YugabyteDB][code-yugabyte-single-change]、[MongoDB][code-mongo-single-node-change]。

etcd 是有意按变化的节点数判断的。[`raftpb/confchange.go`][code-etcd-raft-enter-joint] 中这个判断上方的注释写道：

> NB: in theory, more config changes could qualify for the "simple" protocol but it depends on the config on top of which the changes apply. For example, adding two learners is not OK if both nodes are part of the base config (i.e. two voters are turned into learners in the process of applying the conf change). In practice, these distinctions should not matter, so we keep it simple and use Joint Consensus liberally.

MongoDB 用的正是“一次只变一个节点”。它的 `validateSingleNodeChange` 拒绝一次增删超过一个节点的变更（[repl_set_config_checks.cpp:115][code-mongo-single-node-change]）。调用处的注释说明，这个检查是为了让新旧 quorum 相交（[第 544–546 行][code-mongo-single-node-change-comment]）：

> For non-force reconfigs, verify that the reconfig only adds or removes a single node. This ensures that all quorums of the new config overlap with all quorums of the old config.

MongoDB 重配置协议[论文][ref-mongo-logless-reconfig]的第一作者 William Schultz，在 [2024 年的笔记][ref-schultz-raft-reconfig-bug]中提出把“一次只变一个节点”放宽为 `QuorumsOverlap`，即本文的 `C0 ~ C1`。Schultz 的 TLA+ 模型 [MongoLoglessDynamicRaft.tla][code-schultz-tla-reconfig] 以 `QuorumsOverlap` 作为重配置的前提，但 MongoDB 的代码没有采用这个放宽。

[ref-raft-dissertation]: https://github.com/ongardie/dissertation "Diego Ongaro：Consensus: Bridging Theory and Practice，第 4 章"
[commit-openraft-skip-joint]: https://github.com/databendlabs/openraft/commit/c90c6b5311654f83a9095187923bc102420b36a8 "feat: membership: skip the joint step when quorums intersect"
[code-etcd-raft-enter-joint]: https://github.com/etcd-io/raft/blob/1931ff5beacc1e2539003c0c70f096285f04c425/raftpb/confchange.go#L85-L91 "etcd-io/raft：confchange.go"
[code-raft-rs-enter-joint]: https://github.com/tikv/raft-rs/blob/ad13f3d90780f53aea2488c6a4b76c0d334bf136/proto/src/confchange.rs#L134 "tikv/raft-rs：confchange.rs"
[code-tikv-conf-change-auto]: https://github.com/tikv/tikv/blob/134cdb2ce9852aa30e878ade3849f877dd921018/components/raftstore/src/store/util.rs#L982 "TiKV：util.rs"
[code-cockroach-simple-conf-change]: https://github.com/cockroachdb/cockroach/blob/d30c905fff79ef825adc96bcc647f1872a90f2ff/pkg/kv/kvserver/replica_command.go#L1978 "CockroachDB：replica_command.go"
[code-braft-skip-joint]: https://github.com/baidu/braft/blob/ab0017f0b98d429138d83a04d3ed351197d671a9/src/braft/node.cpp#L3296 "braft：node.cpp"
[code-redpanda-promote-voter]: https://github.com/redpanda-data/redpanda/blob/4254992f6115e92c1dbd86f90bb0aee0b869f15e/src/v/raft/consensus.cc#L550 "Redpanda：consensus.cc"
[code-redpanda-remove-voter-joint]: https://github.com/redpanda-data/redpanda/blob/4254992f6115e92c1dbd86f90bb0aee0b869f15e/src/v/raft/group_configuration.cc#L1391 "Redpanda：group_configuration.cc"
[code-sofajraft-conf-change-joint]: https://github.com/sofastack/sofa-jraft/blob/cb1a0c7ac16ff146ad8abb04b1bcb035270bb234/jraft-core/src/main/java/com/alipay/sofa/jraft/core/NodeImpl.java#L510 "SOFAJRaft：NodeImpl.java"
[code-ratis-conf-change-joint]: https://github.com/apache/ratis/blob/5b52180ff0867fbf879832469051eaec2657953c/ratis-server/src/main/java/org/apache/ratis/server/impl/LeaderStateImpl.java#L632 "Apache Ratis：LeaderStateImpl.java"
[code-logcabin-conf-change-joint]: https://github.com/logcabin/logcabin/blob/ee6c55ae9744b82b451becd9707d26c7c1b6bbfb/Server/RaftConsensus.cc#L1677 "LogCabin：RaftConsensus.cc"
[code-scylla-conf-change-joint]: https://github.com/scylladb/scylladb/blob/5e0d3eb88f8e6b7a88623b8e26816258c68a2c66/raft/fsm.cc#L191 "ScyllaDB：fsm.cc"
[code-zeebe-conf-change-joint]: https://github.com/camunda/camunda/blob/e60d9d54786f77a755fdbb7f4af0200388ab7714/zeebe/atomix/cluster/src/main/java/io/atomix/raft/roles/LeaderRole.java#L360 "Zeebe：LeaderRole.java"
[code-rethinkdb-conf-change-joint]: https://github.com/rethinkdb/rethinkdb/blob/a2cf1308b57dca2e05d744f225a082881bab3fca/src/clustering/generic/raft_core.tcc#L237 "RethinkDB：raft_core.tcc"
[code-hashicorp-raft-single-change]: https://github.com/hashicorp/raft/blob/a5b469295ddc9924541477eafe34bf59a8571063/configuration.go#L224 "hashicorp/raft：configuration.go"
[code-dragonboat-single-change]: https://github.com/lni/dragonboat/blob/076c7f6497dcc18880aed6323246d5079661942c/raftpb/configchange.go#L11 "Dragonboat：configchange.go"
[code-nuraft-single-change]: https://github.com/eBay/NuRaft/blob/46c73ad37cf5750342dd7b3b222422993f638251/src/handle_join_leave.cxx#L78 "NuRaft：handle_join_leave.cxx"
[code-canonical-raft-single-change]: https://github.com/canonical/raft/blob/c17fecbd4841f302b648fee26139ed29efbb2717/include/raft.h#L1091 "canonical/raft：raft.h"
[code-ra-single-change]: https://github.com/rabbitmq/ra/blob/2d81d2126c03aaba50d5b6ac850853e2a77ba3c8/README.md?plain=1#L26 "RabbitMQ Ra：README.md"
[code-kraft-single-change]: https://github.com/apache/kafka/blob/9fbcd3f76cecd04015e5d893976d9849f407af30/raft/src/main/java/org/apache/kafka/raft/internals/AddVoterHandler.java#L51 "Kafka KRaft：AddVoterHandler.java"
[code-kudu-single-change]: https://github.com/apache/kudu/blob/a0409299d44318756156ca8760812b1fdfadf291/src/kudu/consensus/raft_consensus.cc#L2074 "Kudu：raft_consensus.cc"
[code-yugabyte-single-change]: https://github.com/yugabyte/yugabyte-db/blob/d2e9935d89e003240174b045199d9d8242939c71/src/yb/consensus/consensus.proto#L89-L93 "YugabyteDB：consensus.proto"
[code-mongo-single-node-change]: https://github.com/mongodb/mongo/blob/ffc52d7f3327dffdd92e5142a893e079527088c0/src/mongo/db/repl/repl_set_config_checks.cpp#L115 "MongoDB：repl_set_config_checks.cpp"
[code-mongo-single-node-change-comment]: https://github.com/mongodb/mongo/blob/ffc52d7f3327dffdd92e5142a893e079527088c0/src/mongo/db/repl/repl_set_config_checks.cpp#L544-L546 "MongoDB：repl_set_config_checks.cpp"
[ref-schultz-raft-reconfig-bug]: https://will62794.github.io/distributed-systems/2024/02/09/note-on-raft-reconfig-bug.html "William Schultz：On Raft's Reconfiguration Bug"
[code-schultz-tla-reconfig]: https://github.com/will62794/logless-reconfig/blob/05178a700a05e3a3e7f1808c39a5f61f2e6cece0/MongoLoglessDynamicRaft.tla#L95-L99 "MongoLoglessDynamicRaft.tla：Reconfig"
