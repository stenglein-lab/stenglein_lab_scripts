

# 
# The functions in this package return NCBI Taxids for NCBI accessions
#
# Depends on sorted_file_search_by_field.pm package
# Depends also on local copy of NCBI taxonomy db (see below)
# Depends on perl DBI package (to install: cpan DBI)
#
# Mark Stenglein, June 7, 2011
#

package acc_to_taxid;

use DBI;
use strict;

use base 'Exporter';
our @EXPORT = qw(acc_to_taxid);

# connect to mysql database
my $dbh = DBI->connect("DBI:mysql:database=NCBI_Taxonomy",
                       "NCBI_Taxonomy", "NCBI_Taxonomy",
                       {'RaiseError' => 1}) or die $DBI::errstr;

sub acc_to_taxid
{
   my @taxids = _acc_to_taxid(@_);
   return @taxids;
}

sub _acc_to_taxid
{
   my @accs = @_;
   my %acc_taxid_map = ();

   # check to see if accession in gi|XXXXX| format 
   for (my $i = 0; $i < (scalar @accs); $i++)
   {
      # if this gi is in the form it is in NCBI BLAST results
      if ($accs[$i] =~ /gi\|(\d+)\|/)
      {
         # warn "replacing $accs[$i] with $1\n";
         $accs[$i] = $1;
         die ("not supported gi| format")
      }

      # convert from acc.version format to just acc
		# TODO: should this be configurable?
      if ($accs[$i] =~ /(\S+)\.\S+|/)
      {
         $accs[$i] = $1;
      }
   }

   my @taxids = ();

   # determine TAXID for this accession
   my $num_accs = scalar @accs;
   my $qs = ("?");
   if ($num_accs > 1)
   {
      my @qs_array = ("?") x (scalar @accs);
      $qs = join (", ", @qs_array);
   }
   my $sql_string = "SELECT acc, taxid FROM acc_taxid_map where acc in ( $qs )";
   # warn "$sql_string\n";
   my $sth = $dbh->prepare( $sql_string );
   $sth->execute(@accs);
   # warn "ACCS: @accs\n";
   
   # iterate through rows of mysql output
   # need to do this because:
   #
   # (1) some ACCs might not return TAXIDs
   # (2) results not necessarily in order of input
   #
   while ( my ($acc, $taxid) = $sth->fetchrow_array())
   {
      # warn "$acc->$taxid\n";
      $acc_taxid_map{$acc} = $taxid;
   }

   # create array to return
   # will return an array that is 1:1 with input array
   foreach my $acc (@accs)
   {
      push @taxids, $acc_taxid_map{$acc};
   }

   return @taxids;
}



# PERL packages must return a true value
1;
