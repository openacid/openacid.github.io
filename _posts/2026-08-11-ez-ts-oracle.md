---
title: "Build a Distributed Timestamp Oracle with EzRaft"
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
toc_label: Table of Contents
toc_sticky: true
excerpt: "`timestamp_oracle` is a 200-line timestamp service on EzRaft. A background task reserves ranges through Raft; `next_timestamp` allocates from memory. Leader leases and term-scoped caches keep the sequence strictly increasing across failovers, with no Raft write on the request path."
---

![](/post-res/ez-ts-oracle/b43c2a98b06d02ef-ez-time-server-banner.png)

A timestamp oracle issues one globally increasing sequence. Transaction systems built on [MVCC](https://en.wikipedia.org/wiki/Multiversion_concurrency_control) consume two of those values on every commit, so the oracle sits on the critical path of every write. The naive way to keep the sequence safe is one Raft commit per request. That design is correct. It is also too slow.

This article builds the other design: reserve a range with one Raft write, then allocate from memory. The service is [timestamp_oracle](https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs), about 200 lines on [EzRaft](https://github.com/drmingdrmer/ezraft). It runs as a three-node cluster, stays available after any one node fails, and answers `next_timestamp` without waiting for a Raft commit.

[EzRaft](https://github.com/drmingdrmer/ezraft), from the [previous article](https://blog.openacid.com/algo/ezraft/), is a small [Rust](https://www.rust-lang.org/) API over [OpenRaft](https://github.com/databendlabs/openraft). It hides the [Raft](https://raft.github.io/), networking, and storage machinery, so you can start with the service itself.

Three calls carry the design:

-   `EzRaft::write()` commits the upper bound of a reserved range and applies it to the state machine.
-   `EzRaft::wait_metrics()` lets a background task sleep until its node becomes the leader.
-   `EzRaft::linearizable(ReadPolicy::LeaseRead)` checks the leader lease and returns the current term, so each cached range is bound to one term.

The idea underneath those calls is simple. Raft owns a ceiling. The leader spends from below that ceiling in memory. A lease and a term tag decide whether it is still allowed to spend.

![Architecture overview: `next_timestamp` requests allocate timestamps from the leader's memory, while the reservation task connects the in-memory cache to a three-node EzRaft cluster](/post-res/ez-ts-oracle/0830bc2afe95fe2a-time-server-architecture.png)

## What a Timestamp Oracle Must Guarantee

The interface is one call: a client sends `next_timestamp`, and the service returns a timestamp.

Those values usually order distributed transactions. Models such as [Percolator](https://www.usenix.org/legacy/event/osdi10/tech/full_papers/Peng.pdf) give each transaction a start timestamp and a commit timestamp. Those two numbers decide which transaction came first. TiDB's [TSO (Timestamp Oracle)](https://docs.pingcap.com/tidb/stable/glossary/#timestamp-oracle-tso) is the same component.

The service has three hard requirements:

1.  Monotonicity. Timestamps increase in the order requests reach the oracle, and they never go backward after a failover. Every timestamp from the new leader must be greater than every timestamp the old leader already returned.

1.  Fault tolerance. The service stays available while a majority of the cluster is alive. OpenRaft already provides that, so a three-node cluster can lose any one node and keep issuing timestamps.

1.  Low latency. `next_timestamp` sits on the critical path of every operation that needs an ordering point, so each request has to be cheap.

There is a softer requirement as well. The values should stay close to wall-clock time. Correctness only requires the sequence to increase. Closeness to wall-clock time is a quality goal, not a safety property.

## Safe Baseline: One Raft Write per Timestamp

The cluster only has to agree on one durable value: `reserved_end`, the exclusive end of all timestamp space reserved so far. Every value below `reserved_end` is permanently consumed, whether or not a client ever received it.

The obvious safe design writes one Raft log entry for every `next_timestamp` request. Once that entry is replicated and applied, the state machine returns the timestamp it claimed. Every leader walks the same log, so a failover cannot reuse an earlier value.

The state machine is correspondingly small:

```rust
struct Reserve {
    reserve_upto_us: u64,
}

struct Interval {
    start: u64,
    end: u64,
}

struct TimeState {
    reserved_end: u64,
}

impl EzApp for TimeState {
    type Request = Reserve;
    type Response = Interval;

    async fn apply(&mut self, req: Reserve) -> Interval {
        let start = self.reserved_end;
        let end = start.max(req.reserve_upto_us);
        self.reserved_end = end;
        Interval { start, end }
    }
}
```

`Reserve` asks the state machine to move `reserved_end` to at least `reserve_upto_us`. The response is the newly claimed half-open interval `[start, end)`. Those types and `apply()` are all that [`EzApp`][docs-ezraft-ezapp] needs. See [timestamp_oracle.rs:66-112](https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L66-L112).

The `max` in `apply()` makes the transition idempotent. Applying the same upper bound again leaves `reserved_end` unchanged, so a timed-out reservation can be retried safely.

This design is safe. It is also slow: every request pays for Raft replication and state-machine application. The rest of the article takes both of those costs off the request path.

## Fast Path: Reserve Timestamps in Batches

One Raft entry can reserve a wide range instead of a single value. By default the service reserves one second of timestamp space, then the leader hands out individual values from that range in memory.

> `reserved_end` is durable. The leader's position inside the reserved range is not: it lives only in memory.
> If the leader fails, its successor skips the unused suffix and reserves a new range.
> The sequence may contain gaps. It never goes backward.


A background reservation task keeps the leader's cache filled. Each successful reservation is stored in a `Reserved` value with three fields: the term that owns the range, the next available timestamp, and the exclusive upper bound.

```rust
struct Reserved {
    term: u64,
    next: u64,
    end: u64,
}
```

`run_reserver()` uses `wait_metrics()` to wait until the node becomes the leader. Once it is, the task calls `refill()` and repeats every half-reservation interval. See [timestamp_oracle.rs:170-186](https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L170-L186):

```rust
struct TimeService {
    // ...
    reserved: Mutex<Reserved>,
}

impl TimeService {
    async fn run_reserver(&self) {
        let refresh_interval = Duration::from_micros(self.reservation_width.get() / 2);
        loop {
            let leads = self.raft.wait_metrics(None, |m| m.state == ServerState::Leader, "reserve timestamps");
            if let Err(error) = leads.await {
                return;
            }
            if let Err(error) = self.refill().await {
                warn!("{error}");
            }
            tokio::time::sleep(refresh_interval).await;
        }
    }
}
```

`refill()` first obtains a valid leader term. It then computes `now + width`, commits that upper bound through Raft, and stores the returned interval in `TimeService.reserved`. See [timestamp_oracle.rs:188-205](https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L188-L205):

```rust
async fn refill(&self) -> io::Result<()> {
    // ensure leader lease and get leader term.
    let term = self.leader_term().await?;
    let now = unix_timestamp_micros();
    let width = self.reservation_width.get();
    let upto = now.saturating_add(width);

    let interval = self.raft.write(Reserve { reserve_upto_us: upto }).await?;

    self.reserved.lock().await.install(term, interval);
    Ok(())
}
```

The Raft write rate is now independent of the request rate. For a reservation width of `width`, the task writes once every `width / 2`. A single distributed commit can serve 100,000 `next_timestamp` requests.

## Preserve Monotonicity Across Leader Failover

Batch allocation stays safe because the committed upper bound, not the in-memory cursor, is the handoff point. When a new leader is elected, it already has the log. After it applies those entries, `reserved_end` is at least as large as anything the old leader reserved. The new leader never starts from the old leader's in-memory cursor, because that cursor was never replicated.

![Three-node leader failover: Raft log replication and state-machine replay keep `reserved_end` consistent across nodes, so the new leader begins from a safe timestamp range](/post-res/ez-ts-oracle/2df814a86a1bcc27-time-server-failover-safety.png)

That committed bound protects the new leader. It does not stop the old one. A network partition can isolate the old leader long enough for the other nodes to elect a replacement, while the old leader still believes it owns the cluster.

Once the new leader issues a timestamp from a later range, any later allocation from the old leader's range would move time backward. The old leader must refuse requests as soon as it can no longer prove that it still holds leadership.

## Reject a Stale Leader with a Lease

A lease is a time-bounded promise: as long as the leader has heard from a [quorum](https://blog.openacid.com/algo/quorum/) recently, no other node can win an election. Checking that promise is a local read of heartbeat state, so it adds no network round trip to a timestamp request. `timestamp_oracle` performs that check with a [linearizable](https://blog.openacid.com/algo/linearizable/) read using `ReadPolicy::LeaseRead`.

OpenRaft refreshes the lease from heartbeat acknowledgments. A recent acknowledgment from a quorum opens a window during which another leader cannot be elected. The current leader can allocate timestamps for the length of that window.

Once the latest quorum acknowledgment is older than the lease timeout, the node can no longer prove it is the only leader. `linearizable()` returns an error, and `next_timestamp()` stops before it touches the cache.

![Three-node timeline: heartbeat acknowledgments keep the old leader's lease valid; after the lease expires, a local check rejects `next_timestamp` requests, and the cluster then elects a new leader](/post-res/ez-ts-oracle/cac807cbb92f1fc1-time-server-lease-handoff.png)

[`EzRaft::linearizable(ReadPolicy::LeaseRead)`][code-ezraft-linearizable] reads the most recent heartbeat state in memory. It does not contact the quorum again. Internally it calls OpenRaft's [`Raft::ensure_linearizable()`][docs-openraft-ensure-linearizable] and returns `(term, index)`. The term identifies the current leadership; the allocator uses it to validate the cached range:

```rust
async fn leader_term(&self) -> io::Result<u64> {
    let (term, _index) = self.raft.linearizable(ReadPolicy::LeaseRead).await?;
    Ok(term)
}
```

## Serve 
`next_timestamp`
 from Memory

With a reserved range in place, the request path has three steps:

-   Call `leader_term()` to validate the lease and obtain the current term.
-   Allocate one timestamp from the cache and advance the cursor.
-   Return the timestamp to the client.

The HTTP handler, the request path, and the cache allocation fit in a few lines. See [timestamp_oracle.rs:124-133](https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L124-L133) and [timestamp_oracle.rs:162-168](https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L162-L168):

```rust
async fn get_time(service: web::Data<TimeService>) -> Result<web::Json<String>, actix_web::Error> {
    let micros = service.next_timestamp().await.map_err(actix_web::error::ErrorServiceUnavailable)?;
    Ok(web::Json(format_timestamp(micros)))
}

async fn next_timestamp(&self) -> io::Result<u64> {
    let mut reserved = self.reserved.lock().await;
    let term = self.leader_term().await?;
    let timestamp = reserved.take(term, unix_timestamp_micros());
    timestamp.ok_or_else(|| io::Error::other("no reserved timestamp is currently available"))
}

fn take(&mut self, leader_term: u64, now: u64) -> Option<u64> {
    let timestamp = now.max(self.next);
    if self.term != leader_term || timestamp >= self.end {
        return None;
    }
    self.next = timestamp + 1;
    Some(timestamp)
}
```

`now.max(self.next)` keeps timestamps close to wall-clock time while preserving local monotonicity. If the clock advances, the allocator follows it. If several requests arrive in the same microsecond—or the wall clock steps backward—`self.next` keeps every result unique and increasing.

The term comparison in `take()` is not part of the lease check. The next section is why that field exists. `leader_term()` keeps the term and discards the log index; see [timestamp_oracle.rs:207-210](https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L207-L210). The [OpenRaft documentation](https://docs.rs/openraft/0.10.0-alpha.33/openraft/raft/enum.ReadPolicy.html) describes the other `ReadPolicy` options. The underlying read optimization is covered in [How OpenRaft Optimizes ReadIndex](https://blog.openacid.com/algo/openraft-read/).

## Bind Cached Ranges to a Leader Term

A valid lease proves that this node is the leader now. It does not prove that the cached range belongs to the current term.

Suppose node A reserved a range in term 1, lost leadership, and won it back in term 3. The leftover cache is still in the same process, so a restart is not there to wipe it. In between, node B may have been the leader in term 2 and may already have issued later timestamps. Node A's leftover cache now sits behind time. Using it would go backward.

That is why `Reserved` stores the term next to `next` and `end`. A range reserved in term 1 is valid only in term 1. The term-3 leader must commit a new reservation before it can serve requests again.

![Cross-term timeline for three nodes: node A is the leader in terms 1 and 3, but its old reservation cache is invalidated; `next_timestamp` succeeds only after `refill` installs a new range for term 3](/post-res/ez-ts-oracle/5d18bdfd9b3d7222-time-server-reserved-lifecycle.png)

`take()` enforces both cache invariants in one guard. A term mismatch rejects a range from an earlier leadership. `timestamp >= self.end` rejects an exhausted range. Later requests succeed only after the background task installs a valid range.

```rust
if self.term != leader_term || timestamp >= self.end {
    return None;
}
```

With the lease check and the term check in place, the in-memory path is safe across leader changes.

## Run the Service

### Start a Three-Node Cluster

Open three terminals and start one node in each. The first command creates the cluster; the other two use `--seed` to find the first node and join it:

```bash
cargo run --example timestamp_oracle -- --addr 127.0.0.1:8090
cargo run --example timestamp_oracle -- --addr 127.0.0.1:8091 --seed 127.0.0.1:8090
cargo run --example timestamp_oracle -- --addr 127.0.0.1:8092 --seed 127.0.0.1:8090
```

The cluster assigns node IDs automatically. When a node joins, EzRaft writes a blank log entry and uses its index as the new node's ID. Other log entries may be committed between two joins, so IDs such as 0, 8, and 17 are expected. `/api/metrics` now shows three voters with node 0 as the leader:

```json
{"id":0,"current_term":1,"state":"Leader","current_leader":0,
 "membership_config":{"membership":{"configs":[[0,8,17]], ...}}}
```

### Request Timestamps

```bash
curl -X POST 127.0.0.1:8090/time
```

Run the command three times. Each request returns an [RFC 3339](https://www.rfc-editor.org/rfc/rfc3339) timestamp as a JSON string:

```
"2026-08-11T14:43:16.966734Z"
"2026-08-11T14:43:16.973216Z"
"2026-08-11T14:43:16.979556Z"
```

The six-to-seven-millisecond gaps come from starting a new `curl` process for each request. The timestamp allocation itself stays entirely in the leader's memory.

A follower rejects `/time` and names the current leader in its response:

```
$ curl -s -X POST 127.0.0.1:8091/time
has to forward request to: Some(0), Some(BasicNode { addr: "127.0.0.1:8090" })   [HTTP 503]
```

### Stop the Leader

Press Ctrl-C in the terminal running node 0, then keep sending `next_timestamp` requests to the two remaining nodes:

```
14:43:28.998  curl 8090  ->  "2026-08-11T14:43:28.998630Z"                        [200]
14:43:29      kill node 0
14:43:29.3    curl 8091  ->  has to forward request to: Some(0), ...:8090          [503]
   ...        (for about five seconds, both 8091 and 8092 return the same 503)
14:43:34.8    curl 8091  ->  has to forward request to: Some(17), ...:8092         [503]
14:43:34.8    curl 8092  ->  no reserved timestamp is currently available          [503]
14:43:35.169  curl 8092  ->  "2026-08-11T14:43:35.169756Z"                        [200]
```

The timeline shows two stages of recovery. At first the followers still point clients at node 0. Node 17 is then elected leader, but its first `Reserve` entry has not committed, so its in-memory cache is still empty. As soon as that reservation commits, the service resumes.

The timestamps stay monotonic. The first value from the new leader, `14:43:35.169756`, is greater than the last value from the old leader, `14:43:28.998630`. The unused interval between them is a harmless gap. `/api/metrics` confirms that the cluster has advanced from term 1 to term 2:

```json
{"id":17,"current_term":2,"state":"Leader","current_leader":17}
{"id":8,"current_term":2,"state":"Follower","current_leader":17}
```

<!-- No diagram: the timestamped output already shows the sequence before and after leader failover, so another illustration would be redundant. -->

## What Raft Owns

The consensus layer does not need to see every timestamp. It needs to see the ceiling, and it needs to say who may spend below that ceiling. Once those two facts are durable and current, `next_timestamp` is a local increment.

That split is the whole service. EzRaft handles replication, election, and failover. The application code persists the reservation boundary, tags each cached range with a term, and advances a cursor.

## Links

-   Example: [timestamp_oracle.rs](https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs)
-   EzRaft: [github.com/drmingdrmer/ezraft](https://github.com/drmingdrmer/ezraft)
-   crates.io: [crates.io/crates/ezraft](https://crates.io/crates/ezraft)
-   Documentation: [docs.rs/ezraft](https://docs.rs/ezraft)
-   OpenRaft: [github.com/databendlabs/openraft](https://github.com/databendlabs/openraft)
-   Previous article: [EzRaft: Build a Distributed KV Store in 100 Lines](https://blog.openacid.com/algo/ezraft/)



Reference:

- Reserve / Interval / TimeState / impl EzApp : [https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L66-L112](https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L66-L112)

- TimeService::leader_term : [https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L207-L210](https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L207-L210)

- TimeService::next_timestamp : [https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L162-L168](https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L162-L168)

- TimeService::refill : [https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L188-L205](https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L188-L205)

- TimeService::run_reserver : [https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L170-L186](https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L170-L186)

- Reserved::take : [https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L124-L133](https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L124-L133)

- ezraft on crates.io : [https://crates.io/crates/ezraft](https://crates.io/crates/ezraft)

- TiDB: Timestamp Oracle (TSO) : [https://docs.pingcap.com/tidb/stable/glossary/#timestamp-oracle-tso](https://docs.pingcap.com/tidb/stable/glossary/#timestamp-oracle-tso)

- ezraft docs : [https://docs.rs/ezraft](https://docs.rs/ezraft)

- OpenRaft ReadPolicy : [https://docs.rs/openraft/0.10.0-alpha.33/openraft/raft/enum.ReadPolicy.html](https://docs.rs/openraft/0.10.0-alpha.33/openraft/raft/enum.ReadPolicy.html)

- EzRaft: Build a Distributed KV Store in 100 Lines : [https://blog.openacid.com/algo/ezraft/](https://blog.openacid.com/algo/ezraft/)

- Linearizable Transactions in Distributed Systems : [https://blog.openacid.com/algo/linearizable/](https://blog.openacid.com/algo/linearizable/)

- How OpenRaft Optimizes ReadIndex : [https://blog.openacid.com/algo/openraft-read/](https://blog.openacid.com/algo/openraft-read/)

- Quorum Reads and Writes with a Minority : [https://blog.openacid.com/algo/quorum/](https://blog.openacid.com/algo/quorum/)

- Raft : [https://raft.github.io/](https://raft.github.io/)

- Large-scale Incremental Processing Using Distributed Transactions and Notifications : [https://www.usenix.org/legacy/event/osdi10/tech/full_papers/Peng.pdf](https://www.usenix.org/legacy/event/osdi10/tech/full_papers/Peng.pdf)

- ezraft : [https://github.com/drmingdrmer/ezraft](https://github.com/drmingdrmer/ezraft)

- ezraft timestamp_oracle example : [https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs](https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs)

- OpenRaft : [https://github.com/databendlabs/openraft](https://github.com/databendlabs/openraft)

- RFC 3339: Date and Time on the Internet : [https://www.rfc-editor.org/rfc/rfc3339](https://www.rfc-editor.org/rfc/rfc3339)

- Rust : [https://www.rust-lang.org/](https://www.rust-lang.org/)

- Multiversion concurrency control : [https://en.wikipedia.org/wiki/Multiversion_concurrency_control](https://en.wikipedia.org/wiki/Multiversion_concurrency_control)


[code-ezapp]:  https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L66-L112 "Reserve / Interval / TimeState / impl EzApp"
[code-leader-term]:  https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L207-L210 "TimeService::leader_term"
[code-next-timestamp]:  https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L162-L168 "TimeService::next_timestamp"
[code-refill]:  https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L188-L205 "TimeService::refill"
[code-run-reserver]:  https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L170-L186 "TimeService::run_reserver"
[code-take]:  https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs#L124-L133 "Reserved::take"
[crates-ezraft]:  https://crates.io/crates/ezraft "ezraft on crates.io"
[doc-tidb-tso]:  https://docs.pingcap.com/tidb/stable/glossary/#timestamp-oracle-tso "TiDB: Timestamp Oracle (TSO)"
[docs-ezraft]:  https://docs.rs/ezraft "ezraft docs"
[docs-openraft-readpolicy]:  https://docs.rs/openraft/0.10.0-alpha.33/openraft/raft/enum.ReadPolicy.html "OpenRaft ReadPolicy"
[post-ezraft-cn]:  https://blog.openacid.com/algo/ezraft/ "EzRaft: Build a Distributed KV Store in 100 Lines"
[post-linearizable]:  https://blog.openacid.com/algo/linearizable/ "Linearizable Transactions in Distributed Systems"
[post-openraft-read]:  https://blog.openacid.com/algo/openraft-read/ "How OpenRaft Optimizes ReadIndex"
[post-quorum]:  https://blog.openacid.com/algo/quorum/ "Quorum Reads and Writes with a Minority"
[raft-website]:  https://raft.github.io/ "Raft"
[ref-percolator]:  https://www.usenix.org/legacy/event/osdi10/tech/full_papers/Peng.pdf "Large-scale Incremental Processing Using Distributed Transactions and Notifications"
[repo-ezraft]:  https://github.com/drmingdrmer/ezraft "ezraft"
[repo-ezraft-timestamp-oracle]:  https://github.com/drmingdrmer/ezraft/blob/main/examples/timestamp_oracle.rs "ezraft timestamp_oracle example"
[repo-openraft]:  https://github.com/databendlabs/openraft "OpenRaft"
[rfc-3339]:  https://www.rfc-editor.org/rfc/rfc3339 "RFC 3339: Date and Time on the Internet"
[rust-lang]:  https://www.rust-lang.org/ "Rust"
[wiki-mvcc]:  https://en.wikipedia.org/wiki/Multiversion_concurrency_control "Multiversion concurrency control"