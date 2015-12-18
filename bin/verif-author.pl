#!/usr/bin/perl

# EM June 15
#
#


use strict;
use warnings;
use Carp;
use Log::Log4perl;
use Getopt::Std;
use CLGTextTools::ObsCollection;
use CLGTextTools::Logging qw/@possibleLogLevels/;
use CLGTextTools::DocProvider;
use CLGTextTools::Commons /readConfigFile/;
use CLGAuthorshipAnalytics::Verification::VerifStrategy qw/newVerifStrategyFromId/;

my $progNamePrefix = "verif-author"; 
my $progname = "$progNamePrefix.pl";

my $defaultLogFilename = "$progNamePrefix.log";



sub usage {
	my $fh = shift;
	$fh = *STDOUT if (!defined $fh);
	print $fh "\n"; 
	print $fh "Usage: $progname [options] <config file|parameters> [<fileA1:..:fileAn> <fileB1:..:fileBm>]\n";
	print $fh "\n";
	print $fh "  Applies an author verification algorithm to:\n";
	print $fh "    - a pair of sets of documents (fileA1,..,fileAn) vs. (fileB1,..,fileBm) if\n";
	print $fh "      3 arguments are supplied.\n";
	print $fh "    - a series of pairs of sets of documents read from STDIN if only one \n";
	print $fh "      arg is supplied. Format: one pair <fileA1:..:fileAn> <fileB1:..:fileBm>\n";
	print $fh "       on every line.\n";
	print $fh "  The strategy id and the strategy parameters are obtained from the first argument:\n";
	print $fh "    - if <config file|parameters> is a valid path to a non-empty file, then it is\n";
	print $fh "      interpreted as a config file (one paramter by line, format: 'param=value')\n";
	print $fh "    - otherwise, <config file|parameters> is interpreted as a list of \n";
	print $fh "      parameter/value pairs: (quotes are needed if several parameters)\n";
	print $fh "        'param1=val1;param2=val2;..;paramN=valN'\n";
	print $fh "\n";
	print $fh "  Main options:\n";
	print $fh "     -h print this help message\n";
	print $fh "     -l <log config file | Log level> specify either a Log4Perl config file\n";
	print $fh "        or a log level (".join(",", @possibleLogLevels)."). \n";
	print $fh "        By default there is no logging at all.\n";
	print $fh "     -L <Log output file> log filename (useless if a log config file is given).\n";
	print $fh "     -m by default input files are loaded into memory until the end of the script,\n";
	print $fh "        so that the same file does not have to be loaded several times. This option\n";
	print $fh "        prevents that behaviour, in order to save memory space when a lot of input\n";
	print $fh "        files have to be processed (useful only when reading input files from STDIN).\n";



	print $fh "     -s <singleLineBreak|doubleLineBreak> by default all the text is collated\n";
	print $fh "        togenther; this option allows to specify a separator for meaningful units,\n";
	print $fh "        typically sentences or paragraphs.";
	print $fh "        (applies only to CHAR and WORD observations).\n";
	print $fh "     -t pre-tokenized text, do not perform default tokenization\n";
	print $fh "        (applies only to WORD observations).\n";
	print $fh "     -r <resourceId1:filename2[;resourceId2:filename2;...]> vocab resouces files\n";
	print $fh "        with their ids.\n";
	print $fh "\n";
	print $fh "\n";
	print $fh "\n";
}


# PARSING OPTIONS
my %opt;
getopts('hl:L:t:r:s:', \%opt ) or  ( print STDERR "Error in options" &&  usage(*STDERR) && exit 1);
usage(*STDOUT) && exit 0 if $opt{h};
print STDERR "Either 1 or 3 arguments expected, but ".scalar(@ARGV)." found: ".join(" ; ", @ARGV)  && usage(*STDERR) && exit 1 if ((scalar(@ARGV) != 1) && (scalar(@ARGV) != 3));

my $configFileOrParams = $ARGV[0];
my ($docsA, $docsB) = ($ARGV[1], $ARGV[2]);

# init log
my $logger;
if ($opt{l} || $opt{L}) {
    CLGTextTools::Logging::initLog($opt{l}, $opt{L} || $defaultLogFilename);
    $logger = Log::Log4perl->get_logger(__PACKAGE__) ;
}


# strategy parameters
my $strategyParams;
if (-s $configFileOrParams) {
    $strategyParams = readConfigFile($configFileOrParams);
} else {
    my @pairs = split(";", $configFileOrParams);
    foreach my $pair (@pairs) {
	my ($p, $v) = ($pair =~ m/^([^=]+)=(.*)$/);
	$strategyParams{$p} = $v;
    }
}

# extract input sets of documents
my @docsPairs;
if (defined($docsA) & defined($docsB)) {
    my @setA = split(":", $docsA);
    my @setB = split(":", $docsB);
    push(@docsPairs, [ \@setA, \@setB ]);
} else {
    while (my $line = <STDIN>) {
	chomp($line);
	my @pair = split("\s+", $line);
	my @setA = split(":", $pair[0]);
	my @setB = split(":", $pair[1]);
	push(@docsPairs, [ \@setA, \@setB ]);
    }
}


# initiate DocProvider objects for all documents
my %docs;
foreach my $pair (@docsPairs) {
    my ($docs1, $docs2)  = @$pair;
    
}






# text format parameters
my $formattingSeparator = $opt{s};
my $performTokenization = 0 if ($opt{t});
my $resourcesStr = $opt{r};
my $vocabResources;
if ($opt{r}) {
    $vocabResources ={};
    my @resourcesPairs = split (";", $resourcesStr);
    foreach my $pair (@resourcesPairs) {
	my ($id, $file) = split (":", $pair);
#	print STDERR "DEBUG pair = $pair ; id,file = $id,$file\n";
	$vocabResources->{$id} = $file;
    }
}



my $strategy = newVerifStrategyFromId($strategyParams->{strategy}, $strategyParams);



my %params;
$params{logging} = 1 if ($logger);

my @obsTypes = split(":", $obsTypesList);
$params{obsTypes} = \@obsTypes;
$params{wordTokenization} = $performTokenization;
$params{formatting} = $formattingSeparator;
$params{wordVocab} = $vocabResources if (defined($vocabResources));

foreach my $file (@files) {
#    my $textLines = ($file eq "-") ? readLines(*STDIN,0,$logger) : readTextFileLines($file,0,$logger);
    my $data = CLGTextTools::ObsCollection->new(\%params);
    my $doc = CLGTextTools::DocProvider->new({ logging => $params{logging}, obsCollection => $data, obsTypesList => $params{obsTypes}, filename => $file, useCountFiles => 1});
    $doc->getObservations();
}
