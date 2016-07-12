package CLGAuthorshipAnalytics::Verification::Impostors;

#twdoc
#
# "Impostors" verification strategy (see "Determining if Two Documents are by the Same Author" by Koppel and Winter, 2014):
#  Portions of the tested documents are repeatedly compared to each other and to other external (portions of) external documents (impostors). If the similarity between the tested documents is significantly higher than the similarity obtained between a tested document and an impostor, then the tested documents are likely to be by the same author.
#
# ---
# EM Oct 2015
# 
#/twdoc


use strict;
use warnings;
use Carp;
use Log::Log4perl;
use CLGTextTools::Stats qw/pickInList pickNSloppy aggregateVector pickDocSubset pickIndex getDocSize/;
use CLGAuthorshipAnalytics::Verification::VerifStrategy;
use CLGTextTools::Logging qw/confessLog cluckLog warnLog/;
use CLGTextTools::DocCollection qw/createDatasetsFromParams filterMinDocFreq/;
use CLGTextTools::Commons qw/assignDefaultAndWarnIfUndef readTSVFileLinesAsHash rankWithTies/;
use CLGTextTools::SimMeasures::Measure qw/createSimMeasureFromId/;

use File::Basename;
use Data::Dumper;

our @ISA=qw/CLGAuthorshipAnalytics::Verification::VerifStrategy/;
our $nanStr = "NA";
use base 'Exporter';

our $decimalDigits = 10;




#twdoc new($class, $params)
#
# $params is a hash with (possibly) the following elements:
#
# * logging
# * obsTypesList 
# * impostors = ``{ dataset1 => DocCollection1,  dataset2 => DocCollection2 }`` ; impostors will be picked from the various datasets A, B,... with equal probability (i.e. independently from the number of docs in each dataset).
# ** if a ``DocCollection`` dataset has a min doc freq threshold > 1, this threshold will be applied to the probe docs (using the doc freq table from the same dataset).  As a consequence, observations which appear in a probe document but not in the impostors  dataset are removed.
# ** Alternatively, $impostors can be a string with format ``'datasetid1;datasetId2;...'``; the fact that it is not a hash ref is used as marker for this option. In this case parameter 'datasetResources'  must be set.
# * datasetResources = ``{ datasetId1 => path1, datasetId2 => path2, ...}``. Used only if impostors is not provided as a list of ``DocCollection`` (see above).  ``pathX`` is a path where the files included in the dataset are located. datasetResources can only be a single string corresponding to the path where all datasets are located under their ids as a subdir of the subdir impostors, i.e. ``<datasetResources>/impostors/<datasetId>/``
# * minDocFreq: optional (default 1); used only if impostors not provided as a list of ``DocCollection`` objects
# * filePattern: optional (default ``*.txt``); used only if impostors not provided as a list of ``DocCollection`` objects (describes the files used as impostor docs in the directory).

# * selectNTimesMostSimilarFirst: if not zero, instead  of picking impostors documents randomly, an initial filtering stage is applied which retrieves the N most similar documents to the probe documents (but with an equal proportion of documents from each impostor dataset), with N = selectNTimesMostSimilarFirst * nbImpostors. This ensures that the most dissimilar impostors are not used, while maintaining a degree of randomness depending on the value of selectNTimesMostSimilarFirst.
# * nbImpostorsUsed: number of impostors documents to select from the impostors dataset (done only once for all rounds) (default 25)
# * nbRounds: number of rounds (higher number -> more randomization, hence less variance in the result) (default 100)
# * propObsSubset: (0<=p<1) the proportion of observations/occurrences to keep in every document at each round; if zero, the proportion is picked randomly at every round (default 0.5)
# * docSubsetMethod: "byOccurrence" -> the proportion is applied to the set of all occurrences; "byObservation" -> applied only to distinct observations (default byObservation)
# * simMeasure: a ``CLGTextTools::Measure`` object (initialized) (default minMax)
# * preSimValues: used only if selectNTimesMostSimilarFirst>0. preSimValues = ``[ datasetA => preSimDatasetA, dataset2 => preSimDataset2, ...]`` which contains at least the datasets provided in ``impostors``. each preSimDataset = ``{ probeFilename => { impostorFileName => simValue } }``, i.e ``preSimValues->{dataset}->{probeFilename}->{impostorFilename} = simValue``.  This parameter is used (1) to provide similiarity values computed in a meaningful way and (2) avoid repeating the process as many times as the method is called, which might be prohibitive in computing time. If selectNTimesMostSimilarFirst>0 but preSimValues is undef or the specific similarity between a probe file and n impostors is not defined, then pre-similarity are loaded from ``<probeFile>.simdir/<impDataset>.similarities``. 
# * useCountMostSimFeature: 0, original, ASGALF, ASGALFavg. if not "0", the "count most similar" feature is computed with the specified variant; default: "original".
# * kNearestNeighbors: uses only the K (value) most similar impostors when calculating result features. default: 0 (use all impostors).
# * mostSimilarFirst: doc or run: specifies whether the K most similar impostors are selected globally (doc) or for each run (run); unused if GI_kNearestNeighbors=0. Default: doc.
# * aggregRelRank: 0, median, arithm, geom, harmo. if not 0, computes the relative rank of the sim between A and B among sim against all impostors by round; the value is used to aggregate all relative ranks (i.e. the values by round). Default: 0.
# * useAggregateSim: 0, diff, ratio. if not 0, computes X = the aggregate sim value between A and B across all runs and Y= the aggregate sim value between any probe and any impostor across all rounds; returns A-B (diff) or A/B (ratio); default : 0.
# * aggregateSimStat:  median, arithm, geom, harmo. aggregate method to use if useAggregateSim is not 0 (ignored if 0). default: arithm.
#
#/twdoc
#
sub new {
    my ($class, $params) = @_;
    my $self = $class->SUPER::new($params, __PACKAGE__);
    $self->{obsTypesList} = $params->{obsTypesList};
    my $impostors =  $params->{impostors};
    $self->{impostors} = $impostors;
    confessLog($self->{logger}, "Error: at least one impostor dataset must be provided") if (!defined($impostors) || (ref($impostors) && (scalar(@$impostors)==0)) || (!ref($impostors) && ($impostors eq "")));
    if (!ref($impostors)) { # if impostors not provided directly as a list of DocCollection objects
	confessLog($self->{logger}, "Error: if impostors are not provided as a list of DocCollection objects, then parameter 'datasetResources' must be defined.") if (!defined($params->{datasetResources}));
	my @impDatasetsIds = split(/;/, $impostors);
	my %impParams = %$params;
	$impParams{useCountFiles} = 1; # TODO possible problem if the disk is not writable and some count files are generated.
        # minDocFreq is not applied to all the impostors dataset, because this requires loading all observations from all docs
        # instead, it will be applied only to the selected impostors in pickImpostors.
#	$self->{impostors} = createDatasetsFromParams(\%impParams, \@impDatasetsIds, $params->{datasetResources}."/impostors", $params->{minDocFreq}, $params->{filePattern}, $self->{logger});
	$self->{impostors} = createDatasetsFromParams(\%impParams, \@impDatasetsIds, $params->{datasetResources}."/impostors", 0, $params->{filePattern}, $self->{logger});
    }
    $self->{minDocFreq} = defined($params->{minDocFreq}) ?  $params->{minDocFreq} : 1;
    $self->{nbImpostorsUsed} = assignDefaultAndWarnIfUndef("nbImpostorsUsed", $params->{nbImpostorsUsed}, 25, $self->{logger});
    $self->{selectNTimesMostSimilarFirst} = assignDefaultAndWarnIfUndef("selectNTimesMostSimilarFirst", $params->{selectNTimesMostSimilarFirst}, 0, $self->{logger});
    $self->{nbRounds} = assignDefaultAndWarnIfUndef("nbRounds", $params->{nbRounds}, 100, $self->{logger});
    $self->{propObsSubset} = assignDefaultAndWarnIfUndef("propObsSubset", $params->{propObsSubset}, 0.5, $self->{logger});
    $self->{docSubsetMethod} = assignDefaultAndWarnIfUndef("docSubsetMethod", $params->{docSubsetMethod}, "byObservation", $self->{logger}) ;
    $self->{simMeasure} = createSimMeasureFromId(assignDefaultAndWarnIfUndef("simMeasure", $params->{simMeasure}, "minmax", $self->{logger}), $params, 1);
    $self->{preSimValues} = $params->{preSimValues};
    $self->{GI_useCountMostSimFeature} = assignDefaultAndWarnIfUndef("useCountMostSimFeature", $params->{useCountMostSimFeature}, "original", $self->{logger});
    $self->{GI_kNearestNeighbors} = assignDefaultAndWarnIfUndef("kNearestNeighbors", $params->{kNearestNeighbors}, 0, $self->{logger});
    $self->{GI_mostSimilarFirst} =  assignDefaultAndWarnIfUndef("mostSimilarFirst", $params->{mostSimilarFirst}, "doc", $self->{logger});
    $self->{GI_aggregRelRank} = assignDefaultAndWarnIfUndef("aggregRelRank", $params->{aggregRelRank}, "0", $self->{logger});
    $self->{useAggregateSim} = assignDefaultAndWarnIfUndef("useAggregateSim", $params->{useAggregateSim}, "0", $self->{logger});
    $self->{GI_aggregateSimStat} = assignDefaultAndWarnIfUndef("aggregateSimStat", $params->{aggregateSimStat},  "arithm", $self->{logger});
    if (($self->{GI_useCountMostSimFeature} eq "0") && ($self->{GI_aggregRelRank} eq "0") && ($self->{useAggregateSim} eq "0")) {
	warnLog($self->{logger}, "Impostors strategy: no output feature selected at all. Setting parameter 'GI_useCountMostSimFeature' to  default 'original'.");
	$self->{GI_useCountMostSimFeature} = "original";
    }

    bless($self, $class);
#    print STDERR Dumper($self);
    return $self;
}


#twdoc compute($self, $probeDocsLists, $writeScoresTableToFile)
#
# see parent.
#
# * $probeDocsLists: [ [docA1, docA2, ...] ,  [docB1, docB2,...] ]
# ** where docX = ``DocProvider``
# * writeScoresTableToFile (optional)
#/twdoc
#
sub compute {
    my $self = shift;
    my $probeDocsLists = shift;
    my $writeScoresTableToFile = shift;

    $self->{logger}->debug("Impostors strategy: computing features between pair of sets of docs") if ($self->{logger});
    confessLog($self->{logger}, "Cannot process case: no obs types at all") if ((scalar(@{$self->{obsTypesList}})==0) && $self->{logger});
    my $preseletedImpostors = $self->preselectMostSimilarImpostorsDataset($probeDocsLists);
#    foreach my $dataset (keys %$preseletedImpostors) {
#	print STDERR "DEBUG imp dataset = $dataset\n";
#	foreach my $imp (@{$preseletedImpostors->{$dataset}}) {
#	    print STDERR "DEBUG  imp id = '".$imp->getId()."'\n";
#	}
#   }
    my $selectedImpostors = $self->pickImpostors($preseletedImpostors);
    my $scores = $self->computeGI($probeDocsLists, $selectedImpostors);
    $self->writeScoresToFile($scores, $writeScoresTableToFile) if (defined($writeScoresTableToFile));
    return $self->featuresFromScores($scores);
}


#
#
# input: $allImpostorsDatasets->{datasetId}->[impNo] = DocProvider
# output: [ [impostorDocProvider1, datasetId1], ... ]
#
sub pickImpostors {
    my $self = shift;
    my $allImpostorsDatasets = shift;
    my @resImpostors;
    my %countDataset;

    $self->{logger}->trace("Picking a set of impostors randomly") if ($self->{logger});
    my @impostorsDatasets = keys %{$self->{impostors}};
    # pick impostors set (same for all rounds)
    for (my $i=0; $i< $self->{nbImpostorsUsed}; $i++) {
	my $dataset = pickInList(\@impostorsDatasets);
	my $impostor =  pickInList($allImpostorsDatasets->{$dataset});
	$self->{logger}->trace("$i th impostor: picked '".$impostor->getFilename()."' in dataset '$dataset'") if ($self->{logger});
	# apply min doc freq if needed
	my $minDocFreqColl = $self->{impostors}->{$dataset}->getMinDocFreq();
	my $minDocFreq = ($self->{minDocFreq} > $minDocFreqColl) ? $self->{minDocFreq} : $minDocFreqColl ;
	if ($minDocFreq > 1) {
	    $self->{logger}->trace("Applying min doc freq to doc $i '".$impostor->getFilename()."' minDocFreq = $minDocFreq") if ($self->{logger});
	    filterMinDocFreq($impostor->getObservations(), $minDocFreq, $self->{impostors}->{$dataset}->getDocFreqTable(), 1);
	}
	$countDataset{$dataset}++ if ($self->{logger});
	push(@resImpostors, [$impostor, $dataset]);
    }
     if ($self->{logger}) {
	 foreach my $dataset (keys %countDataset) {
	     $self->{logger}->debug("Selected $countDataset{$dataset} impostors from dataset $dataset.");
	 }
     }
    $self->{logger}->trace("Selected impostors: ".Dumper(\@resImpostors)) if ($self->{logger});

    
    return \@resImpostors;
}


#twdoc  computeGI($self, $probeDocsLists, $impostors)
#
# * $probeDocsLists: [ [docA1, docA2, ...] ,  [docB1, docB2,...] ]
# ** where docX = ``DocProvider``
# * $impostors : [ [impostorDocProvider1, datasetId1], ... ]
# * output: $scores->[roundNo] = [  [ probeDocNoA, probeDocNoB ], simProbeAvsB, $simRound ], with $simRound->[probe0Or1]->[impostorNo]
#
#/twdoc
#
sub computeGI {
    my $self = shift;
    my $probeDocsLists = shift;
    my $impostors = shift;

    my @impostorsDatasets = keys %{$self->{impostors}};
    
    $self->{logger}->debug("Starting computeGI") if ($self->{logger});
    my $allObs = undef;
    # compute the different versions of the probe documents after filtering the min doc freq, as defined by the different impostors datasets doc freq tables.
    # $probeDocsListsByDataset->[0|1]->[docNo]->{impDataset}->{obsType}->{obs} = freq
    my @probeDocsListsByDataset;
    foreach my $impDataset (@impostorsDatasets) {
	$self->{logger}->debug("Preparing probe docs w.r.t impostor sets: dataset '$impDataset'") if ($self->{logger});
	my $minDocFreqColl = $self->{impostors}->{$impDataset}->getMinDocFreq();
	my $minDocFreq = ($self->{minDocFreq} > $minDocFreqColl) ? $self->{minDocFreq} : $minDocFreqColl ;
	if ($minDocFreq > 1) {
	    $self->{logger}->trace("Applying minDocFreq=$minDocFreq for '$impDataset'") if ($self->{logger});
	    my $docFreqTable = $self->{impostors}->{$impDataset}->getDocFreqTable();
	    for (my $probeDocNo=0; $probeDocNo<=1; $probeDocNo++) {
		for (my $docNo=0; $docNo<scalar(@{$probeDocsLists->[$probeDocNo]}); $docNo++) {
		    $probeDocsListsByDataset[$probeDocNo]->[$docNo]->{$impDataset} = filterMinDocFreq($probeDocsLists->[$probeDocNo]->[$docNo]->getObservations(), $minDocFreq, $docFreqTable);
		}
	    }
	    if ($self->{docSubsetMethod} eq "byObservation") {
		$self->{logger}->trace("Option 'byObservation is on, computing list of all observations for '$impDataset'") if ($self->{logger});
		foreach my $obsType (@{$self->{obsTypesList}}) {
		    my ($obs, $docFreq);
		    my @obsTypeObservs;
		    while (($obs, $docFreq) = each %{$docFreqTable->{$obsType}}) {
			push(@obsTypeObservs, $obs) if ($docFreq >= $minDocFreq);
		    }
		    push(@{$allObs->{$obsType}}, @obsTypeObservs);
		    $self->{logger}->debug("byObservations: added ".scalar(@obsTypeObservs)." observations to allObs for obs type $obsType. Current total: ".scalar(@{$allObs->{$obsType}})) if ($self->{logger});
		}
	    }	
	} else {
	    $self->{logger}->debug("No min doc freq to apply") if ($self->{logger});
	    for (my $probeDocNo=0; $probeDocNo<=1; $probeDocNo++) {
		for (my $docNo=0; $docNo<scalar(@{$probeDocsLists->[$probeDocNo]}); $docNo++) {
		    $probeDocsListsByDataset[$probeDocNo]->[$docNo]->{$impDataset} = $probeDocsLists->[$probeDocNo]->[$docNo]->getObservations();
		}
	    }
	    if ($self->{docSubsetMethod} eq "byObservation") {
		my $docFreqTable = $self->{impostors}->{$impDataset}->getDocFreqTable();
		foreach my $obsType (@{$self->{obsTypesList}}) {
		    push(@{$allObs->{$obsType}}, keys %{$docFreqTable->{$obsType}});
		    $self->{logger}->debug("byObservations: added observations to allObs for obs type $obsType. Current total: ".scalar(@{$allObs->{$obsType}})) if ($self->{logger});
		}
	    }
	}
    }

    $self->{logger}->trace("Prepared probe documents = ".Dumper(\@probeDocsListsByDataset)) if ($self->{logger});
    $self->{logger}->debug("computeGI: starting rounds") if ($self->{logger});

    my $obsTypes = $self->{obsTypesList};
    my @res;
    for (my $roundNo=0; $roundNo < $self->{nbRounds}; $roundNo++) {
	my @probeDocNo = (pickIndex($probeDocsListsByDataset[0]) , pickIndex($probeDocsListsByDataset[1]));
	my $obsType = pickInList($obsTypes);
	my $propObsRound = ($self->{propObsSubset} > 0) ? $self->{propObsSubset} : rand();
	$self->{logger}->debug("round $roundNo: probeDocNos = ($probeDocNo[0],$probeDocNo[1]); obsType = $obsType; propObsRound = $propObsRound") if ($self->{logger});
#	my @probeDocsRound = ($probeDocsListsByDataset[0]->[$probeDocNo[0]], $probeDocsListsByDataset[1]->[$probeDocNo[1]] );
	my @probeDocsRound;
	my @impDocRound;
	if (defined($allObs)) {
	    my $observs = $allObs->{$obsType};
#	    print STDERR Dumper($observs);
#	    die "stop";
	    my $nb = int($propObsRound * scalar(@$observs) +0.5);
	    $self->{logger}->trace("byObs: propObsRound=$propObsRound; scalar(observs)=".scalar(@$observs)."; picking $nb observations.") if($self->{logger});
	    my $featSubset = pickNSloppy($nb, $observs);
	    $self->{logger}->trace("byObs: picked ".scalar(@$featSubset)." observations.") if($self->{logger});
	    $self->{logger}->trace("Filtering observations for probe docs") if($self->{logger});
	    foreach my $impDataset (@impostorsDatasets) {
		$probeDocsRound[0]->{$impDataset} = filterObservations($probeDocsListsByDataset[0]->[$probeDocNo[0]]->{$impDataset}->{$obsType}, $featSubset);
		$probeDocsRound[1]->{$impDataset} = filterObservations($probeDocsListsByDataset[1]->[$probeDocNo[1]]->{$impDataset}->{$obsType}, $featSubset);
	    }
	    $self->{logger}->trace("Filtering observations for impostors") if($self->{logger});
	    @impDocRound = map { [ filterObservations($_->[0]->getObservations($obsType), $featSubset) , $_->[1] ] } @$impostors; # remark: $_->[1] = dataset
	} else {
	    $self->{logger}->trace("byOccurrence: picking doc subset for probe docs") if ($self->{logger});
	    foreach my $impDataset (@impostorsDatasets) {
		$probeDocsRound[0]->{$impDataset} = pickDocSubset($probeDocsListsByDataset[0]->[$probeDocNo[0]]->{$impDataset}->{$obsType}, $propObsRound, $self->{logger});
		$probeDocsRound[1]->{$impDataset} = pickDocSubset($probeDocsListsByDataset[1]->[$probeDocNo[1]]->{$impDataset}->{$obsType}, $propObsRound, $self->{logger});
	    }
	    $self->{logger}->trace("byOccurrence: picking doc subset for impostors") if ($self->{logger});
	    @impDocRound = map { [ pickDocSubset($_->[0]->getObservations($obsType), $propObsRound, $self->{logger}) , $_->[1] ] } @$impostors;
	}
	my $datasetRnd = pickInList(\@impostorsDatasets); # it makes sense to compare with the same minDocFreq as the impostors, but against which ref dataset doesn't matter so much
	my @probeDocsRoundSize;
	$self->{logger}->trace("computing similarity between selected probe docs (using dataset '$datasetRnd')") if ($self->{logger});
	for (my $probeDocNo=0; $probeDocNo<=1; $probeDocNo++) {
	    $probeDocsRoundSize[$probeDocNo]->{$datasetRnd} = getDocSize($probeDocsRound[$probeDocNo]->{$datasetRnd}); # size of probe doc computed on the fly and reused later if needed
	}
	my $probeDocsSim = $self->{simMeasure}->normalizeCompute($probeDocsRound[0]->{$datasetRnd}, $probeDocsRound[1]->{$datasetRnd}, $probeDocsRoundSize[0]->{$datasetRnd}, $probeDocsRoundSize[1]->{$datasetRnd}, $self->{logger});
	my @simRound;
	for (my $impNo=0; $impNo<scalar(@$impostors); $impNo++) {
	    my ($impDoc, $dataset) = ( $impDocRound[$impNo]->[0], $impDocRound[$impNo]->[1] );
	    my $impSize = getDocSize($impDoc);
	    for (my $probeDocNo=0; $probeDocNo<=1; $probeDocNo++) {
		$self->{logger}->trace("computing similarity between probe doc side $probeDocNo and impostor $impNo from dataset '$dataset'") if ($self->{logger});
		$probeDocsRoundSize[$probeDocNo]->{$dataset} = getDocSize($probeDocsRound[$probeDocNo]->{$dataset}) if (!defined($probeDocsRoundSize[$probeDocNo]->{$dataset})); # size of probe doc computed on the fly and reused later if needed
		$simRound[$probeDocNo]->[$impNo] = $self->{simMeasure}->normalizeCompute($probeDocsRound[$probeDocNo]->{$dataset}, $impDoc, $probeDocsRoundSize[$probeDocNo]->{$dataset}, $impSize, $self->{logger});
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


#twdoc preselectMostSimilarImpostorsDataset($self, $probeDocsLists)
#
# for each impostors dataset, selects a subset of the documents which are the most similar to the input probe documents. The similarity between the impostors and the
# probe documents must have been precomputed, either provided directly in the parameter ``preSimValues`` or the corresponding similarity files must have been stored previously.
#
#/twdoc
#
sub preselectMostSimilarImpostorsDataset {
    my $self = shift;
    my $probeDocsLists = shift;

    $self->{logger}->debug("Preselecting most similar impostors") if ($self->{logger});
    my @impostorsDatasets = keys %{$self->{impostors}};
    my %preSelectedImpostors;
    if ($self->{selectNTimesMostSimilarFirst}>0) {
#	my $preSimValues = defined($self->{preSimValues}) ? $self->{preSimValues} : $self->computePreSimValues($probeDocsLists);
	my $preSimValues = defined($self->{preSimValues}) ? $self->{preSimValues} : {};
	my $nbByDataset = $self->{selectNTimesMostSimilarFirst} * $self->{nbImpostorsUsed} / scalar(@impostorsDatasets);
	$self->{logger}->debug("Preselecting $nbByDataset impostors by dataset (selectNTimesMostSimilarFirst=".$self->{selectNTimesMostSimilarFirst}." x nbImpostorsUsed=".$self->{nbImpostorsUsed}." / nb datasets = ".scalar(@impostorsDatasets).")") if ($self->{logger});

	foreach my $impDataset (@impostorsDatasets) {
	    my $nbToSelect = $nbByDataset;
	    my $impostors = $self->{impostors}->{$impDataset}->getDocsAsList();
	    confessLog($self->{logger}, "Error: 0 impostors in dataset '$impDataset'") if (scalar(@$impostors) == 0);
	    $self->{logger}->debug("dataset '$impDataset': ".scalar(@$impostors)." impostors available, we need $nbToSelect.") if ($self->{logger});
	    my @mostSimilarDocs=();
	    while (scalar(@mostSimilarDocs) <= $nbToSelect - scalar(@$impostors)) { # in case not enough impostors
		$self->{logger}->trace("padding dataset '$impDataset': we have ".scalar(@mostSimilarDocs).", we need $nbToSelect.") if ($self->{logger});
		push(@mostSimilarDocs, @$impostors);
	    }
	    warnLog($self->{logger}, "Warning: not enough impostors in dataset '$impDataset' for preselecting $nbByDataset docs, using all impostors") if (scalar(@mostSimilarDocs) > 0);
	    $nbToSelect = $nbToSelect - scalar(@mostSimilarDocs); # guaranteed to have  0 <= $nbToSelect < scalar(@$impostors)
	    if ($nbToSelect > 0) {
		my @sortedImpBySimByProbe;
		foreach my $probeSide (0,1) {
		    foreach my $probeDoc (@{$probeDocsLists->[$probeSide]}) {
			my $simByImpostor = $preSimValues->{$impDataset}->{$probeDoc->getFilename()}; # $simByImpostor->{impFilename} = sim value
			if (!defined($simByImpostor)) {
			    $simByImpostor = $self->loadPreSimValues($probeDoc, $impDataset);
			    $preSimValues->{$impDataset}->{$probeDoc->getFilename()} = $simByImpostor;  # update the hash (for the caller to get the values back)
			}
			$self->{logger}->trace("Sorting impostors by similarity against  probe file '".$probeDoc->getFilename()."'") if ($self->{logger});
			my @sortedImpBySim = sort { $simByImpostor->{$b} <=> $simByImpostor->{$a} } (keys %$simByImpostor) ;
			$sortedImpBySimByProbe[$probeSide]->{$probeDoc} = \@sortedImpBySim;
#			print STDERR Dumper($sortedImpBySimByProbe[$probeSide]->{$probeDoc});
		    }
		}
		my $nbSelected=0;
		my %selected;
		$self->{logger}->debug("selecting impostors for dataset '$impDataset'") if ($self->{logger});
		while ($nbSelected<$nbToSelect) {
		    my $probeSide = int(rand(2)); # randomly picks one of the sides and one of the docs on this side
		    my $doc = pickInList($probeDocsLists->[$probeSide]);
		    my $impSelected = shift(@{$sortedImpBySimByProbe[$probeSide]->{$doc}}); # gets the most similar impostor for this doc, removing it from the array
		    $self->{logger}->trace("picked probe doc '".$doc->getFilename()."' (side $probeSide) -> impostor '$impSelected' (sim=".$preSimValues->{$impDataset}->{$doc->getFilename()}->{$impSelected}.") ...") if ($self->{logger});
		    if (defined($impSelected) && !defined($selected{$impSelected})) { # not added if the impostor is already in the hash (from different probe docs)
			$self->{logger}->trace("impostor '$impSelected' added") if ($self->{logger});
			$selected{$impSelected} = 1;
			$nbSelected++;
		    }
		}
		my $impDatasetDocsByFilename = $self->{impostors}->{$impDataset}->getDocsAsHash();
		# CAUTION!! converting to obtain the basename, which is used as id in the precomputed similarities. not clean, but too hard to change everything now (and not sure how)
		my ($filename, $doc);
		my %impDatasetDocsById;
		while (my ($filename, $doc)  = each %$impDatasetDocsByFilename) {
		   $impDatasetDocsById{basename($filename)} = $doc; 
		}
		my @selectedDocs = map { $impDatasetDocsById{$_} } (keys %selected);
		$self->{logger}->debug("selected ".scalar(@selectedDocs)." impostors for dataset '$impDataset'")  if ($self->{logger});
#		print STDERR Dumper(\@selectedDocs);
		push(@mostSimilarDocs, @selectedDocs);
	    }
	    $preSelectedImpostors{$impDataset} = \@mostSimilarDocs;
	}
    } else {
	$self->{logger}->debug("Preselecting all impostors docs (no similarity-based preselection)") if ($self->{logger});
	foreach my $impDataset (@impostorsDatasets) {
	    my $imps = $self->{impostors}->{$impDataset}->getDocsAsList();
	    $self->{logger}->trace("impDataset '$impDataset': ".scalar(@$imps)." impostors") if ($self->{logger});
	    $preSelectedImpostors{$impDataset} = $imps;
	}
    }
    return \%preSelectedImpostors;

}


#
# returns a hash: preSim{impostorId} = simValue
#
sub loadPreSimValues {
    my $self = shift;
    my $probeDoc = shift;
    my $impDataset = shift;

    $self->{logger}->debug("Trying to load pre-sim values from file...") if ($self->{logger});
    my $res = loadPreSimValuesFile($probeDoc->getFilename(), $impDataset, $self->{logger});
    if (defined($res)) { # the sim file was found and its content loaded
	# checking that we have a sim value for each impostor, because if not this will cause problems later
	my $impostors = $self->{impostors}->{$impDataset}->getDocsAsHash();
	foreach my $impFile (keys %$impostors) {
	    my $impId=basename($impFile);
	    confessLog($self->{logger}, "Error loading pre-sim values: no value found for impostor '$impId' (probe file ".$probeDoc->getFilename().", dataset '$impDataset')") if (!defined($res->{$impId}));
	}
	return $res ;
    } else { # otherwise the file was not found, sim values have to be computed
	confessLog($self->{logger}, "Pre-sim values: not provided and not found for file '".$probeDoc->getFilename()."'");
    }
}


#
# loadPreSimValuesFile($probeFile, $impDataset, $logger)
# static
#
# if the file exists, loads pre-similarty values from file <probeFile>.simdir/<impDataset>.similarities, which contains lines of the form: ``<impostor filename> <sim value>``; returns undef otherwise
#
# * $logger is optional.
#
sub  loadPreSimValuesFile {
    my ($probeFile, $impDataset, $logger) = @_;
    my $f = "$probeFile.simdir/$impDataset.similarities";
    if ( -f $f) {
	$logger->debug("Load pre-sim values from '$f'") if ($logger);
	my $sims = readTSVFileLinesAsHash($f, $logger);
	return $sims;
    } else {
	$logger->debug("File '$f' does not exist, returning undef") if ($logger);
	return undef;
    }
}



#
# scores: $scores->[roundNo] = [  [ probeDocNoA, probeDocNoB ], simProbeAvsB, $simRound ], with 
#         $simRound->[probe0Or1]->[impostorNo] = sim between doc probe0or1 and imp $impostorNo (as returned by computeGI)
#
sub featuresFromScores {
    my ($self, $scores) = @_;

    my @features;
    $self->{logger}->debug("Computing final features from table of scores") if ($self->{logger});
    $self->removeLeastSimilar($scores); # keeps only K most similar if K>0
    if ($self->{GI_useCountMostSimFeature} ne "0") {
	my $mostSimImpNo = $self->getKMostSimilarImpostorsGlobal($scores, 1);
	my @impNo = ($mostSimImpNo->[0]->[0], $mostSimImpNo->[1]->[0]); 
	$self->{logger}->debug("GI_useCountMostSimFeature is true: most similar impostor for both probe sides = ".join(";", @impNo)) if ($self->{logger});
	# extract vector of similarities (by round) for each probe (from the most similar impostor no)
	my @simImp0 = map { $_->[2]->[0]->[$impNo[0]] } @$scores; # nb rounds items
	my @simImp1 = map { $_->[2]->[1]->[$impNo[1]] } @$scores; # nb rounds items
	$self->{logger}->trace("Sim values for the selected impostor, probe side 0: ".join("; ", @simImp0))  if ($self->{logger});
	$self->{logger}->trace("Sim values for the selected impostor, probe side 1: ".join("; ", @simImp1))  if ($self->{logger});
	my @simValuesProbeDocs = map { $_->[1] } (@$scores);
	$self->{logger}->trace("Sim values between the two probe sides:             ".join("; ", @simValuesProbeDocs))  if ($self->{logger});
	push(@features, $self->countMostSimFeature(\@simValuesProbeDocs ,[\@simImp0, \@simImp1]));
    }
    push(@features, $self->relativeRankFeature($scores)) if ($self->{GI_aggregRelRank} ne "0");
    push(@features, $self->aggregateSimComparison($scores)) if ($self->{useAggregateSim} ne "0");
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
	$self->{logger}->debug("Retaining only $k most similar impostors for each run, either globally or by run") if ($self->{logger});
	my $keepOnly = undef;
	if ($self->{GI_mostSimilarFirst} eq "doc") {
	    $keepOnly  = $self->getKMostSimilarImpostorsGlobal($scores, $k); # $keepOnly->[probeSide] = [ i1, i2, ... ]
	    $self->{logger}->trace("using scores from globally-selected $k most similar impostors: side 0 = [".join(",", @{$keepOnly->[0]})."] ; side 1 = [".join(",", @{$keepOnly->[1]})."]") if ($self->{logger});
	}
	for (my $roundNo = 0; $roundNo < $nbRounds; $roundNo++) {
	    foreach my $probeNo (0,1) {
		if (defined($keepOnly)) { # global (doc)
		    my @selected = map { $scores->[$roundNo]->[2]->[$probeNo]->[$_] } @{$keepOnly->[$probeNo]};
		    $scores->[$roundNo]->[2]->[$probeNo] =  \@selected;
		} else { # most similar by run
		    my @sorted0 = sort { $b <=> $a } @{$scores->[$roundNo]->[2]->[$probeNo]}; # sim values!
		    my @sortedK = @sorted0[0..$k-1];
		    $self->{logger}->trace("round=$roundNo,side=$probeNo: using scores from $k most similar impostors for this run: [".join(",", @sortedK)."]") if ($self->{logger});
		    $scores->[$roundNo]->[2]->[$probeNo] = \@sortedK;
		}
	    }
	}
    } else {
	warnLog($self->{logger}, "Warning: using $k most similar among $nbImp impostors") if ($k >= $nbImp);
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
    my $nbCounted=0;
    for (my $i=0; $i<scalar(@$probeSimVector); $i++) { # iterate rounds
	if ($self->{GI_useCountMostSimFeature} eq "original") {
	    $sum++ if ( $probeSimVector->[$i]**2 > ($impSimVectors->[0]->[$i] * $impSimVectors->[1]->[$i]) );
	    $nbCounted++;
	} elsif ($self->{GI_useCountMostSimFeature} eq "ASGALF") {
	    if ($impSimVectors->[0]->[$i] * $impSimVectors->[1]->[$i] != 0) {
		$sum +=  ( $probeSimVector->[$i]**2 / ($impSimVectors->[0]->[$i] * $impSimVectors->[1]->[$i]) );
		$nbCounted++;
	    }
	} elsif ($self->{GI_useCountMostSimFeature} eq "ASGALFavg") {
	    if ($impSimVectors->[0]->[$i] + $impSimVectors->[1]->[$i] != 0) {
		$sum +=  ( $probeSimVector->[$i] * 2 / ($impSimVectors->[0]->[$i] + $impSimVectors->[1]->[$i]) );
		$nbCounted++;
	    }
	} else {
	    confessLog($self->{logger}, "Error: invalid value '".$self->{GI_useCountMostSimFeature}."' for param 'GI_useCountMostSimFeature' ");
	}
    }
    $self->{logger}->debug("Counting most similar between probe values and impostor values, method '".$self->{GI_useCountMostSimFeature}."': sum = $sum; nb rounds counted = $nbCounted; 'normalized' score = ".($sum / $nbCounted))  if ($self->{logger});
    if ($nbCounted == 0) {
	warnLog($self->{logger}, "Warning: no round counted at all in 'countMostSimFeature'");
	return $nanStr;
    } else {
	# IMPORTANT: the normalisation makes sense only for the original version
	# I don't think we can normalise the two others since we can't be sure
	# that B>=A in A/B (i.e. sim(Pi,Ii)>sim(P1,P2))
	# However dividing every score by the same value doesn't hurt, it's just
	# that the result shouldn't be interpreted as necessarily in [0,1]
	return $sum / $nbCounted;
    }
}




#
# returns res->[probeSide]->[0..k-1] =  k most similar impostors nos.
#
#
sub getKMostSimilarImpostorsGlobal {
    my $self = shift;
    my $scores = shift; # as returned by computeGI
    my $k = shift;

    $self->{logger}->debug("selecting $k most similar impostors globally") if ($self->{logger});
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
	    $self->{logger}->trace("mean sim score for impostor $impNo w.r.t probe $probeNo: $meanSim[$impNo]") if ($self->{logger});
	}
        my $last= $nbImp-1;
        my @avgSorted = sort { $meanSim[$b] <=> $meanSim[$a] } (0..$last);
        my @select = @avgSorted[0..$k];
	$self->{logger}->debug("selected ".($k+1)." most similar impostors for probe $probeNo: ".join(",", @select)) if ($self->{logger});
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
    my $finalScore = aggregateVector(\@res, $self->{GI_aggregRelRank}, $nanStr);
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
    my $valProbe = aggregateVector(\@aggregProbe, $self->{GI_aggregateSimStat}, $nanStr);
    my $valImp = aggregateVector(\@aggregImp, $self->{GI_aggregateSimStat}, $nanStr);
    return $nanStr if (!defined($valProbe) || !defined($valImp) || ($valProbe eq $nanStr) || ($valImp eq $nanStr));
    if ($self->{useAggregateSim} eq "diff") {
	return $valProbe - $valImp;
    } elsif ($self->{useAggregateSim} eq "ratio") {
	return  $nanStr if ($valImp == 0);
	return $valProbe / $valImp;
    } else {
	confessLog($self->{logger}, "Error: invalid value '".$self->{useAggregateSim}."' for param 'useAggregateSim' ");
    }
}


#
# scores: $scores->[roundNo] = [  [ probeDocNoA, probeDocNoB ], simProbeAvsB, $simRound ], with 
#         $simRound->[probe0Or1]->[impostorNo] = sim between doc probe0or1 and imp $impostorNo (as returned by computeGI)
#
# file format: two lines by round (one for each probe side), line = <roundNo> <probeSide> <docNo for probeSide> <sim-probe-A-vs-B> <sim-Imp0> <sim-Imp1> ... <sim-ImpN>
#
#
sub writeScoresToFile {
    my ($self, $scores, $writeScoresTableToFile) = @_;

    my $f = $writeScoresTableToFile;
    my $fh;
    $self->{logger}->debug("Printing scores table to file '$f'") if ($self->{logger});
    open($fh, ">", $f) or confessLog($self->{logger}, "Error: cannot open file '$f' for writing.");
    my $nbImp = scalar(@{$scores->[0]->[2]->[0]});
    my $nbRounds = scalar(@$scores);
    for (my $roundNo=0; $roundNo< $nbRounds; $roundNo++) {
	for (my $probeSide=0; $probeSide<=1; $probeSide++)  {
	    print $fh "$roundNo\t$probeSide\t".$scores->[$roundNo]->[0]->[$probeSide]."\t".$scores->[$roundNo]->[1];
	    for (my $impNo = 0; $impNo<$nbImp; $impNo++) {
		print $fh "\t".sprintf("%.${decimalDigits}f", $scores->[$roundNo]->[2]->[$probeSide]->[$impNo]);
	    }
	}
	print $fh "\n";
    }
    close($fh);
}


1;
