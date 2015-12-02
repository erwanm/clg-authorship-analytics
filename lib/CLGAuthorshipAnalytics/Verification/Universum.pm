package CLGAuthorshipAnalytics::Verification::Universum;

# EM Dec 2015
# 
#


use strict;
use warnings;
use Carp;
use Log::Log4perl;
use CLGTextTools::Stats qw/pickInList pickNSloppy aggregateVector/;
use CLGTextTools::Commons qw/pickDocSubset/;
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

    my $obsTypes = $self->{obsTypesList};
    for (my $roundNo=0; $roundNo < $self->{nbRounds}; $roundNo++) {
	my $obsType = pickInList($obsTypes);
	my @thirds;
	if ($self->{withReplacement}) {
	    for my $probeSide (0,1) {
		for my $thirdNo (0..2) {
		    my $doc = pickInList($probeDocsLists->[$probeSide]);
		    $thirds[$probeSide]->[$thirdNo] = pickDocSubset($doc->{$obsType}, 1/3);
		}
	    }
	} else {
	}

	
    }







    my @impostorsDatasets = keys %$impostors;
    
    my $allObs = undef;
    # compute the different versions of the probe documents after filtering the min doc freq, as defined by the different impostors datasets doc freq tables.
    # $probeDocsListsByDataset->[0|1]->[docNo]->{impDataset}->{obsType}->{obs} = freq
    my @probeDocsListsByDataset;
    foreach my $impDataset (@impostorsDatasets) {
	my $minDocFreq = $self->{impostors}->{$impDataset}->getMinDocFreq();
	if ($minDocFreq > 1) {
	    my $docFreqTable = $self->{impostors}->{$impDataset}->getDocFreqTable();
	    for (my $probeDocNo=0; $probeDocNo<=1; $probeDocNo++) {
		for (my $docNo=0; $docNo<scalar(@{$probeDocsLists->[$probeDocNo]}); $docNo++) {
		    $probeDocsListsByDataset[$probeDocNo]->[$docNo]->{$impDataset} = filterMinDocFreq($probeDocsLists->[$probeDocNo]->[$docNo], $minDocFreq, $docFreqTable);
		}
	    }
	    if ($self->{docSubsetMethod} eq "byObservation") {
		foreach my $obsType (@{$self->{obsTypesList}}) {
		    my ($obs, $docFreq);
		    my @obsTypeObservs;
		    while (($obs, $docFreq) = each %{$minDocFreq->{$obsType}}) {
			push(@obsTypeObservs, $obs) if ($docFreq >= $minDocFreq);
		    }
		    $allObs->{$obsType} = \@obsTypeObservs;
		}
	    }	
	}
    }

	my @probeDocNo = (pickIndex($probeDocsListsByDataset[0]) , pickIndex($probeDocsListsByDataset[1]));
	my $obsType = pickInList($obsTypes);
	my $propObsRound = ($self->{propObsSubset} > 0) ? $self->{propObsSubset} : rand();
	my @probeDocsRound = ($probeDocsListsByDataset[0]->[$probeDocNo[0]]->{$obsType}, $probeDocsListsByDataset[1]->[$probeDocNo[1]]->{$obsType} );
	my @impDocRound;
	if (defined($allObs)) {
	    my $observs = $allObs->{$obsType};
	    my $featSubset = pickNSloppy($propObsRound * scalar($observs), $observs);
	    foreach my $impDataset (@impostorsDatasets) {
		$probeDocsRound[0]->{$impDataset} =  filterObservations($probeDocsRound[0]->{$impDataset}, $featSubset);
		$probeDocsRound[1]->{$impDataset} =  filterObservations($probeDocsRound[1]->{$impDataset}, $featSubset);
	    }
	    @impDocRound = map { [ filterObservations($_->[0]->{$obsType}, $featSubset) , $_->[1] ] } @$impostors; # remark: $_->[1] = dataset
	} else {
	    foreach my $impDataset (@impostorsDatasets) {
		$probeDocsRound[0]->{$impDataset} =  pickDocSubset($probeDocsRound[0]->{$impDataset}, $propObsRound);
		$probeDocsRound[1]->{$impDataset} =  pickDocSubset($probeDocsRound[1]->{$impDataset}, $propObsRound);
	    }
	    @impDocRound = map { [ pickDocSubset($_->[0]->{$obsType}, $propObsRound) , $_->[1] ] } @$impostors;
	}
	my $datasetRnd = pickInLIst(@probeDocsListsByDataset); # it makes sense to compare with the same minDocFreq as the impostors, but against which ref dataset doesn't matter so much
	my $probeDocsSim = $self->{simMeasure}->compute($probeDocsRound[0]->{$datasetRnd}, $probeDocsRound[1]->{$datasetRnd});
	my @simRound;
	for (my $probeDocNo=0; $probeDocNo<=1; $probeDocNo++) {
	    for (my $impNo=0; $impNo<scalar(@$impostors); $impNo++) {
		my ($impDoc, $dataset) = ( $impDocRound[$impNo]->[0], $impDocRound[$impNo]->[1] );
		$simRound[$probeDocNo]->[$impNo] = $self->{simMeasure}->compute($probeDocsRound[$probeDocNo]->{$dataset}, $impDoc);
	    }
	}
	push(@res, [ \@probeDocNo,  $probeDocsSim, \@simRound ]);
    }

    return \@res;
}





sub filterObservations {
    my ($doc, $obsSet) = @_;
    my %subset;
    foreach my $obs (@$obsSet) {
	my $freq = $doc->{$obs};
	$subset{$obs} = $freq if (defined($freq));
    }
    return \%subset;
}

sub pickDocSubset {
    my ($doc, $propObsSubset) = @_;
    my %subset;
    my ($obs, $nb);
    while (($obs, $nb) = each %$doc) {
	for (my $i=0; $i< $nb; $i++) {
	    $subset{$obs}++ if (rand() < $propObsSubset);
	}
    }
    return \%subset;
}



# $self->{selectNTimesMostSimilarFirst}>0
#
sub preselectMostSimilarImpostorsDataset {
    my $self = shift;
    my $probeDocsLists = shift;

    my @impostorsDatasets = keys %{$self->{impostors}};
    my %preSelectedImpostors;
    if ($self->{selectNTimesMostSimilarFirst}>0) {
	my $preSimValues = defined($self->{preSimValues}) ? $self->{preSimValues} : computePreSimValues($probeDocsLists);
	my $nbByDataset = $self->{selectNTimesMostSimilarFirst} * $self->{nbImpostorsUsed} / scalar(@impostorsDatasets);

	foreach my $impDataset (@impostorsDatasets) {
	    my $nbToSelect = $nbByDataset;
	    my $impostors = $self->{impostors}->{$impDataset}->getDocsAsList();
	    my @mostSimilarDocs=();
	    while (scalar(@mostSimilarDocs) <= $nbToSelect - scalar(@$impostors)) { # in case not enough impostors
		push(@mostSimilarDocs, @$impostors);
	    }
	    warnLog("Warning: not enough impostors in dataset '$impDataset' for preselecting $nbByDataset docs, using all impostors") if (scalar(@mostSimilarDocs > 0));
	    $nbToSelect = $nbToSelect - scalar(@mostSimilarDocs); # guaranteed to have  0 <= $nbToSelect < scalar(@$impostors)
	    if ($nbToSelect > 0) {
		my @sortedImpBySimByProbe;
		foreach my $probeSide (0,1) {
		    foreach my $probeDoc (@{$probeDocsLists->[$probeSide]}) {
			my $simByImpostor = $preSimValues->{$impDataset}->{$probeDoc->getFilename()}; # $simByImpostor->{impFilename} = sim value
			confessLog("Error: could not find pre-similaritiy values for probe fine '".$probeDoc->getFilename()."'") if (!defined($simByImpostor));
			my @sortedImpBySim = sort { $simByImpostor->{$b} <=> $simByImpostor->{$a} } (keys %$simByImpostor) ;
			$sortedImpBySimByProbe[$probeSide]->{$probeDoc} = \@sortedImpBySim;
		    }
		}
		my $nbSelected=0;
		my %selected;
		while ($nbSelected<$nbToSelect) {
		    my $probeSide = int(rand(2)); # randomly picks one of the sides and one of the docs on this side
		    my $doc = pickInList(@{$probeDocsLists->[$probeSide]});
		    my $impSelected = shift(@{$sortedImpBySimByProbe[$probeSide]->{$doc}}); # gets the most similar impostor for this doc, removing it from the array
		    if (defined($impSelected) && !defined($selected{$impSelected})) {
			$selected{$impSelected} = 1; # not added if the impostor is already in the hash (from different probe docs)
			$nbSelected++;
		    }
		}
		my $impDatasetDocsByFilename = $self->{impostors}->{$impDataset}->getDocsAsHash();
		my @selectedDocs = map { $impDatasetDocsByFilename->{$_} } (keys %selected);
		push(@mostSimilarDocs, @selectedDocs);
	    }
	    $preSelectedImpostors{$impDataset} = \@mostSimilarDocs;
	}
    } else {
	foreach my $impDataset (@impostorsDatasets) {
	    $preSelectedImpostors{$impDataset} = $self->{impostors}->{$impDataset}->getDocsAsList();
	}
    }
    return \%preSelectedImpostors;

}


#
# $self->{selectNTimesMostSimilarFirst}>0 and $self->{preSimValues} undefined
#
sub computePreSimValues {
    my $self = shift;
    my $probeDocsLists = shift;

    my %preSimValues;
    my @impostorsDatasets = keys %{$self->{impostors}};
    my $obsType = defined($self->{preSimObsType}) ? $self->{preSimObsType} : pickInList($self->{obsTypesList});
    foreach my $impDataset (@impostorsDatasets) {
	my %resDataset;
	foreach my $probeSide (0,1) {
	    foreach my $probeDoc (@{$probeDocsLists->[$probeSide]}) {
		my $probeData = $probeDoc->getObservations($obsType);
		my $impostors = $self->{impostors}->{$impDataset}->getDocsAsHash();
		my %resProbe;
		my ($impId, $impDoc);
		while (($impId, $impDoc) = each(%$impostors)) {
		    $resProbe{$impId} = $self->{simMeasure}->compute($probeData, $impDoc->getObservations($obsType) );
		}
		$resDataset{$probeDoc->getFilename()} = \%resProbe;
	    }
	}
	$preSimValues{$impDataset} = \%resDataset;
    }
    return \%preSimValues;
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
