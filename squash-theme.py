#!/usr/bin/env python
# coding: utf-8

import k3git
import sys

def main(rev):
    g = k3git.Git(k3git.GitOpt(), cwd='.')
    tree = g.tree_of(rev)

    itms = g.tree_items(tree)

    # remove docs and test dir from theme commit
    itms = g.treeitems_replace_item(itms, 'docs', None)
    itms = g.treeitems_replace_item(itms, 'test', None)

    tree = g.tree_new(itms)

    commit = g.tree_commit(tree, "build squashed from {0}".format(rev), [])
    g.branch_set("theme-{0}".format(rev), commit)


if __name__ == "__main__":
    rev = sys.argv[1]
    #  print(rev)
    main(rev)
