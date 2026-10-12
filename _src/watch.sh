#!/bin/sh

fswatch -o "$1" | xargs -n1 -I{} ./build.sh "$1"
