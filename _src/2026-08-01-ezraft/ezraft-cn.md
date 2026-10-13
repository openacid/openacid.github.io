---
title:      "EzRaft: 100 行写一个分布式 KV 存储"
authors:
    - xp
categories:
    - algo
tags:
    - raft
    - consensus
    - distributed

refs:
    - x: y

mathjax: false
toc: true
toc_label: 本文目录
toc_sticky: true
excerpt: "EzRaft 建立在 OpenRaft 之上, 把存储/网络/服务接口都隐藏起来, 用户只需要定义 Request, Response, apply 和 read 四样东西, 就能得到一个三节点容错的分布式 KV 存储."
---

![](ezraft-banner.png)

# EzRaft: 100 行写一个分布式 KV 存储

最近几年, 我的工作一直集中在 [OpenRaft][repo-openraft] 这个项目上.

它是一个开源项目, 全球各地公司的工程项目都在用它. 所以我一直在对 OpenRaft 做抽象, 让它能适应尽可能多的应用场景: log entry、log ID、state machine 和 storage 都用 [Rust][rust-lang] 的 Trait 来描述, 目的就是让不同的用户能按自己的场景去定制.

到今天为止, OpenRaft 的 API 和性能都已经比较稳定. 但它描述 [Raft][raft-website] 算法的方式, 依然是相当抽象的.

## OpenRaft 的门槛

抽象带来的直接后果, 是新手用起来有门槛. 这个门槛主要有三部分:

1. 对 Raft 一致性算法的理解:
   你需要知道这个算法能保证什么、不能保证什么, 才能基于 OpenRaft 实现自己的分布式存储.

2. 对 Rust 语言的门槛:
   OpenRaft 是用 Rust 写的, 你必须对 Rust 的抽象和泛型有一定理解, 才能读懂代码并开发自己的应用.

3. OpenRaft 自身抽象带来的门槛:
   在软件开发中, 抽象让编写变得更简单, 但它是自上而下的. 对熟悉这套系统的人来说, 它提供了足够的便利和灵活; 但对于自下而上的学习和理解来说, 它本身就是门槛.

抽象的东西都有门槛: 必须先弄清各个抽象环节之间的关系, 才能真正理解它. 因为人的思维习惯是从具象到抽象 —— 直接给出一个抽象概念, 让人自己去对应到某个具体的实例上, 对大多数人来说是困难的; 反过来, 给一个具象的场景, 让人从里面抽象出规律, 就容易得多.

所以, OpenRaft 为适应众多场景所做的抽象, 让它更像一个稳定的工具, 而不是一份学习资料.

## EzRaft 的初衷

维护 OpenRaft 的时候, 我也经常遇到对分布式、Rust 或者 OpenRaft 不熟悉的同学来提问. 他们想做一个自己的应用 (比如一个分布式存储系统), 但要学的东西实在太多了.

所以我想, 能不能做一个项目, 让用户只关注自己的业务逻辑, 而不必把精力花在 Raft、Rust 或者 OpenRaft 的学习上.

这就是 EzRaft 的初衷.

[EzRaft][repo-ezraft] 是建立在 OpenRaft 之上的一个简化版分布式存储实现库. 它把 OpenRaft 里那些不那么重要的细节隐藏起来, 让用户在最开始的阶段, 可以把精力完全放在自己的业务上, 而不是技术细节上.

两者的差距大致是这样:

| | OpenRaft | EzRaft |
|---|---|---|
| 需要实现的 Trait | 7+ (RaftLogStorage, RaftStateMachine ...) | 2 (EzApp, EzStorage) |
| 需要实现的方法 | 21+ | 4 |
| 需要自己定义的类型 | 12 个泛型参数 | 2 个 (Request, Response) |
| 网络层代码 | 自己实现, 约 100 行 | 内置, 0 行 |

![The layers of EzRaft and OpenRaft: users implement EzApp, EzRaft provides storage, networking, and service APIs, and OpenRaft handles consensus](assets/ezraft-layers.png)

## 用户要定义的四件事

EzRaft 只要求你想清楚自己的应用里这四件事:

1. 请求长什么样, 也就是 `Request`.
2. 应答长什么样, 也就是 `Response`. 应用本身是一个服务, 请求和应答直接对应业务, 只能由用户来定义.
3. 怎么把一个请求解释成对状态机的修改, 也就是 `apply()`.
4. 怎么读状态机, 也就是 `read()`. 可以简单地把状态机理解成一个 key-value, 通过 key 读出其中的一部分.

这四样由用户提供, 其余的都由 EzRaft 提供: 存储系统、网络通信、服务接口等等. 在 OpenRaft 上开发时, 这些细节都得自己面对; EzRaft 把它们封装到了下一层.

这样, 只关心业务的用户可以直接把应用做出来; 需要的时候, 再深入到下面的细节里去.

```rust
trait EzApp: Serialize + DeserializeOwned {
    type Request;
    type Response;

    async fn apply(&mut self, req: Self::Request) -> Self::Response;
    fn read(&self, key: &str) -> Option<serde_json::Value>;
}
```

这就是一个想开发分布式存储的用户需要关心的全部. 定义好上面四样, 剩下的都交给 EzRaft, 再写几行模板代码把它们串起来, 应用就搭好了.

EzApp 本身就保存着整个应用的状态. 需要持久化的时候, 用它的 serialize 和 deserialize 来存储和加载. 也就是说, snapshot 就是整个状态的序列化结果 —— 这一点决定了 EzRaft 适合状态放得进内存的应用, 后面还会再提到.

## 三步做出一个分布式 KV 存储

用 EzRaft 做一个这样的应用, 需要三步:

1. 实现 `EzApp` trait, 定义自己的业务模型.
2. 用 EzRaft 提供的组件把服务组装起来.
3. 在终端里启动三个节点, 跑一遍看看.

## 第一步: 定义应用

先设计应用. 服务接收的请求支持两个操作: set 一个 key, delete 一个 key.

应用的全部数据就是一个 KV map, 这里用 [B-tree map][rust-btreemap].

apply 非常简单: 把一个请求 (set 或者 delete) 作用到这个 B-tree map 上.

read 也一样直接: 按 key 读出 value, 返回.

这就是应用本身要关心的全部, 剩下的都由 EzRaft 完成.

```rust
enum Request {
    Set { key: String, value: String },
    Delete { key: String },
}

struct KvApp {
    data: BTreeMap<String, String>,
}

impl EzApp for KvApp {
    type Request = Request;
    type Response = Option<String>;

    async fn apply(&mut self, req: Request) -> Option<String> {
        match req {
            Request::Set { key, value } => self.data.insert(key, value),
            Request::Delete { key } => self.data.remove(&key),
        }
    }

    fn read(&self, key: &str) -> Option<serde_json::Value> {
        self.data.get(key).cloned().map(serde_json::Value::String)
    }
}
```

这里 `apply` 返回的是 `insert`/`remove` 的返回值, 也就是这个 key 原来的值. 所以一次写操作会顺便告诉调用者它覆盖掉了什么, 不需要再读一次.

为了让代码看起来更清楚, 上面省略了 derive. 实际写的时候要补上: `Request` 要在网络上传输并写进 log, 所以需要 [serde][serde]; OpenRaft 会把它打印到日志里, 所以还需要 `Debug` 和 `Display`; 转发给 leader 的时候要留一份副本, 所以需要 `Clone`. `KvApp` 自己就是状态, snapshot 靠 serde 完成.

仓库里的 [examples/kvstore.rs][repo-ezraft-kvstore] 是一个 derive 和 import 都齐全、可以直接 `cargo run` 的版本. 它和本文的代码有两处不同: 命令行用 clap 解析 `--addr` 和 `--seed`, 而不是位置参数; 应答用的是一个 `Response` 结构体而不是 `Option<String>`, 所以 HTTP 返回的是 `{"value":"world"}` 而不是 `"world"`.

## 第二步: 组装成一个可运行的服务

第二步是把上面的业务逻辑装进一个可运行的 server. 这个 server 在启动时接受两个参数:

1. 本节点的地址: 它既用于 EzRaft 节点之间的通信, 也用于用户向服务发请求.
2. seed 地址: 当一个新节点还没有初始化自己的存储时, 用它加入到已有的集群.

启动的时候, 第一个节点不需要 seed: 它自己就是一个单节点集群, 起来之后就可以对外服务.

第二、第三个节点启动时, 都把第一个节点的地址作为 seed. 它们会向第一个节点发一个请求, 加入集群, 最终形成一个三节点的集群.

这个过程里, 节点的加入、节点 ID 的分配以及数据同步, 都由 EzRaft 和它下面的 OpenRaft 完成.

![How three EzRaft nodes form a cluster: the first creates it, while two more join through the seed, catch up, and become voters](assets/ezraft-cluster-formation.png)

服务本身非常简单: 先读命令行参数, 再初始化存储.

这里用的是 EzRaft 自带的 FileStorage. 它完整地展现了一个存储该做的事情, 不追求性能, 只把存储的逻辑摆出来.

如果要把它做成一个真正可用的产品, 就需要换成自己的存储. 具体的原因是 FileStorage 不做 fsync: 机器掉电有可能丢掉一条已经向客户端确认过的写入, 而这会[破坏 Raft 的正确性保证][post-raft-io-order-cn]. 自己实现 `EzStorage` 一共只有三个方法, `FileStorage` 的源码就是现成的样板.

存储初始化之后, 建一个应用实例 (也就是上面那个 KvApp), 交给 EzRaft 去启动服务. 到这里, 服务就真正跑起来了.

```rust
#[tokio::main]
async fn main() -> io::Result<()> {
    // Usage: kvstore [addr] [seed-addr]
    let addr = std::env::args().nth(1).unwrap_or("127.0.0.1:8080".to_string());
    let seed = std::env::args().nth(2);

    let storage = FileStorage::new(format!("./data/{}", addr.replace(':', "-"))).await?;
    let (app, config) = (KvApp::default(), EzConfig::default());

    let raft = match seed {
        Some(seed) => EzRaft::join(&addr, seed, app, storage, config).await?,
        None => EzRaft::create(&addr, app, storage, config).await?,
    };

    raft.serve().await
}
```

`create` 和 `join` 是分开的两个方法, 而不是合成一个带 `Option<seed>` 的参数, 这是故意的: 建立集群和加入集群是两件不同的事情. 如果一个本该 join 的节点漏掉了 seed 就去 create, 得到的是两个各自为政的单节点集群, 而且它们永远不会合并. 让调用方把这个选择写出来, 比让它取决于一个配置项是否为空要安全.

## 第三步: 启动三节点集群

下面在三个终端里, 分别启动第一、第二和第三个节点:

```bash
cargo run -- 127.0.0.1:8080
cargo run -- 127.0.0.1:8081 127.0.0.1:8080
cargo run -- 127.0.0.1:8082 127.0.0.1:8080
```

然后新开第四个终端, 就可以向这个服务发请求了.

先写入一份数据. 应答是这个 key 原来的值, 这里它原来不存在, 所以是 `null`:

```bash
curl -X POST 127.0.0.1:8080/api/write \
    -H 'Content-Type: application/json' \
    -d '{"Set": {"key": "hello", "value": "world"}}'
# null
```

然后从另一个节点把它读出来. 注意这里读的是 8082, 一个我们从来没有写入过的节点:

```bash
curl '127.0.0.1:8082/api/read?key=hello'
# "world"
```

每个节点都持有一份完整的状态, 所以读不需要经过 leader, 也不需要一轮共识, 直接从这个节点自己的内存里给出答案. 代价是它可能会稍微落后一点: 读不到那些"刚刚被确认、但还没同步到这个节点"的写入. 需要严格[线性一致][post-linearizable]的读时, 先调用 `linearizable()`, 它会[确认 leader 身份][post-openraft-read]并等本地状态追上, 然后再 `read()`.

## 写请求可以发给任意节点

Raft 里只有 leader 能接受写入, 但这件事不需要用户来操心: 任意一个节点都接受写请求, 如果它自己不是 leader, 它会把请求转发给 leader, 等提交之后再把结果返回给调用者.

所以下面这条命令发给 8081 也一样能写成功, 返回的 `"world"` 就是它覆盖掉的旧值:

```bash
curl -X POST 127.0.0.1:8081/api/write \
    -H 'Content-Type: application/json' \
    -d '{"Set": {"key": "hello", "value": "again"}}'
# "world"
```

这意味着客户端不需要自己去发现和跟踪谁是 leader, 随便连一个节点就可以. 删除也是一样, 返回被删掉的值:

```bash
curl -X POST 127.0.0.1:8080/api/write \
    -H 'Content-Type: application/json' \
    -d '{"Delete": {"key": "hello"}}'
# "again"
```

删掉之后再去读, 这个 key 就不存在了, 返回 404:

```bash
curl '127.0.0.1:8080/api/read?key=hello'
# no value for key "hello"     [HTTP 404]
```

## 测试挂掉一个节点

到这里为止的功能, 单机一个 HashMap 也能做到. 三个节点的意义在于: 挂掉一个, 服务不受影响.

先写一个 key, 然后把 leader (也就是第一个节点 8080) 直接 kill 掉:

```bash
curl -X POST 127.0.0.1:8080/api/write \
    -H 'Content-Type: application/json' \
    -d '{"Set": {"key": "k", "value": "before-failover"}}'
# null

# 在第一个终端里 Ctrl-C, 或者 kill 掉这个进程
```

剩下两个节点是三个节点中的[多数派][post-quorum], 所以它们会在几个心跳之内选出新的 leader. 之前写进去的数据还在, 而且还能继续写:

```bash
curl '127.0.0.1:8081/api/read?key=k'
# "before-failover"

curl -X POST 127.0.0.1:8081/api/write \
    -H 'Content-Type: application/json' \
    -d '{"Set": {"key": "k", "value": "after-failover"}}'
# "before-failover"

curl 127.0.0.1:8081/api/metrics | jq -c '{id, state, current_leader}'
# {"id":2,"state":"Follower","current_leader":6}
```

leader 已经换成了 id 为 6 的那个节点, 整个过程不需要人工介入.

![Failover in a three-node cluster: after the original leader fails, the other two nodes form a majority and elect a new leader](assets/ezraft-failover.png)

然后, 用完全一样的命令行把死掉的节点启动回来:

```bash
cargo run -- 127.0.0.1:8080
```

注意它不需要加 seed: 节点 id 已经持久化在自己的 `./data/127.0.0.1-8080/` 目录里了, 重启的时候直接读回来, 不会再去联系 seed. 这也意味着即使当初那个 seed 节点已经离开集群, 重启也不受影响. 它起来之后会自动把落下的那条写入追上:

```bash
curl '127.0.0.1:8080/api/read?key=k'
# "after-failover"
```

三个节点能容忍挂掉一个, 五个节点能容忍挂掉两个. 偶数个节点没有额外收益: 四个节点和三个节点一样, 都只能容忍挂掉一个.

## 集群状态

EzRaft 还提供了一个默认的接口, 可以看到服务当前的运行状态:

```bash
curl '127.0.0.1:8080/api/metrics' | jq
```

这里的 metrics 直接来自 OpenRaft, 所以它包含 OpenRaft 提供的完整信息:

```json
{
  "running_state": { "Ok": null },
  "id": 0,
  "current_term": 1,
  "vote": {
    "leader_id": { "term": 1, "voted_for": 0 },
    "committed": true
  },
  "last_log_index": 10,
  "local_committed": { "leader_id": 1, "index": 10 },
  "cluster_committed": { "leader_id": 1, "index": 10 },
  "committed": { "leader_id": 1, "index": 10 },
  "last_applied": { "leader_id": 1, "index": 10 },
  "snapshot": null,
  "purged": null,
  "state": "Leader",
  "current_leader": 0,
  "millis_since_quorum_ack": 3,
  "last_quorum_acked": 1785595777894002000,
  "membership_config": {
    "log_id": { "leader_id": 1, "index": 9 },
    "membership": {
      "configs": [ [ 0, 2, 6 ] ],
      "nodes": {
        "0": { "addr": "127.0.0.1:8080" },
        "2": { "addr": "127.0.0.1:8081" },
        "6": { "addr": "127.0.0.1:8082" }
      }
    }
  },
  "committed_membership_config": {
    "log_id": { "leader_id": 1, "index": 9 },
    "membership": {
      "configs": [ [ 0, 2, 6 ] ],
      "nodes": {
        "0": { "addr": "127.0.0.1:8080" },
        "2": { "addr": "127.0.0.1:8081" },
        "6": { "addr": "127.0.0.1:8082" }
      }
    }
  },
  "heartbeat": {
    "0": 1785595777894002750,
    "2": 1785595777894002209,
    "6": 1785595777894002125
  },
  "replication": {
    "0": { "leader_id": 1, "index": 10 },
    "2": { "leader_id": 1, "index": 10 },
    "6": { "leader_id": 1, "index": 10 }
  }
}
```

这里三个节点的 id 是 0, 2, 6, 而不是 0, 1, 2. 因为节点 id 不是配置出来的, 而是集群分配的: 一个节点来 join 的时候, leader 会写一条 log, 并把这条 log 的 index 作为新节点的 id. 这样得到的 id 一定不重复, 但是不连续 —— 两次分配之间还夹着别的 log, 一条是把新节点加为 learner 的 config, 一条是把它提升为 voter 的 membership change. 所以 id 里的空档, 正好是集群自己完成这两步留下的痕迹.

![How node IDs 0, 2, and 6 relate to Raft log indexes written by join, add learner, and membership change operations](assets/ezraft-node-id-log.png)

新加入的节点先作为 learner, 只接收 log 而不参与多数派计算, 等它追上进度之后, 由集群自动提升为 voter. 也就是说, 让集群具备容错能力这件事, 只需要把节点 join 进来就够了.

## 什么时候该用 EzRaft

EzRaft 针对的是这样一类应用: 状态放得进内存, 但是不能丢, 也不能在几个节点之间出现分歧. 配置中心、服务注册与发现、元数据、分布式锁、任务调度的状态, 都属于这一类 —— 数据本身不大, 可是一旦丢失或者出现分歧, 上层的整个业务就乱了. [ZooKeeper][zookeeper] 和 [etcd][etcd] 服务的也正是这一类需求.

之所以正好是这一类, 是因为 EzRaft 的 snapshot 就是整个 `EzApp` 的序列化结果, 安装 snapshot 就是把它反序列化回来. 这个选择把用户在快照上要写的代码, 从"实现一整套快照机制"减到了"给自己的 struct 加一行 derive". 状态放得进内存, 就能享受到这个简化.

它也适合读多写少. 每个节点都持有完整的状态, 读直接走本地内存, 不经过 leader 也不需要一轮共识, 所以读请求可以打到任意一个节点上, 加节点就能加读的吞吐.

它还很适合用来把 Raft 跑通一遍. 上面这一百行左右的代码, 已经包含了选主、日志复制、成员变更、快照和故障切换 —— 你可以直接拿它做实验: kill 掉一个节点看集群怎么选主, 看 metrics 里的 log index 怎么推进, 改一改 `EzConfig` 里的心跳间隔看选举需要多久. 等到这些概念都具体起来之后, 再往下走一层去看 [OpenRaft][repo-openraft], 会比一上来就读 trait 定义容易得多.

真正做成产品的时候, 有两处是要自己接手的: 一是前面说的存储, 换掉 FileStorage; 二是服务接口, 内置的这套 HTTP 接口是给示例用的, 没有认证也没有加密, 真正的服务应该照着 `EzServer` 写自己的路由, 底下调用 `EzRaft::write` 和 `EzRaft::read`. 剩下的部分不需要动.

## 链接

- 代码: [github.com/drmingdrmer/ezraft][repo-ezraft]
- crates.io: [crates.io/crates/ezraft][crates-ezraft]
- 文档: [docs.rs/ezraft][docs-ezraft]
- OpenRaft: [github.com/databendlabs/openraft][repo-openraft]


[repo-ezraft]: https://github.com/drmingdrmer/ezraft "ezraft"
[repo-ezraft-kvstore]: https://github.com/drmingdrmer/ezraft/blob/main/examples/kvstore.rs "ezraft kvstore example"
[crates-ezraft]: https://crates.io/crates/ezraft "ezraft on crates.io"
[docs-ezraft]: https://docs.rs/ezraft "ezraft docs"
[repo-openraft]: https://github.com/databendlabs/openraft "openraft"

[raft-website]: https://raft.github.io/ "Raft"
[rust-lang]: https://www.rust-lang.org/ "Rust"
[rust-btreemap]: https://doc.rust-lang.org/std/collections/struct.BTreeMap.html "BTreeMap"
[serde]: https://serde.rs/ "serde"
[zookeeper]: https://zookeeper.apache.org/ "Apache ZooKeeper"
[etcd]: https://etcd.io/ "etcd"

[post-quorum]: https://blog.openacid.com/algo/quorum/ "多数派读写的少数派实现"
[post-linearizable]: https://blog.openacid.com/algo/linearizable/ "分布式系统中的 Linearizable 事务"
[post-openraft-read]: https://blog.openacid.com/algo/openraft-read/ "Openraft 对 ReadIndex 的优化"
[post-raft-io-order-cn]: https://blog.openacid.com/algo/raft-io-order-complete-cn/ "Raft 中的 IO 执行顺序"
