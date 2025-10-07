---
title:      "Raft IO Execution Order (Revised)"
authors:
    - xp
categories:
    - algo
tags:
    - distributed
    - raft
    - cn


refs:
    - x: y

disabled_article:
    image: /post-res/linearizable/linearizable-banner-big.png

mathjax: false
toc: true
toc_label: Table of Content
toc_sticky: true
excerpt: "I got it wrong in my previous article. The IO ordering bug in Raft isn't about the protocol design—it's about the subtle trap that emerges when implementations split state into SoftState and HardState. Here's what actually happens."
---

![](/post-res/raft-io-order-fix/62b7bb390d222f2e-raft-io-order-fix-banner.webp)

## Preface

I need to come clean about something. In my [previous article on IO ordering in Raft](./2025-10-02-raft-io-order-cn.md), I tried to demonstrate the dangers of "writing log entries before term" using a committed data loss scenario. The problem? That example was fundamentally flawed—it didn't actually capture the real issue with IO reordering at all.

So let's fix that. This article walks through what I got wrong and, more importantly, presents a correct understanding of when and why IO reordering becomes dangerous in Raft implementations.

## What Went Wrong in My Original Analysis

Let me show you the timeline I used in the previous article:

> ```text
> Legend:
> Ni:   Node i
> Vi:   RequestVote, term=i
> Li:   Establish Leader, term=i
> Ei-j: Log entry, term=i, index=j
> 
> N5 |          V5  L5       E5-1
> N4 |          V5           E5-1
> N3 |  V1                V5,E5-1  E1-1
> N2 |  V1      V5                 E1-1
> N1 |  V1  L1                     E1-1
> ------+---+---+---+--------+-----+---------> time
>       t1  t2  t3  t4       t5    t6
> ```
> 
> Here's what I claimed would happen:
> 
> -   At t5: N3 receives entry E5-1 from leader L5 (term=5) and needs to persist both term=5 and E5-1
> -   I argued: "If N3 writes E5-1 first but crashes before writing term=5, it could restart with `term=1, entries=[E5-1]`"
> -   At t6: The old leader L1 (term=1) could then overwrite E5-1, causing data loss
> 
> **Here's the flaw in my reasoning**: Raft's protocol explicitly requires that *both* the term update and log entries must be successfully persisted before a follower responds with success. If either IO fails or is incomplete, the leader never receives confirmation and therefore never considers the entry committed. The Raft paper's design is actually bulletproof here.


So if Raft's design is correct, where does the IO ordering problem actually come from? The answer lies in a subtle gap between theory and implementation—specifically, how real Raft systems separate in-memory state from on-disk state.

## The Real Culprit: SoftState vs HardState

Here's where things get interesting. The Raft paper describes a beautifully simple world where a server has just one state: what's on disk. But real implementations need to be fast, so they introduce an optimization—they split their state into two layers:

**In-memory state (SoftState)**: The "optimistic" view that updates immediately when receiving RPCs
**On-disk state (HardState)**: The "durable" view that updates only after IO completes

Here's how a typical implementation handles an appendEntries request:

1.  Receive appendEntries RPC with `req.term`
1.  If `req.term > soft_term`, immediately update `soft_term` to `req.term`
1.  Asynchronously submit a save-term IO operation
1.  Eventually update `hard_term` when the IO completes

In code, this looks like:

```rust
struct RaftState {
    // In-memory state (SoftState) - may be ahead of what's on disk
    soft_term: u64,

    // On-disk state (HardState) - the durable truth
    hard_term: u64,
}
```

This separation is where the danger lurks. The Raft paper assumes only one "term" variable—what's persisted on disk. But implementations now have *two* term values, and this introduces a behavior the paper never defined or analyzed.

The pattern above is ubiquitous in Raft implementations. And here's the kicker: *without IO reordering, it works perfectly fine*. The bug only surfaces when IOs can complete out of order.

## A Concrete Example: Where IO Reordering Breaks Raft

Let's build a scenario that actually exposes the bug. I'll walk you through it step by step:

```text
Legend:
Ni:   Node i
Vi:   RequestVote, term=i
Li:   Establish Leader, term=i
Ei-j: Log entry, term=i, index=j

N5 |          V5  L5     E5-1     E5-2
N4 |          V5         E5-1     E5-2
N3 |  V1              V5,E5-1  V5,E5-2  E1-1
N2 |  V1      V5                        E1-1
N1 |  V1  L1                            E1-1
------+---+---+---+------+--------+-----+------> time
      t1  t2  t3  t4     t5       t6    t7
```

Here's the sequence of events:

-   **t1-t4**: Two elections occur. First N1 becomes leader (term=1), then N5 becomes leader (term=5)
-   **t5**: Leader L5 sends its first entry E5-1 to follower N3
    -   N3's current state: `soft_term=1`, `hard_term=1`
    -   N3 receives `appendEntries(term=5, entries=[E5-1])`
    -   N3 must persist both term=5 and entry E5-1
    -   N3 responds "success" only after both IOs complete

-   **t6**: Leader L5 sends a second entry E5-2 to N3 ← *This is the critical moment*
    -   N3 might still be waiting for t5's IOs to complete
    -   Whether IO reordering can occur makes all the difference

-   **t7**: The old leader L1 (term=1) attempts to replicate E1-1 to N3

The bug manifests in what happens at **t6**—when the second AppendEntries arrives while the first one's IOs are still in flight. Let's zoom into N3's internal state at each step.

### At t5: The First AppendEntries

When N3 receives `appendEntries(term=5, entries=[E5-1])`, here's what happens inside:

```rust
fn handle_append_entries(&mut self, req: AppendEntries) {
    // Check: Is the RPC term newer than our in-memory term?
    if req.term > self.soft_term {
        self.soft_term = req.term;              // Update memory immediately: 1 → 5
        self.submit_io(save_term(req.term));    // Queue IO to persist term=5
    }

    self.submit_io(save_entries(req.entries));  // Queue IO to persist E5-1

    // Wait for both IOs to complete before responding
    wait_for_both_ios();
    return success();
}
```

After this call executes, N3's state looks like:

-   `soft_term = 5` (memory updated immediately)
-   `hard_term = 1` (disk not yet updated—IO still in flight)
-   IO queue: `[save_term(5), save_entries(E5-1)]` waiting to complete

So far, so good. This request is handled correctly—N3 won't respond until both IOs finish. The trouble starts at the next moment.

### At t6: The Second AppendEntries—Where Everything Goes Wrong

Now here's the critical moment. Before t5's IOs have completed, N3 receives a second request: `appendEntries(term=5, entries=[E5-2])`.

Most implementations check only the in-memory `soft_term` to decide whether to persist the term. Watch what happens:

```rust
fn handle_append_entries(&mut self, req: AppendEntries) {
    // Check: Is 5 > 5? Nope!
    if req.term > self.soft_term {
        // We skip this branch entirely
    }

    // We only queue the entries IO
    self.submit_io(save_entries(req.entries));

    // We only wait for the entries IO to complete
    wait_for_io(save_entries);
    return success();  // We're done!
}
```

See the problem? N3 returns success as soon as `save_entries(E5-2)` completes. But here's the dangerous part: **if IO reordering is allowed**, the system might have:

-   ✅ Completed `save_entries(E5-2)`
-   ✅ Completed `save_entries(E5-1)`
-   ❌ NOT completed `save_term(5)` (still in flight from t5)

N3 happily returns success to Leader L5, which then considers E5-2 replicated and potentially committed.

Now imagine N3 crashes. When it restarts, its disk state is:

-   `hard_term = 1` (the save_term(5) never finished)
-   `entries = [E5-1, E5-2]` (both successfully written)

This is an inconsistent state that Raft's protocol assumes can never exist. And it's about to cause data loss.

### At t7: The Data Loss Materializes

After N3 restarts with `term=1, entries=[E5-1, E5-2]`, the old leader L1 (from term=1) sends an appendEntries request: `appendEntries(term=1, entries=[E1-1])`.

N3's logic:

1.  Check: RPC term (1) == my local term (1) ✅
1.  Accept the request
1.  Write E1-1 at index=1, overwriting E5-1

**The disaster**: Entries E5-1 and E5-2, which Leader L5 believed were successfully replicated and possibly committed, have just been silently destroyed. We've lost committed data.

---

**Important note**: If IO reordering were *not* allowed, this bug wouldn't occur. Here's why: when `save_entries(E5-2)` completes at t6, it would guarantee that `save_term(5)` (queued earlier) has also completed. The sequential ordering ensures that N3's disk state remains consistent, and the AppendEntries success response would be legitimate.

## The Root Cause: A Mismatch Between Theory and Practice

Let's crystallize what we've learned:

**The core issue**: When deciding whether to persist the term, should we check `soft_term` or `hard_term`?

-   If IO reordering is **not allowed** → checking `soft_term` is safe
-   If IO reordering **is allowed** → we must check `hard_term`

This isn't obvious because the Raft paper never talks about "soft" vs "hard" state—it only knows about one kind of state: what's on disk. The paper says: *"Before responding to RPCs, a server must update its persistent state."*

But in real implementations with the SoftState/HardState split, this requirement needs to be more precise:

**Before returning success, we must ensure all IOs that make `hard_term >= req.term` have completed.**

Checking only `soft_term` creates a window where we might respond successfully while the required disk updates are still in flight. If those updates can complete out of order, we've violated Raft's safety guarantees.

## How to Fix It: Check HardState, Not SoftState

If you need to support IO reordering, the fix is conceptually simple—check the on-disk term, not the in-memory term:

```rust
fn handle_append_entries(&mut self, req: AppendEntries) {
    // Check against disk state, not memory!
    let need_save_term = req.term > self.hard_term;

    if need_save_term {
        self.soft_term = req.term;
        self.submit_io(save_term(req.term));
    }

    self.submit_io(save_entries(req.entries));

    // Wait for the right IOs based on what we actually need
    if need_save_term {
        wait_for_both_ios();  // Must wait for term update to complete
    } else {
        wait_for_io(save_entries);  // Only need to wait for entries
    }

    return success();
}
```

By checking `hard_term` instead of `soft_term`, we correctly detect when the term IO is still in flight and wait for it to complete.

**Caveat**: This approach might submit multiple `save_term(T)` IOs for the same term T (if multiple AppendEntries arrive in quick succession). You'll need to handle this carefully—either make the IO layer idempotent or add deduplication logic.

## How Production Systems Solve This

Here's the interesting part: most mature Raft implementations don't actually support IO reordering. Instead, they eliminate the problem entirely by ensuring save-term and save-entries execute in order. This lets them safely check `soft_term` without the bug we just analyzed.

Let's look at three different approaches from production systems:

### 1. Atomic Batching (TiKV)

**Strategy**: Bundle save-term and save-entries into a single atomic IO operation.

When an AppendEntries requires both a term update and log writes, TiKV combines them into one batch and submits it as a single IO request. This makes it impossible for the entries to persist without the term—they're literally the same operation.

This elegantly sidesteps the entire reordering problem. There's no "second AppendEntries that only submits save_entries" scenario because term and entries are always written together.

### 2. Ordered Separation (HashiCorp Raft)

**Strategy**: Persist term and entries separately, but enforce strict ordering.

HashiCorp's Raft implementation writes the term first (with fsync, panicking on failure), then writes the log entries. The key is that these operations execute sequentially—save_entries can't start until save_term completes.

This guarantees that if entries reach disk, the term has definitely reached disk first. Sequential ordering prevents the reordering bug.

### 3. Hybrid Ordering (SOFAJRaft)

**Strategy**: Synchronous term writes, asynchronous batched log writes.

SOFAJRaft writes the term synchronously (blocking the current thread for fsync) but batches log entries for asynchronous writing. The crucial property: save_term always completes before save_entries is even enqueued.

This hybrid approach gets you most of the performance benefits of async IO while maintaining the ordering guarantee that prevents the bug.

## Summary: Bridging Theory and Practice

The IO ordering bug in Raft implementations stems from a subtle gap between the paper's abstract model and real-world code. The Raft paper assumes a single state: what's on disk. Real implementations optimize with a SoftState/HardState split, introducing behaviors the paper never analyzed.

**The invariant we must maintain**:

> If a log entry with term=T is on disk, then hard_term ≥ T must also be on disk.


Violating this invariant—having entries from term T on disk while hard_term < T—breaks Raft's safety guarantees and can cause committed data loss.

**Two ways to maintain the invariant**:

1.  **Eliminate IO reordering** (mainstream approach)

    -   Atomic batching: Write term and entries together
    -   Ordered execution: Guarantee term persists before entries
    -   Hybrid ordering: Synchronous term, async entries

1.  **Handle IO reordering explicitly**

    -   Check `hard_term` instead of `soft_term` when deciding whether to persist the term
    -   Wait for all required IOs to complete before responding

Most production systems choose option 1—it's simpler to reason about and avoids the complexity of tracking multiple in-flight term updates. But if you do need to support IO reordering, now you know where the dragons are hiding.

## Related Resources

-   [The Hidden Danger in Raft: Why IO Ordering Matters](./2025-10-02-raft-io-order.md)
-   [OpenRaft docs: io-ordering](https://github.com/databendlabs/openraft/blob/main/openraft/src/docs/protocol/io_ordering.md)
-   [tikv/tikv](https://github.com/tikv/tikv)
-   [hashicorp/raft](https://github.com/hashicorp/raft)
-   [sofastack/sofa-jraft](https://github.com/sofastack/sofa-jraft)



Reference:

- OpenRaft docs: io-ordering : [https://github.com/databendlabs/openraft/blob/main/openraft/src/docs/protocol/io_ordering.md](https://github.com/databendlabs/openraft/blob/main/openraft/src/docs/protocol/io_ordering.md)

- The Hidden Danger in Raft: Why IO Ordering Matters : [./2025-10-02-raft-io-order.md](./2025-10-02-raft-io-order.md)

- hashicorp/raft : [https://github.com/hashicorp/raft](https://github.com/hashicorp/raft)

- sofastack/sofa-jraft : [https://github.com/sofastack/sofa-jraft](https://github.com/sofastack/sofa-jraft)

- tikv/tikv : [https://github.com/tikv/tikv](https://github.com/tikv/tikv)


[OpenRaft docs: io-ordering]:  https://github.com/databendlabs/openraft/blob/main/openraft/src/docs/protocol/io_ordering.md
[The Hidden Danger in Raft: Why IO Ordering Matters]:  ./2025-10-02-raft-io-order.md
[hashicorp/raft]:  https://github.com/hashicorp/raft
[sofastack/sofa-jraft]:  https://github.com/sofastack/sofa-jraft
[tikv/tikv]:  https://github.com/tikv/tikv