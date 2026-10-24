# Single-decree Paxos

Single-decree Paxos chooses one value among proposals, using uniquely numbered ballots.

1. **Prepare:** collect [[acceptor-promises|promises]] from a [[majority]].
2. **Choose a proposal:** use the value from the highest accepted ballot reported; if none exists, choose any proposed value.
3. **Accept:** send that ballot and value. The value is chosen when a majority accepts it.

[[quorum-intersection|Quorum intersection]] and the ballot rules preserve the value across later ballots. Progress also needs a proposer that can finish without continual interruption.

[Source: Paxos Made Simple, §§2.2–2.4](https://lamport.azurewebsites.net/pubs/paxos-simple.pdf).
