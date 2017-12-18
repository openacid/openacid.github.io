#!/bin/sh

gnuplot <<-'END'
set terminal pngcairo size 600,400
set output "edge-backsource.png"

set title "access y = C/x^s"
set ylabel "back source rate" offset -1,0,0
set xlabel "edge capacity / total capacity"
set grid ytics

set style line 1 linewidth 6 linecolor rgb "orange"
set style line 2 linewidth 2 linecolor rgb "red"


set format x '%.0f%%'
set format y '%.0f%%'


plot "edge-size-vs-backsource-rate.txt" with lines linestyle 1 title  "cached access"
END
