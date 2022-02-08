#!/bin/bash

# EM  May 15, update March 16

source common-lib.sh
source file-lib.sh
source pan-utils.sh

progName=$(basename "$BASH_SOURCE")


outputIdPrefix=""


function usage {
  echo
  echo "Usage: $progName [options] <config prefix> <cases file> <main dir> <dest dir>" 
  echo
  echo " applies a config (can be an indiv strategy config or a meta config)"
  echo " to a set of cases."
  echo " <config prefix> is such that the config file is <prefix>.conf and"
  echo "  the model dir is <prefix>.model."
  echo "  <main dir> must contain a properly initialized dir 'prepared-data'"
  echo "  for a strategy config, or 'apply-strategy-configs' for a meta config."
  echo
  echo "  Options:"
  echo "    -h this help"
  echo "    -g <gold file> also compute perf: the gold file is in the original format"
  echo "       (space, Y/N) and must contain exactly the cases in <cases file>."
  echo "       (remark: this is because train-test.sh cannot have Y/N, needed for eval)"
  echo "       the perf file is written as <dest dir>.perf (i.e. one level up)"
  echo
}




OPTIND=1
while getopts 'hg:' option ; do 
    case $option in
	"h" ) usage
 	      exit 0;;
	"g" ) goldFile="$OPTARG";;
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

prefix="$1"
casesFile="$2"
mainDir="$3"
destDir="$4"

dieIfNoSuchFile "$prefix.conf" "$progName,$LINENO: "
dieIfNoSuchDir "$prefix.model" "$progName,$LINENO: "

mkdirSafe "$destDir" "$progName,$LINENO: "
nbLinesTruth=$(cat "$casesFile" | wc -l)

#readFromParamFile "$prefix.conf" "strategy" "$progName,$LINENO: "
#if [ "$strategy" != "meta" ]; then # indiv (strategy) config
#    dieIfNoSuchDir "$mainDir/prepared-data" "$progName,$LINENO: "
#    specificPreparedInputDir=$(getPreparedSpecificDir "$prefix.conf" "$mainDir/prepared-data/input" "input")
#else # meta config
#    dieIfNoSuchDir "$mainDir/apply-strategy-configs" "$progName,$LINENO: "
#    specificPreparedInputDir="$mainDir/prepared-data" 
#fi

echo "$progName: applying config '$prefix' to cases '$casesFile'; results written to '$destDir'"

# apply
evalSafe "train-test.sh -a \"$casesFile\" -m \"$prefix.model\" \"$mainDir\" \"$prefix.conf\" \"$destDir\""  "$progName,$LINENO: "

# extract answers
# remark: I'm not sure what the dest file should be, see also apply-multi-configs.sh 
#         it's possible that some script expect it somewhere and some others scripts somewhere else
evalSafe "paste \"$casesFile\" \"$destDir/test/predict.tsv\"  >\"$destDir/predicted.answers\"" "$progName,$LINENO: "

# perf, if required
if [ ! -z "$goldFile" ]; then
#    evalSafe "pan14_author_verification_eval.m -i \"$destDir/predicted.answers\" -t \"$goldFile\" -o \"$evalOutput\" >/dev/null 2>&1"  "$progName,$LINENO: "
#    scoreAUC=$(evalSafe "cat \"$evalOutput\" | grep AUC | cut -f 2 -d ':' | tr -d ' },'")
#    scoreC1=$(evalSafe "cat \"$evalOutput\" | grep C1 | cut -f 2 -d ':' | tr -d ' },'")
    #    scoreFinal=$(evalSafe "cat \"$evalOutput\" | grep finalScore | cut -f 2 -d ':' | tr -d ' },'")
    values=$(cat "$goldFile" | while read l; do echo "${l: -1}"; done | sort -u | tr '\n' ':')
    scoreAUC=$(evalSafe "auc.pl -p 6 -l $values \"$goldFile\" \"$destDir/predicted.answers\"")
    scoreC1=$(evalSafe "accuracy.pl -c -p 6 -l $values \"$goldFile\" \"$destDir/predicted.answers\" | cut -f 1")
    scoreFinal=$(perl -e "printf(\"%.6f\n\", $scoreAUC * $scoreC1);")
    if [ -z "$scoreAUC" ] || [ -z "$scoreC1" ] || [ -z "$scoreFinal" ] ; then
        echo "$progName error: was not able to extract one of the evaluation scores from '$destDir/predicted.answers' (predicted) and '$goldFile' (gold)" 1>&2
        exit 1
    fi
    echo -e "$scoreFinal\t$scoreAUC\t$scoreC1" >"$destDir.perf"
fi

echo "$progName: done."


