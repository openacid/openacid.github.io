#!/bin/sh

# calculate the total cost of edge storage and back source bandwidth

# 存储成本: `1 * 7200TB * e`
# 回源带宽成本: `600 * 20Gbps * b`


cat edge-size-vs-backsource-rate.txt | awk '{
edgecost = $1/100 * 1 * 7200
backcost = $2/100 * 600 * 20
print $1 "	" $2 "	" edgecost "	" backcost "	" (edgecost + backcost)
}' > edge-backsource-cost.txt
