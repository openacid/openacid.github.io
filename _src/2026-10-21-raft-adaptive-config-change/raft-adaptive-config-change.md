---
title: "Adaptive Membership Changes in OpenRaft: Skip Joint Consensus When Quorums Overlap"
date: 2026-10-21
url: /distributed/raft-adaptive-config-change/
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
toc_label: Table of Contents
toc_sticky: true
description: "OpenRaft now skips joint consensus when every old quorum intersects every new quorum. A linear-time test identifies exactly when this is safe for majority-based configurations. It covers Raft's familiar one-node-at-a-time changes and a few additional cases, while retaining joint consensus for changes that need it."
---

![](raft-adaptive-config-change-banner-small.png)

OpenRaft now skips joint consensus whenever the old and new configurations have quorum overlap: every old quorum shares at least one node with every new quorum.

For `Raft::change_membership()`, that means two possible paths:

- With quorum overlap, write one entry containing the new configuration.
- Without quorum overlap, write a joint configuration first, then the new configuration: two entries in total.

The idea follows from the purpose of joint consensus. A joint configuration lets us cross from the old configuration to the new one in two steps, each with the required quorum overlap. If the old and new quorums already overlap, we can make that transition directly.

For configurations that use majority quorums, OpenRaft can test this condition exactly in linear time. Raft's familiar [single-server change][ref-raft-dissertation] rule—adding or removing one node at a time—is a simpler way to guarantee the same property. The exact test also admits a few changes involving two nodes.

## 1. Joint consensus provides quorum overlap at each step

Let `C0` be the old configuration, `C1` the new one, and `C01 = [C0,C1]` their joint configuration. Write `C0 ~ C1` when every quorum of `C0` intersects every quorum of `C1`. A direct transition from `C0` to `C1` requires this property; Section 3 of [Raft Membership Changes: When a Leader Must Commit a Current-Term Entry First][post-raft-membership-log-barrier] explains why.

**Joint consensus splits a configuration change into two transitions that each preserve quorum overlap.** Every quorum of `C01` contains a quorum of `C0` and a quorum of `C1`. As a result, `C0 ~ C01` and `C01 ~ C1` always hold, even when `C0 ~ C1` does not.

```text
| Joint change, two entries:
|
|     C0 -----> C01 -----> C1
|        C0 ~ C01   C01 ~ C1
|
| When C0 ~ C1, one entry:
|
|     C0 ----------------> C1
```

When `C0 ~ C1` already holds, we can go straight to `C1`. The joint step would add an entry and another wait for commitment without providing any additional overlap.

There is one other requirement: the leader must first commit an entry from its own term. Skipping that barrier allows the bug described in [The Pitfalls of Raft Membership Change][post-raft-bug-cn]; the [article on membership log barriers][post-raft-membership-log-barrier] explains the failure in detail.

OpenRaft already enforces this barrier for every membership change. It returns `UncommittedLeaderLog` until the first entry the leader writes after its election has committed. With that requirement satisfied, the choice between a direct change and joint consensus comes down to `C0 ~ C1`.

## 2. Majority sizes give us an exact overlap test

For a configuration `C` that uses majority quorums, define its majority size as `maj(C) = ⌊|C|/2⌋ + 1`. Two such configurations have quorum overlap exactly when their majority sizes add up to more than the number of distinct nodes across both configurations:

> **`C0 ~ C1` if and only if `maj(C0) + maj(C1) > |C0 ∪ C1|`.**

We only need to compute one set union. The work is linear in the total number of nodes in the two configurations. Enumerating all possible quorums to check the definition directly would take exponential time.

To see why the test works, suppose we can pick an old quorum and a new quorum that share no nodes. Together, they occupy at least `maj(C0) + maj(C1)` distinct nodes, all within `C0 ∪ C1`. That requires `maj(C0) + maj(C1) ≤ |C0 ∪ C1|`.

The converse holds too. If `maj(C0) + maj(C1) ≤ |C0 ∪ C1|`, build each quorum from nodes unique to its configuration first. Then fill any remaining places with shared nodes, assigning each shared node to only one quorum. The inequality guarantees enough nodes to finish both quorums without overlap.

**Adding or removing one node always passes the overlap test.** When we add one node, `C1` contains all of `C0`, so `|C0 ∪ C1| = |C1| = |C0| + 1`. The two majority sizes add up to:

`maj(C0) + maj(C1) = ⌊|C0|/2⌋ + ⌊(|C0|+1)/2⌋ + 2 = |C0| + 2`

That is one more than the size of the union, so quorum overlap is guaranteed. Removing one node gives the same result with `C0` and `C1` exchanged. The exact test also tells us when a change involving two nodes can skip joint consensus:

| Change                  | Exact test | One-node-at-a-time rule |
|---                      |---|---|
| `{a,b,c} → {a,b,c,d}`   | Overlap | Allowed |
| `{a,b,c} → {b,c,d}`     | No overlap: quorum `{a,b}` of `C0` and quorum `{c,d}` of `C1` share no nodes | Not allowed |
| `{a,b,c,d} → {a,b,c,e}` | Overlap | Not allowed |

The exact test admits three kinds of changes beyond the one-node-at-a-time rule. All three start and end with an even number of voters:

- Replace one voter: `{a,b,c,d} → {a,b,c,e}`.
- Add two voters: `{a,b,c,d} → {a,b,c,d,e,f}`.
- Remove two voters: `{a,b,c,d} → {a,b}`.

Checking the even and odd cases in the formula shows that these are the only additional possibilities. Production clusters usually have an odd number of voters. Starting from an odd-sized configuration, the exact test permits the same changes as the one-node-at-a-time rule.

## 3. OpenRaft chooses the next configuration with bridge_to()

[Commit c90c6b53][commit-openraft-skip-joint] brings this test to `Raft::change_membership()`. It uses `bridge_to()` from [quorum-set][repo-quorum-set] 0.3.0, the library OpenRaft uses for quorum calculations, to choose the next configuration.

When the current configuration is not joint, `bridge_to()` applies the exact test from Section 2. If the quorums overlap, it returns the target configuration, completing the change with one entry. Otherwise, it returns the joint configuration `C01`. `change_membership()` waits for that entry to commit before appending the target configuration.

Adding or removing one voter therefore takes a single entry. So do the three additional cases involving even-sized configurations. Replacing all three voters in `{a,b,c} → {d,e,f}` still goes through joint consensus: the old and new quorums have no overlap.

Before this change, `change_membership()` wrote a joint configuration whenever the voters changed. It now takes the direct path whenever the overlap test permits it.

## 4. How 21 other Raft implementations choose the transition

The 21 implementations below fall into three groups. Each code link is pinned to the commit examined.

**Six implementations use the number of changes to decide whether to skip joint consensus:**

| Implementation | Condition for skipping joint consensus | Code |
|---|---|---|
| etcd-io/raft | The request uses `ConfChangeTransitionAuto` and contains exactly one change | [raftpb/confchange.go:85-91][code-etcd-raft-enter-joint] |
| tikv/raft-rs | The same conditions as etcd-io/raft | [proto/src/confchange.rs:134][code-raft-rs-enter-joint] |
| TiKV | The request contains at most one change, in which case TiKV sends `ConfChangeTransitionAuto` | [util.rs:982][code-tikv-conf-change-auto] |
| CockroachDB | The request contains exactly one change, and that change does not demote a voter | [replica_command.go:1978][code-cockroach-simple-conf-change] |
| braft | The total number of nodes added and removed is at most one | [node.cpp:3296][code-braft-skip-joint] |
| Redpanda | Each learner is promoted to voter individually, skipping joint consensus. Removing a voter always uses joint consensus | [consensus.cc:550][code-redpanda-promote-voter], [group_configuration.cc:1391][code-redpanda-remove-voter-joint] |

**Six implementations use joint consensus whenever the voters change:** [SOFAJRaft][code-sofajraft-conf-change-joint], [Apache Ratis][code-ratis-conf-change-joint], [LogCabin][code-logcabin-conf-change-joint], [ScyllaDB][code-scylla-conf-change-joint], [Zeebe (Camunda's Atomix Raft)][code-zeebe-conf-change-joint], and [RethinkDB][code-rethinkdb-conf-change-joint].

**Nine implementations support only one-node-at-a-time changes, with no joint consensus:** [hashicorp/raft][code-hashicorp-raft-single-change], [Dragonboat][code-dragonboat-single-change], [NuRaft][code-nuraft-single-change], [canonical/raft][code-canonical-raft-single-change], [RabbitMQ Ra][code-ra-single-change], [Kafka KRaft][code-kraft-single-change], [Kudu][code-kudu-single-change], [YugabyteDB][code-yugabyte-single-change], and [MongoDB][code-mongo-single-node-change].

etcd's choice to count changes is deliberate. The comment above the check in [`raftpb/confchange.go`][code-etcd-raft-enter-joint] explains why it uses joint consensus even when a simpler transition might be safe:

> NB: in theory, more config changes could qualify for the "simple" protocol but it depends on the config on top of which the changes apply. For example, adding two learners is not OK if both nodes are part of the base config (i.e. two voters are turned into learners in the process of applying the conf change). In practice, these distinctions should not matter, so we keep it simple and use Joint Consensus liberally.

MongoDB explicitly connects the one-node-at-a-time rule to quorum overlap. Its `validateSingleNodeChange` rejects reconfigurations that add or remove more than one node ([repl_set_config_checks.cpp:115][code-mongo-single-node-change]). The comment at the call site gives the reason ([lines 544–546][code-mongo-single-node-change-comment]):

> For non-force reconfigs, verify that the reconfig only adds or removes a single node. This ensures that all quorums of the new config overlap with all quorums of the old config.

William Schultz, first author of the [paper on MongoDB's reconfiguration protocol][ref-mongo-logless-reconfig], proposed using the more general `QuorumsOverlap` condition in a [2024 note][ref-schultz-raft-reconfig-bug]. This is exactly `C0 ~ C1`. His TLA+ model, [MongoLoglessDynamicRaft.tla][code-schultz-tla-reconfig], already uses `QuorumsOverlap` as a precondition for reconfiguration. MongoDB's implementation still enforces the one-node-at-a-time restriction.

[ref-raft-dissertation]: https://github.com/ongardie/dissertation "Diego Ongaro: Consensus: Bridging Theory and Practice, Chapter 4"
[commit-openraft-skip-joint]: https://github.com/databendlabs/openraft/commit/c90c6b5311654f83a9095187923bc102420b36a8 "feat: membership: skip the joint step when quorums intersect"
[code-etcd-raft-enter-joint]: https://github.com/etcd-io/raft/blob/1931ff5beacc1e2539003c0c70f096285f04c425/raftpb/confchange.go#L85-L91 "etcd-io/raft: confchange.go"
[code-raft-rs-enter-joint]: https://github.com/tikv/raft-rs/blob/ad13f3d90780f53aea2488c6a4b76c0d334bf136/proto/src/confchange.rs#L134 "tikv/raft-rs: confchange.rs"
[code-tikv-conf-change-auto]: https://github.com/tikv/tikv/blob/134cdb2ce9852aa30e878ade3849f877dd921018/components/raftstore/src/store/util.rs#L982 "TiKV: util.rs"
[code-cockroach-simple-conf-change]: https://github.com/cockroachdb/cockroach/blob/d30c905fff79ef825adc96bcc647f1872a90f2ff/pkg/kv/kvserver/replica_command.go#L1978 "CockroachDB: replica_command.go"
[code-braft-skip-joint]: https://github.com/baidu/braft/blob/ab0017f0b98d429138d83a04d3ed351197d671a9/src/braft/node.cpp#L3296 "braft: node.cpp"
[code-redpanda-promote-voter]: https://github.com/redpanda-data/redpanda/blob/4254992f6115e92c1dbd86f90bb0aee0b869f15e/src/v/raft/consensus.cc#L550 "Redpanda: consensus.cc"
[code-redpanda-remove-voter-joint]: https://github.com/redpanda-data/redpanda/blob/4254992f6115e92c1dbd86f90bb0aee0b869f15e/src/v/raft/group_configuration.cc#L1391 "Redpanda: group_configuration.cc"
[code-sofajraft-conf-change-joint]: https://github.com/sofastack/sofa-jraft/blob/cb1a0c7ac16ff146ad8abb04b1bcb035270bb234/jraft-core/src/main/java/com/alipay/sofa/jraft/core/NodeImpl.java#L510 "SOFAJRaft: NodeImpl.java"
[code-ratis-conf-change-joint]: https://github.com/apache/ratis/blob/5b52180ff0867fbf879832469051eaec2657953c/ratis-server/src/main/java/org/apache/ratis/server/impl/LeaderStateImpl.java#L632 "Apache Ratis: LeaderStateImpl.java"
[code-logcabin-conf-change-joint]: https://github.com/logcabin/logcabin/blob/ee6c55ae9744b82b451becd9707d26c7c1b6bbfb/Server/RaftConsensus.cc#L1677 "LogCabin: RaftConsensus.cc"
[code-scylla-conf-change-joint]: https://github.com/scylladb/scylladb/blob/5e0d3eb88f8e6b7a88623b8e26816258c68a2c66/raft/fsm.cc#L191 "ScyllaDB: fsm.cc"
[code-zeebe-conf-change-joint]: https://github.com/camunda/camunda/blob/e60d9d54786f77a755fdbb7f4af0200388ab7714/zeebe/atomix/cluster/src/main/java/io/atomix/raft/roles/LeaderRole.java#L360 "Zeebe: LeaderRole.java"
[code-rethinkdb-conf-change-joint]: https://github.com/rethinkdb/rethinkdb/blob/a2cf1308b57dca2e05d744f225a082881bab3fca/src/clustering/generic/raft_core.tcc#L237 "RethinkDB: raft_core.tcc"
[code-hashicorp-raft-single-change]: https://github.com/hashicorp/raft/blob/a5b469295ddc9924541477eafe34bf59a8571063/configuration.go#L224 "hashicorp/raft: configuration.go"
[code-dragonboat-single-change]: https://github.com/lni/dragonboat/blob/076c7f6497dcc18880aed6323246d5079661942c/raftpb/configchange.go#L11 "Dragonboat: configchange.go"
[code-nuraft-single-change]: https://github.com/eBay/NuRaft/blob/46c73ad37cf5750342dd7b3b222422993f638251/src/handle_join_leave.cxx#L78 "NuRaft: handle_join_leave.cxx"
[code-canonical-raft-single-change]: https://github.com/canonical/raft/blob/c17fecbd4841f302b648fee26139ed29efbb2717/include/raft.h#L1091 "canonical/raft: raft.h"
[code-ra-single-change]: https://github.com/rabbitmq/ra/blob/2d81d2126c03aaba50d5b6ac850853e2a77ba3c8/README.md?plain=1#L26 "RabbitMQ Ra: README.md"
[code-kraft-single-change]: https://github.com/apache/kafka/blob/9fbcd3f76cecd04015e5d893976d9849f407af30/raft/src/main/java/org/apache/kafka/raft/internals/AddVoterHandler.java#L51 "Kafka KRaft: AddVoterHandler.java"
[code-kudu-single-change]: https://github.com/apache/kudu/blob/a0409299d44318756156ca8760812b1fdfadf291/src/kudu/consensus/raft_consensus.cc#L2074 "Kudu: raft_consensus.cc"
[code-yugabyte-single-change]: https://github.com/yugabyte/yugabyte-db/blob/d2e9935d89e003240174b045199d9d8242939c71/src/yb/consensus/consensus.proto#L89-L93 "YugabyteDB: consensus.proto"
[code-mongo-single-node-change]: https://github.com/mongodb/mongo/blob/ffc52d7f3327dffdd92e5142a893e079527088c0/src/mongo/db/repl/repl_set_config_checks.cpp#L115 "MongoDB: repl_set_config_checks.cpp"
[code-mongo-single-node-change-comment]: https://github.com/mongodb/mongo/blob/ffc52d7f3327dffdd92e5142a893e079527088c0/src/mongo/db/repl/repl_set_config_checks.cpp#L544-L546 "MongoDB: repl_set_config_checks.cpp"
[ref-schultz-raft-reconfig-bug]: https://will62794.github.io/distributed-systems/2024/02/09/note-on-raft-reconfig-bug.html "William Schultz: On Raft's Reconfiguration Bug"
[code-schultz-tla-reconfig]: https://github.com/will62794/logless-reconfig/blob/05178a700a05e3a3e7f1808c39a5f61f2e6cece0/MongoLoglessDynamicRaft.tla#L95-L99 "MongoLoglessDynamicRaft.tla: Reconfig"
