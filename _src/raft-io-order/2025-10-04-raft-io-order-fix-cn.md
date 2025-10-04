---
title:      "Raft 中的 IO 执行顺序(修正版: SoftState 与 HardState)"
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
excerpt: "修正之前文章对 Raft IO 顺序问题的理解。问题不在 Raft 的设计，而在于实现中 SoftState 与 HardState 的区分导致的陷阱"
---


![](./raft-io-order-fix-banner.webp)


## 前言

在之前的[Raft 中的 IO 执行顺序](./2025-10-02-raft-io-order-cn.md)中，我用一个已提交数据丢失的例子来解释"先写日志后写 term"可能造成的问题。但那个例子并不能正确反映 IO-reorder 的真正问题。本文将修正这个理解，并给出一个更严谨的例子。


## 回顾之前的错误

之前的文章用了这个时间线：

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
------+---+---+---+--------+-----+---------> time
      t1  t2  t3  t4       t5    t6
```

时间线解释：
- t1-t2: N1 成为 leader（term=1）
- t3-t4: N5 成为 leader（term=5）
- t5: L5 复制 E5-1 到 N3，N3 需要持久化 term=5 和 E5-1
- t6: L1 尝试复制 E1-1 到 N3

我当时的推理：如果 N3 先写了 E5-1，后写 term=5，崩溃重启后可能出现 `term=1, entries=[E5-1]` 的状态，导致在 t6 接受 L1 的请求，覆盖已提交的数据。

**前文错误在于**：Raft 要求 save-term 和 save-entries 的 IO 都必须完成才能返回成功，所以 Leader 不会误认为数据已提交。Raft 的设计本身没有问题。

这个例子不能反映出 IO-reorder 的问题. 要揭露 IO-reorder 的问题,
我们需要考虑 Raft 实现中的 SoftState 和 HardState 的分离.


## SoftState 与 HardState 的陷阱

IO-reorder 之所以成为问题，是因为实际实现中为了性能，会分离内存状态(`soft_term`)和磁盘状态(`hard_term`)。处理 appendEntries 时，先更新内存状态，然后异步下发 IO：
- 收到 appendEntries，如果 `req.term > soft_term`，立即更新 `soft_term`
- 异步提交 save-term IO
- IO 完成后更新 `hard_term`（有些实现中可能没有显式的 `hard_term`）

这种状态分离引入了 Raft 论文中没有定义的行为（Raft 只关注磁盘状态）：

```rust
struct RaftState {
    // In-memory state (SoftState), may be ahead of disk
    soft_term: u64,

    // On-disk state (HardState), updated only after IO completes
    hard_term: u64,
}
```

上面描述的流程是常见的 Raft 实现的流程, 在没有 IO-reorder 时, 它是正确的.


## 问题场景

用一个更完整的时间线来展示 IO-reorder 带来的问题：

```text
Legend:
Ni:   Node i
Vi:   RequestVote, term=i
Li:   Establish Leader, term=i
Ei-j: Log entry, term=i, index=j

N5 |          V5  L5     E5-1     E5-2
N4 |          V5         E5-1     E5-2
N3 |  V1              V5,E5-1  V5,E5-2  E1-1
N2 |  V1      V5                        E1-1
N1 |  V1  L1                            E1-1
------+---+---+---+------+--------+-----+------> time
      t1  t2  t3  t4     t5       t6    t7
```

- t1-t4: 两次选举，N1（term=1）和 N5（term=5）先后成为 leader
- **t5**: L5 复制 E5-1 到 N3（N3 的 `soft_term=1 < req.term=5`）
  - N3 需要执行两个 IO：持久化 term=5 和 E5-1
  - 等待两个 IO 完成才返回成功
- **t6**: L5 复制 E5-2 到 N3（关键时刻）
  - N3 可能还在处理 t5 的 IO
  - 这时是否存在 IO-reorder 至关重要
- t7: L1 尝试复制 E1-1（term=1, index=1）

**关键在于 t6 时刻的第二个 AppendEntries 请求**。让我们看看 N3 的内部状态变化。

### t5 时刻：第一个 AppendEntries

N3 收到 `appendEntries(term=5, entries=[E5-1])`：

```rust
fn handle_append_entries(&mut self, req: AppendEntries) {
    // Check: RPC term > in-memory term?
    if req.term > self.soft_term {
        self.soft_term = req.term;              // Update memory immediately: 5
        self.submit_io(save_term(req.term));    // Submit IO request
    }

    self.submit_io(save_entries(req.entries));  // Submit IO request

    // Wait for both IOs to complete
    wait_for_both_ios();
    return success();
}
```

N3 的状态：
- `soft_term = 5`（内存已更新）
- `hard_term = 1`（磁盘还未更新，IO 进行中）
- IO 队列：`save_term(5)`, `save_entries(E5-1)`

这个请求本身是正确的，问题出现在下一个时刻。


### t6 时刻：第二个 AppendEntries

N3 还没完成 t5 的 IO，就收到了 `appendEntries(term=5, entries=[E5-2])`。

如果代码只检查内存 `soft_term`（大多数实现的做法）, 并提交 save-entries IO：

```rust
fn handle_append_entries(&mut self, req: AppendEntries) {
    // Check: 5 > 5? No
    if req.term > self.soft_term {
        // Won't enter this branch
    }

    // Only submit save_entries(E5-2)
    self.submit_io(save_entries(req.entries));

    // Only wait for save_entries to complete
    wait_for_io(save_entries);
    return success();  // Return success!
}
```

**问题出现**：在允许 IO-reorder 的时候, 
- `save_entries(E5-2)` 完成
- 但 `save_term(5)` 可能还没完成（如果存在 IO 重排序）
- N3 向 Leader 返回成功

如果 N3 此时崩溃重启，磁盘状态可能是：
- `hard_term = 1`（save_term(5) 未完成）
- `entries = [E5-1, E5-2]`（都完成了）
- Leader L5 认为 E5-2 已提交



### t7 时刻：数据丢失

重启后 N3 的磁盘状态：`term=1, entries=[E5-1, E5-2]`

当 L1 发送 `appendEntries(term=1, entries=[E1-1])`：
- N3 检查：RPC term (1) == 本地 term (1)，接受
- E1-1 覆盖 index=1
- **已向 L5 确认提交的 E5-1 和 E5-2 被覆盖**


注意, 如果不允许 IO-reorder, 那么 t6 的 `save_entries(E5-2)` 的完成就暗示了
`save_term(5)` 的完成, 满足了 appendEntries 成功的条件, 不会出现问题.


## 问题的本质

如果允许 IO-reorder，必须检查 `hard_term` 来判断是否下发 save-term IO；如果不允许 IO-reorder，检查 `soft_term` 即可。

Raft 论文不区分 soft/hard state，这是实现相关的陷阱。论文要求 "Before responding to RPCs, a server must update its persistent state"，在实现中需要更精确的表述： **必须等待所有使 `hard_term >= req.term` 的 IO 完成后，才能返回成功**。


## 正确的做法

检查磁盘 term（HardState）而不是内存 term：

```rust
fn handle_append_entries(&mut self, req: AppendEntries) {
    // Check disk state, not in-memory state!
    let need_save_term = req.term > self.hard_term;

    if need_save_term {
        self.soft_term = req.term;
        self.submit_io(save_term(req.term));
    }

    self.submit_io(save_entries(req.entries));

    if need_save_term {
        wait_for_both_ios();  // Must wait for save_term to complete
    } else {
        wait_for_io(save_entries);
    }

    return success();
}
```

注意：这种实现可能多次提交 save-term IO，需要在实现中谨慎优化。


## 主流实现的方案

主流实现（TiKV、HashiCorp Raft、SOFAJRaft）通过限制 save-term 和 save-entries 不能 reorder，因此只检查 `soft_term` 也是安全的：

1. **原子批处理（TiKV）**：将 save-term 和 save-entries 放到一个 IO 请求里，一次性提交。这样根本不存在"第二个 appendEntries 只提交 save_entries"的情况。

2. **有序分离（HashiCorp Raft）**：save-term 和 save-entries 顺序执行，不会重排序。先完成 term 的 fsync（失败则 panic），再写 log。

3. **混合顺序（SOFAJRaft）**：term 同步写入（阻塞等待 fsync），log 异步批处理。保证了 save_term 完成后才会入队 save_entries。


## 总结

Raft 论文的抽象模型（只有 HardState）和实际实现（SoftState + HardState）之间存在微妙的映射关系。

**关键不变式**：log entry (term=T) 在磁盘 → hard_term ≥ T 也必须在磁盘

维护此不变式的两种方式：
1. **消除 IO-reorder**：原子批处理、有序执行或混合方式（主流实现）
2. **处理 IO-reorder**：检查 HardState，等待必要的 IO 完成


## 相关资源

- [之前的文章：Raft 中的 IO 执行顺序](./2025-10-02-raft-io-order-cn.md)
- [OpenRaft docs: io-ordering](https://github.com/databendlabs/openraft/blob/main/openraft/src/docs/protocol/io_ordering.md)
- [tikv/tikv](https://github.com/tikv/tikv)
- [hashicorp/raft](https://github.com/hashicorp/raft)
- [sofastack/sofa-jraft](https://github.com/sofastack/sofa-jraft)
