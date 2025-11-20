---
title:      "Raft Node Rejoin Bug"
authors:
    - xp
categories:
    - algo
tags:
    - distributed
    - 分布式
    - raft
    - en


disabled_article:
    image: /post-res/linearizable/linearizable-banner-big.png

mathjax: false
toc: true
toc_label: Table of Contents
toc_sticky: true
excerpt: "分析 Raft 实现中的 replication session 隔离缺陷。当节点在同一 term 内重新加入集群时，延迟的 AppendEntries 响应可能破坏 progress 跟踪，导致无限重试循环。虽然不影响数据安全，但会造成资源耗尽等运维问题。以 raft-rs 为例探讨触发条件和解决方案。"
---


![](./raft-rejoin-bug-banner.webp)

# Raft 成员变更期间的 replication progress 破坏问题

在 Raft 集群运维中，存在一个容易被忽视的 bug：当节点在同一个 term 内被移除又重新加入集群时，来自旧成员配置的延迟 AppendEntries response 可能会破坏 Leader 对该节点 replication progress 的跟踪，导致 Leader 陷入无限重试循环。

这个问题的根源在于缺少 **replication session 隔离机制**。当同一个节点在不同时间加入集群时，应该被视为不同的 replication session，但如果缺少显式的 session 标识，Leader 就无法区分 response 来自哪个 session。结果就是旧 session 的延迟 response 错误地更新了新 session 的 progress 记录。

虽然这会带来运维上的困扰——资源持续消耗、节点无法追上集群进度，但好在 Raft 的 commit 协议保证了数据安全性不会受到影响。

分析的 Raft libs:

| Implementation | Stars | Language | Status | Analysis |
|----------------|------:|----------|--------|----------|
| Apache Ratis | 1,418 | Java | ✓ PROTECTED | [Report](analysis/apache-ratis.md) |
| NuRaft | 1,140 | C++ | ✓ PROTECTED | [Report](analysis/nuraft.md) |
| OpenRaft | 1,700 | Rust | ✓ PROTECTED | [Report](analysis/openraft.md) |
| RabbitMQ Ra | 908 | Erlang | ✓ PROTECTED | [Report](analysis/rabbitmq-ra.md) |
| braft | 4,174 | C++ | ✓ PROTECTED | [Report](analysis/braft.md) |
| canonical/raft | 954 | C | ✓ PROTECTED | [Report](analysis/canonical-raft.md) |
| sofa-jraft | 3,762 | Java | ✓ PROTECTED | [Report](analysis/sofa-jraft-analysis.md) |
| **LogCabin** | **1,945** | **C++** | **✗ VULNERABLE** | [Report](analysis/logcabin.md) |
| **PySyncObj** | **738** | **Python** | **✗ VULNERABLE** | [Report](analysis/pysyncobj.md) |
| **dragonboat** | **5,262** | **Go** | **✗ VULNERABLE** | [Report](analysis/dragonboat.md) |
| **etcd-io/raft** | **943** | **Go** | **✗ VULNERABLE** | [Report](analysis/etcd-raft.md) |
| **hashicorp/raft** | **8,826** | **Go** | **✗ VULNERABLE** | [Report](analysis/hashicorp-raft-analysis.md) |
| **raft-java** | **1,234** | **Java** | **✗ VULNERABLE** | [Report](analysis/raft-java.md) |
| **raft-rs (TiKV)** | **3,224** | **Rust** | **✗ VULNERABLE** | [Report](analysis/raft-rs.md) |
| **redisraft** | **841** | **C** | **✗ VULNERABLE** | [Report](analysis/redisraft.md) |
| **willemt/raft** | **1,160** | **C** | **✗ VULNERABLE** | [Report](analysis/willemt-raft.md) |
| eliben/raft | 1,232 | Go | N/A | [Report](analysis/eliben-raft.md) |

本文将以 TiKV 使用的 Raft 实现 raft-rs 为例，详细分析这个 bug 的触发条件、影响范围以及解决方案。

完整的分析以及对其他 Raft 实现的调研，可以在 [Raft Rejoin Bug Survey](https://github.com/drmingdrmer/raft-rejoin-bug) 找到

## Raft 日志 replication 基础

在 Raft 中，Leader 通过 AppendEntries RPC 向 Follower 复制 log entry，同时为每个 Follower 维护一个 replication 状态机来跟踪复制进度。

### AppendEntries request-response 流程

整个流程是这样的：Leader 发送 AppendEntries request 时会带上当前的 `term`、新 entry 前一个位置的 `prev_log_index` 和 `prev_log_term`、要复制的 `entries[]`，以及 Leader 的 `leader_commit` index。

Follower 收到后会返回一个 response，包含自己的 `term`、已复制的最高 log index，以及操作是否成功。

### Progress 跟踪

Leader 靠这些 response 来掌握每个 Follower 的复制情况。它用 `matched` 记录确认已复制到该 Follower 的最高 log index，用 `next_idx` 标记下次要发送的位置。当收到成功的 response 且携带 `index=N` 时，Leader 就会更新 `matched=N`，然后计算 `next_idx=N+1` 准备下一轮。

这套机制有个隐含的假设：response 对应的是当前的 replication session。

如果没有处理这个假设, 那么当节点重新加入集群后，Leader 可能会陷入无限重试的循环。它不停地发 AppendEntries request，节点不停地拒绝，然后循环往复，而那个节点就是怎么也追不上集群的状态。

## raft-rs Progress 跟踪机制

raft-rs 使用 Progress 结构跟踪每个 follower 节点的 replication progress：

File: [`src/tracker/progress.rs`](https://github.com/tikv/raft-rs/blob/master/src/tracker/progress.rs#L8-L56)

```rust
pub struct Progress {
    pub matched: u64,      // 已知已复制的最高 log index
    pub next_idx: u64,     // 下一个要发送的 log index
    pub state: ProgressState,
    // ... 其他字段
}
```

这里的 `matched` 字段记录的是已成功复制到该 follower 的最高 log index。每当 Leader 收到成功的 AppendEntries response，就会更新这个字段：

File: [`src/tracker/progress.rs:136-148`](https://github.com/tikv/raft-rs/blob/master/src/tracker/progress.rs#L136-L148)

```rust
pub fn maybe_update(&mut self, n: u64) -> bool {
    let need_update = self.matched < n;  // 只检查单调性
    if need_update {
        self.matched = n;  // 接受更新！
        self.resume();
    }
    need_update
}
```

注意这里的更新逻辑很简单：只要新来的 index 比当前记录的 `matched` 大，就接受更新。当节点从集群移除时，它的 Progress 记录会被删除；等它重新加入时，会创建一个全新的 Progress 记录，此时 `matched = 0`。

## Bug 复现序列

让我们通过一个具体的时间线来看看这个 bug 是怎么发生的。特别要注意的是，所有事件都发生在同一个 term（term=5）里——这正是理解为什么基于 term 的验证会失效的关键。

### 事件时间线

```
| Time | Event                                         | Progress State
|------|-----------------------------------------------|----------------
| T1   | log=1, members={a,b,c}                        | C: matched=0
|      | Leader sends AppendEntries(index=1) to C      |
|      | (Network delay causes slow delivery)          |
|      |                                               |
| T2   | log=5, members={a,b}                          | C: [deleted]
|      | Node C removed from cluster                   |
|      | Progress[C] deleted from leader's tracker     |
|      |                                               |
| T3   | log=100, members={a,b,c}                      | C: matched=0 (new)
|      | Node C rejoins the cluster                    |
|      | New Progress[C] created with matched=0        |
|      |                                               |
| T4   | Delayed response arrives from T1:             |
|      | {from: C, index: 1, success: true}            |
|      | Leader finds Progress[C] (the new one!)       |
|      | maybe_update(1) called: 0 < 1, so update!     | C: matched=1 ❌
|      |                                               |
| T5   | Leader calculates next_idx = matched + 1 = 2  |
|      | Sends AppendEntries(prev_index=1)             |
|      | Node C rejects (doesn't have index 1!)        |
|      | Leader can't decrement (matched == rejected)  |
|      | Infinite loop begins...                       |
```

让我们详细解释一下每个时间点发生了什么：

- **T1**: 此时集群成员是 {a,b,c}，Leader 向节点 C 发送 AppendEntries(index=1)。但是这个 response 在网络上遇到了延迟，迟迟没有到达。
- **T2**: 节点 C 被从集群中移除，成员变为 {a,b}。Leader 删除了 Progress[C] 记录。
- **T3**: 节点 C 重新加入集群，成员恢复为 {a,b,c}。Leader 为节点 C 创建了一个全新的 Progress 记录，此时 matched=0。
- **T4**: 那个在 T1 的延迟 response 终于到达了。Leader 找到了节点 C 的 Progress 记录（但这是 T3 新建的），因为 index=1 > matched=0，所以更新了 matched=1。问题就出在这里！
- **T5**: Leader 根据 matched=1 计算出 next_idx=2，发送 AppendEntries(prev_index=1)。但节点 C 的 log 是空的，没有 index 1，于是拒绝。Leader 想递减 next_idx，但因为 rejected(1) == matched(1)，拒绝递减。无限循环开始。

### T4 的 response 处理

到了时间 T4，那个在 T1 发出、在网络上延迟许久的 response 终于到达了。Leader 收到后会这样处理：

File: [`src/raft.rs`](https://github.com/tikv/raft-rs/blob/master/src/raft.rs) (response 处理逻辑)

```rust
fn handle_append_response(&mut self, m: &Message) {
    // 查找 progress 记录
    let pr = match self.prs.get_mut(m.from) {
        Some(pr) => pr,
        None => {
            debug!(self.logger, "no progress available for {}", m.from);
            return;
        }
    };

    // 如果 index 更高则更新 progress
    if !pr.maybe_update(m.index) {
        return;
    }
    // ...
}
```

File: [`src/tracker/progress.rs:136-148`](https://github.com/tikv/raft-rs/blob/master/src/tracker/progress.rs#L136-L148)

```rust
pub fn maybe_update(&mut self, n: u64) -> bool {
    let need_update = self.matched < n;  // 只检查单调性
    if need_update {
        self.matched = n;  // 接受更新！
        self.resume();
    }
    need_update
}
```

这时候问题就来了：Leader 确实找到了节点 C 的 Progress 记录，但这是 T3 时新创建的那个。因为 message 的 term 和当前 term 都是 5，通过了 [`step()` 函数](https://github.com/tikv/raft-rs/blob/master/src/raft.rs#L1346-L1478)里的 term 检查，于是 Leader 就用这个陈旧的 index 值更新了 progress。

## 根本原因分析

这个 bug 的根源在于 **request-response 缺少 replication session 的标识**。当节点 C 在 T2 被移除又在 T3 重新加入时，这应该是两个不同的 replication session——但 Leader 没有办法区分 T1 发出的 request 对应的 response 和 T3 之后发出的 request 对应的 response。

看一下 raft-rs 的 Message 结构：

File: [`proto/proto/eraftpb.proto:71-98`](https://github.com/tikv/raft-rs/blob/master/proto/proto/eraftpb.proto#L71-L98)

```protobuf
message Message {
    MessageType msg_type = 1;
    uint64 to = 2;
    uint64 from = 3;
    uint64 term = 4;        // 只有 term，没有 session 标识！
    uint64 log_term = 5;
    uint64 index = 6;
    // ...
}
```

Message 里只有 `from` 字段标识发送节点，但同一个节点 ID 在不同时间加入集群时，应该被视为不同的 replication session。Leader 需要能够区分：这个 response 是来自节点 C 第一次加入时的 session，还是第二次加入时的 session？但现在的 Message 结构无法提供这个信息。

## 影响

### 无限重试循环

一旦 Leader 错误地把 `matched` 设成了 1：

File: [`src/tracker/progress.rs`](https://github.com/tikv/raft-rs/blob/master/src/tracker/progress.rs) (递减逻辑)

```rust
pub fn maybe_decr_to(&mut self, rejected: u64, match_hint: u64, ...) -> bool {
    if self.state == ProgressState::Replicate {
        // 如果 rejected <= matched 则无法递减
        if rejected < self.matched
            || (rejected == self.matched && request_snapshot == INVALID_INDEX) {
            return false;  // 忽略拒绝！
        }
        // ...
    }
}
```

现在 Leader 发送 AppendEntries，会设置 `prev_log_index=1`，但节点 C 的 log 是空的，没有 index 1 的条目。所以节点 C 拒绝了这个请求。Leader 想要递减 `next_idx` 来重试更早的位置，但问题来了：因为 `rejected (1) == matched (1)`，递减逻辑直接返回 false，拒绝递减。于是 Leader 只好再发一遍同样的请求，节点 C 再拒绝一次，如此往复，形成了一个死循环。


## 数据仍是安全的

但有个好消息：数据的完整性不会受影响。Raft 的安全机制保证了即使 progress 跟踪出了问题，集群也不会丢失已经 commit 的数据。

原因在于 commit index 的计算仍然是正确的。即便 Leader 误以为节点 C 的 `matched=1`，它计算 commit index 时依然是基于实际的 quorum。比如说节点 A 的 matched=100，节点 B 的 matched=100，节点 C 的 matched=1（虽然不对，但也没关系）。Quorum 看的是 A 和 B 的 matched=100，所以 commit index 会被正确计算为 100。加上 Raft 的 overlapping quorum 特性，任何新选出的 Leader 都必然包含所有已 commit 的 entry，数据安全就这样得到了保障。

## 解决方案

### 方案 1：添加 membership version

最直接的办法就是在 message 里加上 membership 配置的 version：

```protobuf
message Message {
    // ... 现有字段
    uint64 membership_log_id = 17;  // 新字段
}
```

然后在处理 response 时校验一下：

```rust
fn handle_append_response(&mut self, m: &Message) {
    let pr = self.prs.get_mut(m.from)?;

    // 检查 membership version
    if m.membership_log_id != self.current_membership_log_id {
        debug!("stale message from different membership");
        return;
    }

    pr.maybe_update(m.index);
}
```

这样就直接解决了问题的根源——Leader 现在可以分辨出 message 来自哪个 membership 配置了。

### 方案 2：generation counter

另一个思路是在 Progress 里加个 generation counter，每次节点重新加入时就递增：

```rust
pub struct Progress {
    pub matched: u64,
    pub next_idx: u64,
    pub generation: u64,  // 每次重新加入时递增
    // ...
}
```

发 message 时把 generation 带上，收到 response 时验证一下。这个方案比方案 1 轻量一些，不过得小心管理 generation 的生命周期。


## 总结

通过这个 bug 我们可以看到，当成员变更发生在同一个 term 内时，单纯依靠 term 来验证 message 的新鲜度是不够的。如果缺少显式的 session 隔离机制，来自旧 membership 配置的延迟 response 就可能破坏 progress 跟踪。

不过值得庆幸的是，因为 Raft 在 commit index 计算和 overlapping quorum 机制上的保障，这个 bug 并不会危及数据安全。它带来的主要是运维层面的问题——表面上看起来像数据损坏，可能让运维团队花大力气去排查一个并不存在的数据丢失问题。

对于生产环境的 Raft 实现，建议引入显式的 session 管理机制。可以通过 membership version 或者 generation counter 来实现。其中最推荐的做法是在 message 里添加 membership_log_id 字段，这样 Leader 就能清楚地分辨出 response 来自哪个 membership 配置了。

完整的分析以及对其他 Raft 实现的调研，可以在 [Raft Rejoin Bug Survey](https://github.com/drmingdrmer/raft-rejoin-bug) 找到
