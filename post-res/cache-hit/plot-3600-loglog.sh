#!/bin/sh

gnuplot <<-'END'
set terminal pngcairo size 600,400

set ylabel "access-count"
set xlabel "k-th popular object"
set grid ytics

set style line 1 linewidth 4 linecolor rgb "orange"
set style line 2 linewidth 1 linecolor rgb "blue"

set output "3600loglog.png"
set title "access in log-log scale: log(y) = s*log(x) + log(C)"
set logscale

plot "file-access-count-3600.txt" every ::0::360 with lines linestyle 1 title  "cached access", \
     "file-access-count-3600.txt" every ::360::3600 using ($0+360):($1) with lines linestyle 2 title "backsource access"
END
