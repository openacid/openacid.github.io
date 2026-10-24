# Quorum intersection

A quorum is a set of participants sufficient for a protocol step. In basic Paxos, each quorum is a [[majority]] of the acceptors.

Any two such quorums share an acceptor. A later prepare quorum therefore meets every earlier accepting quorum.

[[paxos|Paxos]] combines this overlap with [[acceptor-promises|acceptor promises]] to preserve a chosen value.

[Source: Paxos Made Simple, §2.2](https://lamport.azurewebsites.net/pubs/paxos-simple.pdf).
