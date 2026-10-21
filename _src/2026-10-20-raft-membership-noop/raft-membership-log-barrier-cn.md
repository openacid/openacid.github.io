---
title: "Raft 成员变更：何时需要先提交 leader 的当前 term 日志"
date: 2026-10-20
disabled_url: /distributed/raft-membership-log-barrier-cn/
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
description: "标准 joint 用 config 日志本身建立 barrier，两步都无需额外要求 leader 的 noop 已提交。单步变更与允许 joint 回退的扩展则需要 leader 先提交当前 term 日志，以排除较小 term 遗留的冲突变更。"
---

![Raft 成员变更与日志 barrier](raft-membership-noop-banner-small.png)

Raft 的单步成员变更从 `C0` 直接切换到 `C1`，要求 leader 先提交一条当前 term 的日志，再追加 `C1`。标准 joint 则通过 `C01 = [C0,C1]` 过渡到 `C1`，由 config 日志本身建立 barrier，两步都无需额外要求 leader 的 noop 已提交。如果在标准 joint 之外，额外允许 `C01` 回退到 `C0`，那么完成到 `C1` 与回退到 `C0` 都需要先提交 leader 的当前 term 日志。

要检查的 quorum 关系有两种：变更前后的 `C0` 与 `C1`，以及不同 leader 从 `C0` 先后提出的 `C1` 与 `C2`。文中使用普通 Raft 的多数派 quorum。

## 1. Raft 用单步变更或 joint 变更调整成员

**单步成员变更（single-step config change）**通过一条 config 日志，直接从 `C0` 切换到 `C1`。常见的 single-server change 每次只增加或删除一个投票节点，让 `C0` 与 `C1` 相交。例如，从 `{a,b,c}` 迁移到 `{b,c,d}`，可以先增加 `d`，提交后再删除 `a`。

**joint 成员变更（joint config change）**先写入 joint config `C01 = [C0,C1]`，提交后再写入目标 config `C1`。在 `C01` 下，选举和提交都必须同时取得 `C0` 与 `C1` 各自的 quorum，因此可以一次调整多个节点。[Raft 论文 §6][ref-raft] 规定了 `C01` 先提交、`C1` 再追加的顺序。

下面两列展示同一次迁移，时间都从下往上：

```text
| single-step                 joint
| 
| {b,c,d}                     C1 = {b,c,d}
|     ↑                           ↑  C01 提交后完成
| {a,b,c,d}                   C01 = [{a,b,c},{b,c,d}]
|     ↑                           ↑
| {a,b,c}                      C0 = {a,b,c}
```

后面的反例依赖 config 的启用时机。[《从 Flexible Paxos 到 Raft：read-write quorum》][post-rw-quorum] 中的规则，按本文术语转述如下：

> Raft 通过日志传播 config。节点把 `C1` 的 config 日志追加到本地后，就开始使用 `C1`，不必等 `C1` 提交。

因此，`C1` 即使只留在少数节点上、尚未提交，持有 `C1` 的节点仍可能按 `C1` 收集选票。提出 `C1` 的 leader 宕机，并不会自动排除 `C1`。

## 2. 两个 quorum set 相交的定义

本文将 **config** 与 **quorum set** 视为同一个概念，表示一组合法的 quorum。例如，`C = {a,b,c}` 允许的最小 quorum 是 `{a,b}`、`{a,c}`、`{b,c}`。

> 对两个 config（quorum set）`A` 和 `B`，任取 `qa ∈ A`、`qb ∈ B`，都有 `qa ∩ qb ≠ ∅`，就称 `A` 与 `B` 相交，记作 `Intersect(A,B)`。

后文说“两个 config 相交”，都使用这个定义。例如，`C0 = {a,b,c}` 与 `C1 = {b,c,d}` 共享节点 `b`、`c`，但 `C0` 允许 quorum `{a,b}`，`C1` 允许 quorum `{c,d}`。`{a,b}` 与 `{c,d}` 没有交集，所以 `C0` 与 `C1` 不相交。

## 3. 成员变更要求正在被使用的 quorum 相交，形成互斥

成员变更要求**仍能用于选举或提交的 quorum 之间有交集**。交集中的节点保存日志与投票记录，使不同 quorum 无法作出冲突决定。

设 `C0` 已提交。leader `L1` 从 `C0` 提出 `C1`，`C1` 尚未提交时，`L1` 宕机。没有收到 `C1` 的 leader `L2` 仍从 `C0` 出发，提出 `C2`：

```text
|       C1          C2
|          ↖      ↗
|              C0
```

需要分别检查两组相交要求：

1. **`C0` 与 `C1` 相交，`C0` 与 `C2` 也相交。** 从 `C0` 切换到 `C1` 时，节点可能分别使用 `C0`、`C1`；从 `C0` 切换到 `C2` 时，节点可能分别使用 `C0`、`C2`。每一次切换都需要前后两个 config 互斥。
2. **`C1` 与 `C2` 也需要相交。** 持有 `C1` 的节点可能按 `C1` 重新选出 leader，`L2` 则已经在使用 `C2`。如果 `C1` 的某个 quorum 与 `C2` 的某个 quorum 没有交集，`C1` 和 `C2` 就可能分别作出冲突决定。

如果 `C1` 与 `C2` 本身不相交，协议就必须在启用 `C2` 之前，先排除 `C1` 这条日志分支，使 `C1` 无法再用于选举或提交。后面讨论的日志 barrier，正是用来完成这一步。

## 4. 单步变更缺少 barrier 时，未提交的 Cu 可覆盖已提交的 Cv

### 从同一个 C0 分别增加 u 和 v

[《Raft 成员变更上踩的坑》][post-raft-bug] 讨论过这样一个反例：`C0 = {a,b,c,d}` 已提交，leader `a` 从 `C0` 增加 `u`，提出 `Cu`；leader `d` 从 `C0` 增加 `v`，提出 `Cv`。`Cu`、`Cv` 都与 `C0` 相交，却允许互不相交的 quorum `{a,b,u}`、`{c,d,v}`：

```text
|   Cu = C0 + u          Cv = C0 + v
|   quorum {a,b,u}       quorum {c,d,v}
|              ↖       ↗
|                  C0
|              {a,b,c,d}
```

假设各节点共有的日志到 index 5 为止，最后一条日志来自 term 0。`u`、`v` 已作为非投票节点追上 index 5。暂时拿掉“先提交当前 term 日志”的限制，按旧文的 ASCII 时序图展开。图中 `L1`、`F1` 分别表示 term 1 的 leader、follower，term 2、3 以此类推；`X` 表示宕机，`Cu`、`Cv` 表示节点持有的 config 日志。时间从下往上：

```text
| time ↑ |   u     a     b     c     d     v
|        | -----------------------------------
|  t8    |  Cu    Cu    Cu    Cu    Cu
|  t7    |  F3    L3    F3
|  t6    |                          X
|  t5    |                    Cv    Cv    Cv
|  t4    |              F2    F2    L2
|  t3    |        X
|  t2    |  Cu    Cu
|  t1    |        L1    F1    F1
|        | -----------------------------------
```

1. **t1–t3：term 1 的 `a` 留下未提交的 `Cu`。** `a` 取得 `{a,b,c}` 的选票，按 `C0` 当选。`a` 在 index 6 追加 `Cu`，日志只保存在 `{a,u}` 上，尚未提交，`a` 就宕机了。
2. **t4–t6：term 2 的 `d` 提交 `Cv`。** `b`、`c`、`d` 没收到 `Cu`，仍按 `C0` 选出 `d`。`d` 在 index 6 追加 `Cv`，复制到 `{c,d,v}`，构成 `Cv` 的 quorum，因此 `Cv` 提交。随后 `d` 宕机。`b` 参加了选举，却没有收到 term 2 的日志。
3. **t7：term 3 的 `a` 按 `Cu` 重新当选。** `a` 恢复后，用本地 `Cu` 收集 `{a,b,u}` 的选票。`b` 的日志仍停在 index 5，比 `a` 的 term 1 日志更旧，因此可以投给 `a`。
4. **t8：`a` 提交 `Cu`，并覆盖 `Cv`。** `a` 向 `{a,b,u}` 复制一条 term 3 的 noop，提交这条 noop 及其前面的 `Cu`。之后，`a` 把 `Cu` 复制到 `c` 和恢复后的 `d`，覆盖 `c`、`d` 上已提交的 `Cv`。

term 3 的 noop 用来满足 Raft 的提交规则：`Cu` 属于 term 1，`a` 在 term 3 要先提交自己的当前 term 日志，再连带提交前缀中的 `Cu`。**`a` 没有重新提出 `Cu`，只是提交了本地遗留的 `Cu`。** ASCII 图只标出 config 的传播，省去了这条不改变业务状态的 noop。

这段历史里，每个 term 都只有一个 leader。缺口出在跨 term 的 config 竞争：提交 `Cv` 的 `{c,d,v}`，与后来选出 `a` 的 `{a,b,u}` 完全分离。

### 通过共同的父 config C0 建立互斥

`Cu` 和 `Cv` 的 quorum 可能分离，但 `a` 提出 `Cu`、`d` 提出 `Cv` 时，共同依赖的 config 都是 `C0`。因此，要通过 `C0` 建立互斥：可以在 `C0` 下提交日志，留下后续选举必须遵守的记录；也可以加强选举约束，阻止持有 `Cu`、缺少 `Cv` 的 `a` 重新当选。

单步变更采用日志方案。[旧文][post-raft-bug] 中修正条件的核心，按本文术语转述如下：

> 新 leader 必须先提交一条自己当前 term 的日志，才允许追加成员变更日志。

也就是说，term 2 的 `d` 必须先在 `C0` 下提交一条 term 2 日志，再提出 `Cv`。`C0` 的一个 quorum 因此保存比 term 1 的 `Cu` 更新的日志，能够拒绝只持有 `Cu` 的 `a`。这是 [Ongaro 对单步成员变更给出的修正条件][ref-raft-single-server-bug]。

## 5. 标准 joint 的两步变更都无需额外的 noop 提交 barrier

### 从 C0 提出 C01 或 C02，都保留 C0 的 quorum

leader `L1` 从 `C0` 提出 `C01 = [C0,C1]`，`C01` 尚未提交时，`L1` 宕机。未收到 `C01` 的 leader `L2` 仍从 `C0` 出发，提出 `C02 = [C0,C2]`：

```text
|  C01 = [C0,C1]       C02 = [C0,C2]
|              ↖     ↗
|                 C0
```

`C01` 的每个 quorum 都包含 `C0` 的一个 quorum，`C02` 的每个 quorum 也包含 `C0` 的一个 quorum。`C0` 允许的任意两个 quorum 相交，因此 `C01` 与 `C02` 必定相交。

### C01 提交后，后续 leader 只能完成到 C1

假设 `C01` 已提交，leader `L2` 准备完成到 `C1`。即使 `L2` 在完成之前宕机，接任的 `L3` 也只能继续完成到 `C1`。`L2` 与 `L3` 用来完成变更的 quorum 都属于 `C1`，必定相交。

所以，标准 joint 在进入阶段保证 `C01` 与 `C02` 相交，在完成阶段保证 `L2`、`L3` 都使用 `C1` 的 quorum。**先提交 `C01`，再完成到 `C1`**，让 config 日志本身建立了 barrier，无需额外要求 leader 的 noop 已提交。

如果 `L2` 继承的是 `L1` 尚未提交的 `C01`，`L2` 仍须先提交 `C01`，才能追加 `C1`。由于 `C01` 属于 `L1` 的 term，`L2` 可能需要先提交自己当前 term 的日志，连带确认 `C01`；这是 Raft 本身的提交规则（[论文 §5.4.2][ref-raft]）。

## 6. 如果允许 joint 回退，会破坏 quorum 互斥的前提，因此需要日志 barrier

标准 Raft 在 `C01 = [C0,C1]` 提交后，继续完成到 `C1`。这里我们扩展标准 joint，额外允许 `C01` 回退到 `C0`。取 `C0 = {a,b,c}`、`C1 = {x,y,z}`：

```text
|  C0 = {a,b,c}          C1 = {x,y,z}
|  quorum {a,b}          quorum {x,y}
|              ↖        ↗
|                  C01
|                [C0,C1]
```

`C0` 与 `C01` 相交，`C1` 与 `C01` 也相交，但 `C0` 的 quorum `{a,b}` 与 `C1` 的 quorum `{x,y}` 分离。新增回退后，`C01` 的后继不再都使用 `C1` 的 quorum，标准 joint 用来保证互斥的前提就被破坏了。缺少 barrier 时，leader `a` 可以按 `C0` 继续回退提案，leader `y` 可以按 `C1` 完成变更，`a` 与 `y` 使用的 quorum 可能完全分离。

### 只给回退加 barrier，仍可能提交冲突的 C0 与 C1

当完成与回退同时被允许时，两个方向都需要提交 barrier。只检查回退请求，仍然可能出现下面这段历史：

1. **term 1：`a` 通过 barrier 后提出回退。** `a` 先在 joint quorum `{a,b,x,y}` 提交自己的 noop，再追加回退到 `C0` 的日志。回退日志只留在 `a` 上，尚未提交，`a` 随即宕机。
2. **term 2：`y` 跳过 barrier，直接完成。** `y` 持有 term 1 的 noop，得到 joint quorum `{b,c,x,y}` 的选票。`y` 直接提出 `C1`，并在 `{y,z}` 上提交。`b` 始终没有收到 term 2 的日志。
3. **term 3：`a` 提交旧回退分支。** `a` 的日志比 `b` 多一条 term 1 回退日志，因此能按 `C0` 取得 `{a,b}` 的选票。`a` 再提交 term 3 的 noop，就能连带提交旧回退日志。

term 1 的 `a` 通过了提交 barrier，但 term 2 的 `y` 在提出 `C1` 之前，没有留下更新的日志来约束 `a` 持有的回退提案。term 3 的 `a` 只是提交继承的 `C0` 日志，给“新回退请求”加检查挡不住 `a`。

如果协议始终只允许 `C01` 完成到 `C1`，既不产生回退到 `C0` 的日志，也没有遗留的 `C0` 回退提案，那么完成变更的 leader 都只能使用 `C1` 的 quorum，可以沿用标准 joint 的保证。

## 7. 在公共 config 提交当前 term 日志，为新 config 建立 barrier

**对单步变更和允许 joint 回退的扩展，leader 先在公共 config 的一个 quorum 上提交当前 term 日志，记录自己的 term，再提出新 config。**

例如，`L1` 在 term 1 从 `C0` 提出尚未提交的 `C1`，`L2` 在 term 2 准备从 `C0` 提出 `C2`。`L2` 先在 `C0` 下提交一条 term 2 日志，就相当于在 `C0` 的一个 quorum 上登记：现在接受的 leader 是 term 更高的 `L2`。`C1` 的每个 quorum 都与保存 term 2 日志的这个 quorum 相交；配合 Raft 的 term 与日志新旧检查，旧 leader `L1` 及其遗留的 `C1` 就无法再成功推进与 `L2` 冲突的变更。

这份记录通常是一条 noop，也可以是一条当前 term 的业务日志。同一个 leader 在同一个 term 内已经提交过这样的日志，就不必为每次成员变更重新追加 noop。

### 联合选举也能建立互斥，但 C0 的 quorum 可能已经不可用

假设集群从 `C0` 变到 `C_new`。从互斥的角度，也可以考虑让持有 `C_new` 的 candidate 按 joint config `[C0,C_new]` 重新选举。candidate 同时取得 `C0` 与 `C_new` 的 quorum 选票，就能通过 `C0` 的投票记录，约束较小 term 的 leader。

问题是，**candidate 本地持有 `C_new` 的日志，不一定知道 `C_new` 是否已经在集群中提交，也不能保证旧 `C0` 仍然可用。** 例如，集群从 `C0 = {a,b,c}` 经过 joint 迁移到 `C_new = {x,y,z}`。按 [Raft 论文 §6][ref-raft] 的规则，`C_new` 提交后，`a`、`b`、`c` 就可以全部下线。

此时，candidate `x` 可以取得 `{x,y}` 的选票，按 `C_new` 当选。但如果每次选举都强制 `x` 再取得 `C0` 的 quorum，已经下线的 `a`、`b`、`c` 就会让选举无法完成。

因此，更稳妥的方式是：candidate 先按本地最新的 `C_new` 选举，当选后再按 `C_new` 提交一条当前 term 日志，确认 `C_new` 及其前缀，然后才提出下一份 config `C_next`。对这次成员变更而言，公共 config 就是 `C_new`，不需要依赖已经退出的 `C0`。

## 8. 单步变更与 joint 变更都通过日志提交建立互斥

[《Raft 成员变更上踩的坑》][post-raft-bug] 对两种方法共同点的概括，按本文术语转述如下：

> 成员变更都要通过旧 config 的 quorum 建立互斥，使从同一个旧 config 提出的冲突变更至多有一份被提交。
>
> 单步变更先用一条业务日志或 noop 建立互斥；joint 变更则由 config 日志本身完成这一步。

OpenRaft 的扩展成员变更允许 joint 回退。因此，本文讨论的实现统一检查当前 leader 的第一条 noop 是否提交，覆盖成员变更与直接追加 config 的入口：

```rust
if cluster_committed >= Some(noop_log_id) {
    return Ok(());
}
```

`cluster_committed` 是 quorum 已确认的提交位置，`noop_log_id` 是当前 leader 第一条 noop 日志的位置。标准 joint 路径也经过这个统一检查，从而与回退等扩展情形使用同一组入口约束。

回到本文的问题，三种情况的结论是：

1. **标准 joint 的两步都不需要额外要求 leader 的 noop 已提交。** 从 `C0` 进入 `C01 = [C0,C1]` 时，`C01` 与从同一个 `C0` 提出的 `C02 = [C0,C2]` 都包含 `C0` 的 quorum，必定相交。第一步提交的 `C01` 本身就构成日志 barrier；此后只允许完成到 `C1`，所以第二步也不需要额外的 noop 提交条件。
2. **单步变更需要先提交 leader 的当前 term 日志。** 从 `C0` 分别提出的 `Cu`、`Cv` 虽然都与 `C0` 相交，`Cu` 与 `Cv` 却可能不相交。因此，leader 必须先在 `C0` 下提交当前 term 日志，排除较小 term 遗留的变更，再提出新的 config。
3. **如果额外允许 joint 回退，完成与回退都需要先提交 leader 的当前 term 日志。** `C01` 既能完成到 `C1`，又能回退到 `C0`，而 `C0` 与 `C1` 可能不相交。因此，无论准备追加 `C0` 还是 `C1`，leader 都要先在 `C01` 下提交当前 term 日志，建立 barrier。

需要这个 barrier 时，提交的可以是 noop，也可以是当前 term 的业务日志；关键是**leader 在提出新 config 之前，已经提交过自己当前 term 的日志**。

[post-raft-bug]: /distributed/raft-bug-cn/ "Raft 成员变更上踩的坑"
[post-rw-quorum]: /distributed/raft-rw-quorum/ "从 Flexible Paxos 到 Raft：read-write quorum"
