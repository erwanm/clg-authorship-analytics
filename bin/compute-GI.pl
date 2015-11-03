#!/usr/bin/perl



use strict;
use warnings;
use Getopt::Std;
use Carp;
use Math::CDF;
use Math::Trig;
use Data::Dumper;
use CLGTextTools::ObsCollection qw/extractObservsWrapper/;
use CLGTextTools::Commons qw/readConfigFile/;
use CLGTextTools::Stats qw/aggregateVector pickInList pickInListProbas/;

my $progName="compute-GI.pl";
my $NaN = "NA";
my $colCountFile=1; # 1 = abosulte freq, 2 = relative freq
my $maxAttemptsSplit=10;
my $nbWarnEmptyDocsReturned=0;
my $useCountFile;


sub usage {
	my $fh = shift;
	$fh = *STDOUT if (!defined $fh);
	print $fh "Usage: $progName [options] <config file> <unknown doc> <known doc1>[:<known doc2>...]\n";
	print $fh "\n";
	print $fh " TODO\n";
	print $fh "\n";
	print $fh "   Options:\n";
	print $fh "     -h print this help\n";
	print $fh "     -c use observations count files instead of extracting observations from raw text\n";
	print $fh "        files. The count file corresponding to observation type <obs> for document <doc>\n";
	print $fh "        is read from <doc>.<obs>.count\n";
#	print $fh "     -o <filename prefix> output intermediate indicators (by observation) to <filename prefix>.<obsType>\n";
	print $fh "\n";
}



sub checkParam {
    my ($param, $config, $configFile) = @_;
    die "$progName: error, parameter '$param' not defined in config file '$configFile'" if (!defined($config->{$param}) || ($config->{$param} eq ""));
}


sub readCountFile {
    my $f = shift;

    open(COUNT, "<:encoding(utf-8)", $f) or die "$progName error: cannot open '$f'";
    my %content;
    while (<COUNT>) {
        chomp;
        my @cols = split(/\t/, $_);
        die "$progName error: expecting exactly 3 columns in $f but found ".scalar(@cols).": $!" if (scalar(@cols) != 3);
        $content{$cols[0]} = $cols[$colCountFile];
    }
    close(COUNT);
    return \%content;
}



sub splitDocsWithReplacement {
    my ($listDocs, $obsType, $nbParts) = @_;

    my @parts;
    my $proba = 1 / $nbParts;
    for (my $i=0; $i < $nbParts; $i++) {
	my $doc0 = pickInList($listDocs);
	my $doc = defined($obsType) ? $doc0->{$obsType} : $doc0;
	foreach my $obs (keys %$doc) {
	    for (my $j=0; $j < $doc->{$obs}; $j++) {
		$parts[$i]->{$obs}++ if (rand() < $proba);
	    }
	}
    }
    return \@parts;
}


sub splitDocsWithoutReplacement {
    my ($listDocs, $obsType, $nbParts) = @_;

 #   print STDERR "DEBUG $progName splitDocsWithoutReplacement, nbParts=$nbParts\n";
    # 1. split every doc in nbParts
    my %allParts;
    my $attemptsLeft = $maxAttemptsSplit;
    while ((scalar(keys %allParts)< $nbParts) && ($attemptsLeft>0)) {
	for (my $i=0; $i< scalar(@$listDocs) ; $i++) {
#	    print STDERR "DEBUG $progName i=$i\n";
	    my $doc = defined($obsType) ? $listDocs->[$i]->{$obsType} : $listDocs->[$i];
	    foreach my $obs (keys %{$doc}) {
		for (my $j=0; $j < $doc->{$obs}; $j++) {
		    my $partNo = int(rand($nbParts));
		    $allParts{"$i;$partNo"}->{$obs}++;
		}
	    }
	}
	$attemptsLeft--;
    }

    my @finalParts;
    if (scalar(keys %allParts)< $nbParts) {
	$nbWarnEmptyDocsReturned++;
	@finalParts = values %allParts;
	while (scalar(@finalParts) < $nbParts) { # returning empty doc(s)!!
	    push(@finalParts, {});
	}
    } else {
	# 2 pick nbParts thirds among the list (e.g. if nbParts=3 the list contains exactly 3 if 1 doc, 6 if 2 docs..)
	for (my $i=0; $i< $nbParts; $i++) {
#	    print STDERR "DEBUG $progName: part $i, scalar(keys %allParts) = ".scalar(keys %allParts)."; keys= ".join(";", keys %allParts)." \n";
	    my @keys = keys %allParts;
	    my $key = pickInList(\@keys);
	    push(@finalParts, $allParts{$key});
	    delete $allParts{$key};
	}
    }
    return \@finalParts;
}



sub mergeDocsAndSplitInTwo {
    my ($doc1, $doc2, $prop) = @_;

    my @props = ($prop, 1 - $prop);
    my @docs = ($doc1, $doc2);
    my @resDocs;
    for (my $i=0; $i<2; $i++) {
	foreach my $obs (keys %{$docs[$i]}) {
	    for (my $j=0; $j < $docs[$i]->{$obs}; $j++) {
		if (rand() < $props[$i]) {
		    $resDocs[0]->{$obs}++;
		} else {
		    $resDocs[1]->{$obs}++;
		}
	    }
	}
    }
    return \@resDocs;
}


sub cosine {
    my ($doc1, $doc2) = @_;

    my ($obs1, $freq1);
    my $sumProd=0;
    while (($obs1, $freq1) = each %$doc1) { # remark: only common observations count
        my $freq2 = $doc2->{$obs1};
        $freq2 = 0 if (!defined($freq2));
        $sumProd += $freq1 * $freq2;
    }
    my ($n1, $n2) = ( norm($doc1) , norm($doc2) );
    return 0 if ($n1 * $n2 == 0);
    return $sumProd / ($n1*$n2);
}

sub norm {
    my ($doc) = @_;

    my ($obs1, $freq1);
    my $sum=0;
    while (($obs1, $freq1) = each %$doc) {
	$sum += $freq1**2;
    }
    return sqrt($sum);
}


sub minmax {
    my ($doc1, $doc2) = @_;

    my ($min, $max);
    my ($obs1, $freq1);
    while (($obs1, $freq1) = each %$doc1) {
        my $freq2 = $doc2->{$obs1};
        $freq2 = 0 if (!defined($freq2));
	if ($freq1 <= $freq2) {
	    $min += $freq1 ;
	    $max += $freq2;
	} else {
	    $min += $freq2 ;
	    $max += $freq1;
	}
    }
    my ($obs2, $freq2);
    while (($obs2, $freq2) = each %$doc2) {
	$max += $freq2 if (!defined($doc1->{$obs2}));
    }

    return 0 if (!defined($min) || (!defined($max)) || ($max == 0));
    return $min / $max;
}


sub computeSim {
    my ($doc1, $doc2, $measure) = @_;

    if ($measure eq "cosine") {
	return cosine($doc1, $doc2);
    } elsif ($measure eq "minmax") {
	return minmax($doc1, $doc2);
    } else {
	die "$progName error: invalid measure id '$measure'";
    }
}


sub aggregateMultiVector {
    my ($list, $meanType, $NaN) = @_;

    my $n = scalar(@$list);
    my @v;
    for (my $i=0; $i<scalar(@{$list->[0]}); $i++) {
	my $sum=0;
	for (my $j=0; $j<$n; $j++) {
	    $sum += $list->[$j]->[$i];
	}
	$v[$i] += $sum / $n;
    }
    return aggregateVector(\@v, $meanType, $NaN);
}

sub order {
    my ($kqm1, $kqm2) = @_;

    return ($kqm1 le $kqm2 ) ?  "$kqm1.$kqm2" :  "$kqm2.$kqm1";
}

sub countMostSim {
    my $sims = shift;

    my %mostSim;
    my ($anyKey, $dummy) = each %$sims;
    keys %$sims; # reset iterator;
#    print STDERR "DEBUG $progName anyKey=$anyKey\n";
    my $nbRounds = scalar(@{$sims->{$anyKey}});
    for (my $roundNo=0; $roundNo<$nbRounds; $roundNo++) {
	foreach my $kqm1 ("K", "Q", "M") { # searching best match between kqm1 and... ?
	    my $max2;
	    foreach my $kqm2 ("K", "Q", "M") { # possible matches
#		print STDERR "DEBUG $progName: order($kqm1, $kqm2) = ".order($kqm1, $kqm2)."\n";
#		print STDERR "DEBUG $progName: order($kqm1, $max2) = ".order($kqm1, $max2)."\n";
		$max2 = $kqm2 if (!defined($max2) || ($sims->{order($kqm1, $kqm2)}->[$roundNo] > $sims->{order($kqm1, $max2)}->[$roundNo]));
	    }
	    $mostSim{"$kqm1.$max2"}++;
	}
    }
    foreach my $kqm1 ("K", "Q", "M") {
	foreach my $kqm2 ("K", "Q", "M") {
	    $mostSim{"$kqm1.$kqm2"} = defined($mostSim{"$kqm1.$kqm2"}) ? $mostSim{"$kqm1.$kqm2"} / $nbRounds : 0;

	}
    }
    return \%mostSim;
}



sub readDocDataWrapper {
    my ($docFile, $obsTypesList, $config, $configFile) = @_;

    my $data = {};
    if ($useCountFile) {
	foreach my $obsType (@$obsTypesList) { # loading all data
	    $data->{$obsType} = readCountFile("$docFile.$obsType.count");
	}
    } else {
	checkParam("minFreqObsIndiv", $config, $configFile);
	checkParam("performWordTokenization", $config, $configFile);
	checkParam("InputSegmentationFormat", $config, $configFile);
	# optional, so no check
	#checkParam("wordObsVocabResources", $config, $configFile);
	my %params;
	$params{obsTypes} = $obsTypesList;
	$params{wordTokenization} = $config->{performWordTokenization};
	$params{formatting} = $config->{InputSegmentationFormat};
	$params{wordVocab} = $config->{wordObsVocabResources}; # optional, might be undef
	$data = extractObservsWrapper(\%params, $docFile, $config->{minFreqObsIndiv}, 0);
    }
    return $data;
}





# PARSING OPTIONS
my %opt;
getopts('hc', \%opt ) or  ( print STDERR "Error in options" &&  usage(*STDERR) && exit 1);
usage($STDOUT) && exit 0 if $opt{h};
print STDERR "3 arguments expected but ".scalar(@ARGV)." found: ".join(" ; ", @ARGV)  && usage(*STDERR) && exit 1 if (scalar(@ARGV) != 3);
$useCountFile = $opt{c};

my $configFile=$ARGV[0];
my $unknownPrefix=$ARGV[1];
my $knownPrefixListStr=$ARGV[2];

my $config = readConfigFile($configFile);

checkParam("obsTypesList", $config, $configFile);
my @obsTypesList = split(":", $config->{"obsTypesList"});
#print STDERR "DEBUG $progName: ".join(";",@obsTypesList)."\n";
my @knownPrefixes = split(":", $knownPrefixListStr);



checkParam("univ_nbRounds", $config, $configFile);
checkParam("univ_withReplacement", $config, $configFile);
checkParam("univ_mixedVariableProp", $config, $configFile);
checkParam("univ_simMeasure", $config, $configFile);
checkParam("univ_useMeanSim", $config, $configFile);
checkParam("univ_meanSimType", $config, $configFile);
checkParam("univ_useMostSim", $config, $configFile);


my $unknownDoc;
my @knownDocs;
$unknownDoc = readDocDataWrapper($unknownPrefix, \@obsTypesList, $config);
for (my $i=0; $i < scalar(@knownPrefixes); $i++) {
    $knownDocs[$i] = readDocDataWrapper($knownPrefixes[$i], \@obsTypesList, $config, $configFile);
}


my $nbRounds = $config->{"univ_nbRounds"};
my %sims;

for (my $roundNo=0; $roundNo<$nbRounds; $roundNo++) {
    my $obsType = pickInList(\@obsTypesList);
    my %docsKQ = ( "K" => \@knownDocs, "Q" => [ $unknownDoc ] );

#    print STDERR Dumper(\%docsKQ);

    # 1; splitting the 2 docs in thirds
    my %thirdsKQM;
    foreach my $kq (keys %docsKQ) {
	if ($config->{"univ_withReplacement"} == 0) {
	    $thirdsKQM{$kq} = splitDocsWithoutReplacement($docsKQ{$kq}, $obsType, 3);
	} else {
	    $thirdsKQM{$kq} = splitDocsWithReplacement($docsKQ{$kq}, $obsType, 3);
	}
    }
    # 2.  mixing one third of each with the other:
    my $prop = $config->{"univ_mixedVariableProp"} ? rand() : 0.5;
    $thirdsKQM{"M"} = mergeDocsAndSplitInTwo($thirdsKQM{"K"}->[2], $thirdsKQM{"Q"}->[2], $prop);
    undef $thirdsKQM{"K"}->[2];
    undef $thirdsKQM{"Q"}->[2];

    # 3. similarities:
    foreach my $kq1 (keys %thirdsKQM) {
	foreach my $kq2 (keys %thirdsKQM) {
	    if ($kq1 le $kq2) { # alphabetical order to avoid computing twice the same pair of categories (implies assuming symetrical measure)
		my ($doc1, $doc2);
		if ($kq1 eq $kq2) {
		    ($doc1, $doc2) = ($thirdsKQM{$kq1}->[0], $thirdsKQM{$kq2}->[1]);
		} else { # pairs are independent, so we take a random pair (other option would be to take the avg over all pairs, but we assume that randomization over rounds will take care of that)
		    ($doc1, $doc2) = ($thirdsKQM{$kq1}->[int(rand(2))], $thirdsKQM{$kq2}->[int(rand(2))]);
		}
		$sims{"$kq1.$kq2"}->[$roundNo] = computeSim($doc1, $doc2 ,$config->{"univ_simMeasure"});
	    }
	}
    }

}

print STDERR "$progName Warning: document(s) too small, impossible to find enough partitions, used empty doc(s) $nbWarnEmptyDocsReturned/$nbRounds times.\n" if ($nbWarnEmptyDocsReturned>0);
# aggregate results as features
my @features;
if ($config->{"univ_useMeanSim"} ne "no") {
    if ($config->{"univ_useMeanSim"} eq "all") {
	foreach my $key (sort keys %sims) {
	    push(@features, aggregateVector($sims{$key}, $config->{"univ_meanSimType"}, $NaN));
	}
    } elsif ($config->{"univ_useMeanSim"} eq "homogeneity") {
	push(@features, aggregateMultiVector([ $sims{"K.K"}, $sims{"Q.Q"} ], $config->{"univ_meanSimType"}, $NaN));
	push(@features, aggregateMultiVector([ $sims{"K.M"}, $sims{"M.Q"} ], $config->{"univ_meanSimType"}, $NaN));
	push(@features, aggregateVector( $sims{"K.Q"}, $config->{"univ_meanSimType"}, $NaN));
	push(@features, aggregateVector( $sims{"M.M"}, $config->{"univ_meanSimType"}, $NaN));
    } elsif ($config->{"univ_useMeanSim"} eq "sameCat") {
	push(@features, aggregateMultiVector([ $sims{"K.K"}, $sims{"Q.Q"}, $sims{"M.M"} ], $config->{"univ_meanSimType"}, $NaN));
	push(@features, aggregateMultiVector([ $sims{"K.M"}, $sims{"M.Q"}, $sims{"K.Q"} ], $config->{"univ_meanSimType"}, $NaN));
    } else {
	die "$progName: invalid value '".$config->{"univ_useMeanSim"}."' for parameter 'univ_useMeanSim' in '$configFile'";
    }
}
if ($config->{"univ_useMostSim"} ne "no") {
    my $mostSim = countMostSim(\%sims);
#    print STDERR "DEBUG mostSim :  ";
#    foreach my $k (sort keys %$mostSim) {
#	print STDERR " $k:".$mostSim->{$k};
#   }
#    print STDERR "\n";
    if ($config->{"univ_useMostSim"} eq "all") {
	foreach my $key (sort keys %$mostSim) {
	    push(@features, $mostSim->{$key});
	}
    } elsif ($config->{"univ_useMostSim"} eq "homogeneity") {
	push(@features, ($mostSim->{"K.K"} + $mostSim->{"Q.Q"})  / 2);
	push(@features, ($mostSim->{"K.M"} + $mostSim->{"M.Q"}) / 2);
	push(@features, $mostSim->{"K.Q"});
	push(@features, $mostSim->{"M.M"});
    } elsif ($config->{"univ_useMostSim"} eq "sameCat") {
	push(@features, ($mostSim->{"K.K"} + $mostSim->{"Q.Q"} + $mostSim->{"M.M"} ) / 3);
	push(@features, ($mostSim->{"K.M"} + $mostSim->{"M.Q"} + $mostSim->{"K.Q"} ) / 3);
    } else {
	die "$progName: invalid value '".$config->{"univ_useMostSim"}."' for parameter 'univ_useMostSim' in '$configFile'";
    }
}

#print STDERR "DEBUG $progName: features = ".join(" ", @features)."\n";
print "".join("\t", @features)."\n";
