#!/usr/bin/perl

#
# retreive the results of a esummary query from an NCBI database
#
# Mark Stenglein
# September 21, 2012

package fetch_gi_esummary;

## use LWP::Simple;
use Time::HiRes;
use strict;

use base 'Exporter';
our @EXPORT = qw(fetch_gi_nucleotide_esummary fetch_gi_protein_summary);

my $db=undef;
 
sub fetch_gi_nucleotide_esummary
{
   $db = "nucleotide";
   return fetch_gi_esummary(@_);
}

sub fetch_gi_protein_esummary
{
   $db = "protein";
   return fetch_gi_esummary(@_);
}

sub fetch_gi_esummary
{
   my @ids = ();
   my $id_count = 0;
   my $result = undef;

   foreach my $id (@_)
   {
      push @ids, $id;
      $id_count++;

      # fetch 500 at a time
      if ($id_count % 500 == 0)
      {
         warn "$id_count ";
         $result .= fetch_one_batch(@ids);
         @ids = ();
      }
   }
   if (scalar @ids > 0)
   {
      # fetch remaining gis
      $result .= fetch_one_batch(@ids);
   }

   return $result;
}

# here, actually fetch data from NCBI
sub fetch_one_batch()
{
   my @ids = @_;

   # construct url
   my $base_url = "http://www.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=$db&tool=fetch_gi_summary&email=markstenglein_at_yahoo.com";
   my $id_url = "&id=";
   foreach my $id (@ids)
   {
      $id_url .= "$id".","
   }
   my $url = $base_url.$id_url;

   # warn "URL: $url\n";

   # here is actual interweb transaction
   my $efetch_result = get($url);

   # simply dump the data to stdout
   # print "$efetch_result\n"; 

   return $efetch_result;

   # code below loads result into an XML datastructure
   # my $xs = XML::Simple->new(forcearray=>1);
   # my $ref = $xs->XMLin($efetch_result);

   # wait a third of a sec to avoid overloading NCBI servers (per their request)
   Time::HiRes::usleep(333333);
}

return 1;
