#!/usr/bin/perl

# EM June 15
#
#


use strict;
use warnings;
use Carp;
use Log::Log4perl;
use Getopt::Std;
use Data::Dumper;
use CLGTextTools::ObsCollection;
use CLGTextTools::Logging qw/@possibleLogLevels confessLog warnLog/;
use CLGTextTools::DocProvider;
use CLGTextTools::Commons qw/readConfigFile parseParamsFromString readObsTypesFromConfigHash/;
use CLGAuthorshipAnalytics::Verification::VerifStrategy qw/newVerifStrategyFromId/;


my $progNamePrefix = "verif-author"; 
my $progname = "$progNamePrefix.pl";

my $defaultLogFilename = "$progNamePrefix.log";



sub usage {
	my $fh = shift;
	$fh = *STDOUT if (!defined $fh);
	print $fh "\n"; 
	print $fh "Usage: $progname [options] <config file> [<fileA1:..:fileAn> <fileB1:..:fileBm>]\n";
	print $fh "\n";
	print $fh "  Applies an author verification algorithm to:\n";
	print $fh "    - a pair of sets of documents (fileA1,..,fileAn) vs. (fileB1,..,fileBm) if\n";
	print $fh "      3 arguments are supplied.\n";
	print $fh "    - a series of pairs of sets of documents read from STDIN if only one \n";
	print $fh "      arg is supplied. Format: one pair <fileA1:..:fileAn> <fileB1:..:fileBm>\n";
	print $fh "       on every line.\n";
	print $fh "  The strategy id and the strategy parameters are read from <config file>,\n";
	print $fh "    - except if '-s' is used (see below).\n";
	print $fh "      The config file format is one parameter by line: 'param=value'.\n";
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
	print $fh "     -c use count files (see CLGTextTools::DocProvider)\n";

#	print $fh "     -s <singleLineBreak|doubleLineBreak> by default all the text is collated\n";
#	print $fh "        togenther; this option allows to specify a separator for meaningful units,\n";
#	print $fh "        typically sentences or paragraphs.";
#	print $fh "        (applies only to CHAR and WORD observations).\n";
#	print $fh "     -t pre-tokenized text, do not perform default tokenization\n";
#	print $fh "        (applies only to WORD observations).\n";
	print $fh "     -v <resourceId1=filename1[;resourceId2=filename2;...]> vocab resouces files\n";
	print $fh "        with their ids. Can also be provided in the config as:\n";
	print $fh "          wordVocab.resourceId=filename\n";
	print $fh "     -d <datasetsResourcesPath> for impostors method.\n";
	print $fh "     -s interpret the first argument <config file> as a string which contains a\n";
	print $fh "        list of parameter/value pairs: (quotes are needed if several parameters)\n";
	print $fh "        'param1=val1;param2=val2;..;paramN=valN'\n";
	print $fh "     -p <dir> if specified, for every case processed the raw scores table is written\n";
	print $fh "        to file <dir>/<NNN>.scores, where <NNN> is the number of the case in the\n";
	print $fh "        input list (if reading input cases from STDIN) or '001' (if single case).\n";
	print $fh "     -i <r|w|rw> allow verif strategy to read/write/both to/from resources disk;\n";
	print $fh "        this is currently only used by the impostors strategy for pre-sim values.\n";
	print $fh "\n";
}


# PARSING OPTIONS
my %opt;
getopts('hl:L:mcv:sd:p:i:', \%opt ) or  ( print STDERR "Error in options" &&  usage(*STDERR) && exit 1);
usage(*STDOUT) && exit 0 if $opt{h};
print STDERR "Either 1 or 3 arguments expected, but ".scalar(@ARGV)." found: ".join(" ; ", @ARGV)  && usage(*STDERR) && exit 1 if ((scalar(@ARGV) != 1) && (scalar(@ARGV) != 3));

my $configFileOrParams = $ARGV[0];
my ($docsA, $docsB) = ($ARGV[1], $ARGV[2]);

my $dontLoadAllFiles = $opt{m};
my $useCountFiles = $opt{c};
my $vocabResourcesStr = $opt{v};
my $configAsString=$opt{s};
my $datasetsResourcesPath=$opt{d};
my $printScoreDir = $opt{p};
my $strategyDiskAccess = $opt{i};

# init log
my $logger;
if ($opt{l} || $opt{L}) {
    CLGTextTools::Logging::initLog($opt{l}, $opt{L} || $defaultLogFilename);
    $logger = Log::Log4perl->get_logger(__PACKAGE__) ;
}


# strategy parameters
my $config;
if (defined($configAsString)) {
    $config = parseParamsFromString($configFileOrParams);
} else {
    if (-s $configFileOrParams) {
	$config = readConfigFile($configFileOrParams);
    } else {
	confessLog($logger, "Cannot open config file '$configFileOrParams'");
    }
}

$config->{logging} = $opt{l} || $opt{L};

# word vocab resources
if ($vocabResourcesStr) {
    $config->{wordVocab} = {} if (!defined($config->{wordVocab})); # this way it is possible to define some resources in the config file and some other on the command line
    parseParamsFromString($vocabResourcesStr, $config->{wordVocab}, $logger);
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
	my @pair = split(/\s+/, $line);
	my @setA = split(":", $pair[0]);
	my @setB = split(":", $pair[1]);
	push(@docsPairs, [ \@setA, \@setB ]);
    }
}

confessLog($logger, "Parameter 'strategy' is undefined") if (!defined($config->{strategy}));
$config->{datasetResources} = $datasetsResourcesPath;
# TODO this "disk access" system does not seem the right way to proceed, but I don't see any better option atm
#      currently used only for pre-sim values for the impostors strategy
#     rationale: this script is not supposed to deal with strategy-specific options, but on the other hand
#                reading/writing to disk is not something which should be specified in the config file
$config->{diskReadAccess} = (defined($strategyDiskAccess) && (($strategyDiskAccess eq "r") || ($strategyDiskAccess eq "rw"))) ? 1 : 0;
$config->{diskWriteAccess} = (defined($strategyDiskAccess) && (($strategyDiskAccess eq "w") || ($strategyDiskAccess eq "rw"))) ? 1 : 0;

$logger->trace("config content = \n".Dumper($config)) if (defined($logger));
my $strategy = newVerifStrategyFromId($config->{strategy}, $config, 1);
$strategy->{obsTypesList} = readObsTypesFromConfigHash($config); # for verif strategy (DocProvder reads obs types separately)


my %allDocs;
my $caseNo =1;
my $targetFileScoresTable = undef;
foreach my $pair (@docsPairs) { # for each case to analyze
    $logger->debug("Initializing pair") if ($logger);
    my @casePair;
    foreach my $docSet (@$pair) { # for each of the two documents sets
	$logger->debug("Initializing 1 doc set out of 2") if ($logger);
	my @docProvSet;
	foreach my $doc (@$docSet) { # for each doc in a set
	    $logger->debug("Initializing doc '$doc'") if ($logger);
	    my $docProvider;
	    if ((!$dontLoadAllFiles) && defined($allDocs{$doc})) {
		$docProvider = $allDocs{$doc};
	    } else {
		my %thisConfig = %$config;
		$thisConfig{filename} = $doc;
		$thisConfig{useCountFiles} = $useCountFiles;
		$docProvider = CLGTextTools::DocProvider->new(\%thisConfig);
		$allDocs{$doc} = $docProvider if (!$dontLoadAllFiles);
	    }
	    push(@docProvSet, $docProvider);
	}
	push(@casePair, \@docProvSet);
    }

    confess "bug! casePair must be of size 2!" if (scalar(@casePair) != 2);

    # process case
    $logger->debug("Computing similarity for case") if ($logger);
    if (defined($printScoreDir)) {
	$targetFileScoresTable = "$printScoreDir/".sprintf("%03d", $caseNo).".scores";
	$caseNo++;
    }
    my $features = $strategy->compute(\@casePair, $targetFileScoresTable);
    print join("\t", @$features)."\n";
}

