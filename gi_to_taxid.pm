

# 
# The functions in this package return NCBI Taxids for NCBI GIs
#
# Depends on sorted_file_search_by_field.pm package
# Depends also on local copy of NCBI taxonomy db (see below)
#
# Mark Stenglein, June 7, 2011
#

package gi_to_taxid;

use DBI;
use strict;

use base 'Exporter';
our @EXPORT = qw(gi_to_taxid);

# connect to mysql database
my $dbh = DBI->connect("DBI:mysql:database=NCBI_Taxonomy",
                       "NCBI_Taxonomy", "NCBI_Taxonomy",
                       {'RaiseError' => 1}) or die $DBI::errstr;

sub gi_to_taxid
{
   my @taxids = _gi_to_taxid(@_);
   return @taxids;
}

sub _gi_to_taxid
{
   my @gis = @_;
   my %gi_taxid_map = ();

   # check to see if GIs in gi|XXXXX| format 
   for (my $i = 0; $i < (scalar @gis); $i++)
   {
      # if this gi is in the form it is in NCBI BLAST results
      if ($gis[$i] =~ /gi\|(\d+)\|/)
      {
         # warn "replacing $gis[$i] with $1\n";
         $gis[$i] = $1;
      }
   }

   my @taxids = ();

   # determine TAXID for this GI
   my $num_gis = scalar @gis;
   my $qs = ("?");
   if ($num_gis > 1)
   {
      my @qs_array = ("?") x (scalar @gis);
      $qs = join (", ", @qs_array);
   }
   my $sql_string = "SELECT gi, taxid FROM gi_taxid_map where gi in ( $qs )";
   warn "$sql_string\n";
   my $sth = $dbh->prepare( $sql_string );
   $sth->execute(@gis);
   # warn "GIS: @gis\n";
   
   # iterate through rows of mysql output
   # need to do this because:
   #
   # (1) some GIs might not return TAXIDs
   # (2) results not necessarily in order of input
   #
   while ( my ($gi, $taxid) = $sth->fetchrow_array())
   {
      # warn "$gi->$taxid\n";
      $gi_taxid_map{$gi} = $taxid;
   }

   # create array to return
   # will return an array that is 1:1 with input array
   foreach my $gi (@gis)
   {
      push @taxids, $gi_taxid_map{$gi};
   }

   return @taxids;
}



# PERL packages must return a true value
1;
