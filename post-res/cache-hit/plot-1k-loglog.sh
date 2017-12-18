#!/bin/sh

gnuplot <<-'END'
set terminal pngcairo size 600,400

set ylabel "access-count"
set xlabel "k-th popular object"
set grid ytics

set style line 1 linewidth 6 linecolor rgb "orange"
set style line 2 linewidth 1 linecolor rgb "blue"


set output "1kloglog.png"
set title "access in log-log scale: log(y) = log(c) - s*log(k)"
set logscale

plot "file-access-count.txt" every ::0::100 with lines linestyle 1 title  "cached access", \
     "file-access-count.txt" every ::100::1000 using ($0+100):($1) with lines linestyle 2 title "backsource access"
END
