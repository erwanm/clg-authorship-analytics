#!/bin/bash

# EM April 14
# update March 16

source common-lib.sh
source file-lib.sh
source pan-utils.sh

progName=$(basename "$BASH_SOURCE")

trainCVParams=""                                                             
parallelPrefix=""
sleepTime="5m"
nbFoldsCV=5
perfCriterion="final"
resume=0

function usage {
  echo
  echo "Usage: $progName [options] <configs list file> <input data dir> <output eval dir>"
  echo
  echo "  Takes as input an <input data dir> and a set of"
  echo "  configurations specified in the files in <config list file>; every config is"
  echo "  evaluated using cross-validation, and its performance is stored in a file"
  echo "  with the same prefix in <output eval dir>. Only config files following the"
  echo "  pattern <prefix>.conf are taken into account, and the resulting perf file"
  echo "  is <prefix>.perf."
  echo "  The cases (problems) taken into account are read from <output dir>/cases.list,"
  echo "  and the gold standard (true answer) is read from <output dir>/truth."
  echo
#  echo "  <input data dir> is the complete 'prepared data' dir."
  echo
  echo "  Options:"
  echo "    -h this help"
  echo "    -f <n> specify the number of folds for cross-validation. Default: $nbFoldsCV."
  echo "    -o <train-cv options> options to transmit to train-cv.sh, e.g. '-c -s'."
#  echo "    -c clean up the intermediate files generated in the output eval dir. "
  echo "    -p <id> performance criterion; can be 'AUC', 'C1' or 'final' (default)."
#  echo "    -s failsafe mode: in case of error, does not abort the whole process (which"
#  echo "       is the default) but assigns 0 as performance for the config with which the"
#  echo "       error happened."
  echo "    -P <parallel prefix> specifies a path (possibly with filename prefix) where"
  echo "       tasks are going to be written as individual files instead of being"
  echo "       sequentially executed. This requires an external process which reads the"
  echo "       task files and executes them in parallel."
  echo "    -s <sleep time> (no effect if no -P): if -P, this process will wait for"
  echo "       all tasks to have been executed. The default is $sleepTime between two" 
  echo "       two checks, and this option allows changing this duration."
  echo "    -r resume (keep existing results if existing any instead of recomputing)"
  echo
}






OPTIND=1
while getopts 'hf:p:P:o:rs:' option ; do 
    case $option in
	"s" ) sleepTime="$OPTARG";;
	"o" ) trainCVParams="$OPTARG";;
	"f" ) nbFoldsCV="$OPTARG";;
#	"c" ) trainCVParams="$trainCVParams -c ";;
	"p" ) perfCriterion="$OPTARG";;
	"P" ) parallelPrefix="$OPTARG";;
	"r" ) resume=1;;
	"h" ) usage
 	      exit 0;;
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
if [ ! -z "$printHelp" ]; then
    usage 1>&2
    exit 1
fi
configsFile="$1"
inputDir="$2"
outputPerfDir="$3"


dieIfNoSuchFile "$configsFile" "$progName,$LINENO: "
dieIfNoSuchDir "$inputDir"  "$progName,$LINENO: "
dieIfNoSuchDir "$outputPerfDir" "$progName,$LINENO: "
casesFile="$outputPerfDir/cases.list"
dieIfNoSuchFile "$casesFile" "$progName,$LINENO: "



truthFile="$outputPerfDir/truth"
generateTruthCasesFile "$inputDir" "$truthFile" 1 " | filter-column.pl \"$casesFile\" 1 1" # filter only the  specified cases
nbCases=$(cat "$truthFile" | wc -l)
#echo "DEBUG truthFile=$truthFile; nbCases=$nbCases" 1>&2
#exit 2

if [ $resume -eq 0 ] || [ ! -d "$outputPerfDir/folds" ]; then 
    echo "$progName: generating folds"
    rm -rf "$outputPerfDir/folds" # remove previous folds (especially if previous nbFolds > current nbFolds!!)
    mkdirSafe "$outputPerfDir/folds"
    evalSafe "generate-random-cross-fold-ids.pl $nbFoldsCV $nbCases \"$outputPerfDir/folds/fold\"" "$progName: "
    for foldIndexesFile in "$outputPerfDir/folds"/fold*.indexes; do
#    echo  "DEBUG fold generation: generateTruthCasesFile \"$inputDir\" \"${foldIndexesFile%.indexes}.cases\" 0  \" | select-lines-nos.pl \\\"$foldIndexesFile\\\" 1\" \"$truthFile\"" 1>&2
	generateTruthCasesFile "$inputDir" "${foldIndexesFile%.indexes}.cases" 0  " | select-lines-nos.pl \"$foldIndexesFile\" 1" "$truthFile"
    done
fi

nbConfigs=$(cat "$configsFile" | wc -l)
echo "$progName: evaluating $nbConfigs configs using $nbFoldsCV folds cross-validation ($nbCases cases); resume mode=$resume"
nbConfigs=$(( $nbConfigs - 1 ))
rm -f "$outputPerfDir/configs.results"
waitFile=$(mktemp  --tmpdir  "$progName.main.wait.XXXXXXXXX")
cat "$configsFile" | while read configFile; do
    prefix=$(basename ${configFile%.conf})
    if [ $resume -eq 0 ] || [ ! -s "$outputPerfDir/$prefix.perf" ]; then
	echo "$progName: computing for config $prefix from '$configFile'"
	if [ -z "$parallelPrefix" ]; then
	    echo "$progName: calling 'train-cv.sh $trainCVParams \"$configFile\" \"$inputDir\" \"$outputPerfDir\""
	    evalSafe "train-cv.sh $trainCVParams \"$configFile\" \"$inputDir\" \"$outputPerfDir\"" "$progName,$LINENO: "
	else
	    taskFile=$(evalSafe "mktemp  $parallelPrefix.$prefix.XXXXXXXXX" "$progName,$LINENO: ")
	    echo "train-cv.sh $trainCVParams \"$configFile\" \"$inputDir\" \"$outputPerfDir\" >\"$outputPerfDir/$prefix.log.out\" 2>\"$outputPerfDir/$prefix.log.err\"" >"$taskFile"
	fi
    else
	echo "$progName: using existing results for config $prefix for '$configFile': '$outputPerfDir/$prefix.perf'"
    fi
    evalSafe "echo \"$outputPerfDir/$prefix.perf\" >>\"$waitFile\"" "$progName,$LINENO: "
done
status=$?
#echo "DEBUG $progName status='$status'" 1>&2
if [ $status -ne 0 ]; then
    echo "$progName: an error occured in the main loop, exit code=$status... " 1>&2
    exit 1
fi
waitFilesList "$progName: processing configs. (parallelPrefix='$parallelPrefix')" "$waitFile" $sleepTime
rm -f  "$waitFile"

# extract results
colPerf=
if [ "$perfCriterion" == "AUC" ]; then
    colPerf=2
elif [ "$perfCriterion" == "C1" ]; then
    colPerf=3
elif [ "$perfCriterion" == "final" ]; then
    colPerf=1
else
    echo "$progName error: invalid perfCriterion option '$perfCriterion' (must be 'AUC', 'C1' or 'final')" 1>&2
    exit 1
fi
cat "$configsFile" | while read configFile; do
    prefix=$(basename ${configFile%.conf})
    echo -ne "$configFile\t" >>"$outputPerfDir/configs.results"
    cut -f $colPerf "$outputPerfDir/$prefix.perf" >>"$outputPerfDir/configs.results"
done
echo "$progName: done."


