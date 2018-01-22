#!/usr/bin/perl

# This script parses a blast (m8) or sam output file and 
# tallies the hits by taxonomy.  
#
# The best hit (highest bit score) for each query is 
# attributed to the NCBI TAXID corresponding
# to the hit's GI. 
# 
# In case of a tie (equal bitscores), each TAXID gets 
# attributed 1/number_tying_GIs counts, unless LCA analysis
# is turned on (-lca), in which case the LCA node gets the attribution
#
# The output is tab-delimited with these fields 
# # header line with informative metadata
# TAXID scientific_name common_name kingdom tally median_evalue min_evalue max_evalue
# 
# The output will be written to stdout and will be 
# sorted by tally
#
# Dependencies: these perl modules I've written:
# to interface to the NCBI taxomony data
#
#    taxid_to_description.pm
#    taxid_to_kingdom.pm
#    acc_to_taxid;
#
#   Mark Stenglein June 9, 2011
#   Updated: Dec 14, 2015
#

use strict;
use Getopt::Long;
use Data::Dumper;
use feature "current_sub";
use taxid_to_description;
use taxid_to_kingdom;
use fetch_gi_description;
# use gi_to_taxid;
use acc_to_taxid;
use DBI;

# TODO: make this setable by environmental variable or command line option
my $tax_dir = "/home/databases/NCBI_Taxonomy";

my $print_usage = 0;
my $output_suffix = "tally"; #default
my $max_evalue = undef;
my $tally_cutoff = 0.1;
my $sort_by_evalue = 0;
my $output_descriptions = 0;
my $output_pct_id = 1;
my $num_gis_per_taxid = 10;
my $annotated_blast_output = undef;
my $input_fasta_file = undef;
my $query_weight_file = undef;
my $included_taxid_args = undef;
my $excluded_taxid_args = undef;
my %included_taxids = undef;
my %excluded_taxids = undef;
my $including_taxids = 0;
my $excluding_taxids = 0;
my $no_descendents = 0;
my $krona_output = 0;
my $tab_indent_output = 0;
my $output_query_map = 0;
my %gi_taxid_map = ();
my $collapse_below_species = 0; 

my $ignore_ties = 0;
my $do_lca = 0;
my $output_rank = 0;

# Taxonomy info stored in these hashes
my %node_rank = ();
my %node_parent = ();
my %node_descendents = ();
my %subspecies_taxid_map = ();

my $tree_output = 0;
my $tally_all_hits = 0;

my $usage = <<USAGE;

   This script parses a blast output file (-m8, -m9) and 
   tallies the hits by taxonomy.  

   If a single blast output file (m8 file) is input, then the output
   will go to stdout.  If multiple files are input, output files will be 
   created with a suffix (default = \"$output_suffix\") appended.

   The -t option will aggregate hits up the NCBI taxonomy tree and output
   all nodes in the tree with hits.  

   The --it and --et options can be used to only output taxa subsets 
   (e.g. only viruses: -it 10239).  

   Note that this script depends on several modules I've written:

      taxid_to_description.pm
      taxid_to_kingdom.pm
      fetch_gi_esummary.pm

   Some dependency scripts require a local copy of the NCBI taxonomy databases
   (see that file for more info)

   Assumes: mysql database setup for gi->taxid mapping

   usage: $0 
             [-e max_eval] 
             [-o output_suffix] 
             [-c tally_cutoff] 
             [-m ]
             [-f fasta_file] 
             [-d]
             [-p]
             [-ab]
             [-n num_gis]
             [-i ]
             [-lca ]
             [-t ]
             [-ti ]
             [-it taxid]
             [-et taxid]
             [-k ]
             [-nd]
             [-cs]
             <blast_output_file(s)> 

   -w weight_file  Weight queries by the values specified in this file.  This could be useful, for example
                   if your queries correspond to contigs that account for many inidivual reads in a 
                   dataset.  This file should contain 2 tab-delimited fields per line.  The first field being
                   the query name and the second being the weight.  

   -e max_eval     Only hits with e-values lower than this will be tallied

   -o suffix       Append this suffix to create new output files (only applies for multiple input files)
                   [default = $output_suffix]

   -c tally_cutoff Only output if the tally exceeds this cutoff.  [default = $tally_cutoff].

   -m              Sort output by median evalue [default = sort by tally]

   -f              Additionally output frequencies for each TAXID, in addition to counts
                   this option requires you to input the name of the fasta_file that was
                   used as blast input to calc the frequency = #hits / #fasta_file_records.
                   Using this option only supports a single blast file as input

   -d              For each taxid, output constituent GIs and their descriptions 

   -p              For each taxid, output average percent ID of alignments (default = yes)

   -ab             Annotated blast output - reoutput the blast record with the taxonomic
                   info embedded in the query id field (in the first column)

   -n num_gis      If outputing GIs and descriptions, output this many per taxid
                   (default = $num_gis_per_taxid)

   -i              ignore ties.  Only use the first hit (with the best bitscore) for
                      each query.  [default = don't ignore]

   -lca            If a query hits multiple subjects, perform LCA (lowest common ancestor) analysis
                   Assign the query to the lca node.  By default, this is not done.

   -t              Tally hits up taxonomic tree and output values for each node w/ rank listed

   -ti             use tabs to indent output to reflect tree heirarchy (-t output)

   -r rank         only output taxa with this rank (e.g., -r genus -> only output hits at the genera level)
                   only applies when using -t option)

   -a              all hits are tallied, rather than just the best bitscore hit
                   use this option with caution if you don't know how to interpret the results.

   -it taxid       only include (only output) these taxid or their descendent taxids in the taxonomy tree
                   This option can be used multiple times
                   e.g. ... -it 10239 -it 40674   --> only output hits for viruses (10239) and mammals (40674) 
                   see NCBI Taxonomy browser for taxid (http://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi)

   -et taxid       same as -it but exclude these taxids or their descendent taxids 
                   e.g. ... -et 549779  --> exclude mimiviruses
                   can be used in combination with -it 
                   e.g. ... -it 10239  -et 549779   --> output only viruses but not mimiviruses

   -k              Create a file that can be used as input for the ktImportText krona command
                   to create an interactive visualization of data.  
                   File will be named <input_filename>.krona

   -nd             if -it or -et options are used, don't include or exclude descendent taxids
                   default is to include or exclude descendent taxids

   -cs             Collapse any results from below the species level to the species level
                   default is to report results at the lowest annotated taxonomic level, even if
                   below the species level (i.e. at the sub-species level).

   blast_results   Multiple blast results files can be specified (unless using -f)
                   if a single results file is specified, output will go to stdout
                   if multiple files are specified, output files will be created (see -o)

USAGE

if (scalar @ARGV == 0) { print $usage and exit; }

GetOptions("h" => \$print_usage, 
           "e=s" => \$max_evalue, 
           "o=s" => \$output_suffix, 
           "c=s" => \$tally_cutoff, 
           "d" => \$output_descriptions, 
           "p" => \$output_pct_id, 
           "f=s" => \$input_fasta_file, 
           "w=s" => \$query_weight_file, 
           "ab" => \$annotated_blast_output,
           "n=i" => \$num_gis_per_taxid, 
           "i" => \$ignore_ties,
           "r=s" => \$output_rank,
           "t" => \$tree_output,
           "ti" => \$tab_indent_output,
           "qm" => \$output_query_map,
           "lca" => \$do_lca,
           "it=i@" => \$included_taxid_args,
           "et=i@" => \$excluded_taxid_args,
           "nd" => \$no_descendents,
           "k" => \$krona_output,
           "a" => \$tally_all_hits,
           "cs" => \$collapse_below_species,
           "m" => \$sort_by_evalue);

if ($print_usage) { print $usage and exit; }

# if ($do_lca) { print "Sorry, LCA not correctly implemented yet...\n" and exit; }

# connect to mysql database
my $dbh = DBI->connect("DBI:mysql:database=NCBI_Taxonomy",
                       "NCBI_Taxonomy", "NCBI_Taxonomy",
                       {'RaiseError' => 1}) or die $DBI::errstr;

my @aln_files = ();
while (my $aln_file = shift)
{
   push @aln_files, $aln_file;
}

if ($input_fasta_file and (scalar @aln_files != 1))
{
   print "error: only a single alignment input file should be specified when using the -f option\n"; 
   exit;
}

# parse nodes.dmp
# TODO - don't always do?
## if ($tree_output or defined $included_taxid_args or defined $excluded_taxid_args)
## {
   parse_nodes();
## }


if (defined $included_taxid_args) 
{
   add_included_taxids(@$included_taxid_args);
}

if (defined  $excluded_taxid_args) 
{
   add_excluded_taxids(@$excluded_taxid_args);
}

# if there is just one file, output to stdout
# if there are lots of files, output to name.tally file

my $num_aln_files = scalar @aln_files;
my $print_to_stdout = 0;
if ($num_aln_files <= 0)
{
   print $usage and die ("error: must specify an alignment file\n");
}
elsif ($num_aln_files == 1)
{
   $print_to_stdout = 1;
}

# parse optional fasta file
my $fasta_read_count = undef;
if ($input_fasta_file)
{
   open (my $fasta_fh, "<", $input_fasta_file) or print "error: couldn't open fasta input file: $input_fasta_file\n" and exit; 
   while (<$fasta_fh>)
   {
      if (/^>/)
      {
         # count fasta records in order to calculate fequencies
         $fasta_read_count += 1;
      }
   }
}

# parse optional query weight file
my $weight_queries = 0;
my %query_weights = ();

if ($query_weight_file)
{
   $weight_queries = 1;
   open (my $query_weight_fh, "<", $query_weight_file) or print "error: couldn't open query weight file: $query_weight_file\n" and exit; 
   while (<$query_weight_fh>)
   {
      chomp;
      if (/^\s*#/)
      {
         # ignore comment lines
         next;
      }
      my ($query_id, $weight) = split;
      $query_weights{$query_id} = $weight;
   }
}


# parse alignment files

warn "$num_aln_files files to process\n";

my $aln_fh = undef;

foreach my $aln_file (@aln_files)
{
   if ($aln_fh)
   {
      close ($aln_fh);
   }
   open ($aln_fh, "<", $aln_file) or print $usage and die ("error: couldn't open BLAST results file: $aln_file\n");

   warn "processing file: $aln_file\n";

   my %queries = ();
   my @queries_array = ();
   my $multi_segment_hit = 0;
   my $query = undef;

   # First: read blast output file from stdin
   # Keep track of best hits for each query
   LINE: while (<$aln_fh>)
   {
      # TODO: keep track of best hit for each query
      if ((/^\s*#/) or (/^\s*$/))
      {
         # ignore comment (#...) or empty lines
         next LINE;
      }
      chomp;

      my @fields = split "\t";
      if (scalar (@fields >= 12))
      {
         # this is the format we expect
         # The order of fields for BLAST result in tabular format is: 
         # 0 query id, 1 database sequence (subject) id, 2 percent identity, 3 alignment length, 
         # 4 number of mismatches, 5 number of gap openings, 6 query start, 7 query end, 
         # 8 subject start, 9 subject end, 10 Expect value, 11 HSP bit score. 
         # 12 on optional additional fields...

         my $query = $fields[0];
         push @queries_array , $query;
         my $gi = $fields[1];
         my $evalue = $fields[10];
         my $bit_score = $fields[11];

         if ((defined $max_evalue) && ($evalue > $max_evalue))
         {
            # warn "evalue: $evalue > cutoff: $max_evalue\n";
            next LINE;
         }

         if ($tally_all_hits)
         {
            push @{ $queries{$query}{best_hits} }, $_;
         }
         else
         {
            my $best_bitscore = $queries{$query}{best_bitscore};
            if ((!$best_bitscore) || ($bit_score >= $best_bitscore))
            {
               $queries{$query}{best_bitscore} = $bit_score;
               if ($bit_score > $best_bitscore)
               {
                  $queries{$query}{best_hits} = [ ];
               }
               push @{ $queries{$query}{best_hits} }, $_;
            }
         }
      }
      else
      {
         warn ("ignoring line with unexpected number of fields in BLAST output: $_\n");
      }
   }

   my %taxid_tally = ();
   my %taxid_gi_tally = ();
   my @fields = ();
   my %observed_gi_tally = ();

   # iterate through queries and determine whether to weight them or not
   foreach my $query (keys %queries)
   {
      if (!defined $query_weights{$query})
      {
         # set weight to 1 if query weighting not in effect or a weight not specified for this query
         $query_weights{$query} = 1;
      }
   }

   # iterate through best hits and determine GI->TaxID mapping
   warn "mapping sequence accessions to TaxIDs\n";
   foreach my $query (keys %queries)
   {
      my @hits = @{$queries{$query}{best_hits}};
      my $number_hits = scalar (@hits);
      foreach my $hit (@hits)
      {
         @fields = split "\t", $hit;
         my $gi = $fields[1];
         $observed_gi_tally{$gi} += 1;
      }
   }

   # query DB for GI->TaxID mapping
   # do 5000 at a time
   my $gis_per_batch = 5000;
   my @observed_gis = keys %observed_gi_tally;
   my $num_observed_gis = scalar @observed_gis;
   for (my $i = 0; $i < $num_observed_gis; $i += $gis_per_batch)
   {
      my $last_i = $i+($gis_per_batch-1);
      if ($last_i >= $num_observed_gis)
      {
         $last_i = $num_observed_gis - 1;
      }
      warn "fetching $i to $last_i\n";
      my @gis_to_fetch = @observed_gis[$i..$last_i];
      my @taxids = acc_to_taxid::acc_to_taxid(@gis_to_fetch);
      for (my $j = 0; $j < (scalar @gis_to_fetch); $j++)
      {
         my $gi = $gis_to_fetch[$j];
         my $taxid = $taxids[$j];
         # collapse from sub-species to species level...
         if ($collapse_below_species and $subspecies_taxid_map{$taxid})
         {
            $taxid = $subspecies_taxid_map{$taxid};
            # warn "collapsing $gi -> $taxid\n";
         }
         $gi_taxid_map{$gi} = $taxid;
         # warn "$gi -> $taxid\n";
      }
   }

   # now iterate through best hits and tally scores for TAXIDs
   foreach my $query (keys %queries)
   {
      # warn "query: $query\n";
      my @hits = @{$queries{$query}{best_hits}};
      my $number_hits = scalar (@hits);
      my $lca_taxid = undef;

      my $gi = undef;
      my $mean_evalue = undef;
      my $mean_pct_id = undef;

      my $evalue_sum = 0;
      my $pct_id_sum = 0;

      my %hit_taxids = ();
      foreach my $hit (@hits)
      {
         @fields = split "\t", $hit;
         my $gi = $fields[1];
         my $taxid = $gi_taxid_map{$gi};
         if (!defined $taxid)
         {
            warn "__LINE_ TAXID undefined for GI: $gi.  Setting this taxid to root\n";
            # set to root if not defined.
            # a taxid not being defined may reflect out of sync taxonomy and nt (local) databases...
            $taxid = 1;
         }

         # keep track of which taxids this query hits -> will use to find LCA
         $hit_taxids{$taxid} += 1;

         # calculate average e-value and % identity of hits 
         @fields = split "\t", $hit;
         if (scalar @fields < 12)
         {
            die "error: unexpected format for blast hit: line: $hit\n";
         }
         $evalue_sum += $fields[10];
         $pct_id_sum += $fields[2];
      }

      if ($number_hits > 0)
      {
         my $mean_evalue_unformatted = $evalue_sum / $number_hits;
         $mean_evalue = sprintf "%0.1e", $mean_evalue_unformatted;
         $mean_pct_id = $pct_id_sum / $number_hits;
      }

      # if >1 hit, find the LCA of the hits...
      my $lca_taxid = undef;
      my $num_taxids_hit = scalar keys %hit_taxids;
      if ($do_lca)
      {
         $lca_taxid = identify_lca(keys %hit_taxids); 
      }

      if ($do_lca)
      {
         # non-norm tally
         $taxid_tally{$lca_taxid}{tally} += $query_weights{$query};
         # keep track of which query IDs hit each taxid
         push @{$taxid_tally{$lca_taxid}{queries}}, $query;

         push @{$taxid_tally{$lca_taxid}{evalues}}, $mean_evalue;
         push @{$taxid_tally{$lca_taxid}{pct_ids}}, $mean_pct_id;

         # propagate tally up tree to root 
         if ($tree_output)
         {
            my $parent_taxid = $lca_taxid;
            while ($parent_taxid = $node_parent{$parent_taxid})
            {
               $taxid_tally{$parent_taxid}{tally} += $query_weights{$query};
               push @{$taxid_tally{$parent_taxid}{evalues}}, $mean_evalue;
               push @{$taxid_tally{$parent_taxid}{pct_ids}}, $mean_pct_id;
               if ($parent_taxid == 1) { last; }  # at the root
            }
         }
      }
      else
      {
         my @hits = @{$queries{$query}{best_hits}};
         my $number_hits = scalar (@hits);
         foreach my $hit (@hits)
         {
            @fields = split "\t", $hit;
            if (scalar @fields < 12)
            {
               die "error: unexpected format for blast hit: line: $hit\n";
            }
            my $gi = $fields[1];
            my $unformatted_evalue = $fields[10];
            my $evalue = sprintf "%0.1e", $unformatted_evalue;
            my $pct_id = $fields[2];
            my $taxid = $gi_taxid_map{$gi};
            if (!$taxid)
            {
               warn "__LINE__ 1 TAXID undefined for GI: $gi\n";
            }

            # "normalized" tally
            $taxid_tally{$taxid}{tally} += ($query_weights{$query}/$number_hits);
            if ($output_descriptions)
            {
               $taxid_gi_tally{$taxid}{$gi} += ($query_weights{$query}/$number_hits);
            }
            push @{$taxid_tally{$taxid}{evalues}}, $evalue;
            push @{$taxid_tally{$taxid}{pct_ids}}, $pct_id;

            # propagate tally up tree to root 
            if ($tree_output)
            {
               my $parent_taxid = $taxid;
               while ($parent_taxid = $node_parent{$parent_taxid})
               {
                  $taxid_tally{$parent_taxid}{tally} += ($query_weights{$query} / $number_hits);
                  push @{$taxid_tally{$parent_taxid}{evalues}}, $evalue;
                  push @{$taxid_tally{$parent_taxid}{pct_ids}}, $pct_id;
                  if ($parent_taxid == 1) { last; }  # at the root
               }
            }
         }
      }
   }

   # *****************
   # move on to output
   # *****************

   my $out_fh = undef;
   if ($print_to_stdout)
   {
      open ($out_fh, ">-") or die "error: failed to open stdout for writing\n";
   }
   else
   {
      my $out_fn = $aln_file.".".$output_suffix;
      open ($out_fh, ">", $out_fn) or die "error: failed to open output file $out_fn\n";
   }

   # if (!$do_lca)   # this not implemented for LCA yet
   # {
      # calculate evalue stats and store back in hash
      foreach my $taxid (keys %taxid_tally)
      {
         # TODO: these stats do not take into account query weights 
         my @evalues = @{$taxid_tally{$taxid}{evalues}};
         # my @sorted_evalues = sort {@evalues;
         my @sorted_evalues = sort {$a <=> $b} @evalues;
         my $median_evalue = sorted_median(@sorted_evalues);
         my $min_evalue = $sorted_evalues[0];
         my $max_evalue = $sorted_evalues[$#sorted_evalues];
         $taxid_tally{$taxid}{median_evalue} = $median_evalue;
         $taxid_tally{$taxid}{min_evalue} = $min_evalue;
         $taxid_tally{$taxid}{max_evalue} = $max_evalue;
   
         if ($output_pct_id)
         {
            my @pct_ids = @{$taxid_tally{$taxid}{pct_ids}};
            my @sorted_pct_ids = sort {$a <=> $b} @pct_ids;
            my $median_pct_id = sorted_median(@sorted_pct_ids);
            my $min_pct_id = $sorted_pct_ids[0];
            my $max_pct_id = $sorted_pct_ids[$#sorted_pct_ids];
            $taxid_tally{$taxid}{median_pct_id} = $median_pct_id;
            $taxid_tally{$taxid}{min_pct_id} = $min_pct_id;
            $taxid_tally{$taxid}{max_pct_id} = $max_pct_id;
         }
      }

   # }

   # do sorting
   my @sorted_taxids = ();
   if ($sort_by_evalue)
   {
     @sorted_taxids = sort { $taxid_tally{$a}{median_evalue} <=> $taxid_tally{$b}{median_evalue} } keys %taxid_tally;
   }
   else
   {
     @sorted_taxids = sort { $taxid_tally{$b}{tally} <=> $taxid_tally{$a}{tally} } keys %taxid_tally;
   }

  # output all the queries that map to a particular taxid
  if ($output_query_map)
  {
     foreach my $taxid (@sorted_taxids)
     {
        print "$taxid";
        foreach my $queries (@{$taxid_tally{$taxid}{queries}})
        {
           print "\t$query";
        }
        print "\n";
     }
  }
  elsif (!$tree_output)
  { 
   if ($annotated_blast_output) 
   {  
      # die "unsupported option for gsnap output \n"; 
      foreach my $query (@queries_array)
      {
         my @hits = @{$queries{$query}{best_hits}};
         my $number_hits = scalar (@hits);
         foreach my $hit (@hits)
         {
            @fields = split "\t", $hit;
            if (scalar @fields < 12)
            {
               die "error: unexpected format for blast hit: line: $hit\n";
            }
            my $gi = $fields[1];
            my $unformatted_evalue = $fields[10];
            my $evalue = sprintf "%0.1e", $unformatted_evalue;
            my $taxid = undef;
            my @taxids = acc_to_taxid::acc_to_taxid($gi);
            $taxid = $taxids[0];
            # check to see if we are only outputting a subset of taxids, and if so, is this
            # one of the ones we should output?
            if ( $including_taxids and not $included_taxids{$taxid} )
            {
               ## warn "taxid: $taxid is not in the included list\n";
               next ;
            }
            if ( $excluding_taxids and $excluded_taxids{$taxid} )
            {
               ## warn "taxid: $taxid is excluded\n";
               next ;
            }
            my @scientific_names = taxid_to_description::taxid_to_scientific_name($taxid);
            my $scientific_name = $scientific_names[0];
            my @common_names = taxid_to_description::taxid_to_common_name($taxid);
            my $common_name = $common_names[0];
            my @kingdoms = taxid_to_kingdom::taxid_to_kingdom($taxid);
            my $kingdom = $kingdoms[0];
            my $new_gi = $gi.":".$scientific_name.":".$common_name.":".$kingdom;
            $fields[1] = $new_gi;
            print join "\t" ,  @fields;
            print "\n";
         }
      }
   }
   else
   {
      # finally, output tallys
      print $out_fh "TAXID\tScientific Name\tCommon Name\tKingdom\tTally\t";
      if ($fasta_read_count)
      {
         print $out_fh "Frequency\tRead Count\t";
      }
      if ($output_pct_id)
      {
         print $out_fh "Median %identity\tMin %identity\tMax %identity\t";
      }
      print $out_fh "Median evalue\tMin evalue\tMax evalue\n";
      # foreach my $taxid (sort { $taxid_tally{$b}{tally} <=> $taxid_tally{$a}{tally} } keys %taxid_tally)
      foreach my $taxid (@sorted_taxids) 
      {
         # check to see if we are only outputting a subset of taxids, and if so, is this
         # one of the ones we should output?
         if ( $including_taxids and not $included_taxids{$taxid} )
         {
            ## warn "taxid: $taxid is not in the included list\n";
            next;
         }
         if ( $excluding_taxids and $excluded_taxids{$taxid} )
         {
            ## warn "taxid: $taxid is excluded\n";
            next;
         }

         my $tally = $taxid_tally{$taxid}{tally};
         my $median_evalue = $taxid_tally{$taxid}{median_evalue};
         my $min_evalue = $taxid_tally{$taxid}{min_evalue};
         my $max_evalue = $taxid_tally{$taxid}{max_evalue};
         my $median_pct_id = $taxid_tally{$taxid}{median_pct_id};
         my $min_pct_id = $taxid_tally{$taxid}{min_pct_id};
         my $max_pct_id = $taxid_tally{$taxid}{max_pct_id};
         if ($tally > $tally_cutoff)
         {
            my @scientific_names = taxid_to_description::taxid_to_scientific_name($taxid);
            my $scientific_name = $scientific_names[0];
            my @common_names = taxid_to_description::taxid_to_common_name($taxid);
            my $common_name = $common_names[0];
            my @kingdoms = taxid_to_kingdom::taxid_to_kingdom($taxid);
            my $kingdom = $kingdoms[0];
            my $formatted_tally = sprintf "%0.1f", $tally;
            # print $out_fh "$taxid\t$scientific_name\t$common_name\t$kingdom\t$formatted_tally\t$median_evalue\t$min_evalue\t$max_evalue\n";
            print $out_fh "$taxid\t$scientific_name\t$common_name\t$kingdom\t$formatted_tally\t";
            if ($fasta_read_count)
            {
               my $frequency = $tally / $fasta_read_count;
               printf $out_fh "%0.2e\t%d\t", $frequency, $fasta_read_count;
            }
            if ($output_pct_id)
            {
               printf $out_fh "%0.1f\t%0.1f\t%0.1f\t", $median_pct_id, $min_pct_id, $max_pct_id;
            }
            printf $out_fh "%0.1e\t%0.1e\t%0.1e\n", $median_evalue, $min_evalue, $max_evalue;
            if ($output_descriptions)
            {
               my @gis_for_this_taxid = keys %{$taxid_gi_tally{$taxid}};
               my @gis_sorted_by_tally = sort { $taxid_gi_tally{$taxid}{$b} <=> $taxid_gi_tally{$taxid}{$a} } @gis_for_this_taxid;
               my $num_gis_for_this_taxid = scalar @gis_sorted_by_tally;
               # this is a min() function
               my $num_gis_to_output = ($num_gis_per_taxid < $num_gis_for_this_taxid) ? $num_gis_per_taxid : $num_gis_for_this_taxid;
               my @gis_to_output = @gis_sorted_by_tally [ 0 ..  ($num_gis_to_output-1) ];
               my $gi_descriptions = fetch_gi_description (@gis_to_output); # returns a hash ref of GI->descriptions
               foreach my $gi (@gis_to_output)
               {
                  my $desc = $$gi_descriptions{$gi};
                  my $formatted_tally = sprintf "%0.1f", $taxid_gi_tally{$taxid}{$gi}; 
                  print $out_fh "\t$gi\t$desc\t$formatted_tally\n";
               }
            }
         }
      }
   }
  }
  else
  {
      printf $out_fh "Rank\t";
      print $out_fh "TAXID\tParent TAXID\tScientific Name\tCommon Name\tKingdom\tTally\t";
      if ($fasta_read_count)
      {
         print $out_fh "Frequency\tRead Count\t";
      }
      if ($output_pct_id)
      {
         print $out_fh "Median %identity\tMin %identity\tMax %identity\t";
      }
      print $out_fh "Median evalue\tMin evalue\tMax evalue\n";

      my $tab_level = -1;

      # output the children
      sub output_children
      {
         $tab_level++;
         my $parent_taxid = shift @_;
         if ($node_descendents{$parent_taxid})
         {
            my @child_taxids = @{$node_descendents{$parent_taxid}};
            foreach my $taxid (@child_taxids)
            {
               # print "parent: $parent_taxid\tchild: $taxid\n";
               if ($taxid_tally{$taxid})
               {
                  # check to see if we are only outputting a subset of taxids, and if so, is this
                  # one of the ones we should output?
                  if ( $excluding_taxids and $excluded_taxids{$taxid} )
                  {
                     # This TAXIS is excluded: don't output it or any of its descendents
                     ## warn "taxid: $taxid is excluded\n";
                     next;
                  }

                  # This TAXID many not be included, but its descendents might be
                  if ( not $including_taxids or ($including_taxids and $included_taxids{$taxid} ) )
                  {
                     my $tally = $taxid_tally{$taxid}{tally};
                     my $median_evalue = $taxid_tally{$taxid}{median_evalue};
                     my $min_evalue = $taxid_tally{$taxid}{min_evalue};
                     my $max_evalue = $taxid_tally{$taxid}{max_evalue};
                     my $median_pct_id = $taxid_tally{$taxid}{median_pct_id};
                     my $min_pct_id = $taxid_tally{$taxid}{min_pct_id};
                     my $max_pct_id = $taxid_tally{$taxid}{max_pct_id};
                     my $rank = $node_rank{$taxid};
                     if ($output_rank && ($output_rank ne $rank))
                     {
                        # don't output this 
                     }
                     elsif ($tally > $tally_cutoff) 
                     {
                        if ($tab_indent_output)
                        {
                           for (my $i = 0; $i < $tab_level; $i++)
                           {
                              # this is stupid
                              print $out_fh "\t";
                           }
                        }
                        my @scientific_names = taxid_to_description::taxid_to_scientific_name($taxid);
                        my $scientific_name = $scientific_names[0];
                        my @common_names = taxid_to_description::taxid_to_common_name($taxid);
                        my $common_name = $common_names[0];
                        my @kingdoms = taxid_to_kingdom::taxid_to_kingdom($taxid);
                        my $kingdom = $kingdoms[0];
                        my $rank = $node_rank{$taxid};
                        print $out_fh "$rank\t";
                        print $out_fh "$taxid\t$parent_taxid\t$scientific_name\t$common_name\t$kingdom\t";
                        if ($fasta_read_count)
                        {
                           my $frequency = $tally / $fasta_read_count;
                           printf $out_fh "%0.2e\t%d\t", $frequency, $fasta_read_count;
                        }
                        printf $out_fh "%0.1f\t", $tally;
                        if ($output_pct_id)
                        {
                           printf $out_fh "%0.1f\t%0.1f\t%0.1f\t", $median_pct_id, $min_pct_id, $max_pct_id;
                        }
                        printf $out_fh "%0.1e\t%0.1e\t%0.1e\n", $median_evalue, $min_evalue, $max_evalue;
                     }
                  }
                  else
                  {
                     ## warn "taxid: $taxid is not in the included list \n";
                  }
                  # recurse
                  output_children ($taxid);
               }
            }
         }
         $tab_level--;
      }


      output_children(1);

      if ($krona_output)
      {
         my @ancestor_chain = ();
         my $krona_output_filename = $aln_file.".krona";
         open (my $krona_fh, ">", $krona_output_filename) or print "error: couldn't open krona output file: $krona_output_filename for writing\n";

         output_children_for_krona(1);

         sub output_children_for_krona
         {
            my $this_taxid = shift @_;

            # no tally or less than cutoff
            if (!$taxid_tally{$this_taxid} or ($taxid_tally{$this_taxid}{tally} < $tally_cutoff))
            {
               return;
            }

            # check to see if we are only outputting a subset of taxids, and if so, is this
            # one of the ones we should output?
            if ( $excluding_taxids and $excluded_taxids{$this_taxid} )
            {
               # This TAXIS is excluded: don't output it or any of its descendents
               ## warn "taxid: $taxid is excluded\n";
               return;
            }

            # This TAXID many not be included, but its descendents might be
            if ( $including_taxids and not $included_taxids{$this_taxid}  )
            {
               return;
            }

            # don't process root node
            if ($this_taxid != 1)
            {
               push @ancestor_chain, $this_taxid;
               my $rank = $node_rank{$this_taxid};
               if ($rank eq "genus" or $rank eq "species")
               {
                  # output for krona at genus or species level if genus undefined
                  my $magnitude = $taxid_tally{$this_taxid}{tally};
                  print $krona_fh "$magnitude";
                  foreach my $ancestor (@ancestor_chain)
                  {

                     my @scientific_names = taxid_to_description::taxid_to_scientific_name($ancestor);
                     my $ancestor_name = $scientific_names[0];
                     print $krona_fh "\t$ancestor_name";
                  }
                  print $krona_fh "\n";
                  pop @ancestor_chain;
                  return; # return once we print out a node for this lineage...
               }
            }

            if ($node_descendents{$this_taxid})
            {
               my @child_taxids = @{$node_descendents{$this_taxid}};
               foreach my $taxid (@child_taxids)
               {
                  output_children_for_krona($taxid);
               }
            }

            pop @ancestor_chain;
         }

         close $krona_fh;
      }
  }
   close $out_fh;
}

# calc median of a sorted array
sub sorted_median
{
   my @a = @_;
   return ($a[$#a/2] + $a[@a/2]) / 2;
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
            push @{$node_descendents{$parent_taxid}}, $taxid;
         }
         # print "$taxid\t$parent_taxid\t$rank\n";
      }
      else
      {
         die "error: unexpected format in $nodes_file file: $_\n";
      }
   }

   if ($collapse_below_species)
   {
      generate_subspecies_to_species_map();
   }

   return 0;
}

# this function maps sub species-level rank taxids to their species taxid
sub generate_subspecies_to_species_map
{
   warn "collapsing sub species taxids to species level\n";
   COLLAPSE_TAXID: foreach my $taxid (keys %node_rank)
   {
      my $rank = $node_rank{$taxid};

      # "no" -> "no rank"
      if ($node_rank{$taxid} eq "no")
      {
         my $current_taxid = $taxid;

         # go up to tree to find a species in lineage above it
         while (my $parent_taxid = $node_parent{$current_taxid})
         {

            if ($parent_taxid == 1)
            {
               next COLLAPSE_TAXID;
            }

            if ($node_rank{$parent_taxid} eq "species")
            {
               $subspecies_taxid_map{$taxid} = $parent_taxid;
               # warn "collapsing $taxid -> $parent_taxid\n";
               next COLLAPSE_TAXID;
            }

            $current_taxid = $parent_taxid;
         }
      }

   }
}

# these hashes will contain taxids that should (included) or shouldn't (excluded) be output
sub add_included_taxids
{
   my @taxids = @_;
   foreach my $taxid (@taxids)
   {
      $including_taxids = 1;
      $included_taxids{$taxid} = 1;
      # warn "adding taxid: $taxid to the included list\n";
      if (defined $node_descendents{$taxid} and !$no_descendents)
      # if (!$no_descendents and @{$node_descendents{$taxid}})
      {
         my @children = @{$node_descendents{$taxid}};
         add_included_taxids(@children);
      }
   }
}

sub add_excluded_taxids
{
   my @taxids = @_;
   foreach my $taxid (@taxids)
   {
      $excluding_taxids = 1;
      $excluded_taxids{$taxid} = 1;
      warn "adding taxid: $taxid to the excluded list\n";
      # if (!$no_descendents and @{$node_descendents{$taxid}})
      if (defined $node_descendents{$taxid} and !$no_descendents)
      {
         my @children = @{$node_descendents{$taxid}};
         add_excluded_taxids(@children);
      }
   }
}

# this subroutine will identify the LCA (lowest common ancestor) of a set of TAXIDs
sub identify_lca
{
   my @taxids = @_;

   if (scalar @taxids == 0)
   {
      return;
   } 
   elsif (scalar @taxids == 1)
   {
      return $taxids[0];
   }

   my $taxid_1 = shift @taxids;
   my $taxid_2 = shift @taxids;

   # calculate LCA of 1st 2 taxids
   my $lca = calculate_lca_of_2($taxid_1, $taxid_2);

   # recursively identify LCA of any additional nodes
   # and the LCA of nodes analyzed so far.
   while (my $another_taxid = shift @taxids)
   {
      $lca = calculate_lca_of_2 ($lca, $another_taxid);
   }

   return $lca;
}

# this routine calculates the LCA of 2 nodes in the NCBI Taxonomy tree...
# see: https://www.hackerrank.com/topics/lowest-common-ancestor
sub calculate_lca_of_2
{
   my ($node1, $node2) = @_;

   # node == 1 --> is the root node.  LCA of root and anything is always root
   if ($node1 == 1 or $node2 == 1)
   {
      # return root node
      return 1;
   }

   # to keep track of nodes in 1st node's lineage path to root
   my %nodes_in_first_lineage = ();

   # go up to root from first node
   while (1)
   {
      $nodes_in_first_lineage{$node1} = 1;
      if ($node1 == 1) 
      { 
         # made it to root
         last; 
      } 
      my $child_node = $node1;

      # move up to the parent position in the lineage
      $node1 = $node_parent{$node1};

      # if parent undefined
      if (!defined $node1)
      {
         warn "error: undefined parent in NCBI Taxonomy tree for node: $child_node\n";
         # make parent root if parent undefined
         $node1 = 1;
      }
   }

   # to up to root from 2nd node
   # stop when hit first node also in path from first node
   while (1)
   {
      if ($nodes_in_first_lineage{$node2})
      {
         warn "LCA of $_[0] and $_[1] => $node2\n";
         # this is the LCA: the first point in node2's lineage that is also in node1's lineage
         return $node2;
      }
      my $child_node = $node2;

      # move up to the parent position in the lineage
      $node2 = $node_parent{$node2};

      # if parent undefined
      if (!defined $node2)
      {
         warn "error: undefined parent in NCBI Taxonomy tree for node: $child_node\n";
         # make parent root if parent undefined
         $node2 = 1;
      }
   }
}



