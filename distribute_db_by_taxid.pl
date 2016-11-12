#!/usr/bin/perl

# A program to split up a fasta file based on the taxid corresonding to the GI
# of the records
#
# Takes as input:
# (1) a fasta file to be split
# (2) a file containing a map of GI->TaxID
#
# Mark Stenglein Feb 10, 2013
#

use strict;
use warnings;
use Getopt::Long;
use DBI;

my $print_usage = 0;
my $taxid_file = undef;
my @taxids_to_filter_array = ();
my %taxids_to_filter = ();
my $output_dir = "distributed";

## $0 [[-t taxid1 ... ] or [-f taxid_file]] <fasta_file> <gi_taxid_map_file> 

my $usage = <<USAGE;

  Splits a fasta file by taxID of records into a bunch of subset files...

  Assumes: gi|XXXXXX  format in fasta headers
  Assumes: mysql database setup for gi->taxid mapping

  Mark Stenglein July 30, 2015

      usage: $0 [-o output_dir] [[-t taxid1 ... ] or [-f taxid_file]] <fasta_file> 

  -t t1 -t t2 ...   only output records for these taxids

  -f <taxids_file>  only output records for taxids listed in this file (1 per line)

  -o output_dir     directory in which new files will be created.  default=$output_dir

USAGE

if (scalar @ARGV == 0) { print $usage and exit; }

GetOptions ("h" => \$print_usage, 
            "f=s" => \$taxid_file, 
            "t=s" => \@taxids_to_filter_array,
            "d=s" => \$output_dir);

if ($print_usage) { print $usage; exit; }


# connect to mysql database
my $dbh = DBI->connect("DBI:mysql:database=NCBI_Taxonomy",
                       "NCBI_Taxonomy", "NCBI_Taxonomy",
                       {'RaiseError' => 1}) or die $DBI::errstr;

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
         my @fields = split "\t";
         my $taxid_to_filter = $fields[0];
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

# open fasta file to be split
my $fasta_file = shift or print $usage and die($!);
open (my $fasta_fh, "<", $fasta_file) or warn ("error: couldn't open FASTA file $fasta_file\n");

# max # of file handles open at once
my $max_open_fhs = 50;
# keep track of all the taxids we've seen and the open fhs
my %open_taxid_fh_map = ();

# make a directory to put all the files in
`rm -rf $output_dir`;  # remove old directory
mkdir "$output_dir", 0777 unless -d "$output_dir";

my $record_counter = 0;
warn "distributing FASTA file\n";
# now iterate through FASTA file, determine GI 
# for each sequence and corresponding TAXIDs
my $fh = undef;
FASTA_LINE: while (<$fasta_fh>)
{
   chomp;
   my $gi = undef;

   # fasta header line
   if (/^>/)
   {
      $record_counter += 1;
      if ($record_counter % 100000 == 0)
      {
         warn "record: $record_counter\n";
      }

      if (/>gi\|(\d+)|/)
      {
         $gi = $1;
      }
      else
      {
         die ("unexpected format for fasta header line. couldn't parse GI: $_\n");
      }

      # determine TAXID for this GI
      my $sth = $dbh->prepare( "SELECT taxid FROM gi_taxid_map where gi = $gi" );  
      $sth->execute();
      my ($taxid) = $sth->fetchrow();

      if (!$taxid)
      {
         warn "TAXID undefined for GI $gi\n";
         $taxid = "undefined";
      }
      if ($output_taxid_subset && !$taxids_to_filter{$taxid})
      {

         next FASTA_LINE;
      }

      # if there are too many file handles open, close them all and restart
      if (scalar keys %open_taxid_fh_map > $max_open_fhs)
      {
         ## warn "closing open file handles\n";
         # close fhs
         foreach my $taxid (keys %open_taxid_fh_map)
         {
            my $open_fh = $open_taxid_fh_map{$taxid};
            close ($open_fh);
         }
         # reset hash
         %open_taxid_fh_map = ();
      }

      $fh = $open_taxid_fh_map{$taxid};
      if (!$fh)
      {
         # my $filename = $fasta_file."_".$taxid."_".$desc.".fa";
         my $filename = $output_dir."/".$fasta_file."_".$taxid.".fa";
         open ($fh, ">>", $filename) or die ("error couldn't open filehandle for file $filename\n");
         $open_taxid_fh_map{$taxid} = $fh;
      }
   }

   if (!$fh)
   {
      # output to stderr
      # warn "$current_line\n";
   }
   else
   {
      print $fh "$_\n";
   }
}


# close fhs
foreach my $taxid (keys %open_taxid_fh_map)
{
   my $fh = $open_taxid_fh_map{$taxid};
   close ($fh);
}

$dbh->disconnect();
