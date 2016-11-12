#!/usr/bin/perl

# This script parses a blast output file (-m8, -m9) and 
# tallies the hits by taxonomy.  
#
# The best hit (highest bit score) for each query is 
# attributed to the NCBI TAXID corresponding
# to the hit's GI. 
# 
# In case of a tie (equal bitscores), each TAXID gets 
# attributed 1/number_tying_GIs counts
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
#
# Mark Stenglein June 9, 2011
#

use strict;
use Getopt::Long;
use taxid_to_description;
use taxid_to_kingdom;
use fetch_gi_description;
use gi_to_taxid;
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
my $included_taxid_args = undef;
my $excluded_taxid_args = undef;
my %included_taxids = undef;
my %excluded_taxids = undef;
my $including_taxids = 0;
my $excluding_taxids = 0;
my $no_descendents = 0;
my $tab_indent_output = 0;
my $output_query_map = 0;
my %gi_taxid_map = ();

my $ignore_ties = 0;
my $html_output = 1;
my $output_rank = 0;
# my %tree = ();
my %node_rank = ();
my %node_parent = ();
my %node_descendents = ();
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
             [-f fasta_file] 
             [-d]
             [-p]
             [-ab]
             [-n num_gis]
             [-i ]
             [-m ]
             [-t ]
             [-ti ]
             [-it taxid]
             [-et taxid]
             [-nd]
             <blast_output_file(s)> 

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

   -nd             if -it or -et options are used, don't include or exclude descendent taxids
                   default is to include or exclude descendent taxids

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
           "ab" => \$annotated_blast_output,
           "n=i" => \$num_gis_per_taxid, 
           "i" => \$ignore_ties,
           "w=s" => \$html_output,
           "r=s" => \$output_rank,
           "t" => \$tree_output,
           "ti" => \$tab_indent_output,
           "qm" => \$output_query_map,
           "it=i@" => \$included_taxid_args,
           "et=i@" => \$excluded_taxid_args,
           "nd" => \$no_descendents,
           "a" => \$tally_all_hits,
           "m" => \$sort_by_evalue);

if ($print_usage) { print $usage and exit; }

# connect to mysql database
my $dbh = DBI->connect("DBI:mysql:database=NCBI_Taxonomy",
                       "NCBI_Taxonomy", "NCBI_Taxonomy",
                       {'RaiseError' => 1}) or die $DBI::errstr;

my @blast_files = ();
while (my $blast_file = shift)
{
   push @blast_files, $blast_file;
}

if ($input_fasta_file and (scalar @blast_files != 1))
{
   print "error: only a single blast input file should be specified when using the -f option\n"; 
   exit;
}

# parse nodes.dmp
# TODO - don't always do?
if ($tree_output or defined $included_taxid_args or defined $excluded_taxid_args)
{
   parse_nodes();
}


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

my $num_blast_files = scalar @blast_files;
my $print_to_stdout = 0;
if ($num_blast_files <= 0)
{
   print $usage and die ("error: must specify a blast results file\n");
}
elsif ($num_blast_files == 1)
{
   $print_to_stdout = 1;
}

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

warn "$num_blast_files files to process\n";

my $blast_fh = undef;

foreach my $blast_file (@blast_files)
{
   if ($blast_fh)
   {
      close ($blast_fh);
   }
   open ($blast_fh, "<", $blast_file) or print $usage and die ("error: couldn't open BLAST results file: $blast_file\n");

   warn "processing file: $blast_file\n";

   my %queries = ();
   my $multi_segment_hit = 0;
   my $query = undef;

   # First: read blast output file from stdin
   # Keep track of best hits for each query
   LINE: while (<$blast_fh>)
   {
      # TODO: keep track of best hit for each query
      if ((/^\s*#/) or (/^\s*$/))
      {
         # ignore comment (#...) or empty lines
         next LINE;
      }
      chomp;

      my @fields = split "\t";
      if (/^>/)
      {
         # this is a header line -> parse query ID
         if (scalar (@fields == 4))
         {
            # fastq -> gsnap
            $query = $fields[3];
         }
         elsif (scalar (@fields == 3))
         {
            # fasta -> gsnap
            $query = $fields[2];
         }
         else
         {
            die "error: unexpected format in gsnap output header line: $_\n";
         }
         # warn "query: $query\n";
      }
      else
      {
         # this is a "hit line" -> parse GIs of best hits
         if (scalar (@fields != 5) and scalar (@fields != 6))
         {
            if (scalar (@fields == 4) and $multi_segment_hit)
            {
               # for now, ignore multi-segmented hits
               # TODO: deal with? 
               next LINE;
            }
            else
            {
               die "error: unexpected format in gsnap line: $_\n";
            }
         }
         # my $full_gi = $fields[2];
         my $full_aln_score = $fields[4];
         my $aln_score = undef;

         if ($full_aln_score =~ /align_score:(\d+)/)
         {
            $aln_score = $1;
         }
         else
         {
            die "error: couldn't parse alignment score from field: $full_aln_score\n";
         }

         # determine if going to be a multi-segment hit...
         if ($full_aln_score =~ /segs:(\d+)/)
         {
            if ($1 > 1)
            {
               $multi_segment_hit = 1;
            }
            else
            {
               $multi_segment_hit = 0;
            }
         }
         else
         {
            die "error: couldn't parse number of segments from field: $full_aln_score\n";
         }
   
         if ($tally_all_hits)
         {
            push @{ $queries{$query}{best_hits} }, $_;
         }
         else
         {
            my $best_score = $queries{$query}{best_score};
            if ((!$best_score) || ($aln_score >= $best_score))
            {
               $queries{$query}{best_score} = $aln_score;
               if ($aln_score > $best_score)
               {
                  $queries{$query}{best_hits} = [ ];
               }
               push @{ $queries{$query}{best_hits} }, $_;
            }
         }
      }
   }
   
   my %taxid_tally = ();
   my %taxid_gi_tally = ();
   my @fields = ();
   my %observed_gi_tally = ();
   
   # iterate through best hits and determine GI->TaxID mapping
   warn "mapping GIs->TaxID\n";
   foreach my $query (keys %queries)
   {
      my @hits = @{$queries{$query}{best_hits}};
      my $number_hits = scalar (@hits);
      foreach my $hit (@hits)
      {
         @fields = split "\t", $hit;
         my $full_gi = $fields[2];
         if ($full_gi =~ /^[+-]gi\|(\d+)/)
         {
            my $gi = $1;
            $observed_gi_tally{$gi} += 1;
         }
         else
         {
            die ("unexpected GI format for GI: $full_gi\n");
         }
      }
   }

   # query DB for GI->TaxID mapping
   # do 1000 at a time
   my $gis_per_batch = 1000;
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
      my @taxids = gi_to_taxid::gi_to_taxid(@gis_to_fetch);
      for (my $j = 0; $j < (scalar @gis_to_fetch); $j++)
      {
         my $gi = $gis_to_fetch[$j];
         my $taxid = $taxids[$j];
         $gi_taxid_map{$gi} = $taxid;
         # print "$gi -> $taxid\n";
      }
   }

   # now iterate through best hits and tally scores for TAXIDs
   foreach my $query (keys %queries)
   {
      # warn "query: $query\n";
      my @hits = @{$queries{$query}{best_hits}};
      my $number_hits = scalar (@hits);
      foreach my $hit (@hits)
      {
         @fields = split "\t", $hit;
         my $full_gi = $fields[2];
         if ($full_gi =~ /^[+-]gi\|(\d+)/)
         {
            my $gi = $1;
            my $taxid = $gi_taxid_map{$gi};
            if (!defined $taxid)
            {
               warn "TAXID undefined for GI: $gi\n";
            }

            # "normalized" tally
            $taxid_tally{$taxid}{tally} += (1/$number_hits);
            # keep track of which query IDs hit each taxid
            push @{$taxid_tally{$taxid}{queries}}, $query;
            if ($output_descriptions)
            {
               $taxid_gi_tally{$taxid}{$gi} += (1/$number_hits);
            }

            # propagate tally up tree to root 
            if ($tree_output)
            {
               my $parent_taxid = $taxid;
               while ($parent_taxid = $node_parent{$parent_taxid})
               {
                  $taxid_tally{$parent_taxid}{tally} += (1/$number_hits);
                  if ($parent_taxid == 1) { last; }  # at the root
               }
            }

         }
         else
         {
            die ("unexpected GI format for GI: $full_gi\n");
         }
      }
   }

   my $out_fh = undef;
   if ($print_to_stdout)
   {
      open ($out_fh, ">-") or die "error: failed to open stdout for writing\n";
   }
   else
   {
      my $out_fn = $blast_file.".".$output_suffix;
      open ($out_fh, ">", $out_fn) or die "error: failed to open output file $out_fn\n";
   }

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
   if ($annotated_blast_output) {  die "unsupported option for gsnap output \n"; }
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
}

# these hashes will contain taxids that should (included) or shouldn't (excluded) be output
sub add_included_taxids
{
   my @taxids = @_;
   foreach my $taxid (@taxids)
   {
      $including_taxids = 1;
      $included_taxids{$taxid} = 1;
      ## warn "adding taxid: $taxid to the included list\n";
      if (!$no_descendents and @{$node_descendents{$taxid}})
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
      ## warn "adding taxid: $taxid to the excluded list\n";
      if (!$no_descendents and @{$node_descendents{$taxid}})
      {
         my @children = @{$node_descendents{$taxid}};
         add_excluded_taxids(@children);
      }
   }
}

