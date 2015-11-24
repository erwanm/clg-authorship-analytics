package CLGAuthorshipAnalytics::Verification::Impostors;

# EM Oct 2015
# 
#


use strict;
use warnings;
use Carp;
use Log::Log4perl;
use CLGTextTools::Stats qw/pickInList pickNSloppy/;
use CLGTextTools::Commons qw//;
use CLGAuthorshipAnalytics::Verification::VerifStrategy;

our @ISA=qw/CLGAuthorshipAnalytics::Verification::VerifStrategy/;

use base 'Exporter';
our @EXPORT_OK = qw//;






#
# $params:
# * logging
# * obsTypesList 
# * impostors = { dataset1 => DocCollection1,  dataset1 => DocCollection1 } ; impostors will be picked from the various datasets A, B,... with equal probability (i.e. independently from the number of docs in each dataset).
# ** if a DocCollection dataset has a min doc freq threshold > 1, this threshold will be applied to the probe docs (using the doc freq table from the same dataset).  As a consequence, observations which appear in a probe document but not in the impostors  dataset are removed.
# * selectNTimesMostSimilarFirst: if not zero, instead  of picking impostors documents randomly, an initial filtering stage is applied which retrieves the N most similar documents to the probe documents (but with an equal proportion of documents from each impostor dataset), with N = selectNTimesMostSimilarFirst * nbImpostors. This ensures that the most dissimilar impostors are not used, while maintaining a degree of randomness depending on the value of selectNTimesMostSimilarFirst.
# * nbImpostorsUsed: number of impostors documents to select from the impostors dataset (done only once for all rounds) (default 25)
# * nbRounds: number of rounds (higher number -> more randomization, hence less variance in the result) (default 100)
# * propObsSubset: (0<=p<1) the proportion of observations/occurrences to keep in every document at each round; if zero, the proportion is picked randomly at every round (default 0.5)
# * docSubsetMethod: "byOccurrence" -> the proportion is applied to the set of all occurrences; "byObservation" -> applied only to distinct observations (default ByObservation)
# * simMeasure: a CLGTextTools::Measure object (initialized) (default minMax)
# * preSimValues: used only if selectNTimesMostSimilarFirst>0. preSimValues = [ datasetA => preSimDatasetA, dataset2 => preSimDataset2, ...] which contains at least the datasets provided in <impostors>. each preSimDataset = { probeFilename => { impostorFileName => simValue } }, i.e preSimValues->{dataset}->{probeFilename}->{impostorFilename} = simValue.  This parameter is used (1) to provide similiarity values computed in a meaningful way and (2) avoid repeating the process as many times as the method is called, which might be prohibitive in computing time. If selectNTimesMostSimilarFirst>0 but preSimValues is undef, first-stage similarity between probe and impostors is computed using a random obsType, unless preSimObsType is defined (see below).
# * preSimObsType: the obs type to use to compute preselection similarity between probe docs and impostors, if selectNTimesMostSimilarFirst>0 but preSimValues is not. If preSimObsType is not defined either, then a random obs type is used (in this case the quality of the results could be more random)
#
#
sub new {
    my ($class, $params) = @_;
    my $self = $class->SUPER::new($params);
    $self->{logger} = Log::Log4perl->get_logger(__PACKAGE__) if ($params->{logging});
    $self->{obsTypesList} = $params->{obsTypesList};
    my $impostors =  $params->{impostors};
    $self->{impostors} = $impostors;
    confessLog($self->{logger}, "Error: at least one impostor dataset must be provided") if (!defined($impostors) || (scalar(@$impostors)==0));
    $self->{nbImpostorsUsed} = defined($params->{nbImpostorsUsed}) ? $params->{nbImpostorsUsed} : 25;
    $self->{selectNTimesMostSimilarFirst} = defined($params->{selectNTimesMostSimilarFirst}) ? $params->{selectNTimesMostSimilarFirst} : 0;
    $self->{nbRounds} = defined($params->{nbRounds}) ? $params->{nbRounds} : 100;
    $self->{propObsSubset} = defined($params->{propObsSubset}) ? $params->{propObsSubset} : 0.5 ;
    $self->{docSubsetMethod} = defined($params->{docSubsetMethod}) ? $params->{docSubsetMethod} : "byObservation" ;
    $self->{simMeasure} = defined($params->{simMeasure}) ? $params->{simMeasure} : CLGTextTools::SimMeasures::MinMax->new() ;
    $self->{preSimValues} = $params->{preSimValues};
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

    my @impostorsDatasets = keys %{$self->{impostors}};
    # preselect impostors
    my $preSelectedImpostors;
    if ($self->{selectNTimesMostSimilarFirst}>0) {
	$preSelectedImpostors = $self->preselectMostSimilarImpostorsDataset($probeDocsLists) ;
    } else {
	foreach my $impDataset (@impostorsDatasets) {
	    $preSelectedImpostors->{$impDataset} = $self->{impostors}->{$impDataset}->getDocsAsList();
	}
    }
    my @impostors;
    
    # pick impostors set (same for all rounds)
    for (my $i=0; $i< $self->{nbImpostorsUsed}; $i++) {
	my $dataset = pickInList(\@impostorsDatasets);
	my $impostor =  pickInList($preSelectedImpostors->{$dataset});
	push(@impostors, [$impostor, $dataset]);
    }

    my $allObs = undef;
    # compute the different versions of the probe documents after filtering the min doc freq, as defined by the different impostors datasets doc freq tables.
    # $probeDocsListByDataset->[0|1]->[docNo]->{impDataset}->{obsType}->{obs} = freq
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

    my $obsTypes = $self->{obsTypesList};
    my @res;
    for (my $roundNo=0; $roundNo < $self->{nbRounds}; $roundNo++) {
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
	    @impDocRound = map { [ filterObservations($_->[0]->{$obsType}, $featSubset) , $_->[1] ] } @impostors; # remark: $_->[1] = dataset
	} else {
	    foreach my $impDataset (@impostorsDatasets) {
		$probeDocsRound[0]->{$impDataset} =  pickDocSubset($probeDocsRound[0]->{$impDataset}, $propObsRound);
		$probeDocsRound[1]->{$impDataset} =  pickDocSubset($probeDocsRound[1]->{$impDataset}, $propObsRound);
	    }
	    @impDocRound = map { [ pickDocSubset($_->[0]->{$obsType}, $propObsRound) , $_->[1] ] } @impostors;
	}
	my $datasetRnd = pickInLIst(@probeDocsListsByDataset); # it makes sense to compare with the same minDocFreq as the impostors, but against which ref dataset doesn't matter so much
	my $probeDocsSim = $self->{simMeasure}->compute($probeDocsRound[0]->{$datasetRnd}, $probeDocsRound[1]->{$datasetRnd});
	my @simRound;
	for (my $probeDocNo=0; $probeDocNo<=1; $probeDocNo++) {
	    for (my $impNo=0; $impNo<scalar(@impostors); $impNo++) {
		my ($impDoc, $dataset) = ( $impDocRound[$impNo]->[0], $impDocRound[$impNo]->[1] );
		$simRound[$probeDocNo]->[$impNo] = $self->{simMeasure}->compute($probeDocsRound[$probeDocNo]->{$dataset}, $impDoc);
	    }
	}
	push(@res, [ \@probeDocNo,  $probeDocsSim, \@simRound ]);
    }

#  TODO: return what?

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

    my $preSimValues = defined($self->{preSimValues}) ? $self->{preSimValues} : computePreSimValues($probeDocsLists);
    my @impostorsDatasets = keys %{$self->{impostors}};
    my $nbByDataset = $self->{selectNTimesMostSimilarFirst} * $self->{nbImpostorsUsed} / scalar(@impostorsDatasets);
    my @resAllImpostors;

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
	    push(@resAllImpostors, @mostSimilarDocs);
	}
    }
    

    return \@resAllImpostors;
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


1;
