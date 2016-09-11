#!/bin/bash

# EM April 14
# updated March 16

source common-lib.sh
source file-lib.sh
source pan-utils.sh

progName=$(basename "$BASH_SOURCE")

cleanupTempData=
failSafe=
preferedDataLocation=""

function usage {
  echo
  echo "Usage: $progName [options] <config file> <input dir> <output eval dir>"
  echo
  echo "  High level script which takes as input an <input dir> and a config"
  echo "  file; the config is is evaluated using cross-validation, and its "
  echo "  performance is stored in a file with the same prefix in <output eval dir>."
  echo "  The resulting perf file is <prefix>.perf."
  echo "  "
  echo "  The cases (problems) taken into account are read from <output dir>/cases.list"
  echo
  echo "  Options:"
  echo "    -h this help"
  echo "    -c clean up the intermediate files generated in the output eval dir. "
  echo "    -s failsafe mode: in case of error, does not abort the whole process (which"
  echo "       is the default) but assigns 0 as performance for the config with which the"
  echo "       error happened."
  echo "    -L <prefered input location>"
  echo "       if specified, <input dir> is replaced with this dir if it exists."
  echo
}







OPTIND=1
while getopts 'hcsL:' option ; do 
    case $option in
	"s" ) failSafe=1;;
	"c" ) cleanupTempData=1;;
	"L" ) preferedDataLocation="$OPTARG";;
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
inputDir="$2"
outputPerfDir="$3"


# actually tests already done in train-generation.sh, but playing it safe
dieIfNoSuchFile "$configFile" "$progName,$LINENO: "
dieIfNoSuchDir "$outputPerfDir" "$progName,$LINENO: "

readFromParamFile "$configFile" "strategy" "$progName,$LINENO: "

if [ ! -z "$preferedDataLocation" ] && [ "$strategy" != "meta" ]; then
    if [ -d "$preferedDataLocation" ]; then
	echo "$progName info: Prefered data location '$preferedDataLocation' exists, ok." 1>&2
	if [ ! -f "$preferedDataLocation/lock" ]; then
	    echo "$progName info: Prefered data location: no lock, ok." 1>&2
	    echo "$progName: info: using prefered data location '$preferedDataLocation'" 1>&2
	    inputDir="$preferedDataLocation"
	else
	    echo "$progName info: Prefered data location: locked, cannot use." 1>&2
	fi
    else
	echo "$progName info: Prefered data location '$preferedDataLocation' does not exist" 1>&2
    fi
fi

dieIfNoSuchDir "$inputDir"  "$progName,$LINENO: "


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

#if [ "$strategy" != "meta" ]; then
#    specificPreparedInputDir=$(getPreparedSpecificDir "$configFile" "$inputDir/input" "input")
#else
#    specificPreparedInputDir="$inputDir" # not used
#fi

# test if there is at least one obs type (OR indiv config!)
#readFromParamFile "$configFile" "obsTypesList" "$progName,$LINENO: " "=" 1 # no warning if empty
if [ "$strategy" != "meta" ]; then
    obsTypesListOrStrategiesList=$(echo "$configFile" | extractPossibleObsTypes)
else
    obsTypesListOrStrategiesList=$(echo "$configFile" | extractPossibleObsTypes "indivConf_")
fi

#echo "DEBUG: obsTypesListOrStrategiesList='$obsTypesListOrStrategiesList'" 1>&2


if [ ! -z "$obsTypesListOrStrategiesList" ]; then
    testCasesColFile=$(mktemp --tmpdir "tmp.$progName.main1.XXXXXXXXXX")
    resultsColFile=$(mktemp --tmpdir "tmp.$progName.main2.XXXXXXXXXX")
    status=0 # for non failsafe mode: assume everything ok
    for foldIndexesFile in "$outputPerfDir/folds"/*.train.indexes; do
	foldPrefix=${foldIndexesFile%.train.indexes}
	foldId=$(basename "$foldPrefix")
	echo -n " $foldId;"
	mkdirSafe "$outputPerfDir/$prefix/$foldId" "$progName,$LINENO: "
	if [ -z "$failSafe" ]; then # default: no failsafe, abort if error
	    evalSafe "train-test.sh -l \"$foldPrefix.train.cases\" -m \"$outputPerfDir/$prefix/$foldId/\" \"$inputDir\" \"$configFile\"  \"$outputPerfDir/$prefix/$foldId/\"" "$progName,$LINENO: "
	    evalSafe "train-test.sh -a \"$foldPrefix.test.cases\" -m \"$outputPerfDir/$prefix/$foldId/\" \"$inputDir\" \"$configFile\"  \"$outputPerfDir/$prefix/$foldId/\"" "$progName,$LINENO: "
	else
	    train-test.sh -l "$foldPrefix.train.cases" -m "$outputPerfDir/$prefix/$foldId/" "$inputDir" "$configFile" "$outputPerfDir/$prefix/$foldId/"
	    status=$?
	    if [ $status -eq 0 ]; then
		train-test.sh -a "$foldPrefix.test.cases" -m "$outputPerfDir/$prefix/$foldId/" "$inputDir" "$configFile" "$outputPerfDir/$prefix/$foldId/"
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
# Sept 16:  old version with pan14 eval script, not needed anymore
#	evalSafe "pan14_author_verification_eval.m -i \"$outputPerfDir/$prefix/predicted.answers\" -t \"$truthFile\" -o \"$outputPerfDir/$prefix/eval.out\" >/dev/null 2>&1"  "$progName,$LINENO: "
#	scoreAUC=$(evalSafe "cat \"$outputPerfDir/$prefix/eval.out\" | grep AUC | cut -f 2 -d ':' | tr -d ' },'")
#	scoreC1=$(evalSafe "cat \"$outputPerfDir/$prefix/eval.out\" | grep C1 | cut -f 2 -d ':' | tr -d ' },'")
#	scoreFinal=$(evalSafe "cat \"$outputPerfDir/$prefix/eval.out\" | grep finalScore | cut -f 2 -d ':' | tr -d ' },'")
#	echo -e "V1: $scoreAUC\t$scoreC1\t$scoreFinal" 1>&2
	scoreAUC=$(evalSafe "auc.pl -p 6 -l N:Y \"$truthFile\" \"$outputPerfDir/$prefix/predicted.answers\"")
	scoreC1=$(evalSafe "accuracy.pl -c -p 6 -l N:Y \"$truthFile\" \"$outputPerfDir/$prefix/predicted.answers\" | cut -f 1")
#	echo "DEBUG: printf(\"%.6f\n\", $scoreAUC * $scoreC1);" 1>&2
	scoreFinal=$(perl -e "printf(\"%.6f\n\", $scoreAUC * $scoreC1);")
#	echo -e "V2: $scoreAUC\t$scoreC1\t$scoreFinal" 1>&2
    fi 
    # if status was not zero then we are in falsafe mode AND an error occured;
    # in this case all the scores are undefined and we will set them to zero below:
    # remark: it is also possible that an error occured in computing AUC/C1/final scores,
    #         in this case the error is dealt with below as well.
    if [ -z "$scoreAUC" ] || [ -z "$scoreC1" ] || [ -z "$scoreFinal" ] ; then
	if [ -z "$failSafe" ]; then # default: no failsafe, abort if error
	    echo "$progName error: was not able to compute one of the evaluation scores for '$outputPerfDir/$prefix'" 1>&2
	    exit 1
	else # failsafe mode AND error happened: all scores to zero
	    echo "$progName: an error occured in failsafe mode, returning null scores for '$outputPerfDir/$prefix'" 1>&2
	    scoreAUC=0
	    scoreC1=0
	    scoreFinal=0
	fi
    fi
    echo -e "$scoreFinal\t$scoreAUC\t$scoreC1" >"$outputPerfDir/$prefix.perf"
else # no obs type at all, or no strategy config at all if meta: all scores = zero
    if [ "$strategy" == "meta" ]; then
	echo "$progName, Warning: no strategy config selected at all, returning null scores for '$outputPerfDir/$prefix'" 1>&2
    else
	echo "$progName, Warning: no obs type selected at all, returning null scores for '$outputPerfDir/$prefix'" 1>&2
    fi
    echo -e "0\t0\t0" >"$outputPerfDir/$prefix.perf"
fi

rm -f "$resultsColFile" "$testCasesColFile"
if [ ! -z "$cleanupTempData" ]; then
    rm -rf "$outputPerfDir/$prefix"
fi
