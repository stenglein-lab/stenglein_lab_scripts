#!/usr/bin/perl

# given a GI, return its description
# need to search by NCBI db (nuc or prot, so have to specify)
#
# Mark Stenglein Sept 21, 2012

package fetch_gi_description;

use base 'Exporter';
our @EXPORT = qw(fetch_gi_description);

use strict;
use Getopt::Long;
use fetch_gi_esummary;
use LWP::Simple;
use Time::HiRes;


# input: an array of NCBI GIs
# output: a reference to a hash of GI->descriptions
sub fetch_gi_description
{
   my @gis = @_;
   # warn "fetching descriptions for GIs: @gis\n"; 

   my $result = undef;
   my %gi_desc_hash = ();
   
   if (scalar @gis == 0) { return \%gi_desc_hash; }

   # my @dbs_to_try = qw (protein nucleotide);

   # it looks like searching nucleotide db w/ protein GIs works for eSummary
   my @dbs_to_try = qw (nucleotide);

   foreach my $db (@dbs_to_try)
   {
      $result = fetch_gi_esummary(@gis, $db);
      # warn "esummary: result $result\n";

      # parse XML results manually
      
      open (my $result_fh, "<", \$result) or die ("error parsing results from NCBI\n"); 
      
      my $gi = undef;
      my $description = undef;
      
      while (<$result_fh>)
      {
         chomp;
         if (/<Id>(\S+)<\/Id>/)
         {
            $gi = $1;
            $description = undef;
         }
         elsif (/<Item Name="Title" Type="String">(.+)<\/Item>/)
         {
            $description = $1;
            # warn "$gi\t$description\n";
            $gi_desc_hash{$gi} = $description;
         }
      }
   }

   return \%gi_desc_hash;
}

#
# retreive the results of a esummary query from an NCBI database
#
# Mark Stenglein
# September 21, 2012
sub fetch_gi_esummary
{
   my $db = pop (@_);
   my @ids = ();
   my $id_count = 0;
   my $result = undef;

   foreach my $id (@_)
   {
      push @ids, $id;
      $id_count++;

      # fetch 200 at a time
      if ($id_count % 200 == 0)
      {
         ## warn "$id_count ";
         $result .= fetch_one_batch(@ids, $db);
         @ids = ();

         # wait a third of a sec to avoid overloading NCBI servers (per their request)
         Time::HiRes::usleep(333333);
      }
   }
   if (scalar @ids > 0)
   {
      # fetch remaining gis
      $result .= fetch_one_batch(@ids, $db);
   }

   return $result;
}

# here, actually fetch data from NCBI
sub fetch_one_batch()
{
   my $db = pop (@_);
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
}

