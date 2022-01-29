#!/bin/bash

# EM April 14, modified April 15
# converted to updated framework, March 16

source common-lib.sh
source file-lib.sh
source pan-utils.sh



progName=$(basename "$BASH_SOURCE")

resourcesOptFilename="resources-options.conf"

learnMode=
trainFile=
testFile=
maxAttemptsRandomSubset=5


function usage {
  echo
  echo "Usage: $progName [options] <input data dir> <config file> <output dir>"
  echo
  echo "  Trains or applies a model as specified by the parameters in"
  echo "   <config file>, using cases in <input data dir> as train/test data."
#  echo "  the model from/to <output dir> if train or test mode (but not both)."
#  echo "  At least one of options -l and -a must be specified."
  echo "  Currently exactly one of the options -l or -a must be specified, and"
  echo "  -m must be supplied."
#  echo "  <input data dir> is 'prepared' and must contain the 'reference' data"
#  echo "  dir. (see also -r)"
  echo
#  echo "  if only -a or -l is provided, -m must be supplied as well (location "
#  echo "  of them model to save or to apply)" 
#  echo "  remark" 
  echo
  echo "  Options:"
  echo "    -h this help"
  echo "    -l <cases file> (Learn) train using the cases in the first column of"
  echo "     <cases file> (subdirectories of <input dir>, one by line), and the"
  echo "     corresponding  gold scores in the second column"
  echo "     in <cases prefix>.gold."
  echo "    -a <cases file> (Apply) test using the cases in the first column of"
  echo "     <cases file>; no second column required."
#  echo "    -r <ref data dir> if not <input data dir>/reference"
#  echo "     -i <impostors data dir> if not <input data dir>/impostors"
  echo "    -m <model dir> model to save (-l) or apply (-a)" # not used if both "
#  echo "       -l and -a are supplied."
  echo
}


# reads a list a:b:c and returns a single value picked randomly
function pickRandomFromList {
    local items="$1"

    tmp=$(mktemp --tmpdir "tmp.$progName.pickRandomFromList.XXXXXXXXXX")
    echo "$items" | tr ':' '\n' >"$tmp"
    n=$(cat "$tmp" | wc -l)
    evalSafe "cat \"$tmp\" | random-lines.pl 1 1 \"$n\"" "$progName,$LINENO: "
    rm -f "$tmp"
}


#
# assuming that each individual strategy script extract-features-XXX.sh
# takes as input a problem directory (not a dataset) and prints a single line of numeric
# values (possibly only one) as output; these are the features for the case.
# exception for "robust strategy"
#

function computeFeaturesTSV {
    local casesFile="$1"
    local inputDir="$2"
    local configFile="$3"
    local outputDir="$4"


    featuresFile=$(mktemp --tmpdir "tmp.$progName.computeFeaturesTSV1.XXXXXXXXXX")
    evalSafe "obtain-strategy-features.sh '$casesFile' '$inputDir/input' '$configFile' '$inputDir/$resourcesOptFilename' >'$featuresFile' " "$progName,$LINENO: "
    # small sanity check below
    nbInstances=$(cat "$featuresFile" | wc -l)
    if [ $nbInstances -ne $(cat "$casesFile" | wc -l) ]; then
	echo "$progName error: something is wrong, different number of instances found in features file '$featuresFile' compared to '$casesFile'" 1>&2
	exit 1
    fi
    # UPDATE Jan 2022: now using tab delim to catch column 2 instead of previously using "set -- $line" and obtaining "$2"
    #                  the previous version would work with both space or tab as delim but is not compatible with space in the first column (as now possible)
    #                  note: pan15 truth.txt file contains space as separator, but  generateTruthCasesFile in pan-utils.sh is able to produce tab-separated
    #                  case file with 0/1 instead of N/Y, depending on the options. I would assume that this function must have been used for PAN data,
    #                  otherwise the target would not be 0/1
    cat "$casesFile" | while read line; do
	gold=$(echo "$line" | cut -f 2)
	#	set -- $line
	#	gold="$2"
	#	echo "DEBUG case='$caseId' gold='$gold' from $casesFile" 1>&2
	if [ -z "$gold" ]; then
	    gold="?"
	fi
	echo "$gold"
    done | paste "$featuresFile" - >"$outputDir/features.tsv"

    # step 2: clean up weird NaN values and add header
    local nbCols=$(head -n 1 "$outputDir/features.tsv" | wc -w)
    tmp=$(mktemp --tmpdir "tmp.$progName.computeFeaturesTSV2.XXXXXXXXXX")
    # CAUTION "nan" and especially "-nan" values can be output from perl computations, at least with GI and fine-grained, and that
    # depends on the machine floating point architecture (or something like that).
    # Weka will crash on these values.
    evalSafe "cat \"$outputDir/features.tsv\"  | sed 's/-nan/NA/g'  | sed 's/nan/NA/g' > $tmp" "$progName,$LINENO: "
    echo -n "feat1" >"$outputDir/features.tsv"
    for colNo in $(seq 2 $nbCols); do
	echo -en "\tfeat$colNo" >>"$outputDir/features.tsv"
    done
    echo >>"$outputDir/features.tsv"
    evalSafe "cat $tmp >>\"$outputDir/features.tsv\"" "$progName,$LINENO: "
    rm -f "$featuresFile" "$tmp"

}



#
# arffConvertOpt is used for confidence labels; leave undef or empty otherwise
# 
function generateArff {
    local inputTSV="$1"
    local outputArff="$2"
    local arffConvertOpt="$3"

    evalSafe "cat \"$inputTSV\"  | sed 's/NA/?/g'| convert-to-arff.pl  $arffConvertOpt >\"$outputArff\"" "$progName,$LINENO: "
}


function generateTrainingDataConfidence {
    local predictedScoreTSV="$1"
    local featuresTSV="$2"
    local outPrefix="$3"
    local configFile="$4"

    local nbCols=$(tail -n 1 "$featuresTSV" | wc -w)
    tmpHeader=$(mktemp --tmpdir "tmp.$progName.generateTrainingDataConfidence1.XXXXXXXXXX")
    echo "score">$tmpHeader
    cat "$predictedScoreTSV" >>$tmpHeader
    tmpLabels=$(mktemp --tmpdir "tmp.$progName.generateTrainingDataConfidence2.XXXXXXXXXX")
    echo "confidenceLabel" >$tmpLabels
    tmpGold=$(mktemp --tmpdir "tmp.$progName.generateTrainingDataConfidence3.XXXXXXXXXX")
#    echo "DEBUG featuresTSV=$featuresTSV; predictedScoreTSV=$predictedScoreTSV; tmpGold=$tmpGold; tmpLabels=$tmpLabels" 1>&2
    evalSafe "cut -f $nbCols \"$featuresTSV\" | tail -n +2 >\"$tmpGold\"" "$progName,$LINENO: "
    evalSafe "score-to-confidence-label.pl \"$tmpGold\" \"$predictedScoreTSV\" >>\"$tmpLabels\"" "$progName,$LINENO: "
    local nb1=$(grep CONFIDENT "$tmpLabels" | wc -l)
    local nb2=$(grep UNSURE "$tmpLabels" | wc -l)
    if [ $nb1 -gt 0 ] &&  [ $nb2 -gt 0 ]; then
	rm -f "$outPrefix.no-model" # just in case (?)
	tmpFeats=$(mktemp --tmpdir "tmp.$progName.generateTrainingDataConfidence4.XXXXXXXXXX")
	lastFeat=$(( $nbCols - 1 ))
	evalSafe "cut -f 1-$lastFeat \"$featuresTSV\" >\"$tmpFeats\"" "$progName,$LINENO: "
	evalSafe "paste  $tmpFeats $tmpHeader $tmpLabels >\"$outPrefix.tsv\"" "$progName,$LINENO: "
	generateArff "$outPrefix.tsv" "$outPrefix.arff" "-n \"confidenceLabel;CONFIDENT,UNSURE\""
    else
	echo "$progName warning: no confidence model, all instances have the same label" >"$outPrefix.no-model"
    fi
    rm -f $tmpHeader $tmpLabels $tmpFeats
}


function applyModelAndCheck {
    local arffInput="$1"
    local model="$2"
    local wekaParams="$3"
    local tsvPredict="$4"
    local casesFile="$5"


    local nbCols=$(tail -n 1 "$arffInput" | sed 's/,/ /g' | wc -w)
    arffOutput=$(mktemp --tmpdir "tmp.$progName.applyModelAndCheck.XXXXXXXXXX")
#    echo "DEBUG A1" 1>&2
    evalSafe "weka-learn-and-apply.sh -a \"$model\" \"$wekaParams\" UNUSED \"$arffInput\" \"$arffOutput\"" "$progName,$LINENO: "
#    echo "DEBUG A2" 1>&2
    extractPredictAndCheck "$arffOutput" "$tsvPredict" "$casesFile" $nbCols
    rm -f "$arffOutput"
}


function extractPredictAndCheck {
    local arffOutput="$1"
    local tsvPredict="$2"
    local casesFile="$3"
    local nbCols="$4"

#    echo "DEBUG $@"
    evalSafe "convert-from-arff.pl <\"$arffOutput\" | cut -f $nbCols > \"$tsvPredict\"" "$progName,$LINENO: "
    if [ $(cat "$tsvPredict" | wc -l) -ne $(cat "$casesFile" | wc -l) ]; then
	echo "$progName: error after running weka: different number of lines in '$casesFile' and '$tsvPredict'" 1>&2
	exit 1
    fi
}





function applyUnsupervised {
    local method="$1"
    local tsvInputWithGold="$2"
    local outputPredictFile="$3" # output = 1 column with scores
    local outputGoldFile="$4" # if empty, gold column not provided as output

    local nbColsFeaturesTSV=$(head -n 1 "$tsvInputWithGold" | wc -w)
    local lastCol=$(( $nbColsFeaturesTSV - 1 ))
    local featuresFile=$(mktemp --tmpdir "tmp.$progName.applyUnsupervised.XXXXXXXXXX")
    evalSafe "tail -n +2 \"$tsvInputWithGold\" | cut -f 1-$lastCol >\"$featuresFile\"" "$progName,$LINENO: "
    evalSafe "num-stats.pl -s \"$method\" \"$featuresFile\" > \"$outputPredictFile\"" "$progName,$LINENO: "
    rm -f "$featuresFile"
    if [ ! -z "$outputGoldFile" ]; then
	evalSafe "tail -n +2 \"$tsvInputWithGold\" | cut -f $nbColsFeaturesTSV >\"$outputGoldFile\"" "$progName,$LINENO: "
    fi
}







OPTIND=1
while getopts 'hl:a:r:m:' option ; do 
    case $option in
	"h" ) usage
 	      exit 0;;
	"l" ) trainFile="$OPTARG";;
	"a" ) testFile="$OPTARG";;
	"m" ) modelDir="$OPTARG";;
 	"?" ) 
	    echo "Error, unknow option." 1>&2
            printHelp=1;;
    esac
done
shift $(($OPTIND - 1))
if [ $# -ne 3 ]; then
    echo "Error: expecting 3 args." 1>&2
    printHelp=1
fi
if [ -z "$trainFile" ] &&  [ -z "$testFile" ]; then
    echo "$progName error: one of -l and -a must be supplied." 1>&2
    printHelp=1
elif  [ ! -z "$trainFile" ] &&  [ ! -z "$testFile" ]; then
    echo "$progName error: cannot use both -l and -a." 1>&2
    printHelp=1
fi
if  [ -z "$modelDir" ]; then
    echo "$progName error: -m <model dir> must be supplied." 1>&2
    printHelp=1
fi

#elif  [ -z "$trainFile" ] &&  [ ! -z "$testFile" ] && [ -z "$modelDir" ]; then
#    echo "$progName error: -m <model dir> must be supplied." 1>&2
#    printHelp=1
#elif  [ ! -z "$trainFile" ] &&  [ -z "$testFile" ] && [ -z "$modelDir" ]; then
#    echo "$progName error: -m <model dir> must be supplied." 1>&2
#    printHelp=1
#fi
if [ ! -z "$printHelp" ]; then
    usage 1>&2
    exit 1
fi
inputDir="$1"
configFile="$2"
outputDir="$3"

dieIfNoSuchDir "$inputDir"  "$progName,$LINENO: "
dieIfNoSuchDir "$outputDir" "$progName,$LINENO: "
dieIfNoSuchFile "$configFile" "$progName,$LINENO: "
dieIfNoSuchDir "$inputDir/input" "$progName,$LINENO: "
dieIfNoSuchFile "$inputDir/$resourcesOptFilename" "$progName,$LINENO: "

readFromParamFile "$configFile" "strategy" "$progName,$LINENO: "

readFromParamFile "$configFile" "confidenceTrainProp" "$progName,$LINENO: " "=" 1 "0"
#echo "DEBUG confidenceTrainProp=$confidenceTrainProp" 1>&2

if [ ! -z "$trainFile" ]; then # features for training
    dieIfNoSuchFile "$trainFile" "$progName,$LINENO: "
    mkdirSafe "$outputDir/train"
    mkdirSafe "$modelDir"
    computeFeaturesTSV "$trainFile" "$inputDir" "$configFile" "$outputDir/train"
    nbCols=$(head -n 1 "$outputDir/train/features.tsv" | wc -w)
    if [ "$confidenceTrainProp" != "0" ] && [ "$confidenceTrainProp" != "1" ]; then # if 0, nothing to do; if 1, same training data
	nbCases=$(cat "$trainFile" | wc -l)
	nbCasesConfidence=$(perl -e "print \"\".(int($confidenceTrainProp*$nbCases+0.5)).\"\n\";")
	nbCasesScore=$(( $nbCases - $nbCasesConfidence ))
	# caution: lines no from 2 to N+1 because of header in features.tsv!
	max=$(( $nbCases + 1 ))
	# IMPORTANT : if there are only a few cases, it is possible that all the cases in the subset would have the same label (positive or negative). Several attempts to obtain a subset with 2 labels, then abort if not possible
	nbAttempts=0
	nbLabels=0
	while [ $nbLabels -ne 2 ] && [ $nbAttempts -lt $maxAttemptsRandomSubset ]; do
	    nbAttempts=$(( $nbAttempts + 1 ))
	    if [ $nbAttempts -gt 1 ]; then
		echo "$progName warning: did not find a random subset containing the two labels, attempt $nbAttempts" 1>&2
	    fi
	    evalSafe "seq 2  $max | random-lines.pl -r \"$outputDir/train/confidence-instances.lines\" $nbCasesScore 1 $nbCases >\"$outputDir/train/score-instances.lines\"" "$progName,$LINENO: "
	    nbLabels=$(evalSafe "cat  \"$outputDir/train/features.tsv\" | select-lines-nos.pl \"$outputDir/train/score-instances.lines\" 1 | cut -f $nbCols | sort -u | wc -l"  "$progName,$LINENO: ")
	done
	if [ $nbLabels -ne 2 ]; then
	    echo "$progName error: could not find a random subset containing the two labels in '$outputDir/train/features.tsv' after $maxAttemptsRandomSubset, aborting." 1>&2
	    exit 17
	fi
	evalSafe "head -n 1 \"$outputDir/train/features.tsv\" >\"$outputDir/train/score-instances.tsv"\"  "$progName,$LINENO: "
	evalSafe "head -n 1 \"$outputDir/train/features.tsv\" >\"$outputDir/train/confidence-instances.tsv\""  "$progName,$LINENO: "
	evalSafe "cat  \"$outputDir/train/features.tsv\" | select-lines-nos.pl \"$outputDir/train/score-instances.lines\" 1 >>\"$outputDir/train/score-instances.tsv\""  "$progName,$LINENO: "
	evalSafe "cat  \"$outputDir/train/features.tsv\" | select-lines-nos.pl \"$outputDir/train/confidence-instances.lines\" 1 >>\"$outputDir/train/confidence-instances.tsv\"" "$progName,$LINENO: "
	generateArff "$outputDir/train/confidence-instances.tsv" "$outputDir/train/confidence-instances.arff"
	inputScoresTSV="$outputDir/train/score-instances.tsv"
    else
	inputScoresTSV="$outputDir/train/features.tsv"
    fi
    trainArff="$outputDir/train/score-instances.arff"
    generateArff "$inputScoresTSV" "$trainArff"
fi

if [ ! -z "$testFile" ]; then # features for testing
    dieIfNoSuchFile "$testFile" "$progName,$LINENO: "
    mkdirSafe "$outputDir/test"
    computeFeaturesTSV "$testFile" "$inputDir"  "$configFile" "$outputDir/test"
    generateArff "$outputDir/test/features.tsv" "$outputDir/test/data.arff"
fi

readFromParamFile "$configFile" "learnMethod" "$progName,$LINENO: "

if [ "${learnMethod:0:13}" == "simpleColumn_" ]; then
    echo "$progName: not implemented yet!" 1>&2
    exit 6
elif [ "$learnMethod" == "mean" ] || [ "$learnMethod" == "geomMean" ] || [ "$learnMethod" == "median" ]; then
    readFromParamFile "$configFile" "confidenceLearnMethod" "$progName,$LINENO: "
    if [ ! -z "$trainFile" ]; then # TRAINING ONLY
	# if no confidence , nothing to do (unsupervised)
	if [ "$confidenceTrainProp" != "0" ]; then
	    if [ "$confidenceTrainProp" == "1" ] && [ "$confidenceLearnMethod" == "simpleOptimC1" ]; then
		applyUnsupervised "$learnMethod" "$inputScoresTSV" "$outputDir/train/score-instances.predict.tsv" "$outputDir/train/gold.tsv"
		evalSafe "optimize-c1.pl \"$outputDir/train/score-instances.predict.tsv\" \"$outputDir/train/gold.tsv\" >\"$modelDir/optim-c1.confidence-model\" " "$progName,$LINENO: "
	    else # confidenceProp not 0 or 1 or other confidence method: todo
		echo "$progName,$LINENO: confidenceTrainProp='$confidenceTrainProp'; confidenceLearnMethod='$confidenceLearnMethod'; not implemented yet! " 1>&2
		exit 6
	    fi
	fi
    else # TESTING ONLY
	applyUnsupervised "$learnMethod" "$outputDir/test/features.tsv" "$outputDir/test/predict.tsv"
	rm -f "$noHeader"
	if [ "$confidenceTrainProp" != "0" ]; then
	    if [ "$confidenceTrainProp" == "1" ] && [ "$confidenceLearnMethod" == "simpleOptimC1" ]; then
		scoreTSV="$outputDir/test/score-predict.tsv"
		mv  "$outputDir/test/predict.tsv" "$scoreTSV"
		dieIfNoSuchFile "$modelDir/optim-c1.confidence-model" "$progName,$LINENO: "
		minDontKnow=$(cat "$modelDir/optim-c1.confidence-model" | cut -f 1)
		maxDontKnow=$(cat "$modelDir/optim-c1.confidence-model" | cut -f 2)
#		echo "DEBUG minDontKnow=$minDontKnow; maxDontKnow=$maxDontKnow" 1>&2
		if [ "$minDontKnow" != "0.5" ] || [ "$maxDontKnow" != "0.5" ]; then # otherwise  case [0.5,0.5]: nothing to do
		    # interpolation of variables in perl one liner definitely too complicated with evalSafe
#		    evalSafe "cat \"$scoreTSV\" | perl -e '\$pol' > \"$outputDir/test/predict.tsv\"" "$progName,$LINENO: "
		    cat "$scoreTSV" | perl -e "while (<STDIN>) { print ''.(((\$_ > $minDontKnow) && (\$_ < $maxDontKnow)) ? \"0.5\n\" : \"\$_\") ; }" > "$outputDir/test/predict.tsv"
		else # simple copy
		    evalSafe "cat \"$scoreTSV\" > \"$outputDir/test/predict.tsv\"" "$progName,$LINENO: "
		fi
	    else # confidenceProp not 0 or 1 or other confidence method: todo
		echo "$progName,$LINENO: not implemented yet! " 1>&2
		exit 6
	    fi
	fi
    fi
else # otherwise assume it's a weka algo id
    wekaParams=$(weka-id-to-parameters.sh "$learnMethod")
    if [ ! -z "$trainFile" ]; then # TRAINING ONLY
	    # scores 
	nbCols=$(tail -n 1 "$trainArff" | sed 's/,/ /g' | wc -w)
	if [ "$confidenceTrainProp" == "1" ] || [ "$confidenceTrainProp" == "0" ]; then # different scores-instances and different test set
	    testSetScoresArff="$trainArff"
	    resultScoresArff="$outputDir/train/self-predict.arff"
	else
	    testSetScoresArff="$outputDir/train/confidence-instances.arff"
	    resultScoresArff="$outputDir/train/confidence-instances-score-predict.arff"
	fi
	    # LEARN SCORES
#	echo "DEBUG B1" 1>&2
	evalSafe "weka-learn-and-apply.sh -m \"$modelDir/weka.scores-model\" \"$wekaParams\" \"$trainArff\" \"$testSetScoresArff\" \"$resultScoresArff\"" "$progName,$LINENO: "
#	echo "DEBUG B2" 1>&2
	    #
	if [ "$confidenceTrainProp" != "0" ]; then
	    if [ "$confidenceTrainProp" == "1" ]; then # if 0, nothing to do; if 1, same training data
		confidenceCasesFile="$trainFile"
		confidenceTSV="$inputScoresTSV"
	    else # 0<x<1
		confidenceCasesFile="$outputDir/train/confidence-instances.lines"
		confidenceTSV="$outputDir/train/confidence-instances.tsv"
	    fi
	    extractPredictAndCheck "$resultScoresArff" "$outputDir/train/score-instances.predict0.tsv" "$confidenceCasesFile"  $nbCols
	    evalSafe "restrict-range.pl 0 1 <\"$outputDir/train/score-instances.predict0.tsv\" >\"$outputDir/train/score-instances.predict.tsv\"" "$progName,$LINENO: "

	    readFromParamFile "$configFile" "confidenceLearnMethod" "$progName,$LINENO: "
	    if [ "$confidenceLearnMethod" == "simpleOptimC1" ]; then
		nbColsFeaturesTSV=$(head -n 1 "$confidenceTSV" | wc -w)
		goldConfidenceFile=$(mktemp --tmpdir "tmp.$progName.main1.XXXXXXXXXX")
		evalSafe "tail -n +2 \"$confidenceTSV\" | cut -f $nbColsFeaturesTSV >\"$goldConfidenceFile\"" "$progName,$LINENO: "
#		echo "DEBUG goldConfidenceFile=$goldConfidenceFile" 1>&2
#		echo "DEBUG call optimize-c1.pl \"$outputDir/train/score-instances.predict.tsv\" \"$goldConfidenceFile\" >\"$modelDir/optim-c1.confidence-model\"" 1>&2
		evalSafe "optimize-c1.pl \"$outputDir/train/score-instances.predict.tsv\" \"$goldConfidenceFile\" >\"$modelDir/optim-c1.confidence-model\" " "$progName,$LINENO: "
		rm -f "$goldConfidenceFile"
	    else
		generateTrainingDataConfidence "$outputDir/train/score-instances.predict.tsv" "$confidenceTSV" "$outputDir/train/confidence-labels" "$configFile"
		if [ -s "$outputDir/train/confidence-labels.no-model" ]; then
		    cat "$outputDir/train/confidence-labels.no-model" 1>&2
		    cat "$outputDir/train/confidence-labels.no-model" > "$modelDir/confidence.no-model"
		else
		    wekaParams=$(weka-id-to-parameters.sh "$confidenceLearnMethod")
		    tmpSelfLearn=$(mktemp --tmpdir "tmp.$progName.main2.XXXXXXXXXX")
#		echo "DEBUG C1" 1>&2
		    evalSafe "weka-learn-and-apply.sh -m \"$modelDir/weka.confidence-model\" \"$wekaParams\" \"$outputDir/train/confidence-labels.arff\" \"$outputDir/train/confidence-labels.arff\" \"$tmpSelfLearn\"" "$progName,$LINENO: "
#		echo "DEBUG C2" 1>&2
		    rm -f $tmpSelfLearn
		    dieIfNoSuchFile "$modelDir/weka.confidence-model" "$progName,$LINENO BUG: "
		fi
	    fi
	fi
    else # TESTING ONLY
	dieIfNoSuchFile "$modelDir/weka.scores-model" "$progName,$LINENO: "
	applyModelAndCheck  "$outputDir/test/data.arff" "$modelDir/weka.scores-model" "$wekaParams" "$outputDir/test/predict0.tsv" "$testFile"
	evalSafe "restrict-range.pl 0 1 <\"$outputDir/test/predict0.tsv\" >\"$outputDir/test/predict.tsv\"" "$progName,$LINENO: "
	if [ "$confidenceTrainProp" != "0" ] && [ ! -s "$modelDir/confidence.no-model" ]; then # different scores-instances and different test set
	    scoreTSV="$outputDir/test/score-predict.tsv"
	    mv  "$outputDir/test/predict.tsv" "$scoreTSV"
	    readFromParamFile "$configFile" "confidenceLearnMethod" "$progName,$LINENO: "
	    if [ "$confidenceLearnMethod" == "simpleOptimC1" ]; then
		dieIfNoSuchFile "$modelDir/optim-c1.confidence-model" "$progName,$LINENO: "
		minDontKnow=$(cat "$modelDir/optim-c1.confidence-model" | cut -f 1)
		maxDontKnow=$(cat "$modelDir/optim-c1.confidence-model" | cut -f 2)
#		echo "DEBUG minDontKnow=$minDontKnow; maxDontKnow=$maxDontKnow" 1>&2
		if [ "$minDontKnow" != "0.5" ] || [ "$maxDontKnow" != "0.5" ]; then # otherwise  case [0.5,0.5]: nothing to do
		    # interpolation of variables in perl one liner definitely too complicated with evalSafe
#		    evalSafe "cat \"$scoreTSV\" | perl -e '\$pol' > \"$outputDir/test/predict.tsv\"" "$progName,$LINENO: "
		    cat "$scoreTSV" | perl -e "while (<STDIN>) { print ''.(((\$_ > $minDontKnow) && (\$_ < $maxDontKnow)) ? \"0.5\n\" : \"\$_\") ; }" > "$outputDir/test/predict.tsv"
		else # simple copy
		    evalSafe "cat \"$scoreTSV\" > \"$outputDir/test/predict.tsv\"" "$progName,$LINENO: "
		fi
	    else # weka
		dieIfNoSuchFile "$modelDir/weka.confidence-model" "$progName,$LINENO: "
		
		tmpHeader=$(mktemp --tmpdir "tmp.$progName.main3.XXXXXXXXXX")
		echo "score">$tmpHeader
		cat "$scoreTSV" >>$tmpHeader
		tmpLabels=$(mktemp --tmpdir "tmp.$progName.main4.XXXXXXXXXX")
		echo "confidenceLabel" >$tmpLabels
		nbCases=$(cat "$testFile" | wc -l)
		for in in $(seq 1 $nbInstances); do # print as many '?' as instances
		    echo "?"
		done >>$tmpLabels

		tmpFeats=$(mktemp --tmpdir "tmp.$progName.main5.XXXXXXXXXX")
		nbCols=$(tail -n 1 "$outputDir/test/features.tsv" | wc -w)
		lastFeat=$(( $nbCols - 1 ))
		evalSafe "cut -f 1-$lastFeat \"$outputDir/test/features.tsv\" >\"$tmpFeats\"" "$progName,$LINENO: "
		evalSafe "paste  $tmpFeats $tmpHeader $tmpLabels >\"$outputDir/test/data2.tsv\"" "$progName,$LINENO: " 
#		echo "DEBUG header=$tmpHeader; labels=$tmpLabels; feats=$tmpFeats" 1>&2
		generateArff "$outputDir/test/data2.tsv" "$outputDir/test/data2.arff" "-n \"confidenceLabel;CONFIDENT,UNSURE\""
		applyModelAndCheck  "$outputDir/test/data2.arff" "$modelDir/weka.confidence-model" "$wekaParams" "$outputDir/test/labels-predict.tsv" "$testFile"
		paste "$scoreTSV" "$outputDir/test/labels-predict.tsv" | while read line; do
		    set -- $line
		    score=$1
		    label=$2
		    if [ "$label" == "CONFIDENT" ]; then
			echo "$score"
		    elif [ "$label" == "UNSURE" ]; then
			echo "0.5"
		    else
			echo "$progName error: invalid label '$label' (bug!)" 1>&2
			exit 1
		    fi
		done >"$outputDir/test/predict.tsv"
		rm -f $tmpHeader $tmpLabels $tmpFeats
	    fi
	fi
    fi
fi



