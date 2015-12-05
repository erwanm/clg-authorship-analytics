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



# * docSubsetMethod: "byOccurrence" -> the proportion is applied to the set of all occurrences; "byObservation" -> applied only to distinct observations (default ByObservation)
# * preSimValues: used only if selectNTimesMostSimilarFirst>0. preSimValues = [ datasetA => preSimDatasetA, dataset2 => preSimDataset2, ...] which contains at least the datasets provided in <impostors>. each preSimDataset = { probeFilename => { impostorFileName => simValue } }, i.e preSimValues->{dataset}->{probeFilename}->{impostorFilename} = simValue.  This parameter is used (1) to provide similiarity values computed in a meaningful way and (2) avoid repeating the process as many times as the method is called, which might be prohibitive in computing time. If selectNTimesMostSimilarFirst>0 but preSimValues is undef, first-stage similarity between probe and impostors is computed using a random obsType, unless preSimObsType is defined (see below).
# * preSimObsType: the obs type to use to compute preselection similarity between probe docs and impostors, if selectNTimesMostSimilarFirst>0 but preSimValues is not. If preSimObsType is not defined either, then a random obs type is used (in this case the quality of the results could be more random)
#
# * GI_useCountMostSimFeature: 0, original, ASGALF, ASGALFavg. if not "0", the "count most similar" feature is computed with the specified variant; default: "original".
# * GI_kNearestNeighbors: uses only the K (value) most similar impostors when calculating result features. default: 0 (use all impostors).
# * GI_mostSimilarFirst: doc or run: specifies whether the K most similar impostors are selected globally (doc) or for each run (run); unused if GI_kNearestNeighbors=0. Default: doc.
# * GI_aggregRelRank: 0, median, arithm, geom, harmo. if not 0, computes the relative rank of the sim between A and B among sim against all impostors by round; the value is used to aggregate all relative ranks (i.e. the values by round). Default: 0.
# * GI_useAgregateSim: 0, diff, ratio. if not 0, computes X = the aggregate sim value between A and B across all runs and Y= the aggregate sim value between any probe and any impostor across all rounds; returns A-B (diff) or A/B (ratio); default : 0.
# * GI_aggregateSimStat:  median, arithm, geom, harmo. aggregate method to use if useAgregateSim is not 0 (ignored if 0). default: arithm.


#
sub new {
    my ($class, $params) = @_;
    my $self = $class->SUPER::new($params);
    $self->{logger} = Log::Log4perl->get_logger(__PACKAGE__) if ($params->{logging});
    $self->{obsTypesList} = $params->{obsTypesList};
    $self->{nbRounds} = defined($params->{nbRounds}) ? $params->{nbRounds} : 100;
    $self->{propObsSubset} = defined($params->{propObsSubset}) ? $params->{propObsSubset} : 0.5 ;
    $self->{simMeasure} = defined($params->{simMeasure}) ? $params->{simMeasure} : CLGTextTools::SimMeasures::MinMax->new() ;
    $self->{withReplacement} = defined($params->{withReplacement}) ? $params->{withReplacement} : 0;
    $self->{splitWithoutReplacementMaxNbAttempts} = defined($params->{splitWithoutReplacementMaxNbAttempts}) ? $params->{splitWithoutReplacementMaxNbAttempts} : 5;




    $self->{docSubsetMethod} = defined($params->{docSubsetMethod}) ? $params->{docSubsetMethod} : "byObservation" ;
    $self->{preSimValues} = $params->{preSimValues};
    $self->{GI_useCountMostSimFeature} = defined($params->{GI_useCountMostSimFeature}) ? $params->{GI_useCountMostSimFeature} : "original";
    $self->{GI_kNearestNeighbors} = defined($params->{GI_kNearestNeighbors}) ? $params->{GI_kNearestNeighbors} : 0 ;
    $self->{GI_mostSimilarFirst} =  defined($params->{GI_mostSimilarFirst}) ? $params->{GI_mostSimilarFirst} : "doc" ;
    $self->{GI_aggregRelRank} = defined($params->{GI_aggregRelRank}) ? $params->{GI_aggregRelRank} : "0";
    $self->{GI_useAgregateSim} = defined($params->{GI_useAgregateSim}) ? $params->{GI_useAgregateSim} : "0";
    $self->{GI_agregateSimStat} = defined($params->{GI_agregateSimStat}) ? $params->{GI_agregateSimStat} : "arithm";
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
		    $thirds[$probeSide]->[$thirdNo] = pickDocSubset($doc->{$obsType}, 1/3);
		}
	    } else {
		my @allPossibleThirds;
		foreach my $doc (@{$probeDocsLists->[$probeSide]}) {
		    my $thirdsDoc = splitDocRandomAvoidEmpty($self->{splitWithoutReplacementMaxNbAttempts}, $doc, 3);
		    $nbEmpty++ if (containsUndef($thirdsDoc));
		    push(@allPossibleThirds, @$thirdsDoc);
		}
		my $selectedThirdsIndexes = pickNIndexesAmongMExactly(3, scalar(@allPossibleThirds));
		$thirds[$probeSide] = getArrayValuesFromIndexes(\@allPossibleThirds, $selectedThirdsIndexes);
	    }
	}
	# 2.  mixing one third of each with the other:
	my $prop = ($config->{propObsSubset} == 0) ? rand() : $config->{propObsSubset};
	# 2.a generating two thirds obtained from merging the two sides
	my $mergedMixed = mergeDocs($thirds[0]->[2], $thirds[1]->[2], 1);
	undef $thirds[0]->[2];
	undef $thirds[1]->[2];
	# 2.b split again into two mixed subsets
	$thirds[2] = splitDocRandomAvoidEmpty($mergedMixed, 2, { 0 => $prop  , 1 => 1-$prop} );

	# 3. compute sims between P0a-P0b, P1a-P1b, Ma-Mb, P0?-P1?, P0?-M?, P1?-M?
	my %sim;
	for my $i (0..2) {
	    for my $j (0..$i) {
		my ($docA, $docB);
		if ($i == $j) { # comparing both subsets from the same "category"
		   ($docA, $docB) = ($third[$i]->[0], $third[$i]->[1]); 
		} else {
		    # remark: we could have measured the similiarity of all 4 possible pairs, but this seems ok considering
                    # the randomization at the round level. Notice that this can make a big difference especially in the case where the
		    # proportion for the mixed doc is not 0.5 or not constant.
		   ($docA, $docB) = ($third[$i]->[int(rand(2))], $third[$j]->[int(rand(2))]); 
		}
		$sim{"$i.$j"} = $self->{simMeasure}->compute($docA, $docB);
	    }
	}
	push(@simRounds, \%sim);
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
    $self->removeLeastSimilar($scores); # keeps only K most similar if K>0
    if ($self->{GI_useCountMostSimFeature} != "0") {
	my $mostSimImpNo = $self->getKMostSimilarImpostorsGlobal($scores, 1);
	my @impNo = ($mostSimImpNo->[0]->[0], $mostSimImpNo->[1]->[0]); 
	# extract vector of similarities (by round) for each probe (from the most similar impostor no)
	my @simValuesMostSimImp = ( [ map { $_->[2]->[0]->[$impNo[0]] } (@$scores) ], [ map { $_->[2]->[1]->[$impNo[1]] } (@$scores) ] ); # nb rounds items
	my @simValuesProbeDocs = map { $_->[1] } (@$scores);
	push(@features, $self->countMostSimFeature(\@simValuesProbeDocs ,\@simValuesMostSimImp));
    }
    push(@features, $self->relativeRankFeature($scores)) if ($self->{GI_aggregRelRank} != "0");
    push(@features, $self->aggregateSimComparison($scores)) if ($self->{GI_useAggregateSim} != "0");
    return \@features;
}



#
# keeps only the K most similar impostors for each run (param GI_kNearestNeighbors)
# the selected K can be either global or by run (param GI_mostSimilarFirst; ignored if GI_kNearestNeighbors=0)
# Warning: modifies $scores directly!
#
sub removeLeastSimilar {
    my $self = shift;
    my $scores = shift;

    my $nbImp = scalar(@{$scores->[0]->[2]->[0]});
    my $nbRounds = scalar(@$scores);
    my $k = $self->{GI_kNearestNeighbors};
    if (($k>0) && ($k < $nbImp))  { # otherwise nothing to remove
	my $keepOnly = undef;
	if ($self->{GI_mostSimilarFirst} == "doc") {
	    $keepOnly  = $self->getKMostSimilarImpostorsGlobal($scores, $k);
	}
	for (my $roundNo = 0; $roundNo < $nbRounds; $roundNo++) {
	    foreach my $probeNo (0,1) {
		if (defined($keepOnly)) { # global (doc)
		    $scores->[$roundNo]->[2]->[$probeNo] =  [ map { $scores->[$roundNo]->[2]->[$probeNo]->[$_] } @$keepOnly ];
		} else {
		    my @sorted0 = sort { $b <=> $a } @{$scores->[$roundNo]->[2]->[$probeNo]}; # sim values!
		    my @sortedK = @sorted0[0..$k-1];
		    $scores->[$roundNo]->[2]->[$probeNo] = \@sortedK;
		}
	    }
	}
    }
}



#
# 
#
sub countMostSimFeature {
    my $self = shift;
    my $probeSimVector = shift;
    my $impSimVectors = shift;

    my $sum=0;
    for (my $i=0; $i<scalar(@$probeSimVector); $i++) { # iterate rounds
	if ($self->{GI_useCountMostSimFeature} == "original") {
	    $sum++ if ( $probeSimVector->[$i]**2 > ($impSimVectors->[0]->[$i] * $impSimVectors->[1]->[$i]) );
	} elsif ($self->{GI_useCountMostSimFeature} == "ASGALF") {
	    $sum +=  ( $probeSimVector->[$i]**2 / ($impSimVectors->[0]->[$i] * $impSimVectors->[1]->[$i]) );
	} elsif ($self->{GI_useCountMostSimFeature} == "ASGALFavg") {
	    $sum +=  ( $probeSimVector->[$i] * 2 / ($impSimVectors->[0]->[$i] + $impSimVectors->[1]->[$i]) );
	} else {
	    confessLog($self->{logger}, "Error: invalid value '".$self->{GI_useCountMostSimFeature}."' for param 'GI_useCountMostSimFeature' ");
	}
    }
    # IMPORTANT: the normalisation makes sense only for the original version
    # I don't think we can normalise the two others since we don't can't be sure
    # that B>=A in A/B (i.e. sim(Pi,Ii)>sim(P1,P2))
    # However dividing every score by the same value doesn't hurt, it's just
    # that the result shouldn't be interpreted as necessarily in [0,1]
    return $sum / scalar(@$probeSimVector);
}




#
# returns res->[probeSide]->[0..k-1] =  k most similar impostors nos.
#
#
sub getKMostSimilarImpostorsGlobal {
    my $self = shift;
    my $scores = shift; # as returned by computeGI
    my $k = shift;

    $k--; # arrays slice last index (start at zero)
    my $nbImp = scalar(@{$scores->[0]->[2]->[0]});
    my $nbRounds = scalar(@$scores);
    my @res;
    foreach my $probeNo (0,1) {
	my @meanSim;
	for (my $impNo=0; $impNo < $nbImp; $impNo++) {
	    my $sum=0;
	    for (my $roundNo = 0; $roundNo < $nbRounds; $roundNo++) {
		$sum += $scores->[$roundNo]->[2]->[$probeNo]->[$impNo];
	    }
	    $meanSim[$impNo] = $sum / $nbRounds;
	}
        my $last= $nbImp-1;
        my @avgSorted = sort { $meanSim[$b] <=> $meanSim[$a] } (0..$last);
        my @select = @avgSorted[0..$k];
	$res[$probeNo] = \@select;
    }
    return \@res;
}


#
#
sub relativeRankFeature {
    my $self = shift;
    my $scores = shift;
 
    my $nbImp = scalar(@{$scores->[0]->[2]->[0]});
    my $nbRounds = scalar(@$scores);
    my @res;
    for (my $run=0; $run < $nbRounds; $run++) {
	my @relRankByProbe;
	for my $probeNo (0,1) {
	    my $vector = $scores->[$run]->[2]->[$probeNo];
	    my %asHash;
	    for (my $imp=0; $imp<$nbImp; $imp++) {
		$asHash{$imp} = $vector->[$imp];
	    }
	    $asHash{Q} = $scores->[$run]->[1];
	    my $ranking = rankWithTies({ values => \%asHash, noNaNWarning => 1, firstRank => 0 });
	    $relRankByProbe[$probeNo] = $ranking->{Q} / scalar(@$vector);
	}
	$res[$run] = ( $relRankByProbe[0] + $relRankByProbe[1] ) /2; # simple average between the two sides for each run
    }
    my $finalScore = aggregateVector(\@res, $self->{GI_aggregRelRank});
    return $finalScore;

}
 


sub aggregateSimComparison {
    my $self = shift;
    my $scores = shift;
 
    my $nbImp = scalar(@{$scores->[0]->[2]->[0]});
    my $nbRounds = scalar(@$scores);

    my @aggregProbe;
    my @aggregImp;
    for (my $run=0; $run < $nbRounds; $run++) {
	push(@aggregProbe, $scores->[$run]->[1]);
	for my $probeNo (0,1) {
	    push(@aggregImp, @{$scores->[$run]->[2]->[$probeNo]});
	}
    }
    my $valProbe = aggregateVector(@aggregProbe, $self->{GI_aggregateSimStat});
    my $valImp = aggregateVector(@aggregImp, $self->{GI_aggregateSimStat});
    if ($self->{useAggregateSim} eq "diff") {
	return $valProbe - $valImp;
    } elsif ($self->{useAggregateSim} eq "ratio") {
	return $valProbe / $valImp;
    } else {
	confessLog($self->{logger}, "Error: invalid value '".$self->{useAggregateSim}."' for param 'useAggregateSim' ");
    }
}


1;
