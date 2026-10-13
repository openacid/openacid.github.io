- state: user data 存储系统存储的任意用户逻辑的数据

- commit(提交): 数据一定可以通过某种方式读到, 且每次按照同样的方式都能读到.

问题:
信息
高可靠
高可用
liveness


P  = (granted_index, V=(index, state)), qr, qw
Aᵢ = (granted_index, V=(index, state)), [PrevIndex, ...]

```
trait Index: PartialOrd + PartialEq {}

trait State<Item>: PartialOrd + PartialEq + Extend<Item> {
    fn new() -> Self;
    fn union(self, other: Self) -> Result<Self, Error>;
    fn list_memberships(&self) -> Vec<Membership>
}

struct P<I:Index, ST:State> {
    granted_index: I,
    v: V<I, ST>,
    membership: Membership,
}

struct A<I:Index, ST:State> {
    granted_index: I,
    v:             V<I, ST>,
    prev_index:    HashSet<I, I>,
}

struct V<I:Index, ST:State> {
    index: I,
    state: ST,
}

struct Membership {
    read_quorums: HashSet<Quorum>,
    write_quorums: HashSet<Quorum>,
}

type Quorum = HashSet<NodeId>;
```

香浓信息理论定义:
信息是用来消除随机不定性的东西。
C-info-def


# 存储要做什么

(通过某种策略)写入一个信息, 如果应答OK, 则一定能(通过某种方式)读到.



# 信息确定性 原则要求: 不能覆盖

因此根据C-info-def,
committed 永远能被读到.
因此要求committed 的信息不能被覆盖,
C-committed-no-override


# 数据可靠性要求 多副本写

我有一份数据需要存储
存储不可靠,
于是我需要多副本.

P = (state)

```graphviz
P
+-----.
|     |
v     v
st₁   st₂   st₃

A₁    A₂    A₃   A₄
```


# 数据可用性要求 quorum 写

如果每次写入, 要求所有节点都写成功才算提交,
那么任何一个节点宕机, 都会造成写入失败
也就是说可用性从单机的可用性`1-p`降低到了`1-np`

因此写入必须要求只写部分就认为成功.
qwᵢ: quorum for write: 部分或全部节点的集合

> 例如 可以要求一个 4 节点系统 至少写2份
>
> 这样既能保证有多份数据提供较高的可靠性,
> 也不会因为要求写过多的节点而降低可用性:
>
> ```graphviz
> P
> +-----.
> |     |
> v     v
> st₁   st₂
>
> A₁    A₂   A₃   A₄
> ```
>
> qwᵢ: any 2 accepotrs:
> ```
> {
>   A₁A₂,
>   A₁  A₃,
>   A₁    A₄,
>     A₂A₃,
>     A₂  A₄,
>       A₃A₄,
> }
> ```
>
> 可靠性:
> 可用性:


# 定义 Committed

根据C-info-def, 
信息是用来消除随机不定性的东西。

如果有时能读到有时不能, 它就不是一个 **信息**.
而我们只把确定的 **信息** 定义为 committed.  即,
**如果写入的值满足一定能通过某种方法读取到,
则认为它是 committed**.
C-committed-def

因此 committed 也就是说真正写入了一个信息.
在本文里一定可见就是读一个qrⱼ 一定能见到写的数据.
(但见到的不一定的是提交的)


# 写后必须可见要求 quorum 读

信息要求确定可读,
C-info-def

写入之后要保证能读取到.

例如:
显然, 在qwᵢ qrⱼ = 3/5 个节点, 的系统中,
如果 P 只写了1份数据, 一个执行读取动作的P' 有时可能能从3/5个 replica
中读到St₁,  有时不能.


因此任何一次写入的节点集合, 与任何一次读取的节点集合, 必须有交集,
TODO: 交集能恢复state
才能至少保证写入成功的数据可以被读到

因此要求
C-QWR:
qwᵢ ∩ qrⱼ ≠ ø,

例如 qwᵢ 是 4 个 acceptor 中的任意2个, qrⱼ 是4 个 acceptor  中任意3个.
就可以保证写完qwᵢ的数据 一定可见.



# 信息确定性 原则要求: 单调增

根据C-committed-no-override

为了消除不确定性, 已提交的信息不能被覆盖.
因此 系统存储的信息必须是一个只增的结构:
C-state-mono-incr

[state.md][]

TODO A 的 state, 系统的 state

它是一个 **只增** 的结构: 日志只能追加.
其他系统也都一样. 其核心都是一个 **只增** 的 state.

> 而通常我们使用的存储, 是可以改变状态的:
> 例如先存一个变量x=1, 再覆盖它的值: x=2
> 但这只是一个 **方便** 的抽象.
> 实际上系统中完整的状态是: `x=1, then 2`

而 **信息确定性** 原则就是说, 系统曾经设置x=1,
那么这个曾经出现过的变化, 不论是否以后被x=2 覆盖, 它都不能丢失.
这样不论上层的抽象是什么, 都不会产生数据丢失.

> 例如, 假设上层抽象是: 读取x的值时读取所有x的历史版本,

因为C-committed-no-override:
所以, 要求2个 committed 的 state 必须满足一个包含的关系:
state₁ ⊆ state₂

敲黑板:
这里只有 committed 的才满足这个关系, 后面我们会看到, 未完成 commit
的状态会存在没有大小关系的多个state存在

敲黑板:
简单推论: 每个committed 的 state 都是全序的.
C-committed-state-total-order


### 例子: committed 基于 cmd list 的实现:

能通过任意一个 qrⱼ 读到的 cmd list, 认为是committed.

例如在一个3节点系统中, quorum 定义为 `Qw = Qr = majority({A1, A2, A3})`

```
      y=2
x=1   x=1
A₁    A₂    A₃
```

那么,
`state = [x=1]` 是 committed,
`state = [x=1, y=2]` 不是 committed, 它不一定能被读到, 也就是说, 它不是一个信息.




## 信息确定性原则, 要求不能覆盖 committed State

即, 如果某个 State  committed了,
那就不允许冲突的 State 覆盖

这里committed是一个重要条件, 只有committed才有这个限制:

例如,  `[x=1, y=2]` 不能覆盖已 committed 的 `[x=2]`,
但可以覆盖未提交的`[x=2]`, `<--` TODO
可以覆盖已提交的`[x=1]`



## 多state

提交的值 V 可以是多个 State 的并集.
因为多个集合还是集合,  只要集合的合并满足约束就可以




## 不知道 committed 状态, 导致liveness问题

为了保证 **信息确定性** 原则,
当有多个 P 同时写入时,
```
P1     P2
| .-----+
| |
| |st=[x=2]
| |
v v
x=1

A1    A2   A3
```

如果 2 个 P 写入了互相冲突的  state ,
A 存储了 P1 写入的 state1, 当P2 试图写入一个 冲突的 state2 时,

因为这时 state₁ 可能已经被 P₁ 写入到了某个qwᵢ 包含的所有节点,
达到了 committed 的条件,
TODO committed 条件是写入一个qw
那么根据我们的设计目标,
C-committed-no-override

A 只能拒绝P2的写入请求,
P2 就只能终止了.

(因为假设宕机的节点不能保证在有限的时间内恢复, 那么我们必须假设只有写入者自己知道是否committed了)
这就导致了liveness 问题: 可能无法在有限时间内完成一笔写入.
C-liveness

为了解决这个写到一半发现冲突的问题,
 P 需要先用一轮 RPC 来检查是否有冲突的 state **可能** committed了.
(但P 并不能确定哪些已经真的提交了(只有写入者知道))
如果有,
因为C-state-mono-incr, 
就必须将自己要更新的内容在看到的 state 上重新做一次再尝试.

敲黑板:
所以, P 只要看到某个 state 跟自己 要写入的 state 有冲突, 就不能提交自己的 state 了.
为了保证 **信息确定性** ,
C-info-def
P只能在已提交的 state 添加自己要对系统做出的变更.


## committed state 不能冲突

因为
C-committed-state-total-order, 
所以, 2个冲突的 state 中, 最多只有一个可能是committ

敲黑板
而 P 必须基于 **可能** 已 committed 的 state 追加,
所以第一步, P必须能识别出来至多一个可能 committed 的 state.


假设给定任意2个 V=state, P 都能知道哪个是 可能 committed,
那么就是说,
任意2个V之间有个顺序关系, 即
写入的 V 必须是一个全序关系:
**认为"可能 committed" 总是大于 不可能是 committed**
C-V-total-order


### 检查是否各自冲突: 全序关系

<!--
   - 但这没解决问题, 因为2个看到的 State 互相冲突,
   - P 不知道哪个是提交的.
   -
   - 因为2个互相冲突的 State , 最多只有1个是提交的,
   -
   - 而为了让 P 能知道哪个是提交的,
   -->

实际上就是让写入的数据有一个关系: V1 > V2
但像我们上面 TODO 提到的, State 本身没有全序关系(只有committed 的 State 才满足全序关系),

敲黑板
所以 P 写入的值V, 必须加入一个辅助的信息,
让 V 对任意 state 都可以全序的:

V = (index,  state)

敲黑板
且任意2个写入的 index 不能相同. 否则同样无法判断哪个是已经提交的

### 定义: V 的全序关系

因为不论 state 是什么, V = (index, state) 都要有全序关系.
所以: V1.Index > V2.Index => V1 > V2

所以 V 是一个 [字典序][], 比较V的大小就是顺次比较V的每个元素, 直到不相等.
`V1 > V2 => V1.Index > V2.Index || (V1.Index == V2.Index && V1.state > V2.state)`

因为一个P不会产生冲突的State, 所以 V1.Index == V2.Index时,
V1.State 和 V2.State 一定没有冲突(但不一定有序)
所以同样的Index的 V  一定可以合并.
C-V-eq-index-union

所以第一阶段, P 拿到的最大index的V, 合并之后是 **可能** 已 committed 的值V

TODO: P 取所有看到的同样Index的并集, 所以有序

- 不同Index的一定有序
- 相同Index的, 并集有序

V 只是偏序关系, 但只用到全序关系的比较: TODO


---

<!--
new idea:
prepare: prepare a state P wants to write.
accept: actually write the state.
no need to use index.

introduce index only to impl a persistent leader.
-->

### 防止其他写入

现在 P 通过第一轮 RPC, 可以找出 **可能** 已提交的V,
但并不能防止另一个并发写的P' commit 更大的V'
例如: TODO

```

        A1    A2   A3
        x=1
P1 +--->             <-----+ P2
   `---------> <-----------'
  <-----             ------>
  <----------- ------------>

  [x=1, y=2]          [x=2]
P1 +--->              <----+ P2
   `--------->  <----------'
```

要解决这个问题, P 在写入V前就必须要求A拒绝较小的P的 state 的写入. 否则P' 如果
commit 了一个较小index的V, 那么持有更大index的P会导致commit的丢失.

即, 在写入达到 committed 要求的时候, 无需任何其他操作,
也不会有其他 P 覆盖自己的写入.

## Prepare
(phase 1)

因为V之间的大小决定了最大的才可能是committed,
所以P 必须阻止更小的V commit,
才能保证 C-info-def


所以, P 需要先通知大家, 没提交的, 且V更小的 不能提交了.

所以P在第1阶段还要做一件事情, 就是通知至少一个qr的A, 不大于P.Index
的写入要终止.
而 A 要做的是记录这个Index, 拒绝更小的Index的写(第一或第二阶段).

P 发 (granted_index, V=(Index, State)) 给 A
- 如果`A.granted_index !<= P.granted_index的granted_index`, 那么P应终止, 因为有其他P'
  在阻止其他写入了.
- 如果`A.V > P.V`, 因为V在A上只能递增(否则会造成已committed丢失), 所以P也终止.

C-A-vec-order-p2
综合上面两个结论, A 只接受大于等于自己的P的写入. 且比较大小关系使用 [向量序][],
即, `P >= A : P.granted_index >= A.granted_index && P.V >= A.V`


于是第2阶段:

```
   V=(granted_index, A.Index, A.State, )
P --------------> A
```


再第3阶段再写入(granted_index, Index, State)
因为P保证了不大于 granted_index 的V不能提交了,
且P.V 一定包含 **可能** 已committed 的 State
所以任何不大于 granted_index 的 Index 都可以写.

即, P必须满足一个约束:
`P.granted_index >= P.V.Index`


因为committed不能丢失原则,
而对于 A 来说,
它的约束只有一个, 对它写入的V必须是递增的.
且是向量序.


## 读操作

已经 committed 一定能被一个Q读到,
但一个 q 可能读到多个不同的V,
我们选最大的V
但还不确定V是否已提交.
如果要保证一致的读,
则每次读后, 都必须重新提交一次读到的V



##  成员变更

因为 State 只需满足:
committed 不冲突,

所以State可以是由多个State组成:
在我们的设计中, State有2部分的数据:
业务数据
成员数据

V = (Index, Mem, State)

在增加了成员信息后, V的大小关系为:
### 定义:
V1 > V2 => Index1 > Index2 || (Index1 == Index2 && (Mem1 > Mem2 && State1 > State2 ))



membership 可以与 State 的结构不同, 一般使用一个简单的链表就够了.
表示每次变更后的集群信息.

> 当然也可以用有向图等来支持更灵活的成员变更, 但似乎没有必要.


加入成员变更后, 仍然要满足上面所有的条件:

- committed 必须能读到

所以, 写入时必须要求所有读都能看到.

所以,
敲黑板
第一阶段时, 必须覆盖所有可能存在的Q

假设曾经使用了一个Q:{q1, q2...}
那么读的 Q 必须跟所有的 Qi 有交集.

P.quorum ∩ qᵢⱼ ≠ ø for qij ∈ Qi



### 并发的2个Q必须也有交集

敲黑板
所以, ∀ i,  P.quorum必须包含至少一个qᵢⱼ
TODO 例子
```
P1                      P2


{xy,yz,zx}              {uv,vw,wu}
{ab,bc,ca}  {ab,bc,ca}  {ab,bc,ca}

A1          A2          A3
```

Qr 必须是所有Qᵢ的笛卡尔积
为了让提交的数据能被其他Qi看到,
Qw 也必须是所有Qi.w 的笛卡尔积.

∴ Qr = Q1.r X Q2.r X Q3.r...
∴ Qw = Q1.w X Q2.r X Q3.w...


### 优化

但观察一个现象:

Qi+1 的提交会使所有的Qi中的q都无法选主.

所以如果Qi提交了, 就只需考虑Qi+1...的q

P 的 V committed 之后, 系统中任何一个Qi 都能看到P 提交的 V了.
也就是说, 这时任意其他的P, 在尝试基于一个旧的 State 提交新值时,
都能看到一个更新的V.

敲黑板
于是, 如果P 只需使用
Qr=P.V.Q.last().r
Qw=P.V.Q.last().w
只需使用最后一个Q 就可以了.
进行后续的写入就可以了.

---




### 完整的第一阶段

写入数据定义为 D = (Index, State) 之后,
还不能完全解决问题:

按照现在未完成的流程:
P 先看一圈, TODO,
得到
P1 写入D1 = (Index1, State_1),
P2 写入D2 = (Index2, State_2),
D1 提交了, D2 没有, 但D2 > D1,
这时P 仍然会覆盖已提交的D1.

所以, 第一阶段, P要做2件事情:
查看有哪些已提交的D,
禁止其他更小的Index的写入.

因此要求任意2个Qr交集不为空.

于是第一阶段:
P: (Index, State), phase-1

第二阶段,
P只向处于这个状态的节点写入.


# 撤销:

如果P 还没进行第二阶段前,放弃写入,
P 可以再发一个消息, 将已完成第一阶段的节点恢复到之前的状体.


---

Index, granted_index: 偏序集, 需要支持`>`, `==`
Index::gt(other) -> bool
Index::eq(other) -> bool

State: 集合, 需要支持`>`, `==`, `union(State_1, State_2)`


Q.W,  Q.R: quorum的集合
E.g., Q = (W={ab, bc, ca}, R={ab, bc, ca})

quorum: 节点的集合.

P  = (granted_index, V=(Index, Q, State)), effective_Q
Aᵢ = (granted_index, V=(Index, Q, State)), [PrevIndex...]


`P >= A` : `P.granted_index >= A.granted_index && P.V >= A.V`
`P >= A` : `P.curr >= A.curr && P.granted >= A.V`

`V1 > V2` : `V1.Index > V2.Index || (V1.Index == V2.Index && V1.State > V2.State)`

约束:
P.granted_index >= P.V.Index

functions:
next_index(Index): 根据已接受的Index生成一个更大的Index

P:

rnd: 想要提交的Index
granted: 已知的可写的最大Index
index: 真正要写的Index

p1: read
p2: rnd=next_index(), granted=max(V1 ∪ V2), index=0
p3: rnd=rnd, granted=rnd, index=some value

- initial state:
    Qr 更新所有P.V.Q中所有配置的的笛卡尔积
    Qw 同样
    Qr = P.V.Qr1 X P.V.Qr2 X ...
    Qw = P.V.Qw1 X P.V.Qw2 X ...

- p1:
    P:

    let P.granted_index = next_index(P.v).
    send(P) to Aᵢ

    A:

    respond(Aᵢ)

    if P.granted_index >= A.granted_index
        A.granted_index = P.granted_index

- p2:
    P:

    P.v = union({Aᵢ.v : Aᵢ.v ≮ Aⱼ.v })
    P.v[P.granted_index] = P.v.union()

    let granted = {Aᵢ if P.granted_index >= Aᵢ.granted_index}
    if ! granted ∈ P.membership.r
        goto p1

    if P.v.get_membership() changed:
        goto p1

    send(P) to Aᵢ

    A:

    respond(Aᵢ)

    if P.granted_index >= A.granted_index
        A.v = P.v

    read Vᵢ from qrᵢ ∈ P.Qr
    choose Vᵢ that Vᵢ ≮ Vⱼ
    let P.V = Vᵢ₁ ∪ Vᵢ₂ ∪ ...
    if P.V.Q changed, goto step 1.

    let P.granted = Vi

- p2: write Pᵢ to Aᵢ
    if rejected, goto step 1.

- p3:
    let P.v.index = P.last
    let P.granted = append_state(P. TODO),
    let P.V = subset of granted

    Qr 更新为最后一个已committed的Q 和所有未committed的Q的笛卡尔积
    Qw 同样

    write P to a qwᵢ ∈ Qw

A: accept if P >= A

## Partial write

上面的协议中, 要求P在p3阶段必须写入一个P.v.index == P.last 的值.
实现中, 因为State可能很大, 传输中需要分段写.
例如raft在写入本term的一条日志之前的复制行为.

这部分写入也要保证:
C-committed-no-override

因为P选择的P.v.state一定包含已提交的值(大于),
所以对A来说, 如果P的一次partial write 跟A无冲突:
- P >= A: A中已提交的 state不会被覆盖.
    TODO
