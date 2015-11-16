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
# * preSimValues: used only if selectNTimesMostSimilarFirst>0. preSimValues = [ datasetA => preSimDatasetA, dataset2 => preSimDataset2, ...] which contains at least the datasets provided in <impostors>. each preSimDataset = { probeFilename => { impostorFileName => simValue } }, i.e preSimValues->{dataset}->{probeFilename}->{impostorFilename} = simValue. If selectNTimesMostSimilarFirst>0 but preSimValues is undef, first-stage similarity between probe and impostors is computed using a random obsType. This param is used (1) to provide similiarity values computed in a meaningful way and (2) avoid repeating the process as many times as the method is called, which might be prohibitive in computing time.
#
#
sub new {
    my ($class, $params) = @_;
    my $self = $class->SUPER::new($params);
    $self->{logger} = Log::Log4perl->get_logger(__PACKAGE__) if ($params->{logging});
    $self->{obsTypesList} = $params->{obsTypesList};
    $self->{impostors} = $params->{impostors};
    confessLog($self->{logger}, "Error: at least one impostor dataset must be provided") if (!defined($impostors) || (scalar(@$impostors)==0));
    $self->{nbImpostorsUsed} = defined($params->{nbImpostorsUsed}) ? $params->{nbImpostorsUsed} ; 25;
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
#    ** where docX = hash: docX->{obsType}->{ngram} = freq
#
sub compute {
    my $self = shift;
    my $probeDocsLists = shift;

    # preselect impostors
    my $preSelectedImpostors = ($self->{selectNTimesMostSimilarFirst}>0) ? $self->preselectMostSimilarImpostors() : $self->{impostors};
    my @impostors;
    my @impostorsDatasets = keys %{$self->{impostors}};
    
    # pick impostors set (same for all rounds)
    for (my $i=0; $i< $self->{nbImpostorsUsed}; $i++) {
	my $dataset = pickInList(\@impostorsDatasets);
	my $impostor =  pickInList($self->{impostors}->{$dataset});
	push(@impostors, [$impostor, $dataset]);
    }

    # compute the different versions of the probe documents after filtering the min doc freq, as defined by the different impostors datasets doc freq tables.
    # $probeDocsListByDataset->[0|1]->[docNo]->{impDataset}->{obsType}->{obs} = freq
    my @probeDocsListByDataset;
    foreach my $impDataset (@impostorsDatasets) {
	my $minDocFreq = $impDataset->getMinDocFreq();
	if ($minDocFreq > 1) {
	    my $docFreqTable = $impDataset->getDocFreqTable();
	    for (my $probeDocNo=0; $probeDocNo<=1; $probeDocNo++) {
		for (my $docNo=0; $docNo<scalar(@{$probeDocsLists->[$probeDocNo]}); $docNo++) {
		    $probeDocsListByDataset[$probeDocNo]->[$docNo]->{$impDataset} = filterMinDocFreq($probeDocsList->[$probeDocNo]->[$docNo], $minDocFreq, $docFreqTable);
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
	my $datasetRnd = pickInLIst(@probeDocsListByDataset); # it makes sense to compare with the same minDocFreq as the impostors, but against which ref dataset doesn't matter so much
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



1;
