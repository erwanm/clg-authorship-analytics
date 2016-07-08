#!/usr/bin/perl



use strict;
use warnings;
use Getopt::Std;
use Carp;

my $progName="score-to-confidence-label.pl";

sub usage {
	my $fh = shift;
	$fh = *STDOUT if (!defined $fh);
	print $fh "Usage: $progName [options] <truth file [0,1]> <prediction file [0,1]>\n";
	print $fh "\n";
	print $fh "\n";
	print $fh "\n";
	print $fh "   Options:\n";
	print $fh "     -h print this help\n";
	print $fh "\n";
}




# PARSING OPTIONS
my %opt;
getopts('h', \%opt ) or  ( print STDERR "Error in options" &&  usage(*STDERR) && exit 1);
usage($STDOUT) && exit 0 if $opt{h};
print STDERR "2 arguments expected but ".scalar(@ARGV)." found: ".join(" ; ", @ARGV)  && usage(*STDERR) && exit 1 if (scalar(@ARGV) != 2);
my $goldFile=$ARGV[0];
my $predictedFile=$ARGV[1];

#print STDERR "DEBUG: goldFile='$goldFile'\n";

open(GOLD, "<", $goldFile) or die "$progName: cannot open '$goldFile'";
open(PRED, "<", $predictedFile) or die "$progName: cannot open '$predictedFile'";

my @gold=<GOLD>;
my @pred=<PRED>;
close(GOLD);
close(PRED);
die "$progName error: Different number of lines between '$goldFile' and '$predictedFile'" if (scalar(@gold) != scalar(@pred));
for (my $i=0; $i< scalar(@gold); $i++) {
    chomp($gold[$i]);
    chomp($pred[$i]);
#    print STDERR "DEBUG gold[$i] = '".$gold[$i]."'\n";
    die "$progName error: gold is neither 0 or 1 line $i in '$goldFile'" if (!defined($gold[$i]) || ($gold[$i] eq "") || (($gold[$i]!=0) && ($gold[$i] != 1)));
    print "CONFIDENT\n" if ( (($gold[$i]==1) && ($pred[$i]>0.5)) || (($gold[$i]==0) && ($pred[$i]<0.5)));
    print "UNSURE\n" if ( (($gold[$i]==1) && ($pred[$i]<=0.5)) || (($gold[$i]==0) && ($pred[$i]>=0.5)));
}
