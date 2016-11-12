#!/usr/local/bin/perl -w

package lzw;

#
# Script copied from http://www.merriampark.com/ldperl.htm
#
# How to use:
# my @compressed = compress('TOBEORNOTTOBEORTOBEORNOT');
# print "@compressed\n";
# my $decompressed = decompress(@compressed);
# print "$decompressed\n";
#

use strict;

our @EXPORT = qw (LZWSize LZWRatio);

sub LZWSize
{
   # print "compressing $_[0]\n";
   # my @c = compress ($_[0]);
   # my $s = scalar (@c);
   # print "size: $s\n" ;
   return scalar (compress ($_[0]) );
}

sub LZWRatio
{
   my $string = $_[0];
   my @compressed_string = compress ($string);
   my $compressed_string_length = scalar @compressed_string;
   # print "$string\n$compressed_string\n\n";
   my $ratio = $compressed_string_length / length ($string);
   return $ratio;
}

# Compress a string to a list of output symbols.
sub compress {
    my $uncompressed = shift;
 
    # Build the dictionary.
    my $dict_size = 256;
    my %dictionary = map {chr $_ => chr $_} 0..$dict_size-1;
 
    my $w = "";
    my @result;
    foreach my $c (split '', $uncompressed) {
        my $wc = $w . $c;
        if (exists $dictionary{$wc}) {
            $w = $wc;
        } else {
            push @result, $dictionary{$w};
            # Add wc to the dictionary.
            $dictionary{$wc} = $dict_size;
            $dict_size++;
            $w = $c;
        }
    }
 
    # Output the code for w.
    if ($w) {
        push @result, $dictionary{$w};
    }
    return @result;
}
 
# Decompress a list of output ks to a string.
sub decompress {
    my @compressed = @_;
 
    # Build the dictionary.
    my $dict_size = 256;
    my %dictionary = map {chr $_ => chr $_} 0..$dict_size-1;
 
    my $w = shift @compressed;
    my $result = $w;
    foreach my $k (@compressed) {
        my $entry;
        if (exists $dictionary{$k}) {
            $entry = $dictionary{$k};
        } elsif ($k == $dict_size) {
            $entry = $w . substr($w,0,1);
        } else {
            die "Bad compressed k: $k";
        }
        $result .= $entry;
 
        # Add w+entry[0] to the dictionary.
        $dictionary{$dict_size} = $w . substr($entry,0,1);
        $dict_size++;
 
        $w = $entry;
    }
    return $result;
}
 


1;
