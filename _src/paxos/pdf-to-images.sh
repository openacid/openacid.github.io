#!/bin/sh

mkdir -p tmp

# convert 可靠分布式系统-paxos的直观解释.pdf slide-imgs/paxos-%02d.jpg

# convert -density 300 可靠分布式系统-paxos的直观解释.pdf tmp/paxos-%02d.jpg

mkdir -p resized
for f in $(ls ./tmp); do
    convert -resize "800x" ./tmp/$f ./resized/$f
done
