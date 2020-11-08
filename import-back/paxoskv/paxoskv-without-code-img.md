# 200行代码实现基于paxos的kv存储


本文链接: [https://blog.openacid.com/algo/paxoskv/](https://blog.openacid.com/algo/paxoskv/)

![200行代码实现基于paxos的kv存储](https://tva1.sinaimg.cn/large/0081Kckwly1gkcymcafslj30wn0dwn0a.jpg)

# 前言

写完 [paxos的直观解释](https://blog.openacid.com/algo/paxos) 之后, 网友都说疗效甚好, 但是也会对这篇教程中一些环节提出疑问(有疑问说明真的看懂了 🤔 ) , 例如怎么把只能确定一个值的paxos应用到实际场景中.

既然**Talk is cheap**, 那么就**Show me the code**, 这次我们把教程中描述的内容直接用代码实现出来, 希望能覆盖到教程中的涉及的每个细节. 帮助大家理解paxos的运行机制.

**这是一个基于paxos, 200行代码的kv存储系统的简单实现, 作为 [paxos的直观解释](https://blog.openacid.com/algo/paxos) 这篇教程中的代码示例部分**. Paxos的原理本文不再介绍了, 本文提到的数据结构使用[protobuf](https://developers.google.com/protocol-buffers)定义, 网络部分使用[grpc](https://grpc.io/)定义. 另外200行go代码实现paxos存储.

文中的代码可能做了简化, 完整代码实现在 [paxoskv](https://github.com/openacid/paxoskv/blob/naive/proto/paxoskv.proto#L16) 这个项目中(naive分支).

# 运行和使用

🚀

跑一下:

```sh
git clone https://github.com/openacid/paxoskv.git
cd paxoskv
go test -v ./...
```

这个项目中除了paxos实现, 用3个test case描述了3个paxos运行的例子,

- [TestCase1SingleProposer](https://github.com/openacid/paxoskv/blob/naive/paxoskv/paxos_slides_case_test.go#L11): 无冲突运行.
- [TestCase2DoubleProposer](https://github.com/openacid/paxoskv/blob/naive/paxoskv/paxos_slides_case_test.go#L57): 有冲突运行.
- [Example_setAndGetByKeyVer](https://github.com/openacid/paxoskv/blob/naive/paxoskv/example_set_get_test.go): 作为key-val使用.

测试代码描述了几个paxos运行例子的行为, 运行测试可以确认paxos的实现符合预期.

本文中 protobuf 的数据结构定义如下:

```proto
service PaxosKV {
    rpc Prepare (Proposer) returns (Acceptor) {}
    rpc Accept (Proposer) returns (Acceptor) {}
}
message BallotNum {
    int64 N          = 1;
    int64 ProposerId = 2;
}
message Value {
    int64 Vi64 = 1;
}
message PaxosInstanceId {
    string Key = 1;
    int64  Ver = 2;
}
message Acceptor {
    BallotNum LastBal = 1;
    Value     Val     = 2;
    BallotNum VBal    = 3;
}
message Proposer {
    PaxosInstanceId Id  = 1;
    BallotNum       Bal = 2;
    Value           Val = 3;
}
```

以及主要的函数实现:

```go
// struct KVServer
Storage : map[string]Versions
func Accept(c context.Context, r *Proposer) (*Acceptor, error)
func Prepare(c context.Context, r *Proposer) (*Acceptor, error)
func getLockedVersion(id *PaxosInstanceId) *Version

// struct Proposer
func Phase1(acceptorIds []int64, quorum int) (*Value, *BallotNum, error)
func Phase2(acceptorIds []int64, quorum int) (*BallotNum, error)
func RunPaxos(acceptorIds []int64, val *Value) (*Value)
func rpcToAll(acceptorIds []int64, action string) ([]*Acceptor)

func ServeAcceptors(acceptorIds []int64) ([]*grpc.Server)
```

# 从头实现paxoskv

## Paxos 相关的数据结构

在这个例子中我们的数据结构和服务框架使用 [protobuf](https://developers.google.com/protocol-buffers) 和 [grpc](https://grpc.io/) 实现, 首先是最底层的paxos数据结构:

### Proposer 和 Acceptor

在 [slide-27](https://blog.openacid.com/algo/paxos/#slide-27) 中我们介绍了1个 Acceptor 所需的字段:

> 在存储端(Acceptor)也有几个概念:
>
> - last_rnd 是Acceptor记住的最后一次进行写前读取的Proposer(客户端)是谁, 以此来决定谁可以在后面真正把一个值写到存储中.
> - v 是最后被写入的值.
> - vrnd 跟v是一对, 它记录了在哪个Round中v被写入了.

![img](https://tva1.sinaimg.cn/large/0081Kckwly1gkcymfexbij30m80gowg5.jpg)

原文中这些名词是参考了 [paxos made simple](http://lamport.azurewebsites.net/pubs/pubs.html#paxos-simple) 中的名称, 但在 [Leslie Lamport](http://www.lamport.org/) 后面的几篇paper中都换了名称, 为了后续方便, 在[paxoskv](https://github.com/openacid/paxoskv/blob/naive/proto/paxoskv.proto#L16)的代码实现中也做了相应的替换:

```
rnd      ==> Bal   // 每一轮paxos的编号, BallotNum
vrnd     ==> VBal  // 在哪个Ballot中v被Acceptor 接受(voted)
last_rnd ==> LastBal
```

Proposer的字段也很简单, 它需要记录:

- 当前的ballot number: `Bal`,
- 以及它选择在Phase2运行的值: `Val` ([slide-29](https://blog.openacid.com/algo/paxos/#slide-29)).

于是在这个项目中用protobuf定义这两个角色的数据结构, 如代码 [paxoskv.proto](https://github.com/openacid/paxoskv/blob/naive/proto/paxoskv.proto) 中的声明, 如下:

```proto
message Acceptor {
  BallotNum LastBal = 1;
  Value     Val = 2;
  BallotNum VBal = 3;
}

message Proposer {
  PaxosInstanceId Id = 1;

  BallotNum Bal = 2;
  Value     Val = 3;
}
```

其中Proposer还需要一个PaxosInstanceId, 来标识当前的paxos实例为哪个key的哪个version在做决定, [paxos made simple](http://lamport.azurewebsites.net/pubs/pubs.html#paxos-simple) 中只描述了一个paxos实例的算法(对应一个key的一次修改), 要实现多次修改, 就需要增加这个字段来区分不同的paxos实例:

```proto
message PaxosInstanceId {
  string Key = 1;
  int64  Ver = 2;
}
```

[paxoskv.proto](https://github.com/openacid/paxoskv/blob/naive/proto/paxoskv.proto) 还定义了一个BallotNum, 因为要保证全系统内的BallotNum都有序且不重复, 一般的做法就是用一个本地单调递增的整数, 和一个全局唯一的id组合起来实现:

```proto
message BallotNum {
    int64 N = 1;
    int64 ProposerId = 2;
}
```

### 定义RPC消息结构

RPC消息定义了Proposer和Acceptor之间的通讯.

在一个paxos系统中, 至少要有4个消息:

- Phase1的 Prepare-request, Prepare-reply,
- 和Phase2的 Accept-request, Accept-reply,

如[slide-28](https://blog.openacid.com/algo/paxos/#slide-28) 所描述的(原文中使用rnd, 这里使用Bal, 都是同一个概念):

> Phase-1(Prepare):
>
> ```
> request:
>     Bal: int
> 
> reply:
>     LastBal: int
>     Val:     string
>     VBal:    int
> ```
>
> Phase-2(Accept):
>
> ```
> request:
>     Bal: int
>     Val:   string
> 
> reply:
>     LastBal: int
> ```

在Prepare-request或Accept-request中, 发送的是一部分或全部的Proposer的字段, 因此我们在代码中:

- 直接把Proposer的结构体作为request的结构体.
- 同样把Acceptor的结构体作为reply的结构体.

在使用的时候只使用其中几个字段. 对应我们的 RPC 服务 [PaxosKV](https://github.com/openacid/paxoskv/blob/naive/proto/paxoskv.proto#L16) 定义如下:

```proto
service PaxosKV {
    rpc Prepare (Proposer) returns (Acceptor) {}
    rpc Accept (Proposer) returns (Acceptor) {}
}
```

## 使用protobuf和grpc生成服务框架

🚀

protobuf可以将[paxoskv.proto](https://github.com/openacid/paxoskv/blob/naive/proto/paxoskv.proto)直接生成go代码( 代码库中已经包含了生成好的代码: [paxoskv.pb.go](https://github.com/openacid/paxoskv/blob/naive/paxoskv/paxoskv.pb.go), 只有修改[paxoskv.proto](https://github.com/openacid/paxoskv/blob/naive/proto/paxoskv.proto) 之后才需要重新生成)

- 首先安装protobuf的编译器 protoc, 可以根据 [install-protoc](https://grpc.io/docs/protoc-installation/) 中的步骤安装, 一般简单的一行命令就可以了:

  - Linux: `apt install -y protobuf-compiler`
  - Mac: `brew install protobuf`

  安装好之后通过`protoc --version`确认版本, 至少应该是3.x: `libprotoc 3.13.0`

- 安装protoc的go语言生成插件 protoc-gen-go:

  `go get -u github.com/golang/protobuf/protoc-gen-go`

- 重新编译`protokv.proto`文件: 直接`make gen` 或:

  ```
    protoc \
        --proto_path=proto \
        --go_out=plugins=grpc:paxoskv \
        paxoskv.proto
  ```

生成后的[paxoskv.pb.go](https://github.com/openacid/paxoskv/blob/naive/paxoskv/paxoskv.pb.go)代码中可以看到, 其中主要的数据结构例如Acceptor的定义:

```go
type Acceptor struct {
  LastBal *BallotNum ...
  Val     *Value ...
  VBal    *BallotNum ...
        ...
}
```

以及KV服务的client端和server端的代码, client端是实现好的, server端只有一个interface, 后面我们需要来完成它的实现:

```go
type paxosKVClient struct {
  cc *grpc.ClientConn
}
type PaxosKVClient interface {
  Prepare(
    ctx context.Context,
    in *Proposer,
    opts ...grpc.CallOption
  ) (*Acceptor, error)

  Accept(
    ctx context.Context,
    in *Proposer,
    opts ...grpc.CallOption
  ) (*Acceptor, error)
}

type PaxosKVServer interface {
  Prepare(context.Context,
          *Proposer) (*Acceptor, error)
  Accept(context.Context,
         *Proposer) (*Acceptor, error)
}
```

## 实现存储的服务器端

[impl.go](https://github.com/openacid/paxoskv/blob/naive/paxoskv/impl.go) 是所有实现部分, 我们定义一个KVServer结构体, 用来实现grpc服务的interface `PaxosKVServer`; 其中使用一个内存里的map结构模拟数据的存储:

```go
type Version struct {
  mu       sync.Mutex
  acceptor Acceptor
}
type Versions map[int64]*Version
type KVServer struct {
  mu      sync.Mutex
  Storage map[string]Versions
}
```

其中`Version`对应一个key的一次变化, 也就是对应一个paxos实例. Versions对应一个key的一系列变化. Storage就是所有key的所有变化.

### 实现 Acceptor 的 grpc 服务 handler

Acceptor, 是这个系统里的server端, 监听一个端口, 等待Proposer发来的请求并处理, 然后给出应答.

根据paxos的定义, Acceptor的逻辑很简单: 在 [slide-28](https://blog.openacid.com/algo/paxos/#slide-28) 中描述:

![img](https://tva1.sinaimg.cn/large/0081Kckwly1gkcymfx2kxj30m80go76h.jpg)

根据教程里的描述, 为 KVServer 定义handle Prepare-request的代码:

```go
func (s *KVServer) Prepare(
    c context.Context,
    r *Proposer) (*Acceptor, error) {

  v := s.getLockedVersion(r.Id)
  defer v.mu.Unlock()

  reply := v.acceptor

  if r.Bal.GE(v.acceptor.LastBal) {
    v.acceptor.LastBal = r.Bal
  }

  return &reply, nil
}
```

这段代码分3步:

- 取得paxos实例,
- 生成应答: Acceptor总是返回`LastBal`, `Val`, `VBal` 这3个字段, 所以直接把Acceptor赋值给reply.
- 最后更新Acceptor的状态: 然后按照paxos算法描述, 如果请求中的ballot number更大, 则记录下来, 表示不在接受更小ballot number的Proposer.

其中`getLockedVersion()` 从`KVServer.Storage`中根据request 发来的PaxosInstanceId中的字段key和ver获取一个指定Acceptor的实例:

```go
func (s *KVServer) getLockedVersion(
    id *PaxosInstanceId) *Version {

  s.mu.Lock()
  defer s.mu.Unlock()

  key := id.Key
  ver := id.Ver
  rec, found := s.Storage[key]
  if !found {
    rec = Versions{}
    s.Storage[key] = rec
  }

  v, found := rec[ver]
  if !found {
    // initialize an empty paxos instance
    rec[ver] = &Version{
      acceptor: Acceptor{
        LastBal: &BallotNum{},
        VBal:    &BallotNum{},
      },
    }
    v = rec[ver]
  }

  v.mu.Lock()
  return v
}
```

handle Accept-request的处理类似, 在 [slide-31](https://blog.openacid.com/algo/paxos/#slide-31) 中描述: ![img](https://tva1.sinaimg.cn/large/0081Kckwly1gkcymexkj9j30m80gotah.jpg)

`Accept()` 要记录3个值,

- `LastBal`: Acceptor看到的最大的ballot number;
- `Val`: Proposer选择的值,
- 以及`VBal`: Proposer的ballot number:

```go
func (s *KVServer) Accept(
    c context.Context,
    r *Proposer) (*Acceptor, error) {

  v := s.getLockedVersion(r.Id)
  defer v.mu.Unlock()

  reply := Acceptor{
    LastBal: &*v.acceptor.LastBal,
  }

  if r.Bal.GE(v.acceptor.LastBal) {
    v.acceptor.LastBal = r.Bal
    v.acceptor.Val = r.Val
    v.acceptor.VBal = r.Bal
  }

  return &reply, nil
}
```

Acceptor 的逻辑到此完整了, 再看Proposer:

### 实现Proposer 逻辑

Proposer的运行分2个阶段, Phase1 和 Phase2, 与 Prepare 和 Accept 对应.

#### Phase1

在 [impl.go](https://github.com/openacid/paxoskv/blob/naive/paxoskv/impl.go) 的实现中, `Proposer.Phase1()`函数负责Phase1的逻辑:

```go
func (p *Proposer) Phase1(
    acceptorIds []int64,
    quorum int) (*Value, *BallotNum, error) {

  replies := p.rpcToAll(acceptorIds, "Prepare")

  ok := 0
  higherBal := *p.Bal
  maxVoted := &Acceptor{VBal: &BallotNum{}}

  for _, r := range replies {
    if !p.Bal.GE(r.LastBal) {
      higherBal = *r.LastBal
      continue
    }

    if r.VBal.GE(maxVoted.VBal) {
      maxVoted = r
    }

    ok += 1
    if ok == quorum {
      return maxVoted.Val, nil, nil
    }
  }

  return nil, &higherBal, NotEnoughQuorum
}
```

这段代码首先通过 `rpcToAll()` 向所有Acceptor发送Prepare-request请求, 然后找出所有的成功的reply:

- 如果发现一个更大的ballot number, 表示一个Prepare**失败**: 有更新的Proposer存在;
- 否则, 它是一个**成功**的应答, 再看它有没有返回一个已经被Acceptor接受(voted)的值.

最后, 成功应答如果达到多数派(quorum), 则认为Phase1 完成, 返回最后一个被voted的值, 也就是VBal最大的那个. 让上层调用者继续Phase2;

如果没有达到quorum, 这时可能是有多个Proposer并发运行而造成冲突, 有更大的ballot number, 这时则把见到的最大ballot number返回, 由上层调用者提升ballot number再重试.

#### client 与 server 端的连接

上面用到的 `rpcToAll` 在这个项目中的实现client端(Proposer)到server端(Acceptor)的通讯, 它是一个十分 ~~简洁美观~~ 简陋的 grpc 客户端实现:

```go
func (p *Proposer) rpcToAll(
    acceptorIds []int64,
    action string) []*Acceptor {

  replies := []*Acceptor{}

  for _, aid := range acceptorIds {
    var err error
    address := fmt.Sprintf("127.0.0.1:%d",
        AcceptorBasePort+int64(aid))

    conn, err := grpc.Dial(
        address, grpc.WithInsecure())
    if err != nil {
      log.Fatalf("did not connect: %v", err)
    }
    defer conn.Close()

    c := NewPaxosKVClient(conn)

    ctx, cancel := context.WithTimeout(
        context.Background(), time.Second)
    defer cancel()

    var reply *Acceptor
    if action == "Prepare" {
      reply, err = c.Prepare(ctx, p)
    } else if action == "Accept" {
      reply, err = c.Accept(ctx, p)
    }
    if err != nil {
      continue
    }
    replies = append(replies, reply)
  }
  return replies
}
```

#### Phase2

Proposer运行的Phase2 在[slide-30](https://blog.openacid.com/algo/paxos/#slide-30) 中描述, 比Phase1更简单:

> 在第2阶段phase-2, Proposer X将它选定的值写入到Acceptor中, 这个值可能是它自己要写入的值, 或者是它从某个Acceptor上读到的v(修复).

```go
func (p *Proposer) Phase2(
    acceptorIds []int64,
    quorum int) (*BallotNum, error) {

  replies := p.rpcToAll(acceptorIds, "Accept")

  ok := 0
  higherBal := *p.Bal
  for _, r := range replies {
    if !p.Bal.GE(r.LastBal) {
      higherBal = *r.LastBal
      continue
    }
    ok += 1
    if ok == quorum {
      return nil, nil
    }
  }

  return &higherBal, NotEnoughQuorum
}
```

我们看到, 它只需要确认成 Phase2 的功应答数量达到quorum就可以了. 另外同样它也有责任在 Phase2 失败时返回看到的更大的ballot number, 因为在 Phase1 和 Phase2 之间可能有其他 Proposer 使用更大的ballot number打断了当前Proposer的执行, 就像[slide-33](https://blog.openacid.com/algo/paxos/#slide-33) 的冲突解决的例子中描述的那样. 后面讲.

## 完整的paxos逻辑

完整的 paxos 由 Proposer 负责, 包括: 如何选择一个值, 使得一致性得以保证. 如 [slide-29](https://blog.openacid.com/algo/paxos/#slide-29) 中描述的:

> Proposer X收到多数(quorum)个应答, 就认为是可以继续运行的.如果没有联系到多于半数的acceptor, 整个系统就hang住了, 这也是paxos声称的只能运行少于半数的节点失效. 这时Proposer面临2种情况:
>
> 所有应答中都没有任何非空的v, 这表示系统之前是干净的, 没有任何值已经被其他paxos客户端完成了写入(因为一个多数派读一定会看到一个多数派写的结果). 这时Proposer X继续将它要写的值在phase-2中真正写入到多于半数的Acceptor中.
>
> 如果收到了某个应答包含被写入的v和vrnd, 这时, Proposer X 必须假设有其他客户端(Proposer) 正在运行, 虽然X不知道对方是否已经成功结束, 但任何已经写入的值都不能被修改!, 所以X必须保持原有的值. 于是X将看到的最大vrnd对应的v作为X的phase-2将要写入的值.
>
> 这时实际上可以认为X执行了一次(不知是否已经中断的)其他客户端(Proposer)的修复.

![img](https://tva1.sinaimg.cn/large/0081Kckwly1gkcymczbaaj30m80goac7.jpg)

基于 Acceptor 的服务端和 Proposer 2个 Phase 的实现, 最后把这些环节组合到一起组成一个完整的paxos, 在我们的代码 [RunPaxos](https://github.com/openacid/paxoskv/blob/naive/paxoskv/impl.go#L46) 这个函数中完成这些事情:

```go
func (p *Proposer) RunPaxos(
    acceptorIds []int64,
    val *Value) *Value {

  quorum := len(acceptorIds)/2 + 1

  for {
    p.Val = val

    maxVotedVal, higherBal, err := p.Phase1(
        acceptorIds, quorum)

    if err != nil {
      p.Bal.N = higherBal.N + 1
      continue
    }

    if maxVotedVal != nil {
      p.Val = maxVotedVal
    }

    // val == nil 是一个读操作,
    // 没有读到voted值不需要Phase2
    if p.Val == nil {
      return nil
    }

    higherBal, err = p.Phase2(
        acceptorIds, quorum)

    if err != nil {
      p.Bal.N = higherBal.N + 1
      continue
    }

    return p.Val
  }
}
```

这段代码完成了几件事: 运行 Phase1, 有voted的值就选它, 没有就选自己要写的值`val`, 然后运行 Phase2.

就像 Phase1 Phase2 中描述的一样, 任何一个阶段, 如果没达到quorum, 就需要提升遇到的更大的ballot number, 重试去解决遇到的ballot number冲突.

这个函数接受2个参数:

- 所有Acceptor的列表(用一个整数的id表示一个Acceptor),
- 以及要提交的值.

其中, 按照paxos的描述, 这个值`val`**不一定能提交**: 如果paxos在 Phase1 完成后看到了其他已经接受的值(voted value), 那就要选择已接收的值, 放弃`val`. 遇到这种情况, 在我们的系统中, 例如要写入key=foo, ver=3的值为bar, 如果没能选择bar, 就要选择下一个版本key=foo, ver=4再尝试写入.

这样不断的重试循环, 写操作最终都能成功写入一个值(一个key的一个版本的值).

# 实现读操作

在我们这个NB(naive and bsice)的系统中, 读和写一样都要通过一次paxos算法来完成. 因为写入过程就是一次paxos执行, 而paxos只保证在一个quorum中写入确定的值, 不保证所有节点都有这个值. 因此一次读操作如果要读到最后写入的值, 至少要进行一次**多数派读**.

但多数派读还不够: 它可能读到一个未完成的paxos写入, 如 [slide-11](https://blog.openacid.com/algo/paxos/#slide-11) 中描述的脏读问题, 读取到的最大VBal的值, 可能不是确定的值(写入到多数派).

例如下面的状态:

```
Val=foo    Val=bar    ?
VBal=3     VBal=2     ?
-------    -------    --
A0         A1         A2
```

如果Proposer试图读, 在 Phase1 联系到A0 A1这2个Acceptor, 那么foo和bar这2个值哪个是确定下来的, 要取决于A2的状态. 所以这时要再把最大`VBal`的值跑完一次 Phase2, 让它被确定下来, 然后才能把结果返回给上层(否则另一个Proposer可能联系到A1 和 A2, 然后认为Val=bar是被确定的值).

当然如果 Proposer 在读取流程的 Phase1 成功后没有看到任何已经voted的值(例如没有看到foo或bar), 就不用跑 Phase2 了.

所以在这个版本的实现中, 读操作也是一次 [RunPaxos](https://github.com/openacid/paxoskv/blob/naive/paxoskv/impl.go#L46) 函数的调用, 除了它并不propose任何新的值, 为了支持读操作, 所以在上面的代码中 Phase2 之前加入一个判断, **如果传入的val和已voted的值都为空, 则直接返回**:

```go
if p.Val == nil {
  return nil
}
```

[Example_setAndGetByKeyVer](https://github.com/openacid/paxoskv/blob/naive/paxoskv/example_set_get_test.go) 这个测试用例展示了如何使用paxos实现一个kv存储, 实现读和写的代码大概这样:

```go
prop := Proposer{
  Id: &PaxosInstanceId{
    Key: "foo",
    Ver: 0,
  },
  Bal: &BallotNum{N: 0, ProposerId: 2},
}

// 写:
v := prop.RunPaxos(acceptorIds, &Value{Vi64: 5})

// 读:
v := prop.RunPaxos(acceptorIds, nil)
```

到现在为止, 本文中涉及到的功能都实现完了, 完整实现在 [impl.go](https://github.com/openacid/paxoskv/blob/naive/paxoskv/impl.go) 中.

接着我们用测试用例实现1下 [paxos的直观解释](https://blog.openacid.com/algo/paxos) 中列出的2个例子, 从代码看poxos的运行:

# 文中例子

第1个例子是 paxos 无冲突的运行 [slide-32](https://blog.openacid.com/algo/paxos/#slide-32):

![img](https://tva1.sinaimg.cn/large/0081Kckwly1gkcymdix11j30m80go0ty.jpg)

把它写成test case, 确认教程中每步操作之后的结果都如预期 [TestCase1SingleProposer](https://github.com/openacid/paxoskv/blob/naive/paxoskv/paxos_slides_case_test.go#L11):

```go
func TestCase1SingleProposer(t *testing.T) {
  ta := require.New(t)

  acceptorIds := []int64{0, 1, 2}
  quorum := 2

  // 启动3个Acceptor的服务
  servers := ServeAcceptors(acceptorIds)
  defer func() {
    for _, s := range servers {
      s.Stop()
    }
  }()

  // 用要更新的key和version定义paxos 实例的id
  paxosId := &PaxosInstanceId{
    Key: "i",
    Ver: 0,
  }

  var val int64 = 10

  // 定义Proposer, 随便选个Proposer id 10.
  var pidx int64 = 10
  px := Proposer{
    Id:  paxosId,
    Bal: &BallotNum{N: 0, ProposerId: pidx},
  }

  // 用左边2个Acceptor运行Phase1,
  // 成功, 没有看到其他的ballot number
  latestVal, higherBal, err := px.Phase1(
      []int64{0, 1}, quorum)

  ta.Nil(err, "constitued a quorum")
  ta.Nil(higherBal, "no other proposer is seen")
  ta.Nil(latestVal, "no voted value")

  // Phase1成功后, 因为没有看到其他voted的值,
  // Proposer选择它自己的值进行后面的Phase2
  px.Val = &Value{Vi64: val}

  // Phase 2
  higherBal, err = px.Phase2(
      []int64{0, 1}, quorum)

  ta.Nil(err, "constitued a quorum")
  ta.Nil(higherBal, "no other proposer is seen")
}
```

第2个例子对应2个Proposer遇到冲突并解决冲突的例子, 略长不贴在文中了, 代码可以在 [TestCase2DoubleProposer](https://github.com/openacid/paxoskv/blob/naive/paxoskv/paxos_slides_case_test.go#L57) 看到

![img](https://tva1.sinaimg.cn/large/0081Kckwly1gkcymcjembj30m80goabx.jpg)

# 下一步

我们实现了指定key, ver的存储系统, 但相比真正生产可用的kv存储, 还缺少一些东西:

- 写操作一般都不需要用户指定ver, 所以还需要实现**对指定key查找最大ver的功能**. 这些跟paxos关系不大, 现在这个实现中就省去了这些逻辑. 以后再讲. 🤔

- 其次为了让读操作不需要指定ver, 还需要一个**snapshot**功能, 也就是保存一个key-value的map, 这个map中只需要记录每个key最新的value值(以及ver等). 有了这个map之后, 已经确认的值对应的version就可以删掉了. 也就是说Versions 结构只作为每个key的**修改日志**存在, 用于存储每次修改对应的paxos实例.

- snapshot功能还会引入应另外一个需求, 就是[paxos made simple](http://lamport.azurewebsites.net/pubs/pubs.html#paxos-simple) 中的 learn 的行为, 对应Phase3, 本文中描述的这个存储中, 只有Proposer知道某个key-ver达到多数派, Acceptor还不知道, (所以读的时候还要走一遍paxos). 在论文中的描述是Acceptor接受一个值时(vote), 也要把这个事情通知其他 Learner角色, 我们可以给每个Acceptor也设定成Learner: **Acceptor vote一个值时除了应答Proposer, 也广播这个事件给其他Acceptor**, 这样每个Acceptor也就可以知道哪个值是达到quorum了(safe), 可以直接被读取.

  但在实际实现时, 这种方法产生的消息会达到 n² 级别的数量. 所以一般做法是让Proposer做这件事: 当Proposer收到一个quorum的Phase2应答后, 再广播一条消息告诉所有的Acceptor: 这个paxos实例已经safe了, 这个消息在大多数系统中都就称作**Commit**.

以上这3块内容, 后续播出, 下个版本的实现将使用经典的log 加 snapshot的方式存储数据.

各位朋友对哪些方面感兴趣, 欢迎催更 🤔…

------

本文用到的代码在 paxoskv 项目的 naive 分支上: https://github.com/openacid/paxoskv/tree/naive

如有什么本文遗漏的地方, 或有任何好想法, 欢迎随时交流讨论,

本文相关问题可以在 paxoskv 这个项目上提 基hub [issue](https://github.com/openacid/paxoskv/issues/new/choose).

本文链接: [https://blog.openacid.com/algo/paxoskv/](https://blog.openacid.com/algo/paxoskv/)

![openacid](https://tva1.sinaimg.cn/large/0081Kckwly1gkcymef44aj30m8096aax.jpg)
