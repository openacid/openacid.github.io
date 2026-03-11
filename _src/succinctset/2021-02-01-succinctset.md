---
title:      "100行代码的压缩前缀树: 50% smaller"
authors:
    - xp
categories:
    - algo
tags:
    - memory
    - succinct
    - trie
    - bitmap

refs:
    - "report": https://github.com/openacid/succinct/blob/v0.1.0/report/main.go "report"
    - "前缀树": https://en.wikipedia.org/wiki/Trie "trie"
    - "trie": https://en.wikipedia.org/wiki/Trie "trie"
    - "succinct": https://en.wikipedia.org/wiki/Succinct_data_structure

    - "cpp-popcount":  https://en.cppreference.com/w/cpp/numeric/popcount "popcount"

    - "post-zipf": https://blog.openacid.com/tech/zipf/ "zipf"

    - "repo-slim": https://github.com/openacid/slim "slim"
    - "succinct.Set": https://github.com/openacid/succinct/tree/loc100 "succinct.Set"

    - "google-btree": https://github.com/google/btree "btree"

platform_refs:
    wechat:
    zhihu:
        - "post-zipf": https://zhuanlan.zhihu.com/p/94525243 "zipf"

pdf: false

mathjax: false
toc: true
toc_label: 本文目录
toc_sticky: true
excerpt: "压缩前缀树, 减少50%存储空间, 支持创建和查询, 只需100行代码"
---

![](succinctset-wechat-banner-small.jpg)

这文介绍一个压缩前缀树实现的sorted set(github: [succinct.Set][]), 区区95行代码, 包含了一组完整的功能:

- 用 [前缀树][] 存储一个排序数组, 去掉指针, 压缩掉50%的空间;
  例如在本文的例子中, 存储2.4MB的200万个单词, 只需要1.2MB.

- 创建: 从key列表创建一个压缩的前缀树;

- 查询: 支持Has() 操作来查询1个key是否存在;

- 优化: 通过索引来加速 bitmap 的操作, 将较大的 bitmap 操作优化到O(1)的时间开销.

`loc100` 分支是本文中使用的最简实现, 没有任何外部依赖,
main分支中的实现面向生产环境, 要快4倍左右.

**如果要生产环境使用, 移步 [slim][repo-slim]**.


用20万个网上词汇来测试本文实现的succinctSet:

- succinctSet 空间开销是源数据的 **57%**.
- `Has()` 开销为 `350 ns`.

原始数据大小: 2204 KB

跟 string 数组的 bsearch, 以及 [google-btree][] 的对比:

| Data         | Engine       | Size(KB) | Size/original | ns/op |
| :--          | :--          | --:      | --:           | --:   |
| 200kweb2     | bsearch      |  5890    |  267%         | 229   |
| 200kweb2     | succinct.Set |  1258    |   57%         | 356   |
| 200kweb2     | btree        | 12191    |  553%         | 483   |

# 场景和问题

计算机中的信息, 为了查询方便, 几乎都是排序存储的(即使是hash结构, hash map 中的 hash 值也是顺序存储的).

数据存储领域, 大部分数据也都是静态的, 例如数据库底层的一个page,
rocksdb的一个sstable.
数据越来越大后对存储空间的开销也越来越敏感, 毕竟影响性能的主要瓶颈都在IO上,
不论是CPU对主存的访问延迟, 还是内存到磁盘的延迟, 每2层之间的IO延迟,
基本都在1~2个量级左右.
于是更小的存储开销, 不仅节省存储成本, 另一个bonus是几乎毫无疑问的会提升性能,

本文针对这一个广泛使用的场景: 静态排序数据,
提供一个通用的实现方法来压缩空间开销.

> 生产环境中使用的算法, 和本文介绍的方法同源, 但包括更多的优化,
> 例如通过SIMD指令一次处理多个字节的比较, 用bitmap来优化labels的存储,
> 对只有一个出向label的节点的合并优化等.


# 思路: 前缀树

[前缀树][], 或字典树, prefix tree,  trie, 是解决这类问题的一个典型思路.
例如要存储5个key: [ab, abc, abcd, axy, buv]
可以建立下面这样一个前缀树, 省去大量重复的前缀,
其中`^` 是root节点(也记做0), 1, 2, 3...是trie节点, `$`标记一个叶子节点,
 字母`a,
b...` 表示一个节点到下级节点的边(labeled branch):

```
^ -a-> 1 -b-> 3 $
  |      |      `c-> 6 $
  |      |             `d-> 9 $
  |      `x-> 4 -y-> 7 $
  `b-> 2 -u-> 5 -v-> 8 $
```

但是! 在 trie 的实现中, 就像一般的树形结构实现一样, 需要大量的指针,
每个 label 到其指向的节点需要占用一个指针.
在64位系统中一个指针就要占8字节,
整个 trie 中指针数量至少也是叶子节点的数量.

如果要存储的字符串长度比较短, 很可能编码成 trie 之后, 因为指针开销,
要占用更大空间.
即使是存储较长的字符串, 大部分场合指针的开销也无法忽略不计.

于是对于这类key集合确定的场景(例如rocksdb中的sstable, 就是典型的静态排序key的存储),
使用压缩的前缀树是一种更简洁有效的方式来去掉指针开销.


# 前缀树的压缩算法

在这个前缀树中, 每个节点至多有256个出向label, 指向下一级节点.
一个节点可以是inner节点, 例如root节点`^`, 或`1, 2, 3`.
也可以是叶子节点, 例如`3, 6, 9`. 这里3既是一个inner节点也是一个leaf节点.

```
^ -a-> 1 -b-> 3 $
  |      |      `c-> 6 $
  |      |             `d-> 9 $
  |      `x-> 4 -y-> 7 $
  `b-> 2 -u-> 5 -v-> 8 $
```

要压缩这个 trie, 对每个 trie 节点, 我们需要的最核心的信息是:
- 一个节点的分支(label)都有哪些,
- 以及label指向的节点的位置.

我们有以下这种紧凑的结构来描述这个 trie:

一个 trie 节点的出向 label 都存储在一个[]byte中,
再用一个 bitmap 来描述每个节点的分支, 后面通过这个 bitmap 来定位 label 对应的节点.

先把每个节点对应的 label 列出来, 并为每个 label 分配一个bit `0` 来标记:

```
^: {a, b} 00
1: {b, x} 00
2: {u}    0
3: {c}    0
4: {y}    0
5: {v}    0
6: {d}    0
7: ø
8: ø
9: ø
```

然后将所有的label保存在一个[]byte中,
再将对应的标记label的多个`0...`用`1`做分隔符连接到一起:
这2块信息是 succinctSet 核心的2个字段, 有了这2部分数据就可以实现(不算高效的)key查找:

```
labels(ignore space):  ab bx u c y v d øøø
label bitmap:          0010010101010101111
node-id:               0  1  2 3 4 5 6 789  // node-id 不需要存储
```

## 压缩后的查询

在标准的 trie 中查找一个 key 很简单, 在第L层的一个节点上,
查找key[L]的byte是否是 trie 节点的一个出向 label,
如果是, 走到下一个节点, 否则终止.

例如对`axy`的查找, 要经历3次查找,
`^ -a-> ① -x-> ④ -y-> ⑦ $`:

```
^ -a-> ① -b-> 3 $
  |      |      `c-> 6 $
  |      |             `d-> 9 $
  |      `x-> ④ -y-> ⑦ $
  `b-> 2 -u-> 5 -v-> 8 $
```

在 succinctSet 中的查找也是一样,
唯一不同的是如何在这个没有指针的结构中找到某个出向 label 对应的子节点.

我们把 trie 原来的 label 到子节点的关系, 在压缩后的结构中画出来, 端详端详:

```
|                                .-----.
|                        .--.    | .---|-.
|                        |.-|--. | | .-|-|.
|                        || ↓  ↓ | | | ↓ ↓↓
| labels(ignore space):  ab bx u c y v d øøø
| label bitmap:          0010010101010101111
| node-id:               0  1  2 3 4 5 6 789
|                           || | ↑ ↑ ↑ |   ↑
|                           || `-|-|-' `---'
|                           |`---|-'
|                           `----'
```

从上图可以看出,

-   除了根节点`^`, 每个节点都有一个`0`与之对应(节点入向 label 对应位置的0).
    图中上下箭头, 是 label 到节点的关系, 也就是每个`0`跟它指向的子节点的对应关系.

-   每个节点也都有一个`1`与之一一对应, 也就是每个节点都有一个结束标记`1`.

例如:

-   bitmap 中
    第0个`0`对应节点`1:bx`,
    第1个`0`对应节点`2:u`...

-   同理节点与`1`的关系也类似,
    第0个`1`对应root节点`^`, `0:ab`,
    第1个`1`对应节点`1:bx`,
    第2个`1`对应节点`2:u`...


你品, 你细品...

品完后发现, **要找到某个 label 指向的节点, 只需要先数数这个 label 对应第几个`0`, 例如是第i个`0`,
再找到bitmap中的第i个`1`, 第i个`1`后面就是 label 对应的节点位置了**.

这就是在压缩前缀树中逐层定位节点的算法.

举个栗子 🌰

假设从根节点开始, 要查找的key是axy,

- 首先在根节点 `0:ab` 中找到label `a`,
- label `a` 对应第0个`0`, 然后找到第0个`1`的位置, 也就是`1:bx`节点.
- 再在`1:bx` 节点的 label 中找到 label `x`, 对应第3个`0`, 再找到第3个`1`的位置, 也就是`4:y` 的节点.
- 在`4:y`中找到 label `y`, 对应第6个`0`, 再找到第7个`1`, 也就是`7:ø`的节点.
- 节点7没有任何 label, 结束.

在 succinctSet 数据结构中画出 axy 的查询过程如下:

```
|                         a         y
|                        .--.      .-----.
|                        |  ↓      |     ↓
| labels(ignore space):  ab bx u c y v d øøø
| label bitmap:          0010010101010101111
| node-id:               0  1  2 3 4 5 6 789
|                            |     ↑
|                            `-----'
|                             x
```

## 维护 leaf 节点

上面介绍的查询算法还有一个问题, 就是当某些key是其他key的前缀时,
它对应的节点既是inner节点, 也是leaf节点, 这时无法通过 label 的不匹配结束查询.
例如 abc 对应的节点 `6:d`, 它本身有一个出向分支`d`, 是一个inner节点, 同时也是一个leaf节点.

```
^ -a-> 1 -b-> 3 $
  |      |      `c-> ⑥ $
  |      |             `d-> 9 $
  |      `x-> 4 -y-> ⑦ $
  `b-> 2 -u-> 5 -v-> 8 $
```

所以我们还需要额外的信息来标识所有的 leaf 节点:
再建立一个 **leaves** 的 bitmap, 它的第`i`个bit为`1`, 表示node-id为`i`的节点是leaf节点:

```
labels(ignore space):  ab bx u c y v d øøø
label bitmap:          0010010101010101111
leaves(ignore space):  0  0  0 1 0 0 1 111
node-id:               0  1  2 3 4 5 6 789
```

leaves 的检查在查询的最后一步, 如果一个要查询的 key 匹配到一个trie中的节点,
最后再检查它是否是一个 leaf 节点.

## 优化 bitmap 操作

这个算法中最后还有一个问题没有解决:
我们提到从 label 定位 node 的过程是: 找到一个 label 之前的`0`的个数i, 再找到第i个的`1`的位置.
这2个操作都是O(n)的, 要遍历 bitmap, 最终会导致一次查询的时间效率变成O(n²).

为了能让查询提升效率, 我们需要建立2份额外的信息来优化这2个操作.

第一个是找出一个 bitmap 中第`i`个bit之前有多少个`1`(或多少个`0`).
对定长整数, 例如一个uint64, 它的有O(1)的实现, 例如
- 在cpp里叫做 [popcount][cpp-popcount], i.e., count of population of ones;
- 在go里面它被封装在`bits.OnesCount64()`这个函数, 数数一个uint64里有多少个1;
- 一般的, 叫做rank1(i), 如果要计算一个bitmap里有多少个0, 则是rank0(i).

第二个, 要得到第`i`个1的位置的操作, 叫做select1(i).

我们现在需要为 rank1() 和 select1() 分别建立缓存:

### rank

建立一个数组`rank []int32`: `ranks[i]` 记录 bitmap 中前 `i*64` 个bit中的`1`的数量.
这样要计算 rank(i) 就只需要取 ranks[i/64],
再用一个O(1)的函数调用(如`bits.OnesCount64()`)计算 `bitmap[i:i % 64]` 中的1的个数.

例如 bitmap 中第0个 uint64 有25个1, 第1个 uint64 有11个1, 那么建立的 ranks 索引如下:
[0, 25, 36]

```
ranks:   0  25  36
         |  |   `--------------------.
         |  `----------.             |
         v             v             v
bitmap:  0101...1010   1101...0010   0101...0010
         uint64        uint64        uint64
```

### select

select索引也是一个`[]int32`: `select[i]` 记录第`i*32`个`1`在bitmap中哪个位置.

例如第0个`1`在第1个bit, 第32个`1`在第67个bit, 第64个`1`出现在第126个bit,
那么 selects 的索引就是:`[1, 67, 126]`:

```
selects:  1  67  126
          |  |   `--------------.
          |  `------------.     |
          v               v     v
bitmap:  0101...1010   1101...0010   0101...0010
         uint64        uint64        uint64
```

# 代码实现

## Set 结构定义

有了 ranks 的索引, 找出第i个bit之前的`1`(或`0`)的数量就可以确定用O(1)时间完成;
而 select 索引, 可以尽可能让找出第i个1的开销趋近于O(1);
因为 selects 的2条索引之间可能跨越几个uint64, 取决于 bitmap 中`1`的分布.

这样, 整个 succinctSet 的数据结构就完整了:

```go
type Set struct {
    leaves, labelBitmap []uint64
    labels              []byte
    ranks, selects      []int32
}
```

我们接下来看看完整的代码逻辑:

## 创建 Set

依旧以 `keys = [ab, abc, abcd, axy, buv]` 为例, 来描述 Set 的建立,

-   先扫描所有 keys 的第1列, 找到root节点`^`的出向分支, 有2个label: `a, b`

    同时把整个keys列表按照前缀为`a`和前缀为`b`拆分成2部分, 顺次放到队列尾部等待处理.

-   第2步, 从队列中拿出要处理的第2部分: 前缀为`a`的keys,
    扫描这些 keys 的第2列, 找到节点`1`的出向label: `b, x`

    再次把前缀为`a`的集合拆分为前缀为`ab`的集合和前缀为`ax`的集合,
    顺次放到队列尾部等待处理.

-   第3步, 扫描前缀为`b`的key集合的第2列, 找到1个出向label `u`,
    把所有前缀为`bu`的key放到队列尾部等待处理.

最后直到所有队列中的元素都处理完, trie 就建立完成.
最后再通过`init()`给建好的trie做 rank 和 select 的索引.

扫描前缀的过程, 也就是建立 trie 节点的顺序, 按照node-id标识如下:

```
┍ 0  ┍ 1
| a  | b  ┍ 3
| a  | b  | c  ┍ 6
| a  | b  ↓ c  ↓ d
|    |    ┍ 4
| a  ↓ x  ↓ y
|    ┍ 2  ┍ 5
↓ b  ↓ u  ↓ v
```

```go
func NewSet(keys []string) *Set {

    lIdx := 0
    ss := &Set{}

    type qElt struct{ s, e, col int }

    queue := []qElt{ {0, len(keys), 0} }

    for i := 0; i < len(queue); i++ {
        elt := queue[i]

        if elt.col == len(keys[elt.s]) {
            elt.s++
            setBit(&ss.leaves, i, 1)
        }

        for j := elt.s; j < elt.e; {

            frm := j

            for ; j < elt.e && keys[j][elt.col] == keys[frm][elt.col]; j++ {
            }

            queue = append(queue, qElt{frm, j, elt.col + 1})
            ss.labels = append(ss.labels, keys[frm][elt.col])
            setBit(&ss.labelBitmap, lIdx, 0)
            lIdx++
        }

        setBit(&ss.labelBitmap, lIdx, 1)
        lIdx++
    }

    ss.init()
    return ss
}
```


## 查询

trie的查询过程也很简单:
在要查询的key中取出一个byte,
看它是否在当前节点的 label 中, 如果不在, 就可以确认 key 不在 succinctSet 中.
如果在, 通过之前提到的`select1(rank0(i))`的方法走到下一个节点, 继续以上步骤.

当 key 中所有 byte 都检查完后, 看最后是否停在一个 leaf 节点,
最终确认是否匹配到一个在Set中存在的key.

```go
func (ss *Set) Has(key string) bool {

    nodeId, bmIdx := 0, 0

    for i := 0; i < len(key); i++ {
        c := key[i]
        for ; ; bmIdx++ {

            if getBit(ss.labelBitmap, bmIdx) != 0 {
                return false
            }

            if ss.labels[bmIdx-nodeId] == c {
                break
            }
        }

        nodeId = countZeros(ss.labelBitmap, ss.ranks, bmIdx+1)
        bmIdx = selectIthOne(ss.labelBitmap,
                             ss.ranks, ss.selects, nodeId-1) + 1
    }

    return getBit(ss.leaves, nodeId) != 0
}

func getBit(bm []uint64, i int) uint64 {
    return bm[i>>6] & (1 << uint(i&63))
}
```

## bitmap 的索引

上面我们提到, 从 label 定位节点的过程主要依赖于计算 bitmap 的2个操作:
计算指定位置前有几个1: `rank0(i)`, 以及找出第i个1的位置: `select1(i)`.

go里面提供了 uint64 的rank操作, bits.OnesCount64()
可以在O(1)的时间内返回一个 uint64 中被置为`1`的bit数.
我们用它来给 bitmap 中每个 unit64 提前计算好前面有几个`1`,
这样在使用的时候只需要再处理最后一个uint64就可以了.

select的索引直接逐个计数`1`的个数, 然后在个数满32整数倍时添加一条索引.

```go
func (ss *Set) init() {
    ss.ranks = []int32{0}
    for i := 0; i < len(ss.labelBitmap); i++ {
        n := bits.OnesCount64(ss.labelBitmap[i])
        ss.ranks = append(ss.ranks, ss.ranks[len(ss.ranks)-1]+int32(n))
    }

    ss.selects = []int32{}
    n := 0
    for i := 0; i < len(ss.labelBitmap)<<6; i++ {
        z := int(ss.labelBitmap[i>>6]>>uint(i&63)) & 1
        if z == 1 && n&63 == 0 {
            ss.selects = append(ss.selects, int32(i))
        }
        n += z
    }
}
```

当我们要利用索引取第i个bit前有几个`0`时, 通过`rank0(i) = i - rank1(i)` 来计算:

```go
// countZeros counts the number of "0" in a bitmap before the i-th bit(excluding
// the i-th bit) on behalf of rank index.
// E.g.:
//   countZeros("010010", 4) == 3
//   //          012345
func countZeros(bm []uint64, ranks []int32, i int) int {
    return i - int(ranks[i>>6]) - bits.OnesCount64(bm[i>>6]&(1<<uint(i&63)-1))
}
```

在查找第i个`1`所在位置时, 我们先通过 selects 索引找到一个最接近的 uint64,
再向后逐个查找直到见到第i个`1`. 这一步的性能不是严格的O(1):

```go
// selectIthOne returns the index of the i-th "1" in a bitmap, on behalf of rank
// and select indexes.
// E.g.:
//   selectIthOne("010010", 1) == 4
//   //            012345
func selectIthOne(bm []uint64, ranks, selects []int32, i int) int {
    base := int(selects[i>>6] & ^63)
    findIthOne := i - int(ranks[base>>6])

    for i := base >> 6; i < len(bm); i++ {
        bitIdx := 0
        for w := bm[i]; w > 0; {
            findIthOne -= int(w & 1)
            if findIthOne < 0 {
                return i<<6 + bitIdx
            }
            t0 := bits.TrailingZeros64(w &^ 1)
            w >>= uint(t0)
            bitIdx += t0
        }
    }
    panic("no more ones")
}
```

# 性能分析

我们用网上搜集到的数据集做了下测试.
测试中使用的负载模型都是 [zipf][post-zipf], 比较符合互联网的真实场景, zipf 的参数 s 取 1.5,
细节参考 [report][] 的代码, 结果如下:

-   20万个网上词汇:
    - succinctSet 空间开销是源数据的 **57%**.
    - `Has()` 开销为 `350 ns`.

    原始数据大小: 2204 KB

    跟 string 数组的 bsearch, 以及 [google-btree][] 的对比:

    | Data         | Engine       | Size(KB) | Size/original | ns/op |
    | :--          | :--          | --:      | --:           | --:   |
    | 200kweb2     | bsearch      |  5890    |  267%         | 229   |
    | 200kweb2     | succinct.Set |  1258    |   57%         | 356   |
    | 200kweb2     | btree        | 12191    |  553%         | 483   |

-   87万个某站提供的 ipv4 列表:
    - succinctSet 空间开销是源数据的  **67%**.
    - `Has()` 开销为 `528 ns`.

    原始数据大小: 6823 KB

    | Data         | Engine       | Size(KB) | Size/original | ns/op |
    | :--          | :--          | --:      | --:           | --:   |
    | 870k_ip4_hex | bsearch      | 17057    |  500%         | 276   |
    | 870k_ip4_hex | succinct.Set |  2316    |   67%         | 496   |
    | 870k_ip4_hex | btree        | 40388    | 1183%         | 577   |

可以看出在内存方面:

- succinctSet 对内存开销优势明显, 不仅容量没有额外增加, 还少很多.

- go中的string有2个字段: 到string内容的指针, 以及一个length,
    所以每条记录开销会多16字节.

- [google-btree][] 内部因为还有interface, 额外存储开销更大.


对查询性能:

- 短字符串查询二分查找性能最好, 一个字符串读取一次差不多都能缓存在L1 cache里, 对主存的访问应该非常趋近于lg₂(n).

- succinctSet 因为每个字符串的每个字符都被分散存储了,
    以及ranks和selects的访问也是跳跃的, 在一个key的查询中要访问多个位置.
    所以对缓存的友好不如数组.

- btree的时间开销更大, 可能由于间接访问比较多, 导致btree的优势没有发挥出来.


github: [succinct.Set][]

{% include build_ref %}
