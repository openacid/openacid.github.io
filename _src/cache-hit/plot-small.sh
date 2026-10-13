#!/bin/sh

gnuplot <<-'END'
set terminal pngcairo size 600,400

set ylabel "access-count"
set xlabel "k-th popular object"
set grid ytics

set style line 1 linewidth 4 linecolor rgb "orange"
set style line 2 linewidth 2 linecolor rgb "blue"


set output "1kfile.png"
set title "access y = c/k^s"

plot "file-access-count.txt" every ::0::100 with lines linestyle 1 title  "cached access", \
     "file-access-count.txt" every ::100::1000 using ($0+100):($1) with lines linestyle 2 title "backsource access"
END
