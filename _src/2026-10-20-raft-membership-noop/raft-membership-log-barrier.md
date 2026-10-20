---
title: "Raft Membership Changes: When a Leader Must Commit a Current-Term Entry First"
date: 2026-10-20
url: /distributed/raft-membership-log-barrier/
authors:
    - xp
categories:
    - distributed
tags:
    - raft
    - consensus
    - membership
mathjax: false
toc: true
toc_label: Table of Contents
toc_sticky: true
description: "Standard joint consensus provides its own log barrier through config entries. Single-step changes and joint consensus extended with rollback require a committed current-term entry before a new config. Two failure scenarios show why the difference comes down to quorum overlap."
---

# Raft Membership Changes: When a Leader Must Commit a Current-Term Entry First

![Raft membership changes and log barriers](raft-membership-noop-banner-small.png)

Raft's corrected single-step membership-change protocol requires a leader to commit an entry from its current term before proposing a new config. Standard joint consensus needs no separate noop barrier: its config entries already establish mutual exclusion. If we extend joint consensus to allow rollback, however, both rollback and completion require the extra barrier.

The distinction comes down to which configs can still elect leaders or commit entries. Starting from `C0`, we need to check its overlap with each proposed successor, `C1` and `C2`. We also need to check the overlap between `C1` and `C2` for as long as both can still be used. Throughout this article, elections and commits use ordinary Raft majority quorums.

## 1. Raft supports single-step changes and joint consensus

A **single-step config change** moves directly from `C0` to `C1` with one config entry. The usual single-server variant adds or removes one voting node at a time, ensuring that `C0` and `C1` intersect. For example, to move from `{a,b,c}` to `{b,c,d}`, we first add `d`. Once that change commits, we remove `a`.

A **joint config change** introduces an intermediate config, `C01 = [C0,C1]`. Under `C01`, every election and commit requires both a quorum of `C0` and a quorum of `C1`. The leader commits `C01` before appending the target config `C1`, as specified in [§6 of the Raft paper][ref-raft]. This intermediate step allows several nodes to change at once.

The two columns show the same migration. Time runs upward in both:

```text
single-step                 joint

{b,c,d}                     C1 = {b,c,d}
    ↑                           ↑  after C01 commits
{a,b,c,d}                   C01 = [{a,b,c},{b,c,d}]
    ↑                           ↑
{a,b,c}                      C0 = {a,b,c}
```

The timing of config activation is important to the examples that follow. [Flexible Raft: Read and Write Quorums][post-rw-quorum] describes the rule, which we can restate here:

> Raft propagates membership through config entries in the log. A node begins using `C1` as soon as it appends the corresponding entry, even if that entry is uncommitted.

A leader may therefore leave an uncommitted `C1` on just a few nodes before crashing. Those nodes can still use `C1` in a later election. The crash alone does not rule out the proposal.

## 2. Two quorum sets intersect when every pair of quorums overlaps

Here, **config** and **quorum set** mean the same thing: a collection of permitted quorums. With majority voting, the smallest quorums of `C = {a,b,c}` are `{a,b}`, `{a,c}`, and `{b,c}`.

> Two quorum sets `A` and `B` intersect if every quorum of `A` shares at least one node with every quorum of `B`. Formally, `qa ∩ qb ≠ ∅` for all `qa ∈ A` and `qb ∈ B`. We denote this property by `Intersect(A,B)`.

This definition applies whenever we say that two configs intersect. Consider `C0 = {a,b,c}` and `C1 = {b,c,d}`. They share nodes `b` and `c`, but `C0` permits quorum `{a,b}`, while `C1` permits quorum `{c,d}`. Since those quorums are disjoint, `C0` and `C1` do not intersect.

## 3. Quorums that can still elect or commit must intersect one another

For membership changes to be safe, **the quorums that can still elect leaders or commit entries must intersect**. The log and voting records on shared nodes give Raft the information it needs to reject conflicting decisions.

Suppose `C0` has committed. Leader `L1` proposes `C1` from `C0`, then crashes before `C1` commits. A new leader, `L2`, has not received `C1`. It therefore also starts from `C0` and proposes `C2`:

```text
       C1          C2
          ↖      ↗
              C0
```

This history creates two overlap requirements:

1. **`C0` must intersect both `C1` and `C2`.** As `C1` propagates, some nodes may use `C0` while others use `C1`. The same is true of a transition to `C2`. Each transition needs overlap between the old and new configs.
2. **`C1` and `C2` must intersect while both remain usable.** Nodes retaining `C1` may elect a leader under `C1` while `L2` uses `C2`. If `C1` and `C2` allow disjoint quorums, those leaders may make conflicting decisions.

If `C1` and `C2` allow disjoint quorums, the protocol must rule out the old `C1` proposal before enabling `C2`. Once `C1` can no longer elect a leader or commit entries, it no longer competes with `C2`. A log barrier establishes that ordering.

## 4. Without a barrier, an uncommitted Cu can overwrite a committed Cv

### Adding u and v separately to the same C0

Consider the counterexample from [The Pitfalls of Raft Membership Change][post-raft-bug]. The committed config is `C0 = {a,b,c,d}`. Leader `a` proposes `Cu` by adding `u`; a later leader, `d`, proposes `Cv` by adding `v`. Each successor intersects `C0`, but `Cu` and `Cv` permit disjoint quorums: `{a,b,u}` and `{c,d,v}`.

```text
   Cu = C0 + u          Cv = C0 + v
   quorum {a,b,u}       quorum {c,d,v}
              ↖       ↗
                  C0
              {a,b,c,d}
```

All six nodes initially have the same log through index 5, and the entry at index 5 belongs to term 0. Nodes `u` and `v` have caught up as nonvoting nodes. To expose the bug, suppose leaders can propose configs before committing an entry from their current term.

Read the chart from bottom to top. `L1` and `F1` identify the leader and followers in term 1; terms 2 and 3 use the same notation. `X` marks a crash, and `Cu` and `Cv` mark the config entries stored on each node.

```text
time ↑ |   u     a     b     c     d     v
       | -----------------------------------
 t8    |  Cu    Cu    Cu    Cu    Cu
 t7    |  F3    L3    F3
 t6    |                          X
 t5    |                    Cv    Cv    Cv
 t4    |              F2    F2    L2
 t3    |        X
 t2    |  Cu    Cu
 t1    |        L1    F1    F1
       | -----------------------------------
```

1. **t1–t3: `a` leaves an uncommitted `Cu` in term 1.** Node `a` wins votes from `{a,b,c}` under `C0` and appends `Cu` at index 6. Only `a` and `u` store the entry before `a` crashes.
2. **t4–t6: `d` commits `Cv` in term 2.** Nodes `b`, `c`, and `d` have not received `Cu`, so they elect `d` under `C0`. Leader `d` appends `Cv` at index 6 and replicates it to `{c,d,v}`, a quorum of `Cv`. It commits `Cv`, then crashes. Node `b` votes in the election but receives no term 2 entries.
3. **t7: `a` is elected under `Cu` in term 3.** After recovering, `a` collects votes from `{a,b,u}` using its local `Cu`. The log on `b` still ends at index 5 in term 0. Since `a` holds a term 1 entry, Raft's log comparison allows `b` to vote for `a`.
4. **t8: `a` commits `Cu` and overwrites `Cv`.** Leader `a` replicates a term 3 noop to `{a,b,u}`, committing both the noop and its prefix, including `Cu`. It then sends `Cu` to `c` and the recovered `d`, overwriting their committed `Cv`.

The noop is needed because `Cu` was written in term 1. Under Raft's normal commit rule, `a` commits a term 3 entry, which also commits the preceding entries. **In term 3, `a` commits the `Cu` it originally wrote in term 1.** The chart omits the noop because it tracks only config propagation.

This execution has only one leader per term, yet it loses a committed config. The failure occurs across terms: quorum `{c,d,v}` commits `Cv`, while the disjoint quorum `{a,b,u}` later elects `a`.

### Establishing mutual exclusion through the common parent C0

Both `Cu` and `Cv` are proposed from `C0`, so the protocol can use `C0` to establish mutual exclusion. It can commit an entry under `C0`, leaving a log record that later elections must respect. It could also impose stronger election requirements to prevent `a`, which holds `Cu` but lacks `Cv`, from winning again.

Single-step changes use a log barrier. The correction discussed in [the earlier article][post-raft-bug] can be stated directly:

> A new leader must commit an entry from its current term before appending a membership-change entry.

In this example, `d` must commit a term 2 entry under `C0` before proposing `Cv`. A quorum of `C0` will then hold an entry newer than the term 1 `Cu`. Since every quorum of `Cu` intersects that quorum, `a` cannot win with a log that still ends at `Cu`. This is the condition in [Ongaro's correction for single-server membership changes][ref-single-safety].

## 5. Neither step of standard joint consensus needs a separate noop barrier

### Both C01 and C02 retain a quorum of C0

Suppose leader `L1` proposes `C01 = [C0,C1]` from `C0`, then crashes before `C01` commits. A new leader, `L2`, has not received `C01`, so it starts from `C0` and proposes `C02 = [C0,C2]`:

```text
  C01 = [C0,C1]       C02 = [C0,C2]
              ↖     ↗
                 C0
```

Every quorum of `C01` contains a quorum of `C0`, and so does every quorum of `C02`. Any two quorums of `C0` intersect. Consequently, `C01` and `C02` must intersect, regardless of whether `C1` and `C2` overlap.

### Committing C01 fixes C1 as the destination

Once `C01 = [C0,C1]` commits, standard joint consensus permits only `C1` as the final config for this transition. If leader `L2` crashes while completing the change, its successor `L3` must continue toward the same `C1`. Their completion quorums therefore belong to `C1` and must intersect.

**Committing `C01` provides the log barrier between the two stages.** Before that commit, alternative joint configs such as `C01` and `C02` retain a quorum of `C0`. After it, every leader completing the transition uses `C1`. The config entries themselves establish the required mutual exclusion, so neither stage needs a separate noop barrier.

Raft's rules for committing entries from earlier terms still apply. If `L2` inherits an uncommitted `C01` from `L1`, it must commit `C01` before appending `C1`. That may require `L2` to commit an entry from its own term, committing `C01` as part of the prefix. This follows the ordinary commit rule in [§5.4.2 of the Raft paper][ref-raft].

## 6. Allowing joint rollback breaks mutual exclusion and requires a log barrier

Standard Raft completes the transition to `C1` after committing `C01 = [C0,C1]`. Suppose we extend that protocol to also allow a rollback from `C01` to `C0`. Take `C0 = {a,b,c}` and `C1 = {x,y,z}`:

```text
  C0 = {a,b,c}          C1 = {x,y,z}
  quorum {a,b}          quorum {x,y}
              ↖        ↗
                  C01
                [C0,C1]
```

Both `C0` and `C1` intersect `C01`, but their own quorums can be disjoint: `{a,b}` shares no node with `{x,y}`. Allowing rollback removes the guarantee that every completion uses `C1`. Leader `a` may retain an uncommitted rollback to `C0`, while a later leader `y` completes the transition to `C1`. Without a barrier, `a` can subsequently try to commit its rollback through a quorum disjoint from the one used by `y`.

### Guarding rollback alone can still allow both C0 and C1 to commit

The barrier is required before both rollback and completion. A check that applies only to rollback requests still permits the following execution:

1. **Term 1: `a` satisfies the barrier, then proposes rollback.** Leader `a` commits its noop on joint quorum `{a,b,x,y}`, then appends the entry for returning to `C0`. Only `a` stores the rollback entry before crashing.
2. **Term 2: `y` skips the barrier and completes the change.** Node `y` holds the term 1 noop and wins votes from joint quorum `{b,c,x,y}`. It appends `C1` immediately and commits it on `{y,z}`. Node `b` receives no term 2 entries.
3. **Term 3: `a` commits the old rollback entry.** When `a` recovers, its log has one more term 1 entry than the log on `b`: the rollback to `C0`. It can therefore win votes from `{a,b}` under `C0`. Committing a term 3 noop then also commits the rollback entry.

The missing barrier is in term 2. Before proposing `C1`, `y` needs to commit a term 2 entry under `C01` to rule out the older rollback held by `a`. When `a` returns in term 3, it can commit its existing rollback without proposing a new one. A guard that checks only new rollback requests therefore misses this execution.

The standard joint argument applies when `C01 → C1` is the only permitted completion and no `C0` rollback entries remain. Every leader completing the transition then uses quorums of `C1`.

## 7. A leader establishes the barrier by committing under the common config

**For single-step changes and joint consensus extended with rollback, the leader first commits a current-term entry under the common config. Only then may it propose the next config.**

Suppose `L1` proposes an uncommitted `C1` from `C0` in term 1, and `L2` wants to propose `C2` from `C0` in term 2. By first committing a term 2 entry under `C0`, `L2` records its authority on a quorum of `C0`. Every quorum of `C1` intersects that quorum. Raft's term checks and log comparison rules then prevent `L1` and its old `C1` branch from producing a conflicting commit.

The entry is usually a noop, but a current-term application entry serves the same purpose. Once the leader has committed such an entry in its term, it can reuse that barrier for later membership changes.

### A joint election would depend on C0, which may already be retired

We could also try to establish mutual exclusion through an election. Suppose a candidate's latest config is `C_new`, following `C0`. Requiring the candidate to win under joint config `[C0,C_new]` would record its term on quorums of both configs. The voting records in `C0` would constrain leaders from earlier terms.

The difficulty is that **a candidate may not know whether `C_new` has committed or whether a quorum of `C0` is still available**. For example, a cluster may have moved from `C0 = {a,b,c}` through joint consensus to `C_new = {x,y,z}`. Once `C_new` commits, `a`, `b`, and `c` can all shut down, as described in [§6 of the Raft paper][ref-raft].

Candidate `x` can still win an election under `C_new` with votes from `{x,y}`. Requiring an additional quorum of `C0` would make that election depend on nodes that have already left the cluster.

A log barrier lets the leader work with the config that elected it. The candidate first wins under its latest local config, `C_new`, then commits a current-term entry under `C_new`. That commit confirms `C_new` and its prefix before the leader proposes `C_next`. For this next transition, the common config is `C_new`, so the barrier has no dependency on the retired `C0`.

## 8. Single-step changes and joint consensus enforce mutual exclusion through committed entries

[The Pitfalls of Raft Membership Change][post-raft-bug] describes the principle shared by these protocols. In this article's terminology:

> Membership changes establish mutual exclusion through quorums of the old config. At most one of the conflicting changes proposed from that old config can commit.
>
> Single-step changes first use an application entry or a noop to establish mutual exclusion. Joint consensus does this through the config entries themselves.

In the OpenRaft implementation described here, rollback is permitted. A membership change therefore requires the current leader's first noop to be committed. The same check applies to direct config appends:

```rust
if cluster_committed >= Some(noop_log_id) {
    return Ok(());
}
```

Here, `cluster_committed` is the commit position confirmed by a quorum, and `noop_log_id` identifies the current leader's first noop. This uniform guard also covers ordinary joint transitions exposed through the same API.

The requirement for a separate current-term log barrier depends on the permitted transitions:

1. **Standard joint consensus needs no separate noop barrier in either step.** Proposals `C01 = [C0,C1]` and `C02 = [C0,C2]` both retain a quorum of `C0`, so they intersect. Committing `C01` in the first step provides the log barrier. Every leader completing that transition must then use `C1`, so the second step needs no extra noop condition either.
2. **Single-step changes require a current-term commit before proposing the new config.** Configs `Cu` and `Cv` may each intersect their parent `C0` while allowing disjoint quorums between themselves. The leader must first commit a current-term entry under `C0` to rule out conflicting proposals from earlier terms.
3. **With joint rollback enabled, both completion and rollback require a current-term commit first.** Config `C01` can lead to either `C0` or `C1`, whose quorums may be disjoint. Before appending either config, the leader must commit an entry from its current term under `C01`.

A noop is the usual way to establish the extra barrier, but an application entry from the current term works equally well. Whenever the protocol requires that barrier, **the leader must have committed an entry from its own current term before proposing the new config**.

[post-raft-bug]: /distributed/raft-bug/ "The Pitfalls of Raft Membership Change"
[post-rw-quorum]: /distributed/raft-rw-quorum/ "Flexible Raft: Read and Write Quorums"
[ref-raft]: https://raft.github.io/raft.pdf "In Search of an Understandable Consensus Algorithm"
[ref-single-safety]: https://gist.github.com/ongardie/a11f32b70581e20d6bcd "Diego Ongaro: Safety of Raft single-server membership changes"
