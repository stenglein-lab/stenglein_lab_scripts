#!/usr/bin/perl

# A program to split up reads based on taxid of best blast hit(s)
#
# Idea is based on Sharon's distributeReads.pl script
#
# Takes 2 files as input:
# (1) a fasta file used as a blast input
# (2) the output of the blast (-m8 format)
#
# Program flow:
# (1) parse blast output, creating a map of blast query id -> taxid of best hit
#     and a map of taxid->description
#
# (2) parse fasta file, for each record with a hit, output it to a new file for the
#     taxid of the best hit
#
#  ANOTHER OPTION - NOT IMPLEMENTED
# (2) parse fasta file, distributing original fasta reads into a file with a 
#     modified header.  The new header contains the original header appended with
#     the TAXID of the best hit, description of species name, and e-value  of the hit
#
#     BLAST hit ties are ignored.  Only the first best hit is counted.
# 
# Dependencies: these perl modules I've written:
# to interface to the NCBI taxonomy data
#
#    gi_to_taxid.pm 
#    taxid_to_description.pm
#    taxid_to_kingdom.pm
#
# Mark Stenglein August 13, 2011
# Updated: 4/17/2014
#

use strict;
use warnings;
use Getopt::Long;
use gi_to_taxid;
use taxid_to_description;
use taxid_to_kingdom;

my $print_usage = 0;
my $virus_only = 0;
my $max_evalue = undef;
my $min_tally = 0;
my $taxid_file = undef;
my @taxids_to_filter_array = ();
my %taxids_to_filter = ();
my %higher_level_taxids = ();
my %node_rank = ();
my %node_parent = ();
my %node_descendents = ();
# TODO: make this setable by environmental variable or command line option
my $tax_dir = "/home/mdstengl/NCBI_Taxonomy";
my $output_directory = undef;


my $usage = <<USAGE;

  USAGE: $0 -h [-c min_tally] [-e max_evalue] [-v] [[-t taxid1 ... ] OR [-f taxid_file]] <fasta_file> <blast_output_file> 

  -t t1 -t t2 ...   only output records for these taxids
                    Taxid can be a species or a higher-level node (e.g. 10239 = all viruses).
                    
  -f <taxids_file>  only output records for taxids listed in this file (1 per line)

  -c <min_tally>    only output if number hits for this taxid is above this cutoff

  -e <max_evalue>   only output a fasta record if the corresponding hit's evalue is below this cutoff

  -od <output_dir>  new files will be written to this directory

  -v                only output virus taxids (default = no)
  
  -h                print this message

USAGE

if (scalar @ARGV == 0) { print $usage and exit; }

GetOptions ("h" => \$print_usage, 
            "v" => \$virus_only, 
            "f=s" => \$taxid_file, 
            "c=s" => \$min_tally, 
            "e=s" => \$max_evalue, 
            "od=s" => \$output_directory, 
            "t=s" => \@taxids_to_filter_array);

if ($print_usage) { print $usage; exit; }

if ($taxid_file && @taxids_to_filter_array)
{
   die ("Error: either specify taxids with -t option or -f option\n");
}

my $taxid_fh = undef;
if ($taxid_file)
{
   open ($taxid_fh, "<", $taxid_file) or print $usage and die("error: couldn't open TAXID file $taxid_file\n$!\n");
}

if ($taxid_fh)
{
   # parse through taxids to filter file 
   # print "parsing TAXID file\n";
   while (<$taxid_fh>)
   {
      chomp;
      # ignore commented out lines
      if (!/^\s*#/)
      {
         # my @fields = split "\t";
         my @fields = split /\s+/;  # split on whitespace
         my $taxid_to_filter = $fields[0];
         warn "TAXID: $taxid_to_filter\n";
         $taxids_to_filter{$taxid_to_filter} += 1;
      }
   }
}
elsif (@taxids_to_filter_array)
{
   foreach my $t (@taxids_to_filter_array)
   {
      $taxids_to_filter{$t} = 1;
   }
}

# are we only outputing a subset of TAXIDS?
my $output_taxid_subset =  keys %taxids_to_filter;

# parse flat file w/ NCBI Taxonomy db tree structure (nodes.dmp)
# parse_nodes();

# are any of the taxids upper level? (not species/leaf level)
# foreach my $t (keys %taxids_to_filter)
# {
   # # my @descendents = @{$node_descendents{$t}};
   # if (scalar @descendents)
   # {
      # $higher_level_taxids{$t} = 1;
   # }
# }

# initialize some maps
my %gi_to_taxid_map = ();
my %taxid_to_desc_map = ();
my %taxid_to_kingdom_map = ();

# keep track of all the fhs
my %taxid_fh_map = ();

my $fasta_file = shift or print $usage and die($!);
my $blast_file = shift or print $usage and die($!);

while ($fasta_file && $blast_file)
{
   my %queries = ();
   
   open (my $fasta_fh, "<", $fasta_file) or warn ("error: couldn't open FASTA file $fasta_file\n");
   open (my $blast_fh, "<", $blast_file) or warn ("error: couldn't open BLAST file $blast_file\n");

   if ($blast_fh && $fasta_fh)
   {
      warn "parsing GSNAP output file\n";

      my $query = undef;
      my $top_query_hit_encountered = 0;

      # read blast output file 
      # Keep track of the GIs of the best hits for each query
      LINE: while (<$blast_fh>)
      {
         # TODO: keep track of best hit for each query
         if ((/^\s*#/) or (/^\s*$/))
         {
            # ignore comment and blank lines
            next LINE;
         }
         elsif (/^>/)
         {
            $top_query_hit_encountered = 0;

            chomp;
            my @fields = split "\t";
            if (scalar @fields == 4)
            {
               $query = $fields[3];
            }
            elsif (scalar @fields == 3)
            {
               $query = $fields[2];
            }
            else
            {
               die "unexpected format for line in GSNAP output: $_\n";
            }
            if ($query =~ /(\S+)\s+/)
            {
               $query = $1;
            }
            # warn "q: $query\n";
            @{$queries{$query}{best_gis}} = (); 
         }
         elsif (!$top_query_hit_encountered)
         {
            chomp;
            $top_query_hit_encountered = 1; 
            my @fields = split "\t";
            # warn "processing hit for query: $query\n";
            # TODO - only take best scoring hit?
            # TODO - don't only take the top hit
            my $full_gi = $fields[2];
            if ($full_gi =~ /[+-]gi\|(\d+)|/)
            {
               push @{$queries{$query}{best_gis}}, $1;
            }
            else
            {
               die ("unexpected GI format for GI: $full_gi\n");
            }
         }
      }
      
      warn "determing TAXIDs for GIs\n";
      my $gi_counter = 0;

      # iterate through best hits and tally scores for TAXIDs
      my %taxid_tally = ();
      foreach my $query (keys %queries)
      {
         my @gis = @{$queries{$query}{best_gis}};
         my $number_hits = scalar (@gis);
     
         foreach my $gi (@gis)
         {
            $gi_counter += 1;
            if ($gi_counter % 5000 == 0)
            {
               warn  "gi #: $gi_counter\n";
            }
            my $taxid = $gi_to_taxid_map{$gi};
            if (!defined $taxid)
            {
               my @taxids = gi_to_taxid::gi_to_taxid($gi);
               $taxid = $taxids[0];
            }
            if ((!defined $taxid)||(length($taxid) == 0))
            {
               $taxid = "unknown_taxid";
            }

            # "normalized" tally
            $taxid_tally{$taxid} += (1/$number_hits);
            $gi_to_taxid_map{$gi} = $taxid;
         }
      }
      
      my @current_fhs = ();
      my @current_taxids = ();
      my $record_counter = 0;
      
      warn "filtering FASTA file\n";
      # now iterate through FASTA file, determine best GI(s) 
      # for each sequence and corresponding TAXIDs
      # and output if appropriate
      while (<$fasta_fh>)
      {
         chomp;
         my $current_line = $_;
         if (/^>/)
         {
            $record_counter += 1;
            if ($record_counter % 10000 == 0)
            {
               warn "record: $record_counter\n";
            }
            @current_fhs = ();
            @current_taxids = ();
      
            my $read_id = $_;
            # strip > char
            $read_id =~ s/>//;
            # strip everything after first space
            # because not output by blastall
            # in -m8 format file
            # TODO: fix kludgyness for this
            # $read_id =~ s/ \S+$//g;
            if ($read_id =~ /(\S+)\s+/)
            {
               $read_id = $1;
            }
      
            if ($queries{$read_id})
            {
               my @best_hit_gis = @{$queries{$read_id}{best_gis}};
               my @this_query_taxids = ();
               BEST_HIT_GI: foreach my $gi (@best_hit_gis)
               {
                  # determine TAXID of best blast hit GIs
                  my $taxid = $gi_to_taxid_map{$gi};
                  if (!$taxid)
                  {
                     warn ("error: should already have a taxid for GI: $gi\n");
                     # my @taxids = gi_to_taxid::gi_to_taxid($gi);
                     # $taxid = $taxids[0];
                     # $gi_to_taxid_map{$gi} = $taxid;
                     # if we are only outputing certain TAXIDs, make sure
                     # this is one of them
                  }

                  # are we outputing everything, or
                  # is this one of the taxids we want to output
                  if ( (!$output_taxid_subset) or ($output_taxid_subset && $taxids_to_filter{$taxid}) )
                  {
                     push @this_query_taxids, $taxid;
                  }

                  # determine if this taxid is a descendent of a higher-level TAXID
                  # we are going to output
                  # First, Are we outputing any higher-level taxids?
                  #### if (scalar keys %higher_level_taxids)
                  if (0)
                  {
                     # is this taxid a descendent of a higher level taxid to be output?
                     # if so, aggregate to that 
                     while (my $parent_taxid = $node_parent{$taxid})
                     {
                        if ($higher_level_taxids{$parent_taxid})
                        {
                           # this is a descendent 
                           push @this_query_taxids, $parent_taxid;
                        }
                        # 1 is root node of taxonomy tree
                        if ($parent_taxid == 1)
                        {
                           last;
                        }
                     }
                  }

                  # check to see if any taxids to be output.
                  if (!scalar @this_query_taxids)
                  {
                     next BEST_HIT_GI;
                  }
      
                  # if we are only outputing TAXIDS with a certain number
                  # of hits, make sure we are above cutoff
                  if ($min_tally &&  ($taxid_tally{$taxid} <= $min_tally))
                  {
                     # warn "for read $read_id, count for taxid $taxid not above cutoff\n";
                     next BEST_HIT_GI;
                  }
      
                  foreach my $this_query_taxid (@this_query_taxids)
                  {
                     foreach my $current_taxid (@current_taxids)
                     {
                        if ($current_taxid eq $this_query_taxid)
                        {
                           # we've already accounted for this TAXID in this
                           # hit.  Carry on.
                           next BEST_HIT_GI;
                        }
                     }

                     # determine kingdom (according to NCBI taxonomy db)
                     my @kingdoms = taxid_to_kingdom::taxid_to_kingdom($this_query_taxid);
                     my $kingdom = $kingdoms[0];
                     $taxid_to_kingdom_map{$this_query_taxid} = $kingdom;
      
                     # if only want virus hits, ignore non-virus hits
                     if ($virus_only && ($kingdom ne "V"))
                     {
                        # warn "ignoring non virus taxid $taxid\n";
                        next BEST_HIT_GI;
                     }

      
                     # try to get description of the taxid 
                     my $desc = $taxid_to_desc_map{$this_query_taxid};
                     if ((!$desc)||(length ($desc) == 0))
                     {
                        my @descs = taxid_to_description::taxid_to_description($taxid);
                        $desc = $descs[0];
                        if ((!$desc)||(length ($desc) == 0))
                        {
                           $desc = "no_description";
                        }
                        # need to remove awkward characters (space, /)from description string
                        $desc =~ tr/ /_/;
                        $desc =~ tr/\//_/;
                        $taxid_to_desc_map{$this_query_taxid} = $desc;
                     }
      
                     # keep track of the taxids we have already dealt with for this
                     # fasta record.  This is necessary because some sequences hit
                     # multiple db sequences that map back to the same TAXID (e.g.
                     # different isolates of the same virus)
                     push (@current_taxids, $this_query_taxid);
      
                     my $fh = $taxid_fh_map{$this_query_taxid};
                     if (!$fh)
                     {
                        my $filename = $fasta_file."_".$this_query_taxid."_".$desc.".fa";
                        if (defined $output_directory)
                        {
                           if (! -d $output_directory)
                           {
                              mkdir ($output_directory);
                           }
                           $filename = $output_directory."/".$filename;
                        }
                        open ($fh, ">", $filename) or die ("error couldn't open filehandle for file $filename\n");
                        $taxid_fh_map{$this_query_taxid} = $fh;
                     }
                     push @current_fhs, $fh;
                  }
               }
            }
            else
            {
               # there was no blast hit for this read
               # TODO: (maybe): output to file of no-hit fasta records
               # @current_fhs = ();
               # warn ("warning: no blast hit for read $read_id\n");
            }
         }
      
         if (!@current_fhs)
         {
            # output to stderr
            # warn "$current_line\n";
         }
         else
         {
            foreach my $fh (@current_fhs)
            {
               # print "printing line $_ to filehandle $fh\n"; 
               print $fh "$current_line\n";
            }
         }
      }
   }

   # try to get a couple more records
   $fasta_file = shift;
   $blast_file = shift;
}

# close fhs
foreach my $taxid (keys %taxid_fh_map)
{
   my $fh = $taxid_fh_map{$taxid};
   close ($fh);
}


# parse nodes.dmp file and populate a tree structure with info 
sub parse_nodes
{
   # nodes.dmp file consists of taxonomy nodes. The description for each node includes the following
   # fields:
   # tax_id               -- node id in GenBank taxonomy database
   # parent tax_id           -- parent node id in GenBank taxonomy database
   # rank              -- rank of this node (superkingdom, kingdom, ...)
   # embl code            -- locus-name prefix; not unique
   # division id          -- see division.dmp file
   # inherited div flag  (1 or 0)     -- 1 if node inherits division from parent
   # genetic code id            -- see gencode.dmp file
   # inherited GC  flag  (1 or 0)     -- 1 if node inherits genetic code from parent
   # mitochondrial genetic code id    -- see gencode.dmp file
   # inherited MGC flag  (1 or 0)     -- 1 if node inherits mitochondrial gencode from parent
   # GenBank hidden flag (1 or 0)            -- 1 if name is suppressed in GenBank entry lineage
   # hidden subtree root flag (1 or 0)       -- 1 if this subtree has no sequence data yet
   # comments          -- free-text comments and citations

   # nodes.dmp has a stupid quasi-tab-deliminted format that isn't amenable to splitting
   #   1  |  1  |  no rank  |     |  8  |  0  |  1  |  0  |  0  |  0  |  0  |  0  |     |
   my $nodes_file = $tax_dir."/nodes.dmp";
   open (my $nodes_fh, "<", $nodes_file) or 
          die ("error: couldn't open NCBI nodes.dmp file: $nodes_file\n");

   warn "Parsing $nodes_file\n";
   while (<$nodes_fh>)
   {
      chomp;
      if (/(\d+)\t\|\t(\d+)\t\|\t(\w+)/)
      {
         my $taxid = $1;
         my $parent_taxid = $2;
         my $rank = $3;
         # store the tree not really as a tree but as a couple hashes
         $node_rank{$taxid} = $rank;
         $node_parent{$taxid} = $parent_taxid;
         # keep track of the descendents of each node
         if ($parent_taxid != $taxid)
         {
            # node descendents is a hash of arrays
            push @{$node_descendents{$parent_taxid}}, $taxid;
         }
         # print "$taxid\t$parent_taxid\t$rank\n";
      }
      else
      {
         die "error: unexpected format in $nodes_file file: $_\n";
      }
   }
}

