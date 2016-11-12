#!/usr/bin/perl
#
# This script converts a taxid at species level or lower
# into a species taxid
#
# Mark Stenglein - June 8, 2011
#

use strict;

use base 'Exporter';
our @EXPORT = qw(taxid_to_species_taxid);

my $cat_filename="/home/mdstengl/NCBI_Taxonomy/categories.dmp";
my $cat_fh = undef;
my %species_taxids = ();

sub taxid_to_species_taxid
{
   my @taxids = @_;
   my @species_taxids = ();

   # parse file once
   if (!$cat_fh)
   {
      open ($cat_fh, "<", $cat_filename) or die ("error: couldn't open categories file: $cat_filename\n");

      my $kingdom = undef;
      my $taxid = undef;
      my $species_taxid = undef;

      # read whole categories input file and stick in a hash
      while (<$cat_fh>)
      {
         chomp;
         ($kingdom, $species_taxid, $taxid) = split "\t";
         $species_taxids{$taxid} = $species_taxid;
      }
   }

   # return one species taxid for each input taxid
   foreach my $t (@taxids)
   {
      my $st = $species_taxids{$t};
      push @species_taxids, $st;
   }

   return @species_taxids;
}


# Perl packages must return true value
1; 


# The taxcat dump contains a single file -
# 
#   categories.dmp
# 
# categories.dmp contains a single line for each node
# that is at or below the species level in the NCBI 
# taxonomy database.
# 
# The first column is the top-level category -
# 
#   A = Archaea
#   B = Bacteria
#   E = Eukaryota
#   V = Viruses and Viroids
#   U = Unclassified and Other
# 
# The third column is the taxid itself,
# and the second column is the corresponding
# species-level taxid.
# 
# These nodes in the taxonomy -
# 
#   242703 - Acidilobus saccharovorans
#   666510 - Acidilobus saccharovorans 345-15 
# 
# will appear in categories.dmp as -
# 
# A       242703  242703
# A       242703  666510
# 
