
# Vector clock

所有node上记录的refuse_commit_index 可以看做一个向量时钟:
T={node_1: commit_index_1, node_2: commit_index_2, ...}

令T(a, x) 为 一个VC中至少有quorum个node的commit_index为a
即T(a, x) = {node_i : a, node_j: a, ...} )U {node_j1: x_1, node_j2: x_2, ...}

因为两个quorum必有交集, 所以:
a < b => T(a,x) !> T(b,y)


phase-protect 相当于把系统的时钟向前推进到T(a,x).
