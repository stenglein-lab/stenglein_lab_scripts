#!/usr/bin/env Rscript

args = commandArgs(trailingOnly=TRUE)

usage = "

  This R script takes as input a newick formatted file 
  containing one or more phylogenetic trees and
  outputs the tree(s) in nexus format to stdout.

  Requires an R installation including the ape package.

  USAGE: newick_to_nexus.R tree_file.newick 

"

# test if there is at least one argument: if not, return an error
if (length(args)==0) {
  stop(usage, call.=FALSE)
} else if (length(args)==1) {
  # default output file
  input_file = args[1]
}

# requires APE lib
library(ape)

tree <- read.tree(input_file)

# write out in nexus
write.nexus(tree)

