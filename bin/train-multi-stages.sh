#!/bin/bash

# EM April 14, modif May 15

source common-lib.sh
source file-lib.sh
source pan-utils.sh

progName=$(basename "$BASH_SOURCE")

resume=0
constanntParams=""
parallelPrefix=""
finalNtimes2CV=10
sleepTime=1m
nbFoldsCV=5

function usage {
  echo
  echo "Usage: $progName [options] <input/output dir> <cases file> <(multi-)config file> <prefix params>"
  echo
  echo "TODO"
  echo "  <prefix params> = e.g. indivGenetic"
  echo
  echo "  Options:"
  echo "    -h this help"
#  echo "    -s fail safe model for train-cv.sh  (do not abort on error)."
  echo "    -o <train-cv options> options to transmit to train-cv.sh, e.g. '-c -s'."
  echo "    -f <N> number of folds in final N x 2 folds TODO"
  echo "    -r <num> resume previous process"
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



OPTIND=1
while getopts 'hP:o:r' option ; do 
    case $option in
	"h" ) usage
 	      exit 0;;
	"P" ) parallelPrefix="$OPTARG";;
	"r" ) resume=1
	      constantParams="$constantParams -r";;
	"o" ) constantParams="$constantParams -o \"$OPTARG\"";;
	"?" ) 
	    echo "Error, unknown option." 1>&2
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
casesFile="$2"
configFile="$3"
prefixParams="$4"

rm -f "$outputDir/done.signal"
mkdirSafe "$outputDir"
dieIfNoSuchFile "$configFile" "$progName,$LINENO: "

stagesTmpFile=$(mktemp --tmpdir "tmp.$progName.main.XXXXXXXXX")
evalSafe "grep \"^${prefixParams}_._\" \"$configFile\" | while read l; do echo \${l%_*}; done | sort -u > \"$stagesTmpFile\"" "$progName,$LINENO: "
n=$(cat "$stagesTmpFile" | grep "." | wc -l)
if [ $n -eq 0 ]; then
    echo "Error: could not extract any parameter with prefix '$prefixParams' from '$configFile'" 1>&2
    exit 17
fi
stagesIds=$(cat "$stagesTmpFile" | tr '\n' ' ')
rm -f "$stagesTmpFile"
echo "$progName: stagesIds = $stagesIds; config file=$configFile"

readFromParamFile "$configFile" "${prefixParams}_final_nbFolds" "$progName,$LINENO: " "" "" "" "finalNbFolds"
readFromParamFile "$configFile" "${prefixParams}_final_nbRuns" "$progName,$LINENO: " "" "" "" "finalNbRuns"
readFromParamFile "$configFile" "${prefixParams}_final_returnNbBest" "$progName,$LINENO: " "" "" "" "finalNbBest"
readFromParamFile "$configFile" "strategy" "$progName,$LINENO: "


for stageId in $stagesIds; do
    if [ $resume -eq 0 ] || [ ! -f "$outputDir/$stageId/best-configs.res" ]; then
	echo "$progName: *** starting genetic stage $stageId ***" 
	params="$constantParams"
	if [ ! -z "$parallelPrefix"  ]; then
	    params="$params -P \"$parallelPrefix.$stageId\""
	fi
	mkdirSafe "$outputDir/$stageId"
	rm -f "$outputDir/$stageId/input"  "$outputDir/$stageId/resources-options.conf"
	linkAbsolutePath "$outputDir/$stageId" "$outputDir/input" "$outputDir/resources-options.conf"
	if [ "$strategy" == "meta" ]; then
	    rm -f "$outputDir/$stageId/apply-strategy-configs"
	    linkAbsolutePath "$outputDir/$stageId" "$outputDir/apply-strategy-configs"
	fi
	if [ ! -z "$prevStageBest" ]; then
	    params="$params -f \"$prevStageBest\""
	fi
	evalSafe "echo \"$configFile\" | train-genetic.sh $params \"$outputDir/$stageId\" \"$casesFile\" \"${stageId}_\""  "$progName,$LINENO: "
    fi
    prevStageBest="$outputDir/$stageId/best-configs.res"
done

params="$constantParams -x $finalNbRuns -f $finalNbFolds -b $finalNbBest"
if [ ! -z "$parallelPrefix"  ]; then
    params="$params -P \"$parallelPrefix.runs\""
fi
#echo "$progName DEBUG: params='$params'"
echo "$progName: calling 'train-multi-runs.sh $params \"$outputDir\" \"$casesFile\" \"$prevStageBest\"'"
evalSafe "train-multi-runs.sh $params \"$outputDir\" \"$casesFile\" \"$prevStageBest\""  "$progName,$LINENO: "


bestConfigsRunsList="$outputDir/runs-best-configs.list"

if [ "$indivGenetic_final_selectMethod" == "mean" ]; then
    evalSafe "cut -f 1,2 \"$outputDir/runs/runs.stats\" | sort -r -g -k 2,2 | cut -f 1  >\"$bestConfigsRunsList\"" "$progName,$LINENO: "
elif [ "$indivGenetic_final_selectMethod" == "mixedMeanMedianMinusSD" ]; then
    nbMedian=$(( $metaTestFold_bagging_returnNbBest / 2 ))
    nbMeanMinusSD=$(( $metaTestFold_bagging_returnNbBest - $nbMedian ))
    evalSafe "cut -f 1,3 \"$baggingDir/runs.stats\" | sort -r -g +1 -2 | head -n $nbMedian | cut -f 1 >\"$outputDir/runs-best-configs-median.list\"" "$progName,$LINENO: "
    evalSafe "cut -f 1,5 \"$baggingDir/runs.stats\" | sort -r -g +1 -2 | head -n $nbMeanMinusSD | cut -f 1 >\"$outputDir/runs-best-configs-meanMinusSD.list\"" "$progName,$LINENO: "
    # remove duplicates
    evalSafe "cat \"$outputDir/runs-best-configs-median.list\" \"$outputDir/runs-best-configs-meanMinusSD.list\" | sort -u >\"$bestConfigsRunsList\"" "$progName,$LINENO: "
else
    echo "$progName,$LINENO: invalid value '$indivGenetic_final_selectMethod' for parameter 'indivGenetic_final_selectMethod'" 1>&2
    exit 6
fi



# re-train selected models on all the cases
echo "$progName: re-training selected configs using all cases AND re-cross-validating to obtain unbiased predictions"

bestDir="$outputDir/best"
mkdirSafe "$bestDir"  "$progName,$LINENO: "

echo "$progName: generating folds for CV (unbiased predictions)"
truthFile="$bestDir/truth"
generateTruthCasesFile "$outputDir" "$truthFile" 1 " | filter-column.pl \"$casesFile\" 1 1" # filter only the  specified cases
nbCases=$(cat "$truthFile" | wc -l)
if [ $resume -eq 0 ] || [ ! -d "$bestDir/folds" ]; then
    rm -rf "$bestDir/folds"
    mkdirSafe "$bestDir/folds"
    evalSafe "generate-random-cross-fold-ids.pl $nbFoldsCV $nbCases \"$bestDir/folds/fold\"" "$progName,$LINENO: "
    for foldIndexesFile in "$bestDir/folds"/fold*.indexes; do
        generateTruthCasesFile "$outputDir" "${foldIndexesFile%.indexes}.cases" 0  " | select-lines-nos.pl \"$foldIndexesFile\" 1" "$truthFile"
    done
fi

confNo=1
rm -f "$outputDir/best.prefix-list"
casesForRetrainingFile="$bestDir/cases"
generateTruthCasesFile "$outputDir" "$casesForRetrainingFile" 0 " | filter-column.pl \"$casesFile\" 1 1" # different from truthFile above: 0/1 instead of Y/N
waitFile=$(mktemp --tmpdir="$bestDir" "$progName.main.wait.XXXXXXXXX") # not using local /tmp because different in case running on cluster (unsure if it's useful? but apparently solved a bug??)
#echo "DEBUG $waitFile" 1>&2
cat "$bestConfigsRunsList" | cut -f 1 | while read configFile; do
    confNoStr=$(printf "%04d" $confNo)
    if [ $resume -eq 0 ] || [ ! -d "$bestDir/$confNoStr.model" ] || [ ! -s "$bestDir/$confNoStr/predicted.answers" ] ; then
	evalSafe "cat \"$configFile\" >\"$bestDir/$confNoStr.conf\""  "$progName,$LINENO: "
	mkdirSafe "$bestDir/$confNoStr.model"  "$progName,$LINENO: "
	command1="train-test.sh -l \"$casesForRetrainingFile\" -m \"$bestDir/$confNoStr.model\" \"$outputDir\" \"$bestDir/$confNoStr.conf\" \"$bestDir/$confNoStr.model\""
	command2="train-cv.sh  \"$bestDir/$confNoStr.conf\" \"$outputDir\" \"$bestDir\""

	if [ -z "$parallelPrefix"  ]; then
	    echo "$progName: calling '$command1'"
	    evalSafe "$command1"  "$progName,$LINENO: "
	    echo "$progName: calling '$command2'"
	    evalSafe "$command2"  "$progName,$LINENO: "
	else
            taskFile1=$(evalSafe "mktemp $parallelPrefix.final-train.model.$confNoStr.XXXXXXXXX" "$progName,$LINENO: ")
	    echo "$command1 >\"$bestDir/$confNoStr.model.log.out\" 2>\"$bestDir/$confNoStr.model.log.err\"" >"$taskFile1"
            taskFile2=$(evalSafe "mktemp $parallelPrefix.final-train.cv.$confNoStr.XXXXXXXXX" "$progName,$LINENO: ")
	    echo "$command2 >\"$bestDir/$confNoStr.cv.log.out\" 2>\"$bestDir/$confNoStr.cv.log.err\"" >"$taskFile2"
	fi
    else
	echo "$progName: model already retrained and CV-predictions extracted for config $confNoStr"
    fi
    evalSafe "echo \"$bestDir/$confNoStr\" >>\"$outputDir/best.prefix-list\""  "$progName,$LINENO: "
    evalSafe "echo \"$bestDir/$confNoStr.model\" >>\"$waitFile\""  "$progName,$LINENO: "
    evalSafe "echo \"$bestDir/$confNoStr/predicted.answers\" >>\"$waitFile\""  "$progName,$LINENO: "
    confNo=$(( $confNo + 1 ))
done
if [ $? -ne 0 ]; then
    echo "$progName: error, something wrong in final re-training loop" 1>&2
    exit 3
fi
waitFilesList "$progName: retraining selected configs." "$waitFile" $sleepTime
rm -f  "$waitFile"



# this is the signal for calling script (train-outerCV-1fold.sh) to proceed
echo "done" >"$outputDir/done.signal"

echo "$progName: done."
