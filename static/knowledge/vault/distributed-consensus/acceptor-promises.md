# Acceptor promises

After promising ballot $b$, an acceptor rejects proposals with a lower ballot number.
Its prepare reply also reports its highest accepted ballot and value, if any.

For example, an acceptor that promised ballot 8 rejects an accept request for ballot 7.

The promise and accepted proposal must survive a restart. [[paxos|Paxos]] uses this state to connect successive ballots safely.

[Source: Paxos Made Simple, §2.2](https://lamport.azurewebsites.net/pubs/paxos-simple.pdf).
