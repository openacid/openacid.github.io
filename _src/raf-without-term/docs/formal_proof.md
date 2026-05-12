# raf-without-term 形式化安全证明

本文针对 `2026-05-11-raf-without-term-cn.md` 描述的 `raf-without-term` 协议模型，以及 `raf` 源码当前实现，给出一个可审阅的 safety proof 草案。

直接结论：修正后的设计可以继续使用 `(term, index)` 作为 `LogId`。关键点是：失败 election 留下的 slot 在没有 command 时不是 log entry；当某个 established leader 补齐这些 slots 时，必须把这些 slots 的 term 覆盖为自己的 `leader.term`。因此每个完整 log entry 的 term 都重新拥有唯一 established leader 来源，标准 Raft 的 log matching 和 leader completeness 证明可以平移过来。

## 1. 证明范围

证明覆盖：

- 静态 membership 下的 leader election safety。
- 基于 `prev_log_id` 的 log matching。
- quorum commit 的 leader completeness。
- state machine safety，即任意两个节点在同一 index 上提交的 entry 相同。
- 不单独持久化 `currentTerm` 时，`terms` 与 `cmds` 分离存储的安全性。

证明不覆盖：

- liveness。
- election timer、heartbeat、automatic election trigger。
- snapshot、log compaction、membership change。
- application payload 的持久化语义。当前代码里 `WriteRequest.id` 没有写入 `Cmd`，leader write 追加的是 `Cmd::empty()`。
- crash 发生在多个 storage 操作中间时的恢复语义。本文把每个已完成的 `Core` 状态转移视为原子完成后的状态。

## 2. 源码对应关系

| 协议概念 | 源码位置 | 证明中使用的语义 |
|---|---|---|
| 节点串行状态机 | `Core::run_loop()` | 单节点内所有协议状态转移串行化。 |
| 发起 election | `Core::do_elect()` | 取 `term = terms_len()`，本地 self-vote，并写入 `terms[term] = term`。 |
| 处理 vote | `Core::handle_request_vote()` | 要求 `req.term > local_last_term`、`req.term >= local_next_term_slot`，并检查 `last_log_id` freshness；grant 时写入 `terms[req.term] = req.term`，中间 gap 由 storage 按 index 补齐。 |
| 建立 leader | `Core::establish_leader()` | 达到 quorum 后设置 `established = true`；把 `[cmds_len, terms_len)` 覆盖为 `leader.term`；再追加 empty commands 补齐 `cmds`。 |
| 发送 replication | `Core::try_initialize_replication()` | 以 `prev_log_id` 为匹配点发送连续的 `terms` 和 `cmds` 窗口。 |
| 接收 Append | `Core::handle_append()` | 先检查 `prev_log_id`，再截断冲突 suffix，覆盖 `terms`，追加缺失 `cmds`。 |
| 处理 AppendReply | `Core::handle_append_reply()` | 维护每个 target 的 `matched` 和 `end`，收到更高 term 时退位。 |
| 推进 commit | `Core::try_update_committed()` | 只考虑 `matched >= leader.term` 的节点，并要求这些节点组成 quorum。 |

## 3. 模型和记号

设节点集合为 `N`，静态 membership 的 quorum 集合为 `Quorum(N)`。任意两个 quorum 必须相交。

每个节点 `n` 的持久化状态是两个有限序列：

- `T_n`：term array，对应源码中的 `terms`。
- `C_n`：command array，对应源码中的 `cmds`。

index 从 `0` 开始。约定：

- `T_n[0] = 0`。
- `C_n[0] = empty`。
- `0 < |C_n| <= |T_n|`。
- 当且仅当 `i < |C_n|` 时，节点 `n` 在 index `i` 有完整 log entry。
- `log_id_n(i) = (T_n[i], i)`。
- `last_log_id(n) = log_id_n(|C_n| - 1)`。

`LogId` 使用字典序比较：先比较 `term`，再比较 `index`。这与源码中 `LogId` 派生的 `Ord` 一致。

重要区分：

- `i >= |C_n|` 且 `i < |T_n|` 的位置只是 election marker，不是 log entry。
- election marker 可以记录为 `T_n[i] = i`，用于表示节点已经观察到这个 term slot。
- 当 leader `t` established 后，它会把本地 `[|C|, |T|)` 中的 election markers 改写为 `t`，再补 empty commands。这些位置从此成为 leader `t` 产生的完整 empty log entries。

因此，`T[i] <= i` 不是协议不变量。修正后的核心不变量是：每个非零完整 log entry 的 term 都对应唯一 established leader。

## 4. 证明义务

**P0：Quorum 相交。** `Membership` 中 node id 唯一，所有用于投票和 commit 的节点集合都是 membership 的子集。任意两个多数 quorum 相交。

**P1：单节点状态转移串行化。** 一个节点的 `RequestVote`、`Append`、`AppendReply`、`Write` 等事件由同一个 `Core` 顺序处理，不存在本地并发写坏协议状态。

**P2：存储 well-formed。** 任意可达稳定状态都满足 `T[0] = 0`、`C[0] = empty`、`0 < |C| <= |T|`。

**P3：term slot 唯一占用。** candidate 选择 `t = |T|` 发起 election 时，写入 `T[t] = t`。voter grant `req.term = t` 时，必须让本地 `T` 至少包含 index `t`，并写入 `T[t] = t`。

**P4：同一 term 单次授权。** 对任意节点 `v` 和任意 term `t`，`v` 最多向一个 candidate grant `t`。当前最保守的实现规则是：一旦本地已经观察到 `t`，就不再 grant `t`。这里的“观察到”包括 `terms[t]` slot 已存在，也包括本地最后一条完整 log entry 已经带有 term `t`。

**P5：投票 freshness。** voter 只在 `req.last_log_id >= local_last_log_id` 时 grant vote。

**P6：leader established 后覆盖 gap terms。** candidate 收到 quorum vote 后，必须在服务写入前把本地 `[cmds_len, terms_len)` 的 terms 覆盖成自己的 `leader.term`，再用 empty commands 补齐 `cmds`。

**P7：Append 只复制 leader 的完整 log。** `AppendRequest.terms.len() == AppendRequest.cmds.len()`，窗口从 `prev_log_id.index + 1` 开始，并且每个 entry 都来自 leader 本地完整 log。

**P8：Append 前缀匹配。** follower 只有在本地存在 `prev_log_id.index` 且本地 `log_id(prev_log_id.index) == prev_log_id` 时，才接受后续 entries。否则不修改 log。

**P9：冲突 suffix 可被覆盖，匹配 prefix 不变。** Append 被接受后，follower 只允许从第一个分歧 index 开始截断或覆盖；`prev_log_id.index` 及之前的 prefix 不变。

**P10：commit 只直接提交 leader election index 之后的 entry。** leader 只有在某个 index `i` 被 quorum matched，且 `i >= leader.term` 时，才把 `committed` 推进到 `i` 或更大。被补齐在 `leader.term` 之前的 empty entries 只能被间接提交。

## 5. 基础不变量

### I1：存储形状不变量

任意可达稳定状态都满足 `0 < |C| <= |T|`。

证明：

- 初始 `MemStorage::new()` 创建 `T = [0]` 和 `C = [empty]`。
- election 只追加或覆盖 `T`，不会让 `C` 变长。
- established leader 先覆盖 `[|C|, |T|)` 的 terms，再追加同样数量的 empty commands，因此补齐后 `|C| = |T|`。
- leader write 在 `T[|C|]` 写入 `leader.term`，再追加一个 command。
- Append 接受时先覆盖 `T` 的请求窗口，再只追加缺失的 `C`；若发现分歧，先截断 `C` 到分歧 index，再追加 leader suffix。

### I2：完整 entry 的 leader provenance

对任意非零完整 log entry `i < |C|`，`T[i] = t` 意味着该 entry 由唯一 established leader `t` 创建，或由这个 leader 复制到该节点。

证明：

- candidate 发起 election 时写入的 `T[t] = t` 在 `C[t]` 存在之前只是 election marker，不是完整 log entry。
- candidate established 后，`establish_leader()` 把 `[|C|, |T|)` 统一改写为 `leader.term`，再补 empty commands。因此这些新完成的 entries 都由这个 established leader 创建。
- leader 后续 write 也只写入当前 `leader.term`。
- follower 只能通过接受该 leader 的 Append 获得这些完整 entries。
- 由 I3，同一个 term 不会有两个 established leaders，所以 provenance 唯一。

### I3：同一 term 至多一个 established leader

一个 term `t` 至多被一个 established leader 拥有。

证明：

- 任意 established leader 都必须得到一个 quorum 的 grants。
- 假设 term `t` 有两个不同 established leaders `L1` 和 `L2`。
- 设它们获得的 quorum 分别为 `Q1` 和 `Q2`。
- 由 quorum intersection，存在节点 `v` 同时属于 `Q1` 和 `Q2`。
- `v` 必须分别 grant `t` 给 `L1` 和 `L2`。
- 这违反 P4。

因此同一 term 不可能存在两个 established leaders。

## 6. Log Matching

**定理 T1：如果两个节点在同一 index `i` 上具有相同 `log_id = (t, i)`，则它们在 `i` 及之前的完整 log prefix 相同。**

证明按 `i` 归纳。

index `0` 是固定默认 entry，显然成立。

对 `i > 0`：

- 由 I2，完整 entry `(t, i)` 由唯一 established leader `t` 创建。
- leader `t` 在自己的本地 log 中，index `i` 只有一个 entry。
- 其它节点获得 `(t, i)` 的唯一方式是接受 leader `t` 或后继合法 leader 的 Append。
- Append 由 P8 要求 `prev_log_id` 匹配；由归纳假设，`prev_log_id.index` 及之前的 prefix 已相同。
- P9 保证接受 Append 时不会修改已匹配 prefix。

因此两个节点如果在 index `i` 有同一 `LogId`，它们在 `i` 及之前的完整 prefix 相同。

这里的关键修正是 P6：失败 election marker 在成为完整 entry 前会被 established leader 的 term 覆盖。因此完整 entry 不会保留“没有 leader owner 的 failed term”作为自己的 `LogId`。

## 7. Leader Completeness

**定理 T2：如果 entry `e` 在 index `i` 被 term `t` 的 leader 提交，则所有 term `u > t` 的 established leader 都包含 `e`。**

证明：

1. leader 只直接提交 `i >= t` 的 entry。因此 `e` 是 term `t` leader 在自己 election index 或之后创建并复制到 quorum 的 entry。

2. 设提交 `e` 的 quorum 为 `Qc`。每个 `Qc` 中的节点都 matched 至少到 `i`。

3. 假设存在最小的 `u > t`，使 term `u` 的 established leader `Lu` 不包含 `e`。

4. `Lu` 必须从某个 quorum `Qv` 获得 vote。由 quorum intersection，存在节点 `v` 同时属于 `Qc` 和 `Qv`。

5. `v` 在 `Qc` 中 matched 到 `i`，所以曾经拥有包含 `e` 的 prefix。由于 `u` 是第一个不包含 `e` 的 established leader term，在 `v` 给 `Lu` 投票前，不存在更早的合法 leader 可以覆盖 `e`。因此 `v` 投票时仍包含 `e`。

6. `v` 只会在 `Lu.last_log_id >= v.last_log_id` 时 grant vote。下面分情况说明如果 `Lu` 不包含 `e`，这个 freshness 条件不可能成立：

   - 如果 `Lu.last_log_id.term < t`，它落后于 `v` 中包含 `e` 的 log。
   - 如果 `Lu.last_log_id.term == t`，但 `Lu` 不包含 index `i` 的 `e`，则 `Lu.last_log_id.index < i`，仍落后。
   - 如果 `Lu.last_log_id.term > t`，这个更高 term 的完整 entry 由某个 established leader `w` 创建。由于 `u` 是第一个不包含 `e` 的 established leader term，`w` 必须包含 `e`；再由 T1，拥有 `w` 的后续 entry 也必须拥有包含 `e` 的 prefix。因此 `Lu` 不可能拥有该更高 term entry 却缺少 `e`。

7. 所以 `v` 不可能 grant vote 给不包含 `e` 的 `Lu`，与 `Lu` established 矛盾。

因此所有更高 term 的 established leader 都包含已提交 entry `e`。

## 8. Commit Safety

**定理 T3：一旦某个 entry `e` 在 index `i` 被提交，未来任何合法 Append 都不能在任何节点上把 index `i` 覆盖成不同 entry 并再次提交。**

证明：

- 由 T2，所有未来 established leader 都包含 `e`。
- leader 发送 Append 时，请求窗口来自自己的完整 log，因此未来 leader 在 index `i` 发送的 entry 只能是 `e`。
- follower 接受 Append 前必须匹配 `prev_log_id`。若 follower 已包含 `e` 之前的 prefix，Append 不会把已提交 prefix 改成另一个 entry。
- 若 follower 暂时缺少 `e`，它只能通过包含 `e` 的合法 leader Append 获得 index `i`。

所以 index `i` 上的已提交 entry 在所有未来合法历史中保持不变。

**定理 T4：State Machine Safety。若两个节点分别提交了 index `i` 的 entry，则这两个 entry 相同。**

证明：

- 取两个提交事件中较早发生的一个，提交 entry 为 `e`。
- 由 T3，之后任何合法提交 index `i` 的 entry 都只能是 `e`。
- 因此两个节点在同一 index 上提交的 entry 相同。

## 9. 为什么仍然使用 `index >= leader.term`

修正后的设计会把更早的 gap slots 覆盖成当前 `leader.term`，所以可能出现 `T[i] = leader.term` 且 `i < leader.term` 的 empty entry。

这些 entries 不应被 leader 直接用于推进 commit。原因是：quorum matched 到 `i < leader.term` 并不能证明 quorum 已经匹配到 leader 当选时占用的 election index。`raf` 因此仍然使用更保守的提交门槛：

```rust
if quorum_has_matched(index) && index >= leader.term {
    commit(index);
}
```

一旦 leader 提交了 `leader.term` 或之后的 entry，它当选时占用的 entry 也已经在同一个 committed prefix 中；更早 backfilled empty entries 会随这个 prefix 一起间接提交。

## 10. 当前实现边界

以下是实现边界，不是本文 safety proof 的反例：

- `RequestVote` retry 仍然偏保守。当前没有持久化 `voted_for`，同一个 term 已经被观察后，重复请求会被拒绝。可以用 in-memory `voted_for` 改善可用性。
- `Core::handle_append()` 中 `append.term > last_term` 分支仍是 `TODO`。在当前没有 heartbeat 的最小实现里，非空 Append 会通过 entries 更新 `terms`；如果以后加入空 heartbeat，需要明确记录 observed term 的规则。
- follower commit 推进是保守的：当前只有 `append.commit_index < appended_last_index` 时才推进 follower commit。这可能推迟 follower 可见 commit，但不破坏 safety。
- `Membership::is_quorum()` 假设输入节点已经去重且属于 membership。当前主要调用点通过 `HashSet` 和 `BTreeMap` 满足这个前提；形式化模型仍需显式保留 P0。

## 11. 建议验证用例

建议实现或保留以下测试：

- `request_vote_fills_gap_to_requested_term`：voter 从 `terms.len() = 4` grant `req.term = 6` 后，`terms.len() = 7`，且 `terms[6] = 6`。
- `request_vote_rejects_repeated_gapped_term`：同一个落后 voter grant `term = 6` 一次后，第二个 candidate 请求同一 term 必须被拒绝。
- `request_vote_rejects_observed_term_without_term_slot`：本地完整 log 已经观察到 term `6`，即使 `terms[6]` slot 尚不存在，也必须拒绝 `req.term = 6`。
- `establish_leader_overwrites_gap_terms_with_leader_term`：leader term `6` established 后，原来 `[4, 5]` 的 gap terms 被覆盖成 `[6, 6]`，并追加 empty commands。
- `same_term_two_candidates_cannot_both_establish`：三节点场景中两个 candidate 选择同一 gapped term，不能同时 established。
- `committed_current_term_entry_survives_later_leader`：一个 leader 提交 `index >= leader.term` 后，后续更高 term leader 必须包含该 index 的 entry。

## 12. 总结

`raf-without-term` 的安全核心不是“没有 term”，而是“不再单独持久化 `currentTerm`”。term 仍然存在，并且完整 log entry 仍然用 `(term, index)` 比较新旧。

修正后的 gap completion 规则消除了之前的歧义：失败 election 留下的 term slot 在没有 command 时不是 log entry；一旦它被补成完整 entry，它的 term 会被 established leader 覆盖。于是完整 entry 的 `LogId` 又能指向唯一 leader 历史，log matching 和 leader completeness 可以按 Raft 的标准结构成立。
