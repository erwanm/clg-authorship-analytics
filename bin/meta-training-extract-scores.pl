#!/usr/bin/perl



use strict;
use warnings;
use Getopt::Std;
use CLGTextTools::Commons qw/readConfigFile/;
use Carp;
#use Math::CDF;
#use Math::Trig;
#use Data::Dumper;

my $progName="meta-training-extract-scores.pl";
my $NaN = "NA";
my $startAtCol=1;

sub usage {
	my $fh = shift;
	$fh = *STDOUT if (!defined $fh);
	print $fh "Usage: $progName [options] <cases file> <input dir> <config file>\n";
	print $fh "\n";
	print $fh "  <input dir> contains subdir 'apply-strategy-configs' properly initialized\n";
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
print STDERR "3 arguments expected but ".scalar(@ARGV)." found: ".join(" ; ", @ARGV)  && usage(*STDERR) && exit 1 if (scalar(@ARGV) != 3);

my $casesFile = $ARGV[0];
my $inputDir= $ARGV[1];
my $configFile = $ARGV[2];

die "$progName error: dir '$inputDir' does not contain subdir 'apply-strategy-configs'" if (! -d "$inputDir/apply-strategy-configs");
my $config = readConfigFile($configFile);

my %casesMaybeTruth;
open(FH, "<", $casesFile) or die "$progName error: cannot open '$casesFile'";
while (<FH>) {
    chomp;
    my @cols = split;
    $casesMaybeTruth{$cols[0]} = defined($cols[1]) ? $cols[1] : "?" ;
}
close(FH);
my $nbCases = scalar(keys %casesMaybeTruth);

my %scores;
foreach my $param (keys %$config) {
    if (($param =~ m/^indivConf_/) && ($config->{$param} != 0)) {
	my ($confId)= ($param =~ m/^indivConf_(.*)/);
#	print STDERR "$progName DEBUG confId=$confId\n";
	my $file = "$inputDir/apply-strategy-configs/$confId.answers";
	open(FH, "<", $file) or die "$progName error: cannot open '$file'";
	my $nb=0; # for sanity check
	while (<FH>) {
	    chomp;
	    my ($case, $score) = split;
	    if (defined($casesMaybeTruth{$case})) {
#		print STDERR "$progName DEBUG scores{$case}->{$confId} = $score\n";
		$scores{$case}->{$confId} = $score;
		$nb++;
	    }
	}
	die "$progName error: found only $nb cases in '$file' among the $nbCases expected in '$casesFile'" if ($nb != $nbCases); 
	close(FH);
    }
}

foreach my $case (sort keys %scores) {
    my @features;
    foreach my $confId (sort keys %{$scores{$case}}) {
	push(@features, $scores{$case}->{$confId});
    }
#    push(@features, $casesMaybeTruth{$case}); # done in train-test, not here
    print join("\t", @features)."\n";
}


