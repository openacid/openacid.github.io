---
title:      "Raft 中的 IO 执行顺序"
authors:
    - xp
categories:
    - algo
tags:
    - distributed
    - 分布式
    - raft
    - cn


refs:
    - x: y

disabled_article:
    image: /post-res/linearizable/linearizable-banner-big.png

mathjax: false
toc: true
toc_label: 本文目录
toc_sticky: true
excerpt: "Raft 先写日志后写 term 会导致已提交数据丢失。本文分析问题本质，总结 TiKV、HashiCorp Raft、SOFAJRaft 的三种安全解决方案"
---


![](./raft-io-order-banner.webp)


## 问题：IO 顺序错误导致数据丢失

Raft 在处理appendEntries请求的持久化时，如果**先写日志，再写 term**，会导致**已提交的数据丢失**。

本文分析问题如何发生、主流实现如何解决、以及如何在你的系统中避免这个问题。

### 背景：Raft 的持久化要求

在 Raft 中，当 follower 收到 leader 的 AppendEntries RPC 时，需要持久化两类关键数据：元数据（HardState，包括 term、vote）和日志条目（Entries，业务数据）。只有持久化成功后，follower 才能安全地响应 leader。**问题的关键在于：这两类数据的持久化顺序很重要**。

### 时间线场景

让我们通过一个具体的时间线来理解这个问题：

```text
Legend:
Ni:   Node i
Vi:   RequestVote, term=i
Li:   Establish Leader, term=i
Ei-j: Log entry, term=i, index=j

N5 |          V5  L5       E5-1
N4 |          V5           E5-1
N3 |  V1                V5,E5-1  E1-1
N2 |  V1      V5                 E1-1
N1 |  V1  L1                     E1-1
------+---+---+---+--------+-----+-------------------------------------------> time
      t1  t2  t3  t4       t5    t6
```

- t1: N1 发起选举（term=1），获得 N1、N2、N3 的投票
- t2: N1 成为 leader L1
- t3: N5 发起选举（term=5），获得 N5、N4、N2 的投票
- t4: N5 成为 leader L5
- t5: L5 复制第一个日志条目 E5-1 到 N4 和 N3。关键点：`N3 的存储 term（1）< AppendEntries RPC 的 term（5）`，N3 必须执行两个顺序 IO 操作：持久化 term=5，然后持久化 E5-1
- t6: L1 尝试复制 E1-1（term=1, index=1）

在上面的流程中, t5时刻 N3 的行为是关键:

**如果 IO 操作不能重排序**（正确）：

N3 按顺序执行：**先**持久化 term=5，**后**持久化 E5-1。这确保：如果 E5-1 被持久化，term=5 也必然已持久化。

**如果 IO 操作可以重排序**（错误）：

可能的执行顺序是：持久化 E5-1，然后持久化 term=5。

如果服务器在写入 E5-1 之后、持久化 term=5 之前崩溃，此时 N3 的存储 term 仍然是 1，但 E5-1 已存在于日志中。当 N3 收到 L1 的复制请求 E1-1（term=1, index=1）时，N3 会接受请求（因为 term 1 = 1），E1-1 覆盖 E5-1。这就是问题所在：E5-1 已经被复制到 3 个节点（N5、N4、N3），L5 认为它已提交，但它被旧 leader 的日志覆盖了——**已提交的数据丢失**。

这个问题的根源在于一个关键不变式被打破：

> **如果日志条目 E（term=T）存在于磁盘 → 磁盘上的 term 必须≥T**

正确的 IO 顺序维护这个不变式，确保一旦日志条目被写入，对应的 term 也必然是持久的。


## Raft 论文的隐含假设

Raft 论文说："Before responding to RPCs, a server must update its persistent state."

论文假设持久化是原子的，没有明确说明 term 和 log 的顺序要求。

一个常见的设计陷阱是: 当 follower 收到 AppendEntries RPC 时，需要持久化两类数据：元数据（term、vote 等，存储在 MetaStore）和日志（log entries，存储在 LogStore）。

为了性能和关注点分离，很多实现会将元数据和日志分开存储，并行提交 IO 请求：

```rust
fn handle_append_entries(&mut self, req: AppendEntries) -> Response {
    self.meta_store.save_term_async(req.term);  // 异步提交
    self.log_store.append_async(req.entries);   // 异步提交

    self.log_store.sync();  // 只等待日志持久化！
    return Response::success();  // 忽略 term 是否已持久化
}
```

陷阱的本质是：实现者关注日志的持久化（业务数据），却忽略 term 的持久化（"元数据"）。结果是 entries 在磁盘上，term 还在内存或队列中，崩溃后不变式被打破。


## 真实案例：开源实现的调查

我调查了 4 个主流 Raft 实现，发现了不同的解决方案：

| 实现 | 结果 | 如何避免问题 |
|------|------|------------|
| **TiKV** | ✅ 安全 | 原子批处理：term 和 log 在同一 LogBatch |
| **HashiCorp Raft** | ✅ 安全 | 有序写入：先写 term（panic on fail），再写 log |
| **SOFAJRaft** | ✅ 安全 | 混合顺序：term 同步，log 异步 |
| **tikv/raft-rs 库** | ⚠️ 取决于应用 | 库本身安全，但无顺序强制 |

详细的代码实现见下一章节的三种设计模式。

## 三种安全的解决方案

通过分析成功的实现，总结出三种安全的设计模式：

### 原子批处理（TiKV）

TiKV 把 term 和 log 写入同一个原子批次，一次性提交。代码中可以看到，先把 term 和 entries 都添加到 batch，然后调用`write_batch(sync=true)`一次性写入，并通过 checksum 验证。这样做的好处是要么都可见，要么都不可见，批次内的顺序不重要，推理最简单。代价是需要存储引擎支持原子批处理，但只需要一次 fsync。这个方案适合自定义存储引擎，或者追求最简单安全推理的场景。

```rust
batch.put_term(new_term);
batch.put_entries(entries);
storage.write_batch(batch, sync=true);  // 原子写入 + checksum 验证
```

### 有序分离写入（HashiCorp Raft）

HashiCorp Raft 采用了更直接的方式：先写 term，再写 log，两次都是同步的。在`raft.go:1414,1922`可以看到，`setCurrentTerm`包含 fsync 并且失败会 panic，之后才调用`StoreLogs`写日志。这样做的原理是，一旦 term 持久化，更高的 term 就会阻止旧 leader 的请求。这个方案的好处是实现简单，适用任何存储后端，并且采用 fail-fast 设计。缺点是需要两次 fsync，延迟会稍高。适合使用标准存储（如文件、BoltDB）的通用场景。

```go
// raft.go:1414,1922
r.setCurrentTerm(a.Term)  // 包含 fsync，失败则 panic
r.logs.StoreLogs(entries) // 包含 fsync
```

### 混合顺序（SOFAJRaft）

SOFAJRaft 用了一个巧妙的组合：term 同步写入，log 异步批处理。从`NodeImpl.java:1331,2079`的代码可以看到，`setTermAndVotedFor`是同步调用，会阻塞直到 fsync 完成，而`appendEntries`只是把日志放入队列就立即返回，后台线程批量写入。关键在于 term 的 fsync 完成后，才会把 log 入队，这保证了 term 一定先持久化。这个方案性能最优，因为 term 变更很少（只在 leader 切换时），可以接受同步开销，而 log 写入频繁（每次客户端写入），异步批处理大幅提升吞吐量。缺点是实现复杂，需要可靠的异步管道（SOFAJRaft 用了 LMAX Disruptor）。适合高吞吐量系统（>1000 writes/sec）。

```java
// NodeImpl.java:1331,2079
this.metaStorage.setTermAndVotedFor(req.term, null);  // 同步 fsync，阻塞
this.logManager.appendEntries(entries, closure);      // 异步入队，立即返回
```


## 异步 IO 调度

前面介绍的三种方案都在 **代码层面** 显式控制 IO 顺序：要么串行执行（等前一个完成再提交下一个），要么原子批处理。这些方案安全可靠，但限制了 IO 并发度。

为了追求更高性能，[OpenRaft](https://github.com/databendlabs/openraft) 正在设计一个异步 IO 调度系统：Raft core 把所有 IO 请求提交给执行队列，由队列调度 IO 并通过 callback 通知完成。这能最大化 IO 并发和吞吐量，但引出了核心问题：**哪些 IO 请求可以重排，哪些不可以？**


## 总结

### 核心规则

**Term 必须在 log 之前（或同时）持久化**

不变式：`如果 log(term=T)在磁盘 → term≥T 也在磁盘`

### 时空视角：问题的本质

我喜欢用时间和历史的方式来解释分布式一致性算法。一致性算法实际上虚拟了一个时间线，Raft log 就是这个虚拟时间上发生的事件。

从这个角度看：term 代表时间，log entries 是时间上发生的事件。

如果 IO 允许 term 回退，就相当于允许时间回退。但时间回退不代表已发生事件的回退——系统可以在之前的时间点重新改写历史，用新的事件覆盖已经发生的历史。这就是数据丢失的本质。

### 三种安全方案

原子批处理（TiKV）：term 和 log 同一批次，一次写入。有序分离（HashiCorp）：先写 term（panic on fail），再写 log。混合顺序（SOFAJRaft）：term 同步，log 异步批处理。


## 相关资源

- [OpenRaft docs: io-ordering][]
- [tikv/tikv][]
- [hashicorp/raft][]
- [sofastack/sofa-jraft][]


[OpenRaft docs: io-ordering]: https://github.com/databendlabs/openraft/blob/main/openraft/src/docs/protocol/io_ordering.md
[tikv/tikv]: https://github.com/tikv/tikv
[hashicorp/raft]: https://github.com/hashicorp/raft
[sofastack/sofa-jraft]: https://github.com/sofastack/sofa-jraft
