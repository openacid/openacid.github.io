#!/bin/sh

fswatch -o ./2022-03-27-abstract-paxos.md | xargs -n1 -I{} ./build.sh 2022-03-27-abstract-paxos.md
