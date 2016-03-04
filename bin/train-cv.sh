#!/bin/bash

# EM April 14
# updated March 16

source common-lib.sh
source file-lib.sh
source pan-utils.sh

progName=$(basename "$BASH_SOURCE")

cleanupTempData=
failSafe=

function usage {
  echo
  echo "Usage: $progName [options] <config file> <input data dir> <output eval dir>"
  echo
  echo   DEPRECATED
  echo "  High level script which takes as input an <input data dir> and a set of"
  echo "  configurations specified in the files in <config list file>; every config is"
  echo "  evaluated using cross-validation, and its performance is stored in a file"
  echo "  with the same prefix in <output eval dir>. Only config files following the"
  echo "  pattern <prefix>.conf are taken into account, and the resulting perf file"
  echo "  is <prefix>.perf."
  echo "  The cases (problems) taken into account are read from <output dir>/cases.list"
  echo
  echo "  <input data dir> is the complete 'prepared data' dir."
  echo
  echo "  Options:"
  echo "    -h this help"
  echo "    -c clean up the intermediate files generated in the output eval dir. "
  echo "    -s failsafe mode: in case of error, does not abort the whole process (which"
  echo "       is the default) but assigns 0 as performance for the config with which the"
  echo "       error happened."
  echo
}







OPTIND=1
while getopts 'hcs' option ; do 
    case $option in
	"s" ) failSafe=1;;
	"c" ) cleanupTempData=1;;
#	"r" ) refDataDir=$OPTARG;;
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
configFile="$1"
inputDataDir="$2"
outputPerfDir="$3"


# actually tests already done in train-generation.sh, but playing it safe
dieIfNoSuchFile "$configFile" "$progName,$LINENO: "
dieIfNoSuchDir "$inputDataDir"  "$progName,$LINENO: "
dieIfNoSuchDir "$outputPerfDir" "$progName,$LINENO: "

if [ -z "$failSafe" ]; then # default: no failsafe, abort if error
    echo "$progName: fail safe mode is OFF"
else
    echo "$progName info: fail safe mode is ON"
fi
if [ -z "$cleanupTempData" ]; then
   echo "$progName: cleanup mode is OFF"
else
   echo "$progName: cleanup mode is ON"
fi

truthFile="$outputPerfDir/truth"
prefix=$(basename ${configFile%.conf})
#echo -ne "\r                                                             "
#echo -en "\r$prefix / $nbConfigs: "
mkdirSafe "$outputPerfDir/$prefix" "$progName,$LINENO: "

#readFromParamFile "$configFile" "strategy" "$progName,$LINENO: "
#if [ "$strategy" != "meta" ]; then
#    specificPreparedInputDir=$(getPreparedSpecificDir "$configFile" "$inputDataDir/input" "input")
#else
#    specificPreparedInputDir="$inputDataDir" # not used
#fi

# test if there is at least one obs type (OR indiv config!)
#readFromParamFile "$configFile" "obsTypesList" "$progName,$LINENO: " "=" 1 # no warning if empty
obsTypesList=$(echo "$configFile" | extractPossibleObsTypes)

if [ ! -z "$obsTypesList" ]; then
    testCasesColFile=$(mktemp --tmpdir "tmp.$progName.main1.XXXXXXXXXX")
    resultsColFile=$(mktemp --tmpdir "tmp.$progName.main2.XXXXXXXXXX")
    status=0 # for non failsafe mode: assume everything ok
    for foldIndexesFile in "$outputPerfDir/folds"/*.train.indexes; do
	foldPrefix=${foldIndexesFile%.train.indexes}
	foldId=$(basename "$foldPrefix")
	echo -n " $foldId;"
	mkdirSafe "$outputPerfDir/$prefix/$foldId" "$progName,$LINENO: "
	if [ -z "$failSafe" ]; then # default: no failsafe, abort if error
#	    evalSafe "train-test.sh -l \"$foldPrefix.train.cases\" -m \"$outputPerfDir/$prefix/$foldId/\" \"$specificPreparedInputDir\" \"$configFile\"  \"$inputDataDir\" \"$outputPerfDir/$prefix/$foldId/\"" "$progName,$LINENO: "
#	    evalSafe "train-test.sh -a \"$foldPrefix.test.cases\" -m \"$outputPerfDir/$prefix/$foldId/\" \"$specificPreparedInputDir\" \"$configFile\"  \"$inputDataDir\" \"$outputPerfDir/$prefix/$foldId/\"" "$progName,$LINENO: "
	    evalSafe "train-test.sh -l \"$foldPrefix.train.cases\" -m \"$outputPerfDir/$prefix/$foldId/\" \"$inputDataDir\" \"$configFile\"  \"$inputDataDir\" \"$outputPerfDir/$prefix/$foldId/\"" "$progName,$LINENO: "
	    evalSafe "train-test.sh -a \"$foldPrefix.test.cases\" -m \"$outputPerfDir/$prefix/$foldId/\" \"$inputDataDir\" \"$configFile\"  \"$inputDataDir\" \"$outputPerfDir/$prefix/$foldId/\"" "$progName,$LINENO: "
	else
#	    train-test.sh -l "$foldPrefix.train.cases" -m "$outputPerfDir/$prefix/$foldId/" "$specificPreparedInputDir" "$configFile" "$inputDataDir" "$outputPerfDir/$prefix/$foldId/"
	    train-test.sh -l "$foldPrefix.train.cases" -m "$outputPerfDir/$prefix/$foldId/" "$inputDataDir" "$configFile" "$inputDataDir" "$outputPerfDir/$prefix/$foldId/"
	    status=$?
	    if [ $status -eq 0 ]; then
#		train-test.sh -a "$foldPrefix.test.cases" -m "$outputPerfDir/$prefix/$foldId/" "$specificPreparedInputDir" "$configFile" "$inputDataDir" "$outputPerfDir/$prefix/$foldId/"
		train-test.sh -a "$foldPrefix.test.cases" -m "$outputPerfDir/$prefix/$foldId/" "$inputDataDir" "$configFile" "$inputDataDir" "$outputPerfDir/$prefix/$foldId/"
		status=$?
	    fi
	    if [ $status -ne 0 ]; then # fail safe
		break
	    fi
	fi
	rm -f "$outputPerfDir/$prefix/$foldId/weka.scores-model" "$outputPerfDir/$prefix/$foldId/weka.confidence-model"
	evalSafe "cat \"$foldPrefix.test.cases\" | cut -f 1 >>\"$testCasesColFile\""  "$progName,$LINENO: "
	evalSafe "cat \"$outputPerfDir/$prefix/$foldId/test/predict.tsv\" >>\"$resultsColFile\""  "$progName,$LINENO: "
    done
    echo
    if [ $status -eq 0 ]; then
	evalSafe "paste \"$testCasesColFile\" \"$resultsColFile\" | sort +0 -1 |  sed 's/\t/ /g' >\"$outputPerfDir/$prefix/predicted.answers\""  "$progName,$LINENO: "
	# send also STDERR to /dev/null because of annoying warning DISPLAY not set; not very good
	if [ ! -s "$outputPerfDir/$prefix/predicted.answers" ] || [ ! -s "$truthFile" ]; then # should not happen but....
	    echo "$progName error: one of '$outputPerfDir/$prefix/predicted.answers' and/or '$truthFile' does not exist or is empty; $!" 1>&2
	    exit 42
	fi
	evalSafe "pan14_author_verification_eval.m -i \"$outputPerfDir/$prefix/predicted.answers\" -t \"$truthFile\" -o \"$outputPerfDir/$prefix/eval.out\" >/dev/null 2>&1"  "$progName,$LINENO: "
	scoreAUC=$(evalSafe "cat \"$outputPerfDir/$prefix/eval.out\" | grep AUC | cut -f 2 -d ':' | tr -d ' },'")
	scoreC1=$(evalSafe "cat \"$outputPerfDir/$prefix/eval.out\" | grep C1 | cut -f 2 -d ':' | tr -d ' },'")
	scoreFinal=$(evalSafe "cat \"$outputPerfDir/$prefix/eval.out\" | grep finalScore | cut -f 2 -d ':' | tr -d ' },'")
    else # failsafe mode AND error happened: all scores to zero
	echo "$progName: an error occured in failsafe mode, returning null scores for '$outputPerfDir/$prefix'" 1>&2
	scoreAUC=0
	scoreC1=0
	scoreFinal=0
    fi
    if [ -z "$scoreAUC" ] || [ -z "$scoreC1" ] || [ -z "$scoreFinal" ] ; then
	echo "$progName error: was not able to extract one of the evaluation scores from '$outputPerfDir/$prefix/eval.out'" 1>&2
	exit 1
    fi
    echo -e "$scoreFinal\t$scoreAUC\t$scoreC1" >"$outputPerfDir/$prefix.perf"
else # no obs type at all: all scores = zero
    echo "$progName, Warning: no obs type selected at all, returning null scores for '$outputPerfDir/$prefix'" 1>&2
    echo -e "0\t0\t0" >"$outputPerfDir/$prefix.perf"
fi

rm -f "$resultsColFile" "$testCasesColFile"
if [ ! -z "$cleanupTempData" ]; then
    rm -rf "$outputPerfDir/$prefix"
fi
