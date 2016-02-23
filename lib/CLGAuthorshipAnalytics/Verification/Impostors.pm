package CLGAuthorshipAnalytics::Verification::Impostors;

# EM Oct 2015
# 
#


use strict;
use warnings;
use Carp;
use Log::Log4perl;
use CLGTextTools::Stats qw/pickInList pickNSloppy aggregateVector pickDocSubset pickIndex/;
use CLGAuthorshipAnalytics::Verification::VerifStrategy;
use CLGTextTools::Logging qw/confessLog cluckLog warnLog/;
use CLGTextTools::DocCollection qw/createDatasetsFromParams/;
use CLGTextTools::Commons qw/assignDefaultAndWarnIfUndef readTSVFileLinesAsHash/;
use CLGTextTools::SimMeasures::Measure qw/createSimMeasureFromId/;

use Data::Dumper;

our @ISA=qw/CLGAuthorshipAnalytics::Verification::VerifStrategy/;

use base 'Exporter';
our @EXPORT_OK = qw/loadPreSimValuesFile writePreSimValuesFile/;

our $decimalDigits = 10;





#
# $params:
# * logging
# * obsTypesList 
# * impostors = { dataset1 => DocCollection1,  dataset2 => DocCollection2 } ; impostors will be picked from the various datasets A, B,... with equal probability (i.e. independently from the number of docs in each dataset).
# ** if a DocCollection dataset has a min doc freq threshold > 1, this threshold will be applied to the probe docs (using the doc freq table from the same dataset).  As a consequence, observations which appear in a probe document but not in the impostors  dataset are removed.
# ** Alternatively, $impostors can be a string with format 'datasetid1;datasetId2;...'; the fact that it is not a hash ref is used as marker for this option. In this case parameter 'datasetResources'  must be set.
# * datasetResources = { datasetId1 => path1, datasetId2 => path2, ...}. Used only if impostors is not provided as a list of DocCollection (see above).  'pathX' is a path where the files included in the dataset are located. datasetResources can only be a single string corresponding to the path where all datasets are located under their ids, i.e. <datasetResources>/<datasetId>/
# * minDocFreq: optional (default 1); used only if impostors not provided as a list of DocCollection objects
# * filePattern: optional (default "*.txt"); used only if impostors not provided as a list of DocCollection objects (describes the files used as impostor docs in the directory).

# * selectNTimesMostSimilarFirst: if not zero, instead  of picking impostors documents randomly, an initial filtering stage is applied which retrieves the N most similar documents to the probe documents (but with an equal proportion of documents from each impostor dataset), with N = selectNTimesMostSimilarFirst * nbImpostors. This ensures that the most dissimilar impostors are not used, while maintaining a degree of randomness depending on the value of selectNTimesMostSimilarFirst.
# * nbImpostorsUsed: number of impostors documents to select from the impostors dataset (done only once for all rounds) (default 25)
# * nbRounds: number of rounds (higher number -> more randomization, hence less variance in the result) (default 100)
# * propObsSubset: (0<=p<1) the proportion of observations/occurrences to keep in every document at each round; if zero, the proportion is picked randomly at every round (default 0.5)
# * docSubsetMethod: "byOccurrence" -> the proportion is applied to the set of all occurrences; "byObservation" -> applied only to distinct observations (default ByObservation)
# * simMeasure: a CLGTextTools::Measure object (initialized) (default minMax)
# * preSimValues: used only if selectNTimesMostSimilarFirst>0. preSimValues = [ datasetA => preSimDatasetA, dataset2 => preSimDataset2, ...] which contains at least the datasets provided in <impostors>. each preSimDataset = { probeFilename => { impostorFileName => simValue } }, i.e preSimValues->{dataset}->{probeFilename}->{impostorFilename} = simValue.  This parameter is used (1) to provide similiarity values computed in a meaningful way and (2) avoid repeating the process as many times as the method is called, which might be prohibitive in computing time. If selectNTimesMostSimilarFirst>0 but preSimValues is undef or the specific similarity between a probe file and n impostors is not defined, then first-stage similarity between probe and impostors is computed using a random obsType, unless preSimObsType is defined (see below). In this latter case, if preSimValues is a defined hash (even an empty one) then it is updated (thus the caller can re-use or store the computed pre-sim values). See also diskReadAccess and diskWriteAccess.
# * preSimObsType: the obs type to use to compute preselection similarity between probe docs and impostors, if selectNTimesMostSimilarFirst>0 but preSimValues is not. If preSimObsType is not defined either, then a random obs type is used (in this case the quality of the results could be more random)
#
# * useCountMostSimFeature: 0, original, ASGALF, ASGALFavg. if not "0", the "count most similar" feature is computed with the specified variant; default: "original".
# * kNearestNeighbors: uses only the K (value) most similar impostors when calculating result features. default: 0 (use all impostors).
# * mostSimilarFirst: doc or run: specifies whether the K most similar impostors are selected globally (doc) or for each run (run); unused if GI_kNearestNeighbors=0. Default: doc.
# * aggregRelRank: 0, median, arithm, geom, harmo. if not 0, computes the relative rank of the sim between A and B among sim against all impostors by round; the value is used to aggregate all relative ranks (i.e. the values by round). Default: 0.
# * useAggregateSim: 0, diff, ratio. if not 0, computes X = the aggregate sim value between A and B across all runs and Y= the aggregate sim value between any probe and any impostor across all rounds; returns A-B (diff) or A/B (ratio); default : 0.
# * aggregateSimStat:  median, arithm, geom, harmo. aggregate method to use if useAggregateSim is not 0 (ignored if 0). default: arithm.
# * diskReadAccess: allow reading pre-sim values from files if existing.
# * diskWriteAccess: allow writing computed pre-sim values to files.

#
sub new {
    my ($class, $params) = @_;
    my $self = $class->SUPER::new($params, __PACKAGE__);
    $self->{obsTypesList} = $params->{obsTypesList};
    my $impostors =  $params->{impostors};
    $self->{impostors} = $impostors;
    confessLog($self->{logger}, "Error: at least one impostor dataset must be provided") if (!defined($impostors) || (ref($impostors) && (scalar(@$impostors)==0)) || (!ref($impostors) && ($impostors eq "")));
    if (!ref($impostors)) { # if impostors not provided directly as a list of DocCollection objects
	confessLog("Error: if impostors are not provided as a list of DocCollection objects, then parameter 'datasetResources' must be defined.") if (!defined($params->{datasetResources}));
	my @impDatasetsIds = split(/;/, $impostors);
	$self->{impostors} = createDatasetsFromParams($params, \@impDatasetsIds, $params->{datasetResources}, $params->{minDocFreq}, $params->{filePattern}, $self->{logger});
    }
    $self->{nbImpostorsUsed} = assignDefaultAndWarnIfUndef("nbImpostorsUsed", $params->{nbImpostorsUsed}, 25, $self->{logger});
    $self->{selectNTimesMostSimilarFirst} = assignDefaultAndWarnIfUndef("selectNTimesMostSimilarFirst", $params->{selectNTimesMostSimilarFirst}, 0, $self->{logger});
    $self->{nbRounds} = assignDefaultAndWarnIfUndef("nbRounds", $params->{nbRounds}, 100, $self->{logger});
    $self->{propObsSubset} = assignDefaultAndWarnIfUndef("propObsSubset", $params->{propObsSubset}, 0.5, $self->{logger});
    $self->{docSubsetMethod} = assignDefaultAndWarnIfUndef("docSubsetMethod", $params->{docSubsetMethod}, "byObservation", $self->{logger}) ;
    $self->{simMeasure} = createSimMeasureFromId(assignDefaultAndWarnIfUndef("simMeasure", $params->{simMeasure}, "minmax", $self->{logger}), $params, 1);
    $self->{preSimValues} = $params->{preSimValues};
    $self->{preSimObsType} = assignDefaultAndWarnIfUndef("preSimObsType", $params->{preSimObsType}, "preSimObsType", $self->{logger}) ;
    $self->{GI_useCountMostSimFeature} = assignDefaultAndWarnIfUndef("useCountMostSimFeature", $params->{useCountMostSimFeature}, "original", $self->{logger});
    $self->{GI_kNearestNeighbors} = assignDefaultAndWarnIfUndef("kNearestNeighbors", $params->{kNearestNeighbors}, 0, $self->{logger});
    $self->{GI_mostSimilarFirst} =  assignDefaultAndWarnIfUndef("mostSimilarFirst", $params->{mostSimilarFirst}, "doc", $self->{logger});
    $self->{GI_aggregRelRank} = assignDefaultAndWarnIfUndef("aggregRelRank", $params->{aggregRelRank}, "0", $self->{logger});
    $self->{GI_useAggregateSim} = assignDefaultAndWarnIfUndef("useAggregateSim", $params->{useAggregateSim}, "0", $self->{logger});
    $self->{GI_aggregateSimStat} = assignDefaultAndWarnIfUndef("aggregateSimStat", $params->{aggregateSimStat},  "arithm", $self->{logger});
    $self->{diskReadAccess} = assignDefaultAndWarnIfUndef("diskReadAccess", $params->{diskReadAccess}, 0, $self->{logger});
    $self->{diskWriteAccess} = assignDefaultAndWarnIfUndef("diskWriteAccess", $params->{diskWriteAccess}, 0, $self->{logger});
    bless($self, $class);
    return $self;
}




#
# * $probeDocsLists: [ [docA1, docA2, ...] ,  [docB1, docB2,...] ]
#    ** where docX = DocProvider
# * writeScoresTableToFile (optional)
sub compute {
    my $self = shift;
    my $probeDocsLists = shift;
    my $writeScoresTableToFile = shift;

    $self->{logger}->debug("Impostors strategy: computing features between pair of sets of docs") if ($self->{logger});
    confessLog($self->{logger}, "Cannot process case: no obs types at all") if ((scalar(@{$self->{obsTypesList}})==0) && $self->{logger});
    my $preseletedImpostors = $self->preselectMostSimilarImpostorsDataset($probeDocsLists);
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



#
# input:
# * $probeDocsLists: [ [docA1, docA2, ...] ,  [docB1, docB2,...] ]
#    ** where docX = DocProvider
# * $impostors : [ [impostorDocProvider1, datasetId1], ... ]
#
# output: $scores->[roundNo] = [  [ probeDocNoA, probeDocNoB ], simProbeAvsB, $simRound ], with 
#         $simRound->[probe0Or1]->[impostorNo]
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
	my $minDocFreq = $self->{impostors}->{$impDataset}->getMinDocFreq();
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
		    while (($obs, $docFreq) = each %{$minDocFreq->{$obsType}}) {
			push(@obsTypeObservs, $obs) if ($docFreq >= $minDocFreq);
		    }
		    $allObs->{$obsType} = \@obsTypeObservs;
		}
	    }	
	} else {
	    $self->{logger}->debug("No min doc freq to apply") if ($self->{logger});
	    for (my $probeDocNo=0; $probeDocNo<=1; $probeDocNo++) {
		for (my $docNo=0; $docNo<scalar(@{$probeDocsLists->[$probeDocNo]}); $docNo++) {
		    $probeDocsListsByDataset[$probeDocNo]->[$docNo]->{$impDataset} = $probeDocsLists->[$probeDocNo]->[$docNo]->getObservations();
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
	    my $featSubset = pickNSloppy($propObsRound * scalar($observs), $observs);
	    $self->{logger}->trace("byObs: picked ".scalar(@$featSubset)." observations.");
	    $self->{logger}->trace("Filtering observations for probe docs");
	    foreach my $impDataset (@impostorsDatasets) {
		$probeDocsRound[0]->{$impDataset} = filterObservations($probeDocsListsByDataset[0]->[$probeDocNo[0]]->{$impDataset}->{$obsType}, $featSubset);
		$probeDocsRound[1]->{$impDataset} = filterObservations($probeDocsListsByDataset[1]->[$probeDocNo[1]]->{$impDataset}->{$obsType}, $featSubset);
	    }
	    $self->{logger}->trace("Filtering observations for impostors");
	    @impDocRound = map { [ filterObservations($_->[0]->getObservations($obsType), $featSubset) , $_->[1] ] } @$impostors; # remark: $_->[1] = dataset
	} else {
	    $self->{logger}->trace("byOccurrence: picking doc subset for probe docs");
	    foreach my $impDataset (@impostorsDatasets) {
		$probeDocsRound[0]->{$impDataset} = pickDocSubset($probeDocsListsByDataset[0]->[$probeDocNo[0]]->{$impDataset}->{$obsType}, $propObsRound, $self->{logger});
		$probeDocsRound[1]->{$impDataset} = pickDocSubset($probeDocsListsByDataset[1]->[$probeDocNo[1]]->{$impDataset}->{$obsType}, $propObsRound, $self->{logger});
	    }
	    $self->{logger}->trace("byOccurrence: picking doc subset for impostors");
	    @impDocRound = map { [ pickDocSubset($_->[0]->getObservations($obsType), $propObsRound, $self->{logger}) , $_->[1] ] } @$impostors;
	}
	my $datasetRnd = pickInList(\@impostorsDatasets); # it makes sense to compare with the same minDocFreq as the impostors, but against which ref dataset doesn't matter so much
	$self->{logger}->trace("computing similarity between selected probe docs (using dataset '$datasetRnd')");
	my $probeDocsSim = $self->{simMeasure}->compute($probeDocsRound[0]->{$datasetRnd}, $probeDocsRound[1]->{$datasetRnd});
	my @simRound;
	for (my $probeDocNo=0; $probeDocNo<=1; $probeDocNo++) {
	    for (my $impNo=0; $impNo<scalar(@$impostors); $impNo++) {
		my ($impDoc, $dataset) = ( $impDocRound[$impNo]->[0], $impDocRound[$impNo]->[1] );
		$self->{logger}->trace("computing similarity between probe doc side $probeDocNo and impostor $impNo from dataset '$dataset'");
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




# $self->{selectNTimesMostSimilarFirst}>0
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
			if (!defined($simByImpostor)) {
			    $simByImpostor = $self->computeOrLoadPreSimValues($probeDoc, $impDataset);
			    $preSimValues->{$impDataset}->{$probeDoc->getFilename()} = $simByImpostor;  # update the hash (for the caller to get the values back)
			}
			$self->{logger}->trace("Sorting impostors by similarity against  probe file '".$probeDoc->getFilename()."'") if ($self->{logger});
			my @sortedImpBySim = sort { $simByImpostor->{$b} <=> $simByImpostor->{$a} } (keys %$simByImpostor) ;
			$sortedImpBySimByProbe[$probeSide]->{$probeDoc} = \@sortedImpBySim;
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
		my @selectedDocs = map { $impDatasetDocsByFilename->{$_} } (keys %selected);
		$self->{logger}->debug("selected ".scalar(@selectedDocs)." impostors for dataset '$impDataset'")  if ($self->{logger});
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
sub computeOrLoadPreSimValues {
    my $self = shift;
    my $probeDoc = shift;
    my $impDataset = shift;

    if ($self->{diskReadAccess}) {
	$self->{logger}->debug("Trying to load pre-sim values from file...") if ($self->{logger});
	my $res = loadPreSimValuesFile($probeDoc->getFilename(), $impDataset, $self->{logger});
	if (defined($res)) { # the sim file was found and its content loaded
	    # checking that we have a sim value for each impostor, because if not this will cause problems later
	    my $impostors = $self->{impostors}->{$impDataset}->getDocsAsHash();
	    foreach my $impId (keys %$impostors) {
		confessLog($self->{logger}, "Error loading pre-sim values: no value found for impostor '$impId' (probe file ".$probeDoc->getFilename().", dataset '$impDataset')") if (!defined($res->{$impId}));
	    }
	    return $res ;
	} # otherwise the file was not found, sim values have to be computed
    }
    my $obsType;
    if (defined($self->{preSimObsType})) {
	$obsType =  $self->{preSimObsType};
    } else { 
	$obsType = pickInList($self->{obsTypesList});
	warnLog($self->{logger}, "Warning: parameter 'preSimObsType' undefined, picking random obs type for computing pre-similiarity values (probe='".$probeDoc->getFilename()."', dataset=$impDataset); picked '$obsType'");
    }
    $self->{logger}->debug("Computing pre-sim values between probe doc '".$probeDoc->getFilename()."' and all impostors in dataset '$impDataset' for pre-selection; obsType='$obsType'") if ($self->{logger});
    my $probeData = $probeDoc->getObservations($obsType);
    my $impostors = $self->{impostors}->{$impDataset}->getDocsAsHash();
    my %resProbe;
    my ($impId, $impDoc);
    while (($impId, $impDoc) = each(%$impostors)) {
	$resProbe{$impId} = $self->{simMeasure}->compute($probeData, $impDoc->getObservations($obsType) );
	$self->{logger}->debug("Pre-sim value between probe '".$probeDoc->getFilename()."' and impostor '$impId' (dataset 'impDataset') = $resProbe{$impId}") if ($self->{logger});
    }
    if ($self->{diskWriteAccess}) {
	$self->{logger}->debug("Saving pre-sim values to file if the file doesn't exist yet...") if ($self->{logger});
	writePreSimValuesFile(\%resProbe, $probeDoc->getFilename(), $impDataset, $self->{logger});
    }
    return \%resProbe;
}


#
# loadPreSimValuesFile($probeFile, $impDataset, $logger)
# static
#
# if the file exists, loads pre-similarty values from file <probeFile>.simdir/<impDataset>.similarities, which contains lines of the form: <impostor filename> <sim value>; returns undef otherwise
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
# writePreSimValuesFile($probeFile, $impDataset, $logger)
# static
#
# writes pre-similarity values to file <probeFile>.simdir/<impDataset>.similarities (format: <impostor filename> <sim value>)
# Warning: if the file already exists, nothing is written.
#
# * $logger is optional.
#
sub writePreSimValuesFile {
    my ($values, $probeFile, $impDataset, $logger) = @_;

    my $dir = "$probeFile.simdir";
    if (! -d $dir) {
	mkdir "$dir" or confessLog($logger, "Cannot create directory '$dir'");
    }
    my $f = "$dir/$impDataset.similarities";
    if ( ! -f "$f") {
	my $fh;
	open($fh, ">:encoding(utf-8)", $f) or confessLog($logger, "Cannot open pre-sim file '$f' for writing");
	my ($impId, $value);
	while (($impId, $value) = each(%$values)) {
	    printf $fh "$impId\t%.${decimalDigits}f\n", $value;
	}
	close($fh);
	$logger->debug("Wrote pre-sim values to file '$f'") if ($logger);
    } else {
	$logger->debug("pre-sim file '$f' already exists, nothing written") if ($logger);
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
	$self->{logger}->debug("Retaining only $k most similar impostors for each run") if ($self->{logger});
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
	if ($self->{GI_useCountMostSimFeature} eq "original") {
	    $sum++ if ( $probeSimVector->[$i]**2 > ($impSimVectors->[0]->[$i] * $impSimVectors->[1]->[$i]) );
	} elsif ($self->{GI_useCountMostSimFeature} eq "ASGALF") {
	    $sum +=  ( $probeSimVector->[$i]**2 / ($impSimVectors->[0]->[$i] * $impSimVectors->[1]->[$i]) );
	} elsif ($self->{GI_useCountMostSimFeature} eq "ASGALFavg") {
	    $sum +=  ( $probeSimVector->[$i] * 2 / ($impSimVectors->[0]->[$i] + $impSimVectors->[1]->[$i]) );
	} else {
	    confessLog($self->{logger}, "Error: invalid value '".$self->{GI_useCountMostSimFeature}."' for param 'GI_useCountMostSimFeature' ");
	}
    }
    $self->{logger}->debug("Counting most similar between probe values and impostor values, method '".$self->{GI_useCountMostSimFeature}."': sum = $sum; nb rounds = ".scalar(@$probeSimVector)."; 'normalized' score = ".($sum / scalar(@$probeSimVector)))  if ($self->{logger});

    # IMPORTANT: the normalisation makes sense only for the original version
    # I don't think we can normalise the two others since we can't be sure
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
