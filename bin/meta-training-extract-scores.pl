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
# Feb 22: fixed bug related to order of cases: used to have scores only as a map %scores
#         with the final scores printed by sorted cases, except that if the input cases
#         were not sorted this would result in completely wrong order since the cases
#         ids are not printed in the output.
my @casesOrderedSameAsInput;

open(FH, "<", $casesFile) or die "$progName error: cannot open '$casesFile'";
while (<FH>) {
    chomp;
    my @cols = split('\t');
    if (scalar(@cols) == 1) { # no tab; if 2 cols found with tab it's already ok
	@cols = split(" ");
	if (scalar(@cols)==2) {
	    if (length($cols[1])>1) { # DANGER, ASSUMING SINGLE CHAR = TRUE ANSWER
		@cols = ($cols[0]." ".$cols[1], undef);
	    } # otherwise <case> <answer>
	} else {
	    if (scalar(@cols)>2) { 
		die "$progName error: cannot recognize format in cases file.";
	    } # otherwise no space (and no tab) -> ok just case id
	}
    }
    warn "Warning: id '$cols[0]' found twice in '$casesFile'" if (defined($casesMaybeTruth{$cols[0]}));
    $casesMaybeTruth{$cols[0]} = defined($cols[1]) ? $cols[1] : "?" ;
    push(@casesOrderedSameAsInput,$cols[0]);
}
close(FH);
my $nbCases = scalar(keys %casesMaybeTruth);

my %scores;
foreach my $param (keys %$config) {
    if (($param =~ m/^indivConf_/) && ($config->{$param} != 0)) {
	my ($confId)= ($param =~ m/^indivConf_(.*)/);
#	print STDERR "$progName DEBUG confId=$confId\n";
	my $file = "$inputDir/apply-strategy-configs/$confId.answers";
#	print STDERR "DEBUG $file\n";
	open(FH, "<", $file) or die "$progName error: cannot open '$file'";
	my $nb=0; # for sanity check
	while (<FH>) {
	    chomp;
	    my $l = $_;
	    my ($case, $score) = ($l =~ m/^(.+)\s(\S+)$/);
#	    print STDERR "DEBUG reading case='$case', score='$score'\n";
	    if (defined($casesMaybeTruth{$case})) {
#		print STDERR "$progName DEBUG scores{$case}->{$confId} = $score\n";
		if (!defined($scores{$case}->{$confId})) { # duplicate case
		    $scores{$case}->{$confId} = $score;
		    $nb++;
		}
	    }
	}
	foreach my $case (keys %casesMaybeTruth) {
	    if (!defined($scores{$case}->{$confId})) {
		die "Error: missing case '$case' in '$file'";
	    }
	}
#	die "$progName error: found $nb cases in '$file' among the $nbCases expected in '$casesFile'" if ($nb != $nbCases); 
	close(FH);
    }
}

foreach my $case (@casesOrderedSameAsInput) {
    my @features;
    foreach my $confId (sort keys %{$scores{$case}}) {
	push(@features, $scores{$case}->{$confId});
    }
#    push(@features, $casesMaybeTruth{$case}); # done in train-test, not here
    print join("\t", @features)."\n";
}


