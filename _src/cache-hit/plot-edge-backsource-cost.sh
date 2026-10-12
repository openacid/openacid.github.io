#!/bin/sh

gnuplot <<-'END'
set terminal pngcairo size 600,400
set output "edge-backsource-cost.png"

set title "cost by edge node capacity"
set ylabel "RMB / day / edge-node" offset -1,0,0
set xlabel "edge capacity / total capacity"
set grid ytics

set style line 1 linewidth 1 linecolor rgb "orange"
set style line 2 linewidth 1 linecolor rgb "blue"
set style line 3 linewidth 3 linecolor rgb "red"


set format x '%.0f%%'
# set format y '%.0f%'

stats "edge-backsource-cost.txt" using 1:5 nooutput
set xrange [STATS_min_x:STATS_max_x]
set yrange [0:STATS_max_y*1.3]

plot "edge-backsource-cost.txt" using 1:3 with lines linestyle 1 title  "storage cost", \
     "edge-backsource-cost.txt" using 1:4 with lines linestyle 2 title  "bandwidth cost", \
     "edge-backsource-cost.txt" using 1:5 with lines linestyle 3 title  "total", \
     STATS_min_y with lines linecolor rgb"#444444" dashtype 2 notitle


END
