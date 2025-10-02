---
title:      "The Hidden Danger in Raft: Why IO Ordering Matters"
authors:
    - xp
categories:
    - algo
tags:
    - distributed
    - 分布式
    - raft
    - en


disabled_article:
    image: /post-res/linearizable/linearizable-banner-big.png

mathjax: false
toc: true
toc_label: Table of Contents
toc_sticky: true
excerpt: "Writing logs before persisting term in Raft can silently destroy committed data. Here's why production systems like TiKV and HashiCorp Raft carefully control IO order—and three battle-tested solutions."
---


![](./raft-io-order-banner.webp)


## IO Reordering Breaks Committed Data

In Raft, if you **write log entries before the term** when persisting AppendEntries, you risk **losing committed data**.

This article explores how this happens, how production systems handle it, and how to prevent it.

### Background

When a follower receives an `AppendEntries` RPC in Raft, it must persist two critical pieces: metadata (`HardState`, containing term and vote) and log entries (the actual application data). Only after both are safely on disk can the follower respond to the leader. **Here's the catch: persistence order matters tremendously**.


### How Data Loss Happens

Let's walk through a concrete timeline to see how this plays out:

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

- t1: N1 starts an election (term=1), receives votes from N1, N2, N3
- t2: N1 becomes leader L1
- t3: N5 starts an election (term=5), receives votes from N5, N4, N2
- t4: N5 becomes leader L5
- t5: L5 replicates its first log entry E5-1 to N4 and N3. Key point: N3's **stored** term (1) is stale compared to the RPC's term (5), so N3 must perform two sequential IO operations: persist term=5, then persist E5-1
- t6: L1 attempts to replicate E1-1 (term=1, index=1)

The critical moment is t5, where N3's behavior determines everything:

**If IO operations is not reordered** (correct):

N3 executes sequentially: **first** persist term=5, **then** persist E5-1. This guarantees that whenever E5-1 is on disk, term=5 is already there too.

**If IO operations can be reordered** (wrong):

IO operations might complete out of order: E5-1 hits disk first, then term=5.

Here's where disaster strikes: if the server crashes after writing E5-1 but before persisting term=5, N3's stored term stays at 1 while E5-1 sits in the log.

When N3 recovers and receives L1's replication request for E1-1 (term=1, index=1), it accepts it—the terms match! E1-1 overwrites E5-1.

The damage is done: E5-1 was already replicated to 3 nodes (N5, N4, N3) and considered committed by L5, but now it's gone, replaced by stale data. **Committed data has vanished**.

At its core, this problem breaks a critical invariant:

> **If a log entry E (term=T) exists on disk → the stored term must be ≥T**

Proper IO ordering preserves this invariant, guaranteeing that whenever a log entry hits disk, its term is already there.


## What Raft's Paper Doesn't Say

The Raft paper states: "Before responding to RPCs, a server must update its persistent state."

The paper assumes persistence is atomic without explicitly spelling out the ordering requirements between term and log.

**The trap most implementations fall into:** when a follower receives an AppendEntries RPC, it needs to persist two types of data—metadata (term, vote, etc., in MetaStore) and log entries (in LogStore).

For performance and clean separation of concerns, many implementations store these separately and submit IO requests in parallel:

```rust
fn handle_append_entries(&mut self, req: AppendEntries) -> Response {
    self.meta_store.save_term_async(req.term);  // Async submit
    self.log_store.append_async(req.entries);   // Async submit

    self.log_store.sync();  // Only wait for log persistence!
    return Response::success();  // Ignore whether term is persisted
}
```

The trap is subtle: developers focus on persisting logs (the "real" application data) while treating term as mere "metadata" that can wait. The result? Logs hit disk while term **is still in memory**—or worse, in a write queue. When the server crashes, the invariant shatters.


## Production Implementations

I examined 4 production Raft implementations to see how they tackle this:

| Implementation | Result | How It Avoids the Problem |
|------|------|------------|
| **TiKV** | ✅ Safe | Atomic batching: term and log in the same LogBatch |
| **HashiCorp Raft** | ✅ Safe | Ordered writes: write term first (panic on fail), then log |
| **SOFAJRaft** | ✅ Safe | Hybrid order: term sync, log async |
| **tikv/raft-rs library** | ⚠️ Depends on application | Library itself is safe, but no ordering enforcement |

## Three Safe Solutions

From successful production implementations, three safe patterns emerge:

### Atomic Batching (TiKV)

TiKV bundles term and log entries into a single atomic batch. The code adds both to a batch, then calls `write_batch(sync=true)` to commit everything at once with checksum verification.

The beauty: **all-or-nothing**. Order within the batch doesn't matter, making correctness reasoning trivial.

The trade-off? You need atomic batch support, but **you only pay one fsync**. Perfect for custom storage engines or when you want the simplest possible safety guarantees.

```rust
batch.put_term(new_term);
batch.put_entries(entries);
storage.write_batch(batch, sync=true); // Atomic write + checksum verification
```

### Sequential Writes (HashiCorp Raft)

HashiCorp Raft keeps it simple: write term first, then log—both synchronously.

Looking at `raft.go:1414,1922`, `setCurrentTerm` includes an fsync that panics on failure before `StoreLogs` even runs. Once term is on disk, the higher term acts as a shield against stale leader requests.

The upside? Dead simple to implement, works with any storage backend, and embraces fail-fast philosophy. The price? Two fsyncs mean slightly higher latency. Great for general use with standard storage like files or BoltDB.

```go
// raft.go:1414,1922
r.setCurrentTerm(a.Term)  // Includes fsync, panics on failure
r.logs.StoreLogs(entries) // Includes fsync
```

### Hybrid Approach (SOFAJRaft)

SOFAJRaft splits the difference: synchronous term writes, asynchronous log batching.

In `NodeImpl.java:1331,2079`, `setTermAndVotedFor` blocks until fsync completes, while `appendEntries` just enqueues the log and returns instantly—background threads handle the batch writes.

The key: logs **queue only after** term's fsync completes, guaranteeing term persists first. This delivers peak performance because term changes are rare (only during leader switches), making sync acceptable, while log writes are constant (every client request), where async batching shines.

The catch? Complex implementation needing a bulletproof async pipeline (SOFAJRaft uses LMAX Disruptor). Ideal when you're **pushing >10K writes/sec**.

```java
// NodeImpl.java:1331,2079
this.metaStorage.setTermAndVotedFor(req.term, null); // Sync fsync, blocks
this.logManager.appendEntries(entries, closure);     // Async enqueue, returns immediately
```


## Async IO Scheduling

All three approaches **guarantee safety by sacrificing IO concurrency**: either serial execution (wait for one to finish before starting the next) or atomic batching.

For higher performance, [OpenRaft](https://github.com/databendlabs/openraft) is exploring an async IO scheduler: the Raft core fires all IO requests into an execution queue, which schedules them and signals completion via callbacks. This maximizes IO parallelism and throughput but surfaces a fundamental question: **which IOs can be reordered safely, and which absolutely cannot?**


## Summary

**Term must be persisted before (or at the same time as) log**

Invariant: `If log(term=T) is on disk → term≥T must also be on disk`

I like thinking about distributed consensus through time and history. Consensus algorithms create a virtual timeline, and the Raft log is simply the sequence of events on that timeline. In this view: term is time itself, and log entries are the events happening in that time.

When IO lets term roll back, you're letting time itself rewind. But here's the paradox: rewinding time doesn't erase what happened—the system can rewrite history at an earlier point, letting new events overwrite the old. That's data loss at its core.

**Choose your approach:** Atomic batching for simplicity, ordered writes for compatibility, hybrid for maximum throughput.


## Related Resources

- [OpenRaft docs: io-ordering](https://github.com/databendlabs/openraft/blob/main/openraft/src/docs/protocol/io_ordering.md)
- [tikv/tikv](https://github.com/tikv/tikv)
- [hashicorp/raft](https://github.com/hashicorp/raft)
- [sofastack/sofa-jraft](https://github.com/sofastack/sofa-jraft)

