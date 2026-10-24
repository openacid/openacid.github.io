# Majority

A majority contains more than half the members of a fixed set.
For $N$ members, the smallest majority has $\lfloor N/2 \rfloor + 1$ members.

With five replicas, a majority needs three replies. Any two sets of three replicas overlap: two disjoint sets would require six replicas.

This counting argument gives [[quorum-intersection|quorum intersection]], a prerequisite for [[paxos|Paxos]].
