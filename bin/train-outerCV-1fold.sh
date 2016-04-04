#!/bin/bash

# EM  May 15

source common-lib.sh
source file-lib.sh
source pan-utils.sh

progName=$(basename "$BASH_SOURCE")

resume=0
constantParams=""
parallelPrefix=""
applyMultiConfigsParams="-p -s 5s"
#sleepTimeIndivGenetic=15m
sleepTimeIndivGenetic=1m

function usage {
  echo
  echo "Usage: $progName [options] <input/output dir> <train cases file> <test cases file> <multi-conf dir>"
  echo
  echo "  Reads the multi-config files in <multi-conf dir>/*.multi-conf"
  echo "  For each multi-conf file (strategy), a full training process is launched."
  echo "TODO"
  echo
  echo "  Options:"
  echo "    -h this help"
#  echo "    -s fail safe model for train-cv.sh  (do not abort on error)."
  echo "    -o <train-cv options> options to transmit to train-cv.sh, e.g. '-c -s'."
  echo "    -r resume previous process"
#  echo "       remark: recomputes generation <num> and following if existing"
  echo "    -P <parallel prefix> TODO"
#  echo "    -f <first gen configs list file> use a list of individual configs"
#  echo "       to initiate the genetic process (reads only the first column"
#  echo "       of the file)"
#  echo "    -e exhaustive generation of configurations for the first generation;"
#  echo "       Can be used with trainingNbGenerations=1 in order to only"
#  echo "       compute the result of a given set of regular configs provided"
#  echo "       instead of the multi-configs (don't forget to set the parameter"
#  echo "       at least in the first config file)."
#  echo "       Warning: do not use if the multi-conf files contain billions"
#  echo "                of possibilities!"
  echo
}




function generateMetaMultiConf {
    local mcInputFile="$1"
    local indivConfigsFile="$2"
    local mcOutputFile="$3"

    cat "$mcInputFile" >"$mcOutputFile"
    cat "$indivConfigsFile" | cut -f 1 | while read configId; do
#	configId=$(basename "$configDir")
	echo "indivConf_$configId=0 1" 
    done >>"$mcOutputFile"
    if [ $? -ne 0 ]; then
	echo "$progName: bug line $LINENO" 1>&2
	exit 6
    fi

}



OPTIND=1
while getopts 'hP:o:r' option ; do 
    case $option in
	"h" ) usage
 	      exit 0;;
	"P" ) parallelPrefix="$OPTARG"
	      applyMultiConfigsParams="$applyMultiConfigsParams -P \"$parallelPrefix\"";;
	"r" ) resume=1
	      applyMultiConfigsParams="$applyMultiConfigsParams -r"
	      constantParams="$constantParams -r";;
        "o" ) constantParams="$constantParams -o \"$OPTARG\"";;
 	"?" ) 
	    echo "Error, unknow option." 1>&2
            printHelp=1;;
    esac
done
shift $(($OPTIND - 1))
if [ $# -ne 4 ]; then
    echo "Error: expecting 4 args." 1>&2
    printHelp=1
fi
if [ ! -z "$printHelp" ]; then
    usage 1>&2
    exit 1
fi
outputDir="$1"
trainCasesFile="$2"
testCasesFile="$3"
multiConfDir="$4"

rm -f "$outputDir/best-meta-configs.list"
dieIfNoSuchDir "$outputDir" "$progName,$LINENO: "
dieIfNoSuchDir "$multiConfDir" "$progName,$LINENO: "
dieIfNoSuchFile "$outputDir/meta-template.multi-conf" "$progName,$LINENO: "
mkdirSafe "$outputDir/strategy-training"
nbStrategies=0
waitFile=$(mktemp --tmpdir "$progName.main1.wait.XXXXXXXXX")
for multiConfStrategyFile in "$multiConfDir"/*.multi-conf; do
    strategy=$(basename "${multiConfStrategyFile%.multi-conf}")
    strategyDir="$outputDir/strategy-training/$strategy"
    rm -f "$strategyDir/done.signal"
    mkdirSafe "$strategyDir"
    rm -f "$strategyDir/input" "$strategyDir/resources-options.conf" 
    linkAbsolutePath "$strategyDir" "$outputDir/input"  "$outputDir/resources-options.conf" 
    echo "$progName: launching training process for strategy '$strategy' in '$strategyDir'; multiConfStrategyFile=$multiConfStrategyFile"
    rm -f "$strategyDir/done.signal"
    if [ -z "$parallelPrefix" ]; then
	evalSafe "train-multi-stages.sh $constantParams \"$strategyDir\" \"$trainCasesFile\" \"$multiConfStrategyFile\" \"indivGenetic\"" "$progName,$LINENO: "
    else
	eval "train-multi-stages.sh -P \"$parallelPrefix.$strategy\" $constantParams \"$strategyDir\" \"$trainCasesFile\" \"$multiConfStrategyFile\" \"indivGenetic\" >\"$strategyDir/train-multi-stages.out\" 2>\"$strategyDir/train-multi-stages.err\""  &
    fi
    evalSafe "echo \"$strategyDir/done.signal\" >>\"$waitFile\"" "$progName,$LINENO: "
    nbStrategies=$(( $nbStrategies + 1 ))
done


waitFilesList "$progName: genetic process in progress." "$waitFile" $sleepTimeIndivGenetic
rm -f  "$waitFile"

# apply indiv strategies to all data (both training fold + test fold for later)


applyDir="$outputDir/apply-strategy-configs"
mkdirSafe "$applyDir"

generateTruthCasesFile "$outputDir" "$applyDir/train.truth" 1 " | filter-column.pl \"$trainCasesFile\" 1 1"
#evalSafe "cut -d ' ' -f 1 \"$applyDir/train.truth\" >\"$applyDir/train.cases\""  "$progName,$LINENO: "
generateTruthCasesFile "$outputDir" "$applyDir/test.truth" 1 " | filter-column.pl \"$testCasesFile\" 1 1"
#evalSafe "cut -d ' ' -f 1 \"$applyDir/test.truth\" >\"$applyDir/test.cases\""  "$progName,$LINENO: "

mkdirSafe "$applyDir/fold.train"
echo "$progName: applying every selected strategy config/model to all cases (train fold: copy; test fold: compute)"
rm -f "$outputDir/selected-strategy-configs.list"
for multiConfStrategyFile in "$multiConfDir"/*.multi-conf; do
    strategy=$(basename "${multiConfStrategyFile%.multi-conf}")
    strategyDir="$outputDir/strategy-training/$strategy"

#    for trainTest in train test; do
#	evalSafe "apply-multi-configs.sh -o \"$strategy.\" $applyMultiConfigsParams -m \"$outputDir\" \"$strategyDir/best.prefix-list\" \"$applyDir/$trainTest.truth\" \"$applyDir/fold.$trainTest\""  "$progName,$LINENO: "
#    done

    # only for test fold; for train fold, using answers obtained with CV (see below)
    evalSafe "apply-multi-configs.sh -o \"$strategy.\" $applyMultiConfigsParams -m \"$outputDir\" \"$strategyDir/best.prefix-list\" \"$applyDir/test.truth\" \"$applyDir/fold.test\""  "$progName,$LINENO: "

    # global predictions
    cat "$strategyDir/best.prefix-list" | while read prefix; do
	id=$(basename "$prefix")
	id="$strategy.$id"
	# copy predictions obtained with CV for train fold
	mkdirSafe "$applyDir/fold.train/$id"
	evalSafe "cat \"$prefix/predicted.answers\" > \"$applyDir/fold.train/$id/predicted.answers\"" "$progName,$LINENO: "
	evalSafe "cat \"$prefix.perf\" > \"$applyDir/fold.train/$id.perf\"" "$progName,$LINENO: "
	evalSafe "cat \"$applyDir/fold.train/$id/predicted.answers\" \"$applyDir/fold.test/$id/predicted.answers\" | sort +0 -1 >\"$applyDir/$id.answers\"" "$progName,$LINENO: "
	evalSafe "echo -e \"$id\\t$prefix\" >>\"$outputDir/selected-strategy-configs.list\"" "$progName,$LINENO: "
    done
    if [ $? -ne 0 ]; then
	echo "$progName: BUG line $LINENO" 1>&2
	exit 2
    fi
done



##################################################
# MAJOR RE-DESIGN: using test fold, divided in two
##################################################


nbCases=$(cat "$testCasesFile" | wc -l)
if [ $resume -ne 0 ] || [ ! -d "$outputDir/sub-folds" ]; then
    echo "$progName: generating sub-folds"
    mkdir "$outputDir/sub-folds"
    evalSafe "generate-random-cross-fold-ids.pl 2 $nbCases \"$outputDir/sub-folds/fold\"" "$progName,$LINENO: "
    for foldIndexesFile in "$outputDir/sub-folds"/fold*.indexes; do
        evalSafe "cat \"$testCasesFile\" | select-lines-nos.pl \"$foldIndexesFile\" 1 >\"${foldIndexesFile%.indexes}.cases\""  "$progName,$LINENO: "
    done
fi



########## !!!
metaTrainCasesFile="$outputDir/sub-folds"/fold.1.train.cases
metaTestCasesFile="$outputDir/sub-folds"/fold.1.test.cases
##########


metaDir="$outputDir/meta-training"
metaMC="$metaDir/meta.multi-conf"
mkdirSafe "$metaDir"
echo "$progName: generating the mluti-conf file for meta training stage in '$metaMC'"
generateMetaMultiConf "$outputDir/meta-template.multi-conf" "$outputDir/selected-strategy-configs.list" "$metaMC"
rm -f "$metaDir/$(basename "$applyDir")" 
linkAbsolutePath "$metaDir" "$applyDir" 
# prepared-data because sub-scripts use the truth file from there; not great design but harmless
#rm -f "$metaDir/prepared-data" 
#linkAbsolutePath "$metaDir" "$outputDir/prepared-data"
linkAbsolutePath "$metaDir" "$outputDir/input" "$outputDir/resources-options.conf"


echo "$progName: launching training process for meta stage in '$metaDir'; multiConfStrategyFile=$metaMC"
if [ -z "$parallelPrefix" ]; then
    evalSafe "train-multi-stages.sh $constantParams \"$metaDir\" \"$metaTrainCasesFile\" \"$metaMC\" \"metaGenetic\"" "$progName,$LINENO: "
else
    eval "train-multi-stages.sh -P \"$parallelPrefix.meta\" $constantParams \"$metaDir\" \"$metaTrainCasesFile\" \"$metaMC\" \"metaGenetic\" >\"$metaDir/train-multi-stages.out\" 2>\"$metaDir/train-multi-stages.err\""
fi


# apply META CONFIGS to all data

echo "$progName: applying every selected meta-config to all cases (meta train fold: copy; strategy train fold + meta test fold: compute)"
# folds = meta-train; meta-test; strategy-train
metaApplyDir="$outputDir/apply-meta-configs"
mkdirSafe "$metaApplyDir"
mkdirSafe "$metaApplyDir/fold.meta-train" 
#echo "DEBUG command:" 1>&2
#echo  "apply-multi-configs.sh $applyMultiConfigsParams -m \"$outputDir\" \"$metaDir/best.prefix-list\" \"$metaTestCasesFile\" \"$metaApplyDir/fold.meta-test\"" 1>&2
evalSafe "apply-multi-configs.sh $applyMultiConfigsParams -m \"$outputDir\" \"$metaDir/best.prefix-list\" \"$metaTestCasesFile\" \"$metaApplyDir/fold.meta-test\""  "$progName,$LINENO: "
evalSafe "apply-multi-configs.sh $applyMultiConfigsParams -m \"$outputDir\" \"$metaDir/best.prefix-list\" \"$trainCasesFile\" \"$metaApplyDir/fold.strategy-train\""  "$progName,$LINENO: "

# global predictions for meta- configs/models
rm -f "$outputDir/selected-meta-configs.list"
cat "$metaDir/best.prefix-list" | while read prefix; do
    id=$(basename "$prefix")
    mkdirSafe "$metaApplyDir/fold.meta-train/$id"
    evalSafe "cat \"$prefix/predicted.answers\" > \"$metaApplyDir/fold.meta-train/$id/predicted.answers\"" "$progName,$LINENO: "
    evalSafe "cat \"$prefix.perf\" > \"$metaApplyDir/fold.meta-train/$id.perf\"" "$progName,$LINENO: "
    evalSafe "cat \"$metaApplyDir/fold.meta-train/$id/predicted.answers\" \"$metaApplyDir/fold.meta-test/$id/predicted.answers\" \"$metaApplyDir/fold.strategy-train/$id/predicted.answers\" | sort +0 -1 >\"$metaApplyDir/$id.answers\"" "$progName,$LINENO: "
    evalSafe "echo \"$metaApplyDir/$id\" >>\"$outputDir/selected-meta-configs.list\"" "$progName,$LINENO: "
done

# repackaging the indiv strategy configs as meta configs (so that answers are properly obtained for last stage in top-level)
# WARNING: answers on the train set might still be overevaluated!!
echo "$progName: refactoring strategy configs"

rm -f "$outputDir/refactored-strategy-configs.list"
rm -rf "$outputDir/refactored-strategy-configs"
mkdir "$outputDir/refactored-strategy-configs"
cut -f 1 "$outputDir/selected-strategy-configs.list" | while read strategyId; do
    metaPrefix="$outputDir/refactored-strategy-configs/strategy-as-meta.$strategyId"
    echo "strategy=meta" >"$metaPrefix.conf"
    echo "confidenceTrainProp=0" >>"$metaPrefix.conf"
    echo "confidenceLearnMethod=simpleOptimC1" >>"$metaPrefix.conf"
    echo "learnMethod=mean" >>"$metaPrefix.conf"
    echo "indivConf_${strategyId}=1" >>"$metaPrefix.conf"
    mkdir "$metaPrefix.model" # empty dir, nothing needed
    echo "$metaPrefix" >>"$outputDir/refactored-strategy-configs.list"
done
if [ $? -ne 0 ]; then
    echo "$progName: bug line $LINENO" 1>&2
    exit 5
fi

# BAGGING on meta-test cases only

readFromParamFile "$metaMC" "metaTestFold_bagging_nbRuns" "$progName,$LINENO: "
readFromParamFile "$metaMC" "metaTestFold_bagging_returnNbBest" "$progName,$LINENO: "

allPrefixes="$outputDir/strategy+best-meta.prefix-list"
evalSafe "cat \"$outputDir/refactored-strategy-configs.list\" \"$metaDir/best.prefix-list\" > \"$allPrefixes\"" "$progName,$LINENO: "

baggingDir="$outputDir/bagging-meta-test-fold"
resumeParam=""
if [ $resume -ne 0 ]; then
    resumeParam="-r"
fi
evalSafe "apply-bagging.sh $resumeParam  -o \"$applyMultiConfigsParams -m $outputDir\" \"$metaTestFold_bagging_nbRuns\" \"$allPrefixes\" \"$metaTestCasesFile\" \"$baggingDir\"" "$progName,$LINENO: "

nbMedian=$(( $metaTestFold_bagging_returnNbBest / 2 ))
nbMeanMinusSD=$(( $metaTestFold_bagging_returnNbBest - $nbMedian ))

#evalSafe "cut -f 1 \"$baggingDir/runs.final-rank\" >\"$outputDir/best-meta-configs.list\"" "$progName,$LINENO: "
evalSafe "cut -f 1,3 \"$baggingDir/runs.stats\" | sort -r -g +1 -2 | head -n $nbMedian | cut -f 1 >\"$outputDir/best-meta-configs-median.list\"" "$progName,$LINENO: "
evalSafe "cut -f 1,4 \"$baggingDir/runs.stats\" | sort -r -g +1 -2 | head -n $nbMeanMinusSD | cut -f 1 >\"$outputDir/best-meta-configs-meanMinusSD.list\"" "$progName,$LINENO: "
# remove duplicates
evalSafe "cat \"$outputDir/best-meta-configs-median.list\" \"$outputDir/best-meta-configs-meanMinusSD.list\" | sort -u >\"$outputDir/best-meta-configs.list\"" "$progName,$LINENO: "


echo "$progName: done."


