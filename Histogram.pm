#!/usr/bin/perl

# a package with histogram-related functions
# 
# Mark Stenglein, June 23, 2011

package Histogram;

use base 'Exporter';
our @EXPORT = qw(histogram_hash histogram_hash_defined_bins);

use strict;

my $default_number_bins = 20;

# This function takes an array of numeric values
# and returns a reference to a hash containing 
# a histogram of the values
# 
# arguments: $_[0] -> reference to an array of values hash
#            $_[1] -> number of bins [optional, default = 20]
#
sub histogram_hash
{
   my $values_array_ref = shift @_;
   my @values = @$values_array_ref;
   my $bins = shift @_;
   if (!defined $bins)
   {
      $bins = $default_number_bins;
   }
   my %histo = ();
   my $num_values = scalar @values;

   if ($num_values == 0)
   {
      return undef;
   }

   my $min_val = undef;
   my $max_val = undef;
   foreach my $v (@values)
   {
      if ((!defined $min_val)||($v < $min_val))
      {
         $min_val = $v;
      }
      if ((!defined $max_val)||($v > $max_val))
      {
         $max_val = $v;
      }
   }
   my $bin_width = ($max_val - $min_val) / $bins;

   # treat special case where all the values are the 
   # same (or there is only a single value)
   if ($bin_width == 0)
   {
      $histo{$values[0]} = $num_values;
      return \%histo;
   }

   # initialize histogram
   for (my $i = 0; $i < $bins; $i++)
   {
      my $bin_bottom = $min_val + ($i * $bin_width);
      $histo{$bin_bottom} = 0;
   }

   VALUE: foreach my $v (@values)
   {
      for (my $i = 0; $i < $bins; $i++)
      {
         my $bin_bottom = $min_val + ($i * $bin_width);
         my $bin_top = $bin_bottom + $bin_width;
         if (($v >= $bin_bottom) && ($v < $bin_top))
         {
            $histo{$bin_bottom} += 1;
            next VALUE;
         }
      }
   }
   return \%histo;
}

sub histogram_hash_defined_bins
{
   my $input_hash_ref = shift;
   my @values = @{$$input_hash_ref{values}};
   my $bin_min = $$input_hash_ref{bin_min};
   my $bin_max = $$input_hash_ref{bin_max};
   my $bin_width = $$input_hash_ref{bin_width};

   if ((!defined $bin_width)||($bin_width <= 0)||(!defined $bin_min)||(!defined $bin_max))
   {
      die ("error: invalid arguments passed to histogram_hash_defined_bins $!\n");
   }

   my $bins = ($bin_max - $bin_min) / $bin_width;
   if ($bins != int($bins))
   {
      die ("error: there should be an integer number of bin widths ($bin_width) between min ($bin_min) and max ($bin_max). $!\n");
   }

   my %histo = ();
   my $num_values = scalar @values;

   if ($num_values == 0)
   {
      return undef;
   }

   my $first_bin = undef;
   my $last_bin = undef;
   # initialize histogram
   for (my $i = 0; $i < $bins; $i++)
   {
      my $bin_bottom = $bin_min + ($i * $bin_width);
      $histo{$bin_bottom} = 0;
      if ($i == 0)
      {
         $first_bin = $bin_bottom;   
      }
      if ($i == ($bins - 1))
      {
         $last_bin = $bin_bottom;   
      }
   }

   VALUE: foreach my $v (@values)
   {
      for (my $i = 0; $i < $bins; $i++)
      {
         my $bin_bottom = $bin_min + ($i * $bin_width);
         my $bin_top = $bin_bottom + $bin_width;
         if ($v <= $bin_min)
         {
            $histo{$first_bin} += 1;
            next VALUE;
         }
         elsif ($v >= $bin_max)
         {
            $histo{$last_bin} += 1;
            next VALUE;
         }
         elsif (($v >= $bin_bottom) && ($v < $bin_top))
         {
            $histo{$bin_bottom} += 1;
            next VALUE;
         }
      }
   }
   return \%histo;
}

# perl packages must return true value
1

