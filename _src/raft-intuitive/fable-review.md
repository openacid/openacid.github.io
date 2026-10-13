# 《Raft 的直观解释》正确性 review (fable)

Review 对象: [2026-08-08-raft-intuitive-cn.md](./2026-08-08-raft-intuitive-cn.md), 行号以当前修订版为准. 本 review 把文中框架当作独立协议来验证, 与检查论文一致性的 [另一份 review](./2026-08-08-raft-intuitive-cn-review.md) 角度不同.

## 总评

文章的协议内容已无本 review 已知的缺陷. 剩下的是几项需要作者输入才能完成的编辑项 (第一节), 以及已验证正确, 后续修改时不要动的部分 (第二节). 此前各轮发现的问题 (两个 quorum 不同带来的安全漏洞, Raft 选举规则的表述, commit 量化域, 读取规则的可执行化与偏序无最大 leaf 的情形, fence 维护规则, 子树陈述, 以及若干措辞) 均已在正文修复, 本文档不再记录过程. 写流程已由三阶段合并为两阶段 (第 1 阶段 = 禁写 + 读取, 第 2 阶段 = 写入), 全文编号引用已同步.

## 一. 剩余编辑项 (需要作者输入)

- 行 249 已把树上节点的 TimePoint 限定为全序子集, 因此行 259 的"视图中无最大 leaf, 只有多个极大 leaf"情形在框架内不会出现. 这不是错误, 是冗余: 该段可以简化, 或标注为"不采用行 249 限定时的一般情形".
- TODO 配图 7 处 (行 93, 113, 119, 135, 170, 205, 396).
- frontmatter refs 为占位符 "x: y" (行 12–13). 正文已点名 Paxos Made Simple 的 P2c (行 257), refs 应含它与 Raft 论文, 可选 Flexible Paxos.
- excerpt 为空 (行 19).

## 二. 已验证正确, 修改时保留

- 多历史/单历史拆分 (行 164–168, 245, 282–288): 正确. 多历史框架只靠 `cm2-grow-only` 和 `cm3-unique-timepoint` 就天然无冲突, commit 弱化为"写完一个 `WriteQuorum`"是安全的; `cs1`–`cs3` 恰好是收缩到单历史所需的全部增量.
- `cs1-global-max` (行 245): 正确, 且是全文核心价值——它统一了 Raft "leader 只能通过复制本 term 的 entry 来 commit" (Figure 8 / §5.4.2) 与 Paxos "只在自己的 ballot 上 accept": 旧 term 段作为 leaf 不大于其他分支的 leaf, 复制到多数派也不构成单历史 commit.
- 读取的最大 leaf 规则 (行 259–261): 正确. 读取者无法观测 committed, 按最大 leaf (大于视图中其余所有 leaf) 选择; committed 分支 (或其后代) 必然是任何合法视图的最大 leaf, 无最大 leaf 时所有极大 leaf 均未 committed, 任选安全.
- 两层选举映射 (行 340–347, 366–376): 正确. 禁写步骤比较 candidate 的 `(term, node_id)` (偏序, 拒绝不可比 = one-vote-per-term), 读取步骤比较 last log (leaf 的 TimePoint 大小); 与 `RequestVote` 四参数一一对应, 已逐条核对 Raft 投票规则.
- quorum 配置 (行 160–162): 正确, 含 1-write/4-read 在内都满足 `cm4-quorum-intersection`, 且框架正确地不要求 WriteQuorum 之间相交 (Flexible Paxos 的结论, 可注明出处). 注意 node_id 省略论证额外依赖 "majority 两两相交" (行 374 已注明), 这是 Raft 特有性质.
- 截断即隐藏 (行 392–394): 正确, 是把 Raft 放进 grow-only 树模型的正确方式; 行 386 对 Paxos acceptor 替换 value 的调和采用同一理解.
- membership 论证 (行 419–435): 正确. log 按前缀携带全部历史 ⇒ 新 config 的 write quorum 写入时旧数据一并到位 ⇒ 只需相邻 config 的 quorum 相交, 加上"前一个 config committed 后才 propose 下一个", 即单步变更的已知正确做法.
