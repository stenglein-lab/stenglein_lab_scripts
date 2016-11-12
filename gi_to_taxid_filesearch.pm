#!/usr/bin/perl

# 
# The functions in this package return NCBI Taxids for NCBI GIs
#
# Depends on sorted_file_search_by_field.pm package
# Depends also on local copy of NCBI taxonomy db (see below)
#
# Mark Stenglein, June 7, 2011
#

package gi_to_taxid_filesearch;

use sorted_file_search_by_field;
use strict;

use base 'Exporter';
our @EXPORT = qw(gi_to_taxid);

# NCBI Taxonomy DB flatfile locations
my $gi_to_taxid_file = "/home/databases/NCBI_Taxonomy/gi_taxid.dmp";

my $fh = undef;

sub gi_to_taxid
{
   # only open the file once
   if (!$fh)
   {
      open ($fh, "<", $gi_to_taxid_file) 
            or die ("error: couldn't open NCBI GI->TAXID database file $gi_to_taxid_file\n$!\n");
   }
   my @taxids = _gi_to_taxid($fh, @_);
   return @taxids;
}

sub _gi_to_taxid
{
   my $fh = shift @_;
   my @gis = @_;

   my @fields = ();
   my @taxids = ();

   foreach my $full_gi (@gis)
   {
      my $gi = $full_gi;

      # if this gi is in the form it is in NCBI BLAST results
      if ($gi =~ /gi\|(\d+)\|/)
      {
         $gi = $1;
      }
      # warn "$full_gi -> $gi\n";

      @fields = sorted_file_search_by_field::sorted_file_search($fh, $gi);
      my $taxid = undef;
      if (!@fields)
      {
         # no results - leave taxid undefined
         # print "could not find record for GI $gi\n";
      }
      else
      {
         $taxid = $fields[1];
         # print "found for GI $gi TAXID $taxid\n";
      }
      push @taxids, $taxid;
   }
   return @taxids;
}



# PERL packages must return a true value
1;
