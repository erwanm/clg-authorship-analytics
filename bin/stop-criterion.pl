#!/usr/bin/perl

# EM 04/15


use strict;
use warnings;
use Getopt::Std;

my $progName="stop-criterion.pl";
my $colNo=1;

sub usage {
	my $fh = shift;
	$fh = *STDOUT if (!defined $fh);
	print $fh "Usage: stop-criterion.pl [options] <nb windows> <window size>\n";
	print $fh "\n";
	print $fh "   Reads a list of files from STDIN;\n";
	print $fh "   Prints '1' if and only if the <nb windows> last consecutive sets of <window size>\n";
	print $fh "   files do not show any increase in their average values by window. Prints\n";
	print $fh "   '0' otherwise.\n";
	print $fh "   More precisely: checks whether every window after the first one (oldest) \n";
	print $fh "   has a lower average than the first one. If yes, return 1.\n";
	print $fh "\n";
	print $fh "OPTIONS:\n";
	print $fh "  -h help message\n";
	print $fh "  -c <col no> default: $colNo\n";
	print $fh "  -l <file> write detailed results by window to the file.\n";
	print $fh "\n";
}

# PARSING OPTIONS
my %opt;
getopts('hc:l:', \%opt ) or  ( print STDERR "Error in options" &&  usage(*STDERR) && exit 1);
usage($STDOUT) && exit 0 if $opt{h};
print STDERR "2 argument expected but ".scalar(@ARGV)." found: ".join(" ; ", @ARGV)  && usage(*STDERR) && exit 1 if (scalar(@ARGV) != 2);
my $nbWindows=$ARGV[0];
my $windowSize=$ARGV[1];

$colNo=$opt{c} if (defined($opt{c}));
my $detailFile=$opt{l};
$colNo--;

my @files;
while (<STDIN>) {
    chomp;
    push(@files,$_);
}

if (scalar(@files) < $nbWindows * $windowSize) {
    print "0\n";
    if (defined($detailFile)) {
	open(LOG, ">", $detailFile) or die "$progName: cannot open '$detailFile' for writing";
	print LOG "\n";
	close(LOG);
    }
} else {
    my @avgByWindow;
    if (defined($detailFile)) {
	open(LOG, ">", $detailFile) or die "$progName: cannot open '$detailFile' for writing";
	print LOG "first\twindow\tmean\n";
    }
    my $index=scalar(@files)-1;
    for (my $windowNo=$nbWindows; $windowNo>0; $windowNo--) {
	my $sumAll=0;
	for (my $i=0; $i<$windowSize;$i++) {
	    my $sumThis = 0;
	    my $f = $files[$index];
	    my $nbValues=0;
	    open(FH, "<", $f) or die "$progName: cannot open res file '$f'";
	    while (<FH>) {
		chomp;
		my @cols = split;
		my $v = $cols[$colNo];
		$sumThis += $v;
		$nbValues++;
	    }
	    close(FH);
	    $sumAll += $sumThis / $nbValues ;
	    $index--;
	}
	$avgByWindow[$windowNo]  = $sumAll / $windowSize;
	print LOG "$files[$index+1]\t$windowNo\t$avgByWindow[$windowNo]\n" if (defined($detailFile));
    }
    close(LOG) if (defined($detailFile));
    for (my $windowNo=2; $windowNo<=$nbWindows; $windowNo++) {
	if ($avgByWindow[1] < $avgByWindow[$windowNo]) {
	    print "0\n";
	    exit 0;
	}
    }
    print "1\n";
 }

