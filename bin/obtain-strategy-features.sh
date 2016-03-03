#!/bin/bash

# EM March 16

source common-lib.sh
source file-lib.sh
source pan-utils.sh



progName=$(basename "$BASH_SOURCE")

learnMode=
trainFile=
testFile=
maxAttemptsRandomSubset=5


function usage {
  echo
  echo "Usage: $progName [options] <cases file> <input data dir> <config file> <resourcesDir>"
  echo
  echo "  Computes the verif strategy features, as specified in the config file,"
  echo "  for every case indicated in <cases file>. The actual cases are"
  echo "  read in <input dir>/<case>, and specific resources (depending on the"
  echo "  strategy) are located under <resourcesDir>. Resulting features are"
  echo "  printed to STDOUT."
  echo
  echo "  Options:"
  echo "    -h this help"
  echo
}



OPTIND=1
while getopts 'h' option ; do 
    case $option in
	"h" ) usage
 	      exit 0;;
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

casesFile="$1"
inputDataDir="$2"
configFile="$3"
resourcesDir="$4"

dieIfNoSuchFile "$casesFile" "$progName,$LINENO: "
dieIfNoSuchDir "$inputDataDir"  "$progName,$LINENO: "
dieIfNoSuchFile "$configFile" "$progName,$LINENO: "

vocabResources=""
for f in "$resourcesDir"/stop-words/*.list; do
    id=$(filename "${f%.list}")
    vocabResources="$vocabResources;$id=$f"
done
vocabResources="${vocabResources:1}"


readFromParamFile "$configFile" "strategy" "$progName,$LINENO: "
if [ "$strategy" == "meta" ]; then
	# TODO VERY DIRTY
	# remark: $inputDir = dir/prepared-data, plus it's a link so ../ doesn't work
    myInputDir=$(dirname "$inputDir")
    evalSafe "meta-training-extract-scores.pl \"$casesFile\" \"$myInputDir\" \"$configFile\"" "$progName,$LINENO: "
else
    if [ "$strategy" == "DUMMYSTRATEGY" ]; then  # any other strategy goes here
	echo "$progName error: invalid value for parameter 'strategy': '$strategy'" 1>&2
	exit 1
    fi
    cut -f 1 "$casesFile" | while read line; do
	knownDocsList=$(ls "$inputDir/$caseId"/known*.txt)
	knownDocsList=$(echo "$knownDocsList" | tr ' ' ':')
	echo "$knownDocsList $inputDir/$caseId/unknown.txt"
    done | "evalSafe verif-strategy.pl -w rw -c -v '$vocabResources' -d '$resourcesDir/impostors-data' '$configFile' " "$progName,$LINENO: "
fi



