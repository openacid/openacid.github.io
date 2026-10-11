# Build every post in ../_posts/ with build.sh.
# The source of a post is the file in a folder here that has the same name as the post.
# Each source is a target, so `make paxos/2020-06-01-paxos.md` builds one post.

posts   := $(notdir $(wildcard ../_posts/*.md))
sources := $(wildcard $(addprefix */,$(posts)))

.PHONY: all $(sources)

all: $(sources)

$(sources):
	./build.sh $@
