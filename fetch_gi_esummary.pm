#!/usr/bin/perl

#
# retreive the results of a esummary query from an NCBI database
#
# Mark Stenglein
# September 21, 2012
#

package fetch_gi_esummary;

# use LWP::Simple;
use Time::HiRes;
use strict;

use base 'Exporter';
our @EXPORT = qw(fetch_gi_nucleotide_esummary fetch_gi_protein_esummary fetch_gi_taxonomy_esummary);

my $db=undef;
my $counter = 0;
my $verbose = 1;
 
sub fetch_gi_taxonomy_esummary
{
   $db = "taxonomy";
   return fetch_gi_esummary(@_);
}
 
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
         # warn "$id_count ";
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

	warn "$counter\n";
	$counter += 1;

   # construct url
   my $base_url = "https://www.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=$db&tool=fetch_gi_summary&email=markstenglein_at_yahoo.com";
   my $id_url = "&id=";
   foreach my $id (@ids)
   {
      $id_url .= "$id".","
   }
   my $url = $base_url.$id_url;

	if ($verbose)
	{
      warn "URL: $url\n";
	}

   # here is actual interweb transaction
   # my $efetch_result = get($url);
   my $efetch_result = `curl -s "$url"`;

	if ($verbose)
	{
	   warn "$efetch_result\n";
	}

	#
	# If we get a returned string like this:
	#
   # <ERROR>Otherdb uid="146411794" db="nuccore" term="146411794"</ERROR>
   #	
	# it means we queried the wrong db.  Try query once more w/ right db
	#
	# We are assuming all IDs are from same db
	#
	 
	my $new_db = undef;

   # <ERROR>Otherdb uid="146411794" db="nuccore" term="146411794"</ERROR>
	if ($efetch_result =~ /<ERROR>Otherdb uid="(\d+)" db="(\S+)"/)
	{
		$new_db = $2;

      # construct url
      my $base_url = "http://www.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=$new_db&tool=fetch_gi_summary&email=markstenglein_at_yahoo.com";
      my $id_url = "&id=";
      foreach my $id (@ids)
      {
         $id_url .= "$id".","
      }
      my $url = $base_url.$id_url;

      # warn "Retry URL: $url\n";

      # wait a third of a sec to avoid overloading NCBI servers (per their request)
      Time::HiRes::usleep(333333);

      # try again
      $efetch_result = get($url);
	}

   # warn "$efetch_result\n"; 

   return $efetch_result;

   # code below loads result into an XML datastructure
   # my $xs = XML::Simple->new(forcearray=>1);
   # my $ref = $xs->XMLin($efetch_result);

   # wait a third of a sec to avoid overloading NCBI servers (per their request)
   Time::HiRes::usleep(333333);
}

return 1;
