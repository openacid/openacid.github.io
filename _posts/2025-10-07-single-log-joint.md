---
title:      "Raft Configuration Change with Single Log Entry"
authors:
    - xp
categories:
    - algo
tags:
    - distributed
    - raft
    - config-change
    - joint


refs:
    - x: y

disabled_article:
    image: /post-res/linearizable/linearizable-banner-big.png

mathjax: false
toc: true
toc_label: Table of Contents
toc_sticky: true
excerpt: "Is the single-log-entry approach to Raft configuration change simpler than the standard Joint Consensus?"
---

![](/post-res/single-log-joint/c915c4fcc98591ed-single-log-joint-banner.webp)

# Preface

**TL;DR**

Standard Raft configuration changes use two log entries with multi-phase commits and careful state management. Can we complete a configuration change with just one log entry? We'll introduce **effective-config**, prove its correctness, then discover why the simple approach isn't so simple after all. The standard Joint Consensus method wins for good reasons.

**What We'll Cover**

1.  How Raft's Joint Consensus works (the two-phase approach)
1.  The single-log-entry idea and its mechanics
1.  Why it's theoretically correct
1.  Why it's practically problematic (and the patches we'd need)
1.  Why we should stick with Joint Consensus

# Introduction to Raft Joint Consensus: 2 Config Log Entries

Changing cluster membership in Raft is tricky. Switching from the old configuration `{a,b,c}` to a new one `{x,y,z}` in one step is dangerous.

Nodes can't all switch configurations at the exact same moment. During the transition, some nodes (say `a,b`) might still be using `C_old` while others (`x,y,z`) have moved to `C_new`. If these two groups don't overlap—meaning a quorum from `C_old` (like `{a,b}`) and a quorum from `C_new` (like `{x,y}`) share no common nodes—we could elect two leaders in the same term, violating Raft's fundamental safety guarantee.

The Raft paper solves this with a two-phase protocol called **Joint Consensus**:

![Figure 1: Joint Consensus Two-Phase Process](/post-res/single-log-joint/a7acea752fd84833-raft-joint.x.svg)

1.  **Phase 1: Enter the Joint phase (`C_old_new`)**
    When the leader receives a configuration change request, it writes a log entry containing `C_old_new`—a joint configuration that includes both old and new members. In this state, any decision (like committing a log entry) needs approval from a quorum of `C_old` *and* a quorum of `C_new`. The leader starts using `C_old_new` as soon as it writes this entry to its own log.

1.  **Phase 2: Move to the new configuration (`C_new`)**
    Once `C_old_new` commits, the leader writes a second log entry containing just `C_new`. From this point forward, the leader uses only `C_new`, and all subsequent log entries need only commit on a `C_new` quorum. When this second entry commits, the configuration change is complete.

The intermediate joint phase ensures that any two quorums—whether based on `C_old`, `C_new`, or `C_old_new`—must overlap, preventing split brain. This requires **two** log entries for each configuration change.

# Can We Do It With Just One Log Entry?

Can we do this safely with just **one** log entry?

We need a new concept: **effective-config**. This is the configuration the leader *actually uses* to determine if log entries are committed. It might not match any specific configuration stored in a log entry—it's a runtime state that changes as the configuration change progresses.

## Terminology

-   **effective-config**: The runtime configuration the leader uses to determine if entries are committed
-   **Joint config**: A configuration containing both old and new members, like `C_old_new = [{a,b,c}, {x,y,z}]`
-   **Uniform config**: A configuration with just one set of members, like `C_new = {x,y,z}`
-   **Barrier entry**: A marker log entry that signals the joint phase has safely ended

## How It Works

-   **Starting point**: The cluster is running with `C_old = {a,b,c}`, and that configuration has been committed. The effective-config is `C_old`.

    ![Figure 2: Single Log Entry Change - Initial State](/post-res/single-log-joint/667db9f105260fea-single-1-start.x.svg)

-   **Propose the change**: To change to `C_new = {x,y,z}`, the leader writes a single log entry `entry-i` containing just `C_new`.

-   **Enter joint mode immediately**: The moment the leader appends `entry-i` to its own log—before it commits, before it replicates—the leader switches its effective-config to the joint configuration `C_old_new = [{a,b,c}, {x,y,z}]`. Now `entry-i` and all subsequent entries must commit on a quorum from *both* `{a,b,c}` and `{x,y,z}`.

    ![Figure 3: Single Log Entry Change - Entering Joint Phase](/post-res/single-log-joint/64bd23d7d6bd8fd7-single-2-joint.x.svg)

-   **Normal operation continues**: The cluster keeps processing requests. Every entry commits using the joint quorum rules.

-   **Exit joint mode**: Once `entry-i` commits under `C_old_new`, the leader switches effective-config to `C_new = {x,y,z}`. All subsequent entries need only a `C_new` quorum.

With one log entry, the system transitions through three states: `C_old → C_old_new → C_new`.

### Correctness Proof

We need to show that we can't elect two leaders—neither during the configuration change nor afterward.

Assume leader `t` is doing the configuration change (writing `entry-i`). Later, some candidate `u` tries to get elected in term `u > t`. We prove `t` and `u` can't both be leaders.

**Analyzing candidate `u`'s election**

Candidate `u` either has `entry-i` in its log or it doesn't.

-   **Case 1: `u` has `entry-i`**

    Then `u`'s effective-config includes `{x,y,z}`. Leader `t`'s effective-config is either `C_old_new = [{a,b,c}, {x,y,z}]` (still in joint mode) or `C_new = {x,y,z}` (finished). Either way, it includes `{x,y,z}`.

    Since `u` needs a quorum from `{x,y,z}` to get elected, and `t` needs a quorum from `{x,y,z}` to stay leader, these quorums must overlap. No split brain.

-   **Case 2: `u` doesn't have `entry-i`**

    Then `u`'s effective-config is `C_old = {a,b,c}`. Now we consider where leader `t` is:

    -   If `t`'s effective-config is `C_old_new`, then `t` needs a quorum from `{a,b,c}` and `u` needs a quorum from `{a,b,c}`. These must overlap. No split brain.

    -   If `t`'s effective-config is `C_new = {x,y,z}`, that means `entry-i` committed under `C_old_new`. So `entry-i` must exist on a quorum of `{a,b,c}`. Those nodes have logs at least as long as index `i`.

        But `u` doesn't have `entry-i`, so its log is shorter than `i`. When `u` requests votes from nodes in `{a,b,c}`, they'll reject it because their logs are more up-to-date. The election fails.

In every case, we can't have both `t` and `u` as leaders. The algorithm is safe.

However, although theoretically correct, it introduces problems in actual implementation:

## Problem 1: The Memory-Only Transition

When we move from `C_old_new` to `C_new`, we only change the in-memory effective-config. Nothing hits disk. This creates trouble.

Nodes from `C_old` can still initiate elections and compete with `C_new` nodes, because `C_old` logs are as long as `C_new` logs. Even after the configuration change completes, `C_old` nodes can steal leadership from `C_new` nodes. The root cause is that the state change is not recorded on the persistent layer. This is problematic because nodes intended for removal can still become leaders.

Compare this to standard Joint Consensus: it writes a second log entry containing `C_new`. That entry acts as a barrier. Nodes from `C_old` have shorter logs and lose elections. The single-entry approach has no such barrier—the transition from `C_old_new` to `C_new` is invisible on disk.

Look at the diagram below. The cluster transitions from `C_old_new` to `C_new`, but no logs change. Leadership moves to node `x` in `{x,y,z}`. But nodes from `C_old` can still start elections and steal leadership from `x`.

![Figure 4: Patch-1 Persistent Layer Problem Example](/post-res/single-log-joint/3e6fb36ca8cf87de-single-3-elect.x.svg)

**Patch-1**: After entering `C_new`, immediately append a no-op entry. This lengthens the logs of `C_new` nodes, blocking elections from `C_old` nodes.

## Problem 2: The Restart Ambiguity

When a node restarts, it can't tell if the cluster is in joint mode or has finished the change.

-   The restarting node reads its log. It sees `entry-i` containing `C_old` and `entry-j` containing `C_new`.

-   We know `entry-i` is committed (Raft requires it before starting a new change).

-   But what about `entry-j`? The node can't tell just from its local log:

    -   If `entry-j` isn't committed yet, the cluster is in joint mode with effective-config `C_old_new`
    -   If `entry-j` is committed, the cluster is using `C_new`

Without talking to other nodes, there's no way to know.

![Figure 5: Patch-2 New Node Restart State Example](/post-res/single-log-joint/004bf3df9c4de529-restart.x.svg)

In the diagram above, even if `entry-3` has committed, the restarting nodes `b`, `c`, `x`, `y` can't tell whether the cluster is in joint mode or using the new configuration. (Nodes `a` and `z` never received `entry-3` and are still using `{a,b,c}`.)

**Patch-2**: Always start in joint mode after a restart.

1.  When a node starts up, it sets effective-config to the joint configuration formed from the last two config entries in its log
1.  It uses this joint config for elections and normal operation
1.  Only after confirming that the latest config entry has committed under the joint configuration can it switch to the new configuration

**Example**: A node sees configs `{a,b,c}` and `{u,v,w}` in its log. It starts with effective-config `[{a,b,c}, {u,v,w}]`. To become leader, it needs quorums from both groups. Only after it confirms the new config committed under the joint rules can it switch to just `{u,v,w}`.

## Problem 3: Calling Home to Dead Nodes

Patch-2 solves the ambiguity problem but creates a worse one: **nodes might try to contact old cluster members that no longer exist, making elections impossible**.

**Example**:

![Figure 6: Regression to C-old-new After Restart](/post-res/single-log-joint/0507172bcfea4f35-restart-after-uniform.x.svg)

1.  The cluster changes from `{a,b,c}` to `{x,y,z}`

1.  The config entry commits under `C_old_new`

1.  The cluster transitions to `C_new = {x,y,z}`

1.  Nodes `a`, `b`, `c` are no longer members. They get shut down, their data gets wiped, and they're gone

1.  Then something happens and all remaining nodes restart

1.  Node `x` restarts and follows Patch-2: it sees configs `{a,b,c}` and `{x,y,z}` in its log, so it sets effective-config to `[{a,b,c}, {x,y,z}]`

1.  Node `x` tries to run an election, but `b` and `c` don't exist anymore! It can't get a quorum from both groups. The election fails. The cluster is stuck.

This is state regression. The transition from `C_old_new` to `C_new` wasn't persisted, so after a restart, the system rolls back to needing `C_old`.

## Adding a Barrier to Prevent Regression

Restarting nodes need to **know for certain** that the joint phase has ended—proof that it's safe to use `C_new` without calling back to `C_old`.

**Patch-3: Add a barrier entry**

After `entry-j` (containing `C_new`) commits under `C_old_new`, append a special **barrier entry** to mark that `entry-j` has committed.

> **Important**: The barrier must come *after* `entry-j` commits. Otherwise it can't serve as proof of the commit.


When a restarting node sees this barrier, it knows the joint phase ended successfully. It can safely use `C_new` for elections without trying to contact old nodes that might not exist anymore.

In the diagram below, when `entry-3` commits under `C_old_new`, we add barrier `entry-4`:

![Figure 7: Patch-3 Introducing Barrier Entry Process](/post-res/single-log-joint/a1b3d0adfde6319d-barrier.x.svg)

Now when all nodes restart, there's no regression. Nodes `x` and `y` see the barrier, so they use `C_new = {x,y,z}` directly. Even though `b` and `c` are gone, `x` or `y` can still get elected:

![Figure 8: Barrier Entry After Restart](/post-res/single-log-joint/431e950cac307092-barrier-restart.x.svg)

> **Alternative: Persisting commit-index**
> 
> Instead of a barrier entry, we could persist the commit-index—an idea from [Ma Jianjiang](https://weibo.com/u/1516609505).
> 
> The rule: joint consensus ends when commit-index reaches a quorum of `C_new`. To make this work, we'd need to persist commit-index (standard Raft doesn't require this).
> 
> When a node restarts, it checks: if the persisted commit-index covers the config change entry, it knows `C_old_new` finished and can safely use `C_new`. No need to contact old nodes.
> 
> But this still has Problem 1—`C_old` and `C_new` nodes competing for leadership. Here's why: `C_new` nodes don't have extra log entries, and committing commit-index to just `C_new` doesn't guarantee `C_old` nodes see it. This is the classic distributed systems dilemma of at-least-once vs at-most-once delivery:
> 
> -   **At-least-once** (commit on `C_old_new`): commit-index might succeed, then `C_old` nodes get decommissioned, then we can't commit it again to reach them. We're stuck.
> -   **At-most-once** (commit on `C_new` only): commit-index reaches `C_new` but might not reach `C_old`. Those nodes don't know the cluster moved on, so they keep trying to run elections.
> 
> Either way, we can still end up with `C_old` and `C_new` nodes competing for leadership.


So here's what the **patched single-log approach** looks like:

1.  Start with `effective-config = C_old = {a,b,c}`

1.  Leader writes `entry-j` containing `C_new = {x,y,z}` and immediately switches `effective-config` to `C_old_new = [{a,b,c}, {x,y,z}]`

1.  All entries from index `j` onward replicate and commit under `C_old_new`

1.  **Critical step**: Once `entry-j` commits under `C_old_new`, the leader writes a special **barrier entry**. This entry has no configuration data—it just marks "the joint phase is done." The leader can switch to `effective-config = C_new` and use `C_new` to replicate the barrier.

1.  When the barrier entry commits, the configuration change is complete

**Restart behavior**:

When a node restarts, it reads its log. It sees `entry-i` (`C_old`) and `entry-j` (`C_new`). It checks: is there a barrier after `entry-j`?

-   **Barrier present**: Joint phase ended. Set `effective-config = C_new`. No need to contact old nodes.

-   **No barrier**: Joint phase might still be active. Set `effective-config = C_old_new`.

Patch-3 adds a second log entry. We're no longer doing "one log entry" configuration changes. We need "one config entry + one barrier entry."

# Conclusion

Configuration changes must pass through three states—`C_old → C_old_new → C_new`. One log entry gives us one bit of persistent information: `C_old` or `C_new`. That's only two states. We can't represent three states with two values.

To safely handle all three states, we need at least two log entries. That gives us two bits of information and up to four possible states, which is enough to encode the three states we actually need.

The "single-log-entry" approach, after all the patches, ends up needing two entries anyway—one for the configuration and one for the barrier. And it's more complex than standard Joint Consensus, with trickier edge cases around restarts and state transitions.

Stick with Joint Consensus. It's cleaner, simpler, and solves the problem directly without patches.

## References

-   Diego Ongaro & John Ousterhout. In Search of an Understandable Consensus Algorithm (Raft paper): https://raft.github.io/raft.pdf
-   OpenRaft(rust): https://github.com/databendlabs/openraft
-   etcd/raft source code: https://github.com/etcd-io/raft
-   Hashicorp Raft implementation: https://github.com/hashicorp/raft



Reference:

- 马健将 : [https://weibo.com/u/1516609505](https://weibo.com/u/1516609505)


[people-ma-jianjiang]: https://weibo.com/u/1516609505 "马健将"