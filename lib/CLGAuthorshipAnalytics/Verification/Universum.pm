package CLGAuthorshipAnalytics::Verification::Universum;

# EM Dec 2015
# 
#


use strict;
use warnings;
use Carp;
use Log::Log4perl;
use CLGTextTools::Stats qw/pickInList pickNSloppy aggregateVector pickDocSubset splitDocRandomAvoidEmpty/;
use CLGTextTools::Commons qw/getArrayValuesFromIndexes containsUndef mergeDocs/;
use CLGAuthorshipAnalytics::Verification::VerifStrategy;
use CLGTextTools::Logging qw/confessLog cluckLog/;

our @ISA=qw/CLGAuthorshipAnalytics::Verification::VerifStrategy/;

use base 'Exporter';
our @EXPORT_OK = qw//;






#
# $params:
# * logging
# * obsTypesList 
# * nbRounds: number of rounds (higher number -> more randomization, hence less variance in the result) (default 100)
# * propObsSubset: (0<=p<1) the proportion of observations/occurrences used to mix 2 documents together at each round (p and 1-p); if zero, the proportion is picked randomly at every round (default 0.5)
# * simMeasure: a CLGTextTools::Measure object (initialized) (default minMax)
# * withReplacement: 0 1. default: 0
# * splitWithoutReplacementMaxNbAttempts: max number of attempts to try splitting doc without replacement if at least one of the subsets is empty. Default: 5.
# * finalScoresMethod: aggregSimByRound countMostSimByRound both: overall method(s) to obtain the features: by aggregating the similarities for each category or counting the most similar category among rounds. default: 'countMostSimByRound'
# * aggregSimByRound: all homogenity sameCat mergedOrNot: 'all' means use all individual categories as features. with 'homogenity' four final features are considered: AA+BB, AM+BM, AB, MM; with 'sameCat' there are only two final features: AA+BB+MM, AB+AM+BM. with 'mergedOrNot' there are two categories: AA+BB+AB, AM+BM+MM. default = 'sameCat'
# * countMostSimByRound: all homogenity sameCat mergedOrNot. see above.  default = 'sameCat'
# * aggregSimByRoundAggregType: median, arithm, geom, harmo. default = "arithm"




#
sub new {
    my ($class, $params) = @_;
    my $self = $class->SUPER::new($params, __PACKAGE__);
    $self->{obsTypesList} = $params->{obsTypesList};
    $self->{nbRounds} = assignDefaultAndWarnIfUndef("nbRounds", $params->{nbRounds}, 100, $self->{logger});
    $self->{propObsSubset} = assignDefaultAndWarnIfUndef("propObsSubset", $params->{propObsSubset}, 0.5, $self->{logger});
    $self->{simMeasure} = assignDefaultAndWarnIfUndef("simMeasure", $params->{simMeasure}, CLGTextTools::SimMeasures::MinMax->new(), $self->{logger}) ;
    $self->{withReplacement} = assignDefaultAndWarnIfUndef("withReplacement", $params->{withReplacement}, 0, $self->{logger});
    $self->{splitWithoutReplacementMaxNbAttempts} = assignDefaultAndWarnIfUndef("splitWithoutReplacementMaxNbAttempts", $params->{splitWithoutReplacementMaxNbAttempts}, 5, $self->{logger});
    $self->{finalScoresMethod} = assignDefaultAndWarnIfUndef("finalScoresMethod", $params->{finalScoresMethod}, "countMostSimByRound", $self->{logger});
    $self->{aggregSimByRound} = assignDefaultAndWarnIfUndef("aggregSimByRound", $params->{aggregSimByRound}, "sameCat" , $self->{logger});
    $self->{countMostSimByRound} = assignDefaultAndWarnIfUndef("countMostSimByRound", $params->{countMostSimByRound}, "sameCat", $self->{logger});
    $self->{aggregSimByRoundAggregType} = assignDefaultAndWarnIfUndef("aggregSimByRoundAggregType", $params->{aggregSimByRoundAggregType}, "arithm", $self->{logger});
    bless($self, $class);
    return $self;
}




#
# * $probeDocsLists: [ [docA1, docA2, ...] ,  [docB1, docB2,...] ]
#    ** where docX = DocProvider
#
sub compute {
    my $self = shift;
    my $probeDocsLists = shift;

    my $scores = $self->computeUniversum($probeDocsLists);
    return $self->featuresFromScores($scores);
}




#
#
# output: $scores->[roundNo] = [  [ probeDocNoA, probeDocNoB ], simProbeAvsB, $simRound ], with 
#         $simRound->[probe0Or1]->[impostorNo]
#
sub computeUniversum {
    my $self = shift;
    my $probeDocsLists = shift;

    $self->{logger}->debug("Universum strategy: computing features between pair of sets of docs") if ($self->{logger});
    confessLog($self->{logger}, "Cannot process case: no obs types at all") if ((scalar(@{$self->{obsTypesList}})==0) && $self->{logger});
    my @simRounds;
    my $nbEmpty=0;
    my $obsTypes = $self->{obsTypesList};
    for (my $roundNo=0; $roundNo < $self->{nbRounds}; $roundNo++) {
	my $obsType = pickInList($obsTypes);
	my @thirds;
	# Goal is to obtain 6 subsets: 2 x P0, 2 x P1, 2 x M (where Px = Probe x and M = merged P0-P1)
	# after preparing everything we will have:
	#  thirds[0] = [P0a, P0b] ; thirds[1] = [P1a, P1b] ; thirds[2] = [Ma, Mb]
	#
	# 1; splitting the 2 docs in thirds; if serveral docs on one side, pick a third at random
	for my $probeSide (0,1) {
	    if ($self->{withReplacement}) {
		for my $thirdNo (0..2) {
		    my $doc = pickInList($probeDocsLists->[$probeSide]);
		    $thirds[$probeSide]->[$thirdNo] = pickDocSubset($doc->getObservations($obsType), 1/3);
		}
	    } else {
		my @allPossibleThirds;
		foreach my $doc (@{$probeDocsLists->[$probeSide]}) {
		    my $docObsHash = $doc->getObservations($obsType);
		    my $thirdsDoc = splitDocRandomAvoidEmpty($self->{splitWithoutReplacementMaxNbAttempts}, $docObsHash, 3);
		    $nbEmpty++ if (containsUndef($thirdsDoc));
		    push(@allPossibleThirds, @$thirdsDoc);
		}
		my $selectedThirdsIndexes = pickNIndexesAmongMExactly(3, scalar(@allPossibleThirds));
		$thirds[$probeSide] = getArrayValuesFromIndexes(\@allPossibleThirds, $selectedThirdsIndexes);
	    }
	}
	# 2.  mixing one third of each with the other:
	my $prop = ($self->{propObsSubset} == 0) ? rand() : $self->{propObsSubset};
	# 2.a generating two thirds obtained from merging the two sides
	my $mergedMixed = mergeDocs($thirds[0]->[2], $thirds[1]->[2], 1);
	undef $thirds[0]->[2];
	undef $thirds[1]->[2];
	# 2.b split again into two mixed subsets
	$thirds[2] = splitDocRandomAvoidEmpty($mergedMixed, 2, { 0 => $prop  , 1 => 1-$prop} );

	# 3. compute sims between P0a-P0b, P1a-P1b, Ma-Mb, P0?-P1?, P0?-M?, P1?-M?
	my @sim;
	for my $i (0..2) {
	    for my $j (0..$i) {
		my ($docA, $docB);
		if ($i == $j) { # comparing both subsets from the same "category"
		   ($docA, $docB) = ($thirds[$i]->[0], $thirds[$i]->[1]); 
		} else {
		    # remark: we could have measured the similiarity of all 4 possible pairs, but this seems ok considering
                    # the randomization at the round level. Notice that this can make a big difference especially in the case where the
		    # proportion for the mixed doc is not 0.5 or not constant.
		   ($docA, $docB) = ($thirds[$i]->[int(rand(2))], $thirds[$j]->[int(rand(2))]); 
		}
		$sim[$i]->[$j] = $self->{simMeasure}->compute($docA, $docB);
	    }
	}
	push(@simRounds, \@sim);
    }
    warnLog($self->{logger}, "doc(s) too small => impossible to find enough partitions => used possibly empty doc(s) $nbEmpty times.") if ($nbEmpty>0);
    return \@simRounds;
}






#
# scores: $scores->[roundNo] = [  [ probeDocNoA, probeDocNoB ], simProbeAvsB, $simRound ], with 
#         $simRound->[probe0Or1]->[impostorNo] = sim between doc probe0or1 and imp $impostorNo (as returned by computeGI)
#
sub featuresFromScores {
    my ($self, $scores) = @_;

    my @features;
    if (($self->{finalScoresMethod} eq "aggregSimByRound") || ($self->{finalScoresMethod} eq "both")) {
	my $catLists = getCatLists($self->{aggregSimByRound});
	my @f = map { computeFeatureFromCatListAggreg($scores, $_, $self->{aggregSimByRoundAggregType}) } @$catLists;
	push(@features, @f);
    }
    if (($self->{finalScoresMethod} eq "countMostSimByRound") || ($self->{finalScoresMethod} eq "both")) {
	my $mostSimByRound = countMostSimByRound($scores); # first step if most sim method: extract most sim by round
	my $catLists = getCatLists($self->{countMostSimByRound});
	my @f = map { computeFeatureFromCatListCount($mostSimByRound, $_) } @$catLists;
	push(@features, @f);

    }

    return \@features;
}


#
# catList = a list of pairs [i,j] of categories to aggregate
#
sub computeFeatureFromCatListAggreg {
    my $scores = shift;
    my $catList = shift;
    my $aggregType = shift;

    my $nbRounds = scalar(@$scores);
    my @values;
    foreach my $simRound (@$scores) {
	my $sumRound = 0;
	foreach my $pair (@$catList) {
	    $sumRound += $scores->[$pair->[0]]->[$pair->[1]];
	}
	my $valueRound = $sumRound / scalar(@$catList);
	push(@values, $valueRound);
    }
    return aggregateVector(\@values, $aggregType);
}


#
# catList = a list of pairs [i,j] of categories to aggregate
#
sub computeFeatureFromCatListCount {
    my $counts = shift;
    my $catList = shift;

    my $sum = 0;
    foreach my $pair (@$catList) {
	$sum += $counts->[$pair->[0]]->[$pair->[1]];
    }
    return $sum / scalar(@$catList);
}




sub getCatLists {
    my $categsId = shift;

    my @categsLists;
    if ($categsId eq "all") {
	for my $i (0..2) {
	    for my $j (0..$i) {
		push(@categsLists, [ [$i,$j] ] );
	    }
	}
    } elsif ($categsId eq "homogenity") {
	push(@categsLists, [ [0,0] , [1,1] ]);
	push(@categsLists, [ [2,0] , [2,1] ]);
	push(@categsLists, [ [1,0] ]);
	push(@categsLists, [ [2,2] ]);
    } elsif ($categsId eq "sameCat") {
	push(@categsLists, [ [0,0] , [1,1] , [2,2] ]);
	push(@categsLists, [ [2,0] , [2,1] , [1,0] ]);
    } elsif ($categsId eq "mergedOrNot") {
	push(@categsLists, [ [0,0] , [1,1] , [1,0] ]);
	push(@categsLists, [ [2,0] , [2,1] , [2,2] ]);
    }    
    return \@categsLists;
}



sub countMostSimByRound {
    my $scores = shift;

    my @mostSimByRound;
    my $nbRounds = scalar(@$scores);
    foreach my $simRound (@$scores) {
	my ($maxI, $maxJ) =(undef,undef);
	for my $i (0..2) {
	    for my $j (0..$i) {
		my $thisSim = $simRound->[$i]->[$j];
		($maxI, $maxJ) = ($i, $j) if (!defined($maxI) || !defined($maxJ) || ($thisSim > $simRound->[$maxI]->[$maxJ])); 
	    }
	}
	$mostSimByRound[$maxI]->[$maxJ]++;
    }
    for my $i (0..2) { # normalize and define as zero if undef
	for my $j (0..$i) {
	    if (defined($mostSimByRound[$i]->[$j])) {
		$mostSimByRound[$i]->[$j] /= $nbRounds;
	    } else {
		$mostSimByRound[$i]->[$j] = 0;
	    }
	}
    }
    return \@mostSimByRound;
}




1;
