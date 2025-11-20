---
title:      "Raft Node Rejoin Bug"
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
excerpt: "Analyzes a replication session isolation bug in Raft implementations. When a node rejoins the cluster within the same term, delayed AppendEntries responses can corrupt progress tracking, causing infinite retry loops. While data safety remains intact, it creates operational issues like resource exhaustion. Uses raft-rs as a case study to examine trigger conditions and solutions."
---

![](./raft-rejoin-bug-banner.webp)


In Raft cluster operations, there's an easily overlooked bug: when a node is removed and then re-added to the cluster within the same term, delayed AppendEntries responses from the old membership configuration can corrupt the leader's replication progress tracking for that node, causing the leader to enter an infinite retry loop.

The root cause is the lack of a **replication session isolation mechanism**. When the same node joins the cluster at different times, these should be treated as different replication sessions. However, without explicit session identifiers, the leader cannot distinguish which session a response belongs to. The result is that delayed responses from old sessions incorrectly update the progress records of new sessions.

While this creates operational challenges—continuous resource consumption and nodes unable to catch up with the cluster—the good news is that Raft's commit protocol ensures data safety remains intact.

Analyzed Raft libs:

| Implementation | Stars | Language | Status | Analysis |
|----------------|------:|----------|--------|----------|
| Apache Ratis | 1,418 | Java | ✓ PROTECTED | [Report](analysis/apache-ratis.md) |
| NuRaft | 1,140 | C++ | ✓ PROTECTED | [Report](analysis/nuraft.md) |
| OpenRaft | 1,700 | Rust | ✓ PROTECTED | [Report](analysis/openraft.md) |
| RabbitMQ Ra | 908 | Erlang | ✓ PROTECTED | [Report](analysis/rabbitmq-ra.md) |
| braft | 4,174 | C++ | ✓ PROTECTED | [Report](analysis/braft.md) |
| canonical/raft | 954 | C | ✓ PROTECTED | [Report](analysis/canonical-raft.md) |
| sofa-jraft | 3,762 | Java | ✓ PROTECTED | [Report](analysis/sofa-jraft-analysis.md) |
| **LogCabin** | **1,945** | **C++** | **✗ VULNERABLE** | [Report](analysis/logcabin.md) |
| **PySyncObj** | **738** | **Python** | **✗ VULNERABLE** | [Report](analysis/pysyncobj.md) |
| **dragonboat** | **5,262** | **Go** | **✗ VULNERABLE** | [Report](analysis/dragonboat.md) |
| **etcd-io/raft** | **943** | **Go** | **✗ VULNERABLE** | [Report](analysis/etcd-raft.md) |
| **hashicorp/raft** | **8,826** | **Go** | **✗ VULNERABLE** | [Report](analysis/hashicorp-raft-analysis.md) |
| **raft-java** | **1,234** | **Java** | **✗ VULNERABLE** | [Report](analysis/raft-java.md) |
| **raft-rs (TiKV)** | **3,224** | **Rust** | **✗ VULNERABLE** | [Report](analysis/raft-rs.md) |
| **redisraft** | **841** | **C** | **✗ VULNERABLE** | [Report](analysis/redisraft.md) |
| **willemt/raft** | **1,160** | **C** | **✗ VULNERABLE** | [Report](analysis/willemt-raft.md) |
| eliben/raft | 1,232 | Go | N/A | [Report](analysis/eliben-raft.md) |

This article uses raft-rs, the Raft implementation used by TiKV, as a case study to analyze this bug's trigger conditions, impact, and potential solutions.

Complete analysis and survey of other Raft implementations can be found in the [Raft Rejoin Bug Survey](https://github.com/drmingdrmer/raft-rejoin-bug)

## Raft Log Replication Basics

In Raft, the leader replicates log entries to followers through AppendEntries RPC calls, while maintaining a replication state machine for each follower to track replication progress.

### AppendEntries Request-Response Flow

Here's how it works: The leader sends AppendEntries requests with the current `term`, the `prev_log_index` and `prev_log_term` pointing to the position just before the new entries, the `entries[]` array to replicate, and the leader's `leader_commit` index. The follower responds with its own `term`, the highest log `index` it replicated, and whether the operation succeeded.

### Progress Tracking

The leader relies on these responses to track each follower's replication status. It uses `matched` to record the highest log index confirmed to be replicated on that follower, and `next_idx` to mark where to send next. When a successful response comes back with `index=N`, the leader updates `matched=N` and calculates `next_idx=N+1` for the next round.

This tracking mechanism has an implicit assumption: responses correspond to the current replication session.

If this assumption isn't handled properly, when a node rejoins the cluster, the leader can get stuck in an infinite retry loop. It keeps sending AppendEntries requests, the node keeps rejecting them, and the cycle repeats endlessly while that node never manages to catch up with the cluster.

## raft-rs Progress Tracking

raft-rs tracks replication progress using a Progress structure for each follower node:

```rust
// From raft-rs/src/tracker/progress.rs
pub struct Progress {
    pub matched: u64,      // Highest log index known to be replicated
    pub next_idx: u64,     // Next log index to send
    pub state: ProgressState,
    // ... other fields
}
```

The `matched` field records the highest log index successfully replicated to this follower. Whenever the leader receives a successful AppendEntries response, it updates this field:

```rust
// From raft-rs/src/tracker/progress.rs
pub fn maybe_update(&mut self, n: u64) -> bool {
    let need_update = self.matched < n;  // Only check monotonicity
    if need_update {
        self.matched = n;  // Accept the update!
        self.resume();
    }
    need_update
}
```

Notice the update logic is quite simple: as long as the new index is higher than the current `matched`, it accepts the update. When a node gets removed from the cluster, its Progress record is deleted. When it rejoins, a brand new Progress record is created with `matched = 0`.

## Bug Reproduction Sequence

Let's walk through a concrete timeline to see how this bug unfolds. Pay special attention to the fact that all events happen within a single term (term=5)—this is key to understanding why term-based validation fails.

### Event Timeline

```
| Time | Event                                         | Progress State
|------|-----------------------------------------------|----------------
| T1   | log=1, members={a,b,c}                        | C: matched=0
|      | Leader sends AppendEntries(index=1) to C      |
|      | (Network delay causes slow delivery)          |
|      |                                               |
| T2   | log=5, members={a,b}                          | C: [deleted]
|      | Node C removed from cluster                   |
|      | Progress[C] deleted from leader's tracker     |
|      |                                               |
| T3   | log=100, members={a,b,c}                      | C: matched=0 (new)
|      | Node C rejoins the cluster                    |
|      | New Progress[C] created with matched=0        |
|      |                                               |
| T4   | Delayed response arrives from T1:             |
|      | {from: C, index: 1, success: true}            |
|      | Leader finds Progress[C] (the new one!)       |
|      | maybe_update(1) called: 0 < 1, so update!     | C: matched=1 ❌
|      |                                               |
| T5   | Leader calculates next_idx = matched + 1 = 2  |
|      | Sends AppendEntries(prev_index=1)             |
|      | Node C rejects (doesn't have index 1!)        |
|      | Leader can't decrement (matched == rejected)  |
|      | Infinite loop begins...                       |
```

### Response Handling at T4

At time T4, that response sent at T1 and delayed in the network finally arrives. Here's how the leader handles it:

```rust
// From raft-rs/src/raft.rs
fn handle_append_response(&mut self, m: &Message) {
    // Find the progress record
    let pr = match self.prs.get_mut(m.from) {
        Some(pr) => pr,
        None => {
            debug!(self.logger, "no progress available for {}", m.from);
            return;
        }
    };

    // Update progress if the index is higher
    if !pr.maybe_update(m.index) {
        return;
    }
    // ...
}
```

Here's where things go wrong: The leader does find a Progress record for node C, but it's the new one created at T3. Since the message's term matches the current term, it passes the term check in the [`step()` function](https://github.com/tikv/raft-rs/blob/master/src/raft.rs#L1346-L1478), and the leader updates progress with this stale index value.

## Root Cause Analysis

The root of this bug is that **request-response messages lack replication session identification**. When node C gets removed at T2 and rejoins at T3, these should be two distinct replication sessions—but the leader has no way to distinguish between responses from requests sent at T1 versus responses from requests sent after T3.

Look at raft-rs's Message structure:

File: [`proto/proto/eraftpb.proto:71-98`](https://github.com/tikv/raft-rs/blob/master/proto/proto/eraftpb.proto#L71-L98)

```protobuf
message Message {
    MessageType msg_type = 1;
    uint64 to = 2;
    uint64 from = 3;
    uint64 term = 4;        // Only term, no session identifier!
    uint64 log_term = 5;
    uint64 index = 6;
    // ...
}
```

The Message only has a `from` field identifying the sending node, but the same node ID joining the cluster at different times should be treated as different replication sessions. The leader needs to distinguish: is this response from node C's first session or its second session? But the current Message structure provides no way to tell.

## Impact Analysis

### Infinite Retry Loop

Once the leader incorrectly sets `matched=1`, trouble begins. Here's what happens:

```rust
// From raft-rs/src/tracker/progress.rs
pub fn maybe_decr_to(&mut self, rejected: u64, match_hint: u64, ...) -> bool {
    if self.state == ProgressState::Replicate {
        // Can't decrement if rejected <= matched
        if rejected < self.matched
            || (rejected == self.matched && request_snapshot == INVALID_INDEX) {
            return false;  // Ignore the rejection!
        }
        // ...
    }
}
```

The leader sends AppendEntries with `prev_log_index=1`, but node C's log is empty—it doesn't have index 1. Node C rejects the request. The leader wants to decrement `next_idx` to retry an earlier position, but here's the problem: because `rejected (1) == matched (1)`, the decrement logic returns false and refuses to decrement. So the leader just sends the same request again, node C rejects it again, and this cycle continues forever.

### Operational Impact

This bug creates a series of operational problems. First, there's resource exhaustion: the continuous AppendEntries-rejection cycle keeps consuming CPU and network bandwidth.

## Why Data Remains Safe

Despite all the operational chaos, there's good news: data integrity remains intact. Raft's safety properties ensure that even with corrupted progress tracking, the cluster won't lose any committed data.

The reason is that commit index calculation still works correctly. Even if the leader mistakenly thinks node C has `matched=1`, it calculates the commit index based on the actual majority. For example, node A has matched=100, node B has matched=100, and node C has matched=1 (which is wrong, but doesn't matter). The majority looks at A and B with matched=100, so the commit index is correctly calculated as 100. Combined with Raft's overlapping majorities property, any newly elected leader will necessarily have all committed entries, keeping data safe.

## Solutions

### Solution 1: Add Membership Version (Recommended)

The most straightforward fix is to add a membership configuration version to messages:

```protobuf
message Message {
    // ... existing fields
    uint64 membership_log_id = 17;  // New field
}
```

Then validate it when processing responses:

```rust
fn handle_append_response(&mut self, m: &Message) {
    let pr = self.prs.get_mut(m.from)?;

    // Check membership version
    if m.membership_log_id != self.current_membership_log_id {
        debug!("stale message from different membership");
        return;
    }

    pr.maybe_update(m.index);
}
```

This directly fixes the root cause—the leader can now tell which membership configuration a message comes from.

### Solution 2: Generation Counters

Another approach is to add a generation counter to Progress that increments each time a node rejoins:

```rust
pub struct Progress {
    pub matched: u64,
    pub next_idx: u64,
    pub generation: u64,  // Incremented on each rejoin
    // ...
}
```

Include the generation in messages and validate it when responses arrive. This is lighter weight than solution 1, but you need to carefully manage the generation lifecycle.

## Summary

This bug shows us that when membership changes happen within the same term, relying on term-based validation alone isn't enough to ensure message freshness. Without explicit session isolation, delayed responses from old membership configurations can corrupt progress tracking.

Fortunately, because Raft's commit index calculation and overlapping quorum mechanisms provide strong guarantees, this bug doesn't compromise data safety. The main impact is operational—the symptoms look like data corruption, which can send operations teams down the rabbit hole investigating a data loss problem that doesn't actually exist.

For production Raft implementations, it's recommended to introduce explicit session management mechanisms. This can be achieved through membership versioning or generation counters. The most recommended approach is to add a membership_log_id field to messages, which lets the leader clearly distinguish which membership configuration a response comes from.

Complete analysis and survey of other Raft implementations can be found in the [Raft Rejoin Bug Survey](https://github.com/drmingdrmer/raft-rejoin-bug)
