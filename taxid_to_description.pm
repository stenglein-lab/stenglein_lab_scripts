#!/usr/bin/perl

# 
# The functions in this package return descriptions
# corresponding to NCBI TAXIDs
#
# Mark Stenglein, June 9, 2011
#

package taxid_to_description;

use strict;

use base 'Exporter';
our @EXPORT = qw(taxid_to_description taxid_to_scientific_name taxid_to_common_name);

# NCBI Taxonomy DB flatfile locations
my $names_dmp_file = "/home/databases/NCBI_Taxonomy/names.dmp";
my $fh = undef;
my %scientific_names = ();
my %common_names = ();

sub parse_names_file
{
   # only open and parse the file once
   if (!$fh)
   {
      # warn "parsing NCBI taxonomy names db file\n";
      open ($fh, "<", $names_dmp_file) 
            or die ("error: couldn't open NCBI taxonomic names database file $names_dmp_file\n$!\n");
      my @fields = ();

      # store the TAXID->scientific name map in a hash
      NAME_LINE: while (<$fh>)
      {
         chomp;
         if (/scientific name/)
         {
            # weird delimiters in this file (annoying)...
            @fields = split /\t\|\t/;
            $scientific_names{$fields[0]} = $fields[1];
         }
         if (/common name/)
         {
            # weird delimiters in this file (annoying)...
            @fields = split /\t\|\t/;
            $common_names{$fields[0]} = $fields[1];
         }
      }
   }
}

sub taxid_to_scientific_name
{
   my @taxids = @_;
   my @descriptions = ();

   parse_names_file;

   foreach my $taxid (@taxids)
   {
      my $description = $scientific_names{$taxid};
      push @descriptions, $description;
   }
   return @descriptions;
}

sub taxid_to_common_name
{
   my @taxids = @_;
   my @descriptions = ();

   parse_names_file;

   foreach my $taxid (@taxids)
   {
      my $description = $common_names{$taxid};
      push @descriptions, $description;
   }
   return @descriptions;
}

sub taxid_to_description
{
   return taxid_to_scientific_name(@_);
}


# PERL packages must return a true value
1;
