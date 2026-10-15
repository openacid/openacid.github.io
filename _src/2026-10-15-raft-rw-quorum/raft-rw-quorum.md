---
title: "Flexible Raft: Read and Write Quorums"
date: 2026-10-15
url: /distributed/raft-rw-quorum/
authors:
    - xp
categories:
    - distributed
tags:
    - raft
    - consensus
    - distributed
mathjax: false
toc: true
toc_label: Table of Contents
toc_sticky: true
description: "A Raft leader usually waits for a majority before committing a write. We can reduce that wait, but the election rules and leader identities must still protect the log. Through a few small clusters, we explore two ways to do this, then follow the consequences for reads, failures, and membership changes."
---

# Flexible Raft: `Read and Write Quorums`

![](images/raft-rw-quorum-banner-small.png)

Picture a five-node Raft cluster handling a write. The leader has saved the entry locally and sent it to the followers. One follower replies. Then a second. Now the leader has three copies, enough to commit.

That wait is part of every write. Electing a leader also takes three votes. But elections and writes do different jobs, so we have some room to change who we wait for. If we're willing to ask more nodes to vote in an election, we can sometimes ask fewer nodes to acknowledge each write.

Let's give those two groups names. A quorum is a group of nodes whose replies let an operation proceed. We'll call the group used for elections a **`read quorum`**, and the group used to commit an entry a **`write quorum`**.

Raft can use different rules for these two groups. We just have to make sure those rules still let the cluster deal safely with competing leaders. **We can either keep one elected leader per term, or give the protocol a way to order leaders within the same term.**

We'll start with a few nodes running Paxos, see what happens when two leaders try to write, and then bring the same idea to Raft. I'll assume you're already familiar with the basics of both protocols.

## Flexible Paxos separates election and replication quorums

### Every `read quorum` must intersect every `write quorum`

In the usual Paxos setup, both phases need a majority. Any two majorities share at least one node, so all the quorums overlap. That's the arrangement in Lamport's [Paxos Made Simple][ref-paxos-simple].

Flexible Paxos lets us be more selective about that overlap. We use a `read quorum` in phase 1 to establish a leader, and a `write quorum` in phase 2 to commit a command. The rule we need is this: **every `read quorum` must share a node with every `write quorum`**. Two `read quorums` can be disjoint. So can two `write quorums`.

Let's put four nodes on a grid and see what that buys us.

### In a four-node grid, a row elects and a column replicates

Here's our cluster:

|       | Column 1 | Column 2 |
| ----- | -------- | -------- |
| Row 1 | node-1   | node-2   |
| Row 2 | node-3   | node-4   |

We'll use a whole row to elect a leader and a whole column to commit a command. So our `read quorums` are `{1, 2}` and `{3, 4}`, and our `write quorums` are `{1, 3}` and `{2, 4}`.

Pick any row, then any column. They always meet at one node. That gives us exactly the intersection Flexible Paxos asks for, with only two nodes in each quorum. A majority of four would need three.

Node-1, for example, can finish phase 1 with `{1, 2}`. When it wants to write, it can use either column, `{1, 3}` or `{2, 4}`.

![Four-node grid: read rows intersect write columns](images/01-quorum-grid.png)

There's something else to notice about those rows. They don't overlap with each other. Node-1 can get enough votes from the top row while node-4 gets enough from the bottom row. Both can finish phase 1.

That's allowed. Paxos has another rule that settles what happens when they try to write.

### Paxos resolves competing leaders in phase 2

Each Paxos election attempt has a ballot. Ballots are globally unique and totally ordered, which means we can always tell which of two different ballots is higher.

**When a node promises to honor a ballot, it's also promising to reject later writes with a lower ballot.** A leader finishes phase 1 only after a `read quorum` has made that promise. Every `write quorum` touches that `read quorum`, so every possible `write quorum` contains someone who can enforce the promise.

Now let's follow node-1 and node-4. Node-1 uses `ballot_1`, node-4 uses `ballot_4`, and `ballot_1 < ballot_4`. Both finish phase 1 before either tries to write at a new index `i`.

Node-1 wants to write `a` through `{1, 3}`. It sends the entry to node-3. But node-3 has already promised to honor `ballot_4`. Its answer is effectively, "I've promised a higher ballot. I can't accept this write." Node-1 is missing an acknowledgment, so it can't commit `a`.

Next, node-4 tries to write `b` through `{2, 4}`. Node-2 has promised `ballot_1`, which is lower than `ballot_4`, so it can accept the newer ballot. Node-4 can accept its own ballot too. That completes the `write quorum`, and `b` commits.

![Paxos rejects the lower ballot in phase 2](images/02-paxos-phase-conflict.png)

Both leaders made it through phase 1. Once they tried to write, the ballot ordering gave the nodes a way to settle the competition. In this execution, only the leader with the higher ballot can finish phase 2.

That's why the `read quorums` can be disjoint. The overlap between an election quorum and every `write quorum` still gives the promises somewhere to take effect. The rest of Paxos, including recovery of previously accepted values, stays in place. [Flexible Paxos, §2, §4.1, §5][ref-flexible-paxos]

## Raft also needs a guarantee about competing leaders

It's tempting to give Raft the same grid. Its election does the job of Paxos phase 1, and its log replication does the job of phase 2. In a nine-node grid, we could use three nodes in a row for an election and three in a column for a write. The usual majority would be five.

Before we change the quorum rules, though, we need to look at an assumption Raft already makes: each term elects at most one leader. The grid can give us two leaders in the same term, and Raft's existing replication rules aren't prepared for that.

Let's run the four-node example again, this time with Raft.

### Disjoint `read quorums` can commit different commands at the same index

All four nodes start with the same log, and the next available index is `i`. We'll keep the same `read quorums`, `{1, 2}` and `{3, 4}`, and `write quorums`, `{1, 3}` and `{2, 4}`.

Node-1 and node-4 both start an election in term `t`. Node-1 gets the votes in the top row. Node-4 gets the votes in the bottom row. Both have enough votes under our new rules.

We'll use `voted_for` to track each node's vote in this term. Node-2 has `voted_for = 1`, and node-3 has `voted_for = 4`.

Now node-1 writes `a` at index `i` and sends it to node-3. Node-3 checks the request. The term matches its own term. The log prefix matches too. So it accepts the entry, even though it voted for node-4. Node-1 now has the `write quorum` `{1, 3}`. It commits and executes `a`.

Then node-4 writes `b` at the same index and sends it to node-2. Node-2 makes the same checks: matching term, matching prefix. It accepts `b`, despite having voted for node-1. Node-4 has the `write quorum` `{2, 4}`, so it commits and executes `b`.

![Raft with disjoint read quorums commits conflicting commands](images/03-raft-same-term-conflict.png)

**We've now executed two different commands at the same index.** That's a consensus failure.

The surprising part is that neither follower rejected the other leader's write. In standard Raft, a follower can accept AppendEntries from the elected leader even if it voted for someone else. The sender doesn't have to match `voted_for`; the request still has to pass the term and log matching checks. [Raft paper, Figures 2 and 3][ref-raft]

That behavior is useful when there's one elected leader. Our new election rules have allowed two.

### Raft relies on a unique leader within each term

Think about how a node tells one leader from another. For this discussion, let's write an election identity as `(term, voted_for)` and call it a `LeaderId`. The `voted_for` part names the candidate in that election.

In Paxos, ballots give us a total order. Standard Raft's rules work more like a partial order. A higher term is newer. The same term and candidate ID describe the same election. But two different candidates in the same term don't have an ordering. OpenRaft's [partial comparison rules][code-openraft-leader-id-cmp] express that directly.

Raft gets away with this because **each term elects at most one leader**. With majority election quorums, two candidates would have to share at least one voter. That voter only votes once, so both candidates can't win.

Now imagine a follower that voted for the losing candidate. It still needs to follow the winner. It can keep its election vote and accept valid replication requests from the elected leader. The vote and the leader it follows serve different purposes.

If two leaders win in the same term, that same follower has a problem. The term doesn't tell it which leader should take precedence.

You can see the same assumption in the log. Raft uses `(term, index)` as a log ID. Since one leader creates the entries for a term, the same term and index identify the same entry. In our broken grid example, two leaders created different entries with that same ID.

So we have two ways forward. We can change the `read quorums` to keep one leader per term. Or we can change the identities and the protocol rules so nodes can order leaders within a term.

## Two ways to implement `read and write quorums` in Raft

### Approach 1: `Read quorums` also intersect one another

Let's try the smaller protocol change first. We'll keep Raft's existing identity and voting rules, and make sure **any two election quorums share a voter**.

We now have three quorum rules:

1. Every `read quorum` intersects every `write quorum`.
2. Every pair of `read quorums` intersects.
3. `Write quorums` can still be disjoint.

On our four-node grid, we can build a `read quorum` from a whole row plus a whole column. That gives us three nodes. We'll keep each `write quorum` as one column, so a write still needs two nodes.

Take `read quorums` `{1, 2, 3}` and `{2, 3, 4}`. They share node-2 and node-3. Any other pair of these three-node `read quorums` shares at least two nodes as well. And because every `read quorum` includes a whole row, it still meets every write column.

![Two read quorums share nodes 2 and 3 in a four-node grid](images/04-quorum-size-tradeoff.png)

We can also describe this using quorum sizes alone. Let `N` be the number of nodes, `R` the `read quorum` size, and `W` the `write quorum` size. To make every `read quorum` meet every `write quorum`, we need `R ≥ N-W+1`. To make any two `read quorums` meet, we also need `R ≥ floor(N/2)+1`.

Put those together, and the smallest `read quorum` we can choose is **`R = max(N-W+1, floor(N/2)+1)`**.

Here's what that means for the five-node cluster we started with. Choose `R=4,W=2`, and a leader can commit after two nodes have the entry. But electing its replacement takes four votes.

Now let the leader and one other node fail. Three nodes are still running, but they can't produce the four votes we asked for. The cluster has to wait. With the usual `R=3,W=3` majority setup, those same three nodes could elect a leader and keep writing.

So a smaller `write quorum` has a cost. **We wait for fewer acknowledgments while the leader is running, but we need more nodes available when it's time to elect a replacement.** Majority quorums tolerate the most arbitrary node failures when we need to preserve both elections and writes.

#### Dedicated election nodes can provide the shared votes

There's another way to make those election quorums overlap. We can add a small group of nodes whose job is to vote. They persist their term and `voted_for`, but they don't normally receive log entries or run for leader.

Every `read quorum` must include a majority of these election nodes. Any two of those majorities share a voter. That voter can't vote twice in a term, so two candidates can't both win.

We still need the nodes that actually store the log. A `read quorum` must meet every `write quorum` at one of those data nodes. Before granting a vote, a data node checks that the candidate's log is at least as up to date as its own. That's how the election protects committed entries. **The dedicated voters keep the leader unique; the data nodes keep the log safe.** [Raft paper, §5.4.1, §5.4.3][ref-raft]

For example, keep four data nodes in the `2×2` grid and add three election nodes. To elect a leader, take one whole data row and any two election nodes. To commit a write, take one whole data column.

Every election quorum shares a voter with every other election quorum. It also meets every `write quorum` at a data node. We now have seven nodes in all, with four votes needed for an election and two acknowledgments for a write.

![Dedicated election nodes connect small read quorums](images/05-election-only-nodes.png)

Both versions of this first approach do the same job: they arrange for two elections to share a voter. If we want to let election quorums be disjoint, we'll need to give the protocol another way to handle competing leaders.

### Approach 2: Use ordered leader identities throughout the protocol

Let's give Raft the ordering that helped Paxos earlier. Each election attempt gets a globally unique `(term, voted_for)` identity. Compare the terms first. If the terms match, compare the candidate IDs. Now `(t, 1) < (t, 4)` has a clear meaning.

A candidate must use a fresh identity each time it campaigns, and each identity belongs to just one candidate. Two leaders can then belong to the same term while still having identities that every node can compare.

We have to carry that comparison through the protocol. Changing the election alone would leave us with the same kind of problem we just saw. There are three places to pay attention to:

1. When a vote request arrives, the voter checks the full leader identity against the highest identity it has accepted. It rejects a lower identity and checks the candidate's log before accepting a higher one. The accepted identity is persisted, even if the term hasn't changed.
2. When AppendEntries arrives, the receiver makes the same full-identity comparison. It rejects a lower identity and persists a higher one when accepting it. Once it has accepted the higher identity, later writes from the lower one are rejected.
3. The entries themselves record who created them. A log ID becomes `(term, voted_for, index)`. That candidate ID stays with the entry, even as the receiver votes in later elections. Elections compare the last entries by leader identity first, then index. Prefix matching and conflict detection use the full log ID too.

Commitment has to follow the same rule. **To commit an entry directly, the leader needs an entry from its own current full `LeaderId`.** Committing that entry also commits the entries before it, as in standard Raft.

Once all those rules agree, a node that has accepted a higher identity can stop a lower leader's writes. We can use the Flexible Paxos quorum rule again: **every `read quorum` must meet every `write quorum`, while `read quorums` can be disjoint.**

Let's see how that changes the story for nodes 1 and 4. We're back on the four-node grid. The `read quorums` are `{1, 2}` and `{3, 4}`, and the `write quorums` are `{1, 3}` and `{2, 4}`. The logs are identical before term `t`. Node-1 campaigns with `(t, 1)`, node-4 with `(t, 4)`, and node-1 wants to commit `a` at index `i`.

Suppose node-3 votes for node-4 first. It saves `(t, 4)`. When node-1 later sends AppendEntries with `(t, 1)`, node-3 rejects the request. Node-1 can't get the acknowledgment it needs from `{1, 3}`.

Now reverse the order. Node-1 first commits `a` through `{1, 3}`, so node-3 already has the entry. When node-4 asks for a vote, its log is still shorter. Node-3 rejects it on log freshness, and node-4 can't win through `{3, 4}`. To win that election, node-4 first needs a sufficiently up-to-date log that preserves `a`.

![Ordered leader identities handle two message orders](images/06-raft-ordered-leader.png)

In one order, the vote prevents the conflicting write. In the other, the committed entry prevents an election from discarding it. That's the protection we were missing when we first gave Raft the grid.

We should also try a failure while we're looking at grids. Take nine nodes in a `3×3` grid, with rows for elections and columns for writes. Let the three nodes on a diagonal fail.

Six nodes are still alive. But look at the rows: every row is missing a node. Every column is missing one too. We can't put together a single election quorum or `write quorum`.

With majority quorums, the nine-node cluster would need five nodes. The same six survivors could still elect a leader and commit writes. **The grid's availability depends on where the failures land, as well as how many nodes fail.**

![Three diagonal failures stop grid quorums; five of six survivors still form a majority](images/07-quorum-failure-comparison.png)

This second approach lets us use disjoint election quorums, but it changes more of the protocol. **The log ID grows from `(term, index)` to `(term, voted_for, index)`.** Votes, replication requests, and commitment checks all need to use that full identity.

If you'd like to see what those changes look like in code, OpenRaft has examples of [voting and persisting full leader identities][code-openraft-vote], [checking prefixes with full log IDs][code-openraft-prefix], and [checking the current leader identity before committing][code-openraft-commit].

## Client reads can confirm leadership through a `write quorum`

Now suppose a client sends a read instead of a write. For that read to be linearizable, it has to reflect every write that finished before the read began.

ReadIndex gives the leader two jobs. It needs to confirm that it's still allowed to act as leader, then wait until its state machine has applied enough of the log to answer the read.

There's a startup condition to keep here. **Before serving ReadIndex requests, a leader must have committed an entry from its current leadership.** In standard Raft, that means its current term. In the second approach, it means its current full leader identity. Changing the quorums doesn't remove that requirement. You can see the standard check in [etcd/raft's ReadIndex readiness code][code-etcd-read-index-ready].

After that, **either approach can confirm leadership through a `write quorum`**. Here's how a read proceeds:

1. The request arrives, and the leader records its current commit index as `read_index`.
2. The leader sends a fresh round of heartbeats and waits for a `write quorum` to acknowledge its current identity. It includes a round identifier so replies from an earlier round won't count for this read.
3. The leader waits for its local state machine to apply every entry through `read_index`. Only then does the application read the state and return the result. [etcd/raft ReadIndex interface and application requirements][code-etcd-read-index]

The heartbeats use the same identity rules as the rest of the protocol. The first approach compares terms. The second compares the full `(term, voted_for)` identity.

To see why a `write quorum` is enough, imagine that a newer leader was elected before this read arrived. That election used a `read quorum`. Our old leader is now asking a `write quorum` to acknowledge its heartbeat.

Those two groups have to share a node. The shared node has already accepted the newer identity, so it rejects the old leader's heartbeat. The old leader can't collect the replies it needs, and it can't return a stale read.

In our five-node cluster with `R=4,W=2`, any two nodes share at least one member with every four-node election quorum. So ReadIndex can confirm leadership with just two acknowledgments.

## Membership changes must preserve intersections across configurations

So far, we've kept the same nodes in the cluster. Now let's add or remove some. The quorum rules change with the membership, and the nodes won't all learn about that change at the same instant.

We'll call the old configuration `c0` and the new one `c1`. Between them, we'll use a joint configuration, `c01`. The cluster moves through `c0 → c01 → c1`.

While `c01` is in use, an election has to satisfy the `read quorum` rules of both `c0` and `c1`. A write has to satisfy both sets of `write quorum` rules. That gives us overlap while the cluster moves from one membership to the other.

This part of the story applies to nodes that store the log. The dedicated election nodes we discussed earlier would need their own way to learn and activate membership changes.

### Commit the joint configuration before activating the new configuration

Raft sends membership changes through the log. In the transition we're describing, a node uses the configuration in its latest local configuration entry. It switches as soon as it appends that entry, before the entry commits.

Let's follow the leader through the change:

1. It appends and replicates `c01`. Each node starts using `c01` when it appends that entry locally.
2. It waits for `c01` to commit under `c01`'s `write quorum` rules. Only then does it append and replicate `c1`. Nodes start using `c1` as they append that entry.
3. It commits `c1` under `c1`'s `write quorum` rules. The membership change is complete.

At first, some nodes may still be using `c0` while others have moved to `c01`. Later, some may be using `c01` while others have moved to `c1`.

The wait between those two stages matters. **By committing `c01` before introducing `c1`, we keep the old and new configurations from making independent decisions.** The election freshness check and commitment rules also make later leaders retain the committed configuration entry. A change of leader therefore preserves that ordering. [Raft paper, §6, Figure 11][ref-raft]

So we check intersections across each adjacent pair: `c0` with `c01`, then `c01` with `c1`. **Every `read quorum` on either side must meet every `write quorum` on the other side.** With the first approach, `read quorums` must also meet across the pair, so we still elect only one leader per term. With the second approach, ordered leader identities handle the competition.

### The joint configuration combines `read and write quorums` separately

Let's make the joint quorums concrete. Call one `read quorum` from the old configuration `c0.read`, and one `write quorum` `c0.write`. We'll use the same notation for `c01` and `c1`.

To build a joint `read quorum`, take a `read quorum` from each configuration and combine them. To build a joint `write quorum`, do the same with a `write quorum` from each:

- `c01.read` contains a `c0.read` quorum and a `c1.read` quorum.
- `c01.write` contains a `c0.write` quorum and a `c1.write` quorum.

![Three phases: c0, c01, and c1 each show read and write quorums](images/08-joint-quorums.png)

The joint configuration now shares the quorums it needs with both sides. The old and new configurations can even have completely different members. They still connect through `c01`.

Both pieces matter: the joint quorums give us the overlap, and committing `c01` before introducing `c1` makes sure we use that overlap throughout the change.

## Quorums and leader identities must be designed together

Go back to that five-node leader waiting for its third copy of a write. We can let it commit with two copies. One way is to ask for four votes at the next election. Another is to order full leader identities and carry that ordering through voting, replication, log matching, and commitment, so we can safely use other quorum arrangements.

In either case, every `read quorum` still has to meet every `write quorum`. The same overlap helps us confirm leadership for reads and move safely between memberships.

We can make the leader wait for fewer acknowledgments. We just need to be clear about what we're asking the rest of the cluster to do in return, especially when a leader fails or the membership changes.

[ref-paxos-simple]: https://lamport.azurewebsites.net/pubs/paxos-simple.pdf "Paxos Made Simple"
[ref-flexible-paxos]: https://arxiv.org/pdf/1608.06696 "Flexible Paxos: Quorum intersection revisited"
[ref-raft]: https://raft.github.io/raft.pdf "In Search of an Understandable Consensus Algorithm"
[code-openraft-leader-id-cmp]: https://github.com/databendlabs/openraft/blob/728e66bba05c4305dd37016535d1c247a35d2059/openraft/src/vote/leader_id/leader_id_cmp.rs#L9-L27 "OpenRaft: partial comparison of leader IDs"
[code-openraft-vote]: https://github.com/databendlabs/openraft/blob/728e66bba05c4305dd37016535d1c247a35d2059/openraft/src/engine/handler/vote_handler/mod.rs#L101-L155 "OpenRaft: vote with and persist the full leader identity"
[code-openraft-prefix]: https://github.com/databendlabs/openraft/blob/728e66bba05c4305dd37016535d1c247a35d2059/openraft/src/engine/handler/following_handler/mod.rs#L120-L139 "OpenRaft: check log prefixes with full log IDs"
[code-openraft-commit]: https://github.com/databendlabs/openraft/blob/728e66bba05c4305dd37016535d1c247a35d2059/openraft/src/engine/handler/replication_handler/mod.rs#L230-L244 "OpenRaft: check the current leader identity before committing"
[code-etcd-read-index-ready]: https://github.com/etcd-io/raft/blob/v3.6.0/raft.go#L1278-L1285 "etcd/raft: serve ReadIndex only after committing in the current term"
[code-etcd-read-index]: https://github.com/etcd-io/raft/blob/v3.6.0/node.go#L199-L205 "etcd/raft: ReadIndex interface and application requirements"
