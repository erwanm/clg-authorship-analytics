#!/bin/bash

# EM March 16

source common-lib.sh
source file-lib.sh
source pan-utils.sh



progName=$(basename "$BASH_SOURCE")

function usage {
  echo
  echo "Usage: $progName [options] <cases file> <input data dir> <config file> <resourcesOptionsFile>"
  echo
  echo "  Computes the verif strategy features, as specified in the config file,"
  echo "  for every case indicated in <cases file>. The actual cases are"
  echo "  read in <input dir>/<case>, and other resources options are"
  echo "  specified in <resourcesOptionsFile>. Resulting features are"
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
resourcesOptionsFile="$4"

dieIfNoSuchFile "$casesFile" "$progName,$LINENO: "
dieIfNoSuchDir "$inputDataDir"  "$progName,$LINENO: "
dieIfNoSuchFile "$configFile" "$progName,$LINENO: "
dieIfNoSuchFile "$resourcesOptionsFile" "$progName,$LINENO: "

readFromParamFile "$resourcesOptionsFile" "vocabResources"  "$progName,$LINENO: "
readFromParamFile "$resourcesOptionsFile" "useCountFiles"  "$progName,$LINENO: "
readFromParamFile "$resourcesOptionsFile" "datasetResourcesPath"  "$progName,$LINENO: "
readFromParamFile "$resourcesOptionsFile" "resourcesAccess"  "$progName,$LINENO: "

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
    verifParams="-i $resourcesAccess -v '$vocabResources' -d '$resourcesDir/impostors-data' "
    if [ "$useCountFiles" == "1" ]; then
	verifParams="-c $verifParams"
    fi
    tmpCasesFile=$(mktemp  --tmpdir  "$progName.main.XXXXXXXXX")
    cut -f 1 "$casesFile" | while read caseId; do
	knownDocsList=$(ls "$inputDataDir/$caseId"/known*.txt)
	knownDocsList=$(echo "$knownDocsList" | tr ' ' ':')
	echo "$knownDocsList $inputDataDir/$caseId/unknown.txt"
    done >"$tmpCasesFile"
#    echo "DEBUG cases for verif-author = $tmpCasesFile" 1>&2
    evalSafe "cat '$tmpCasesFile' | verif-author.pl  $verifParams '$configFile' " "$progName,$LINENO: "
    rm -f $tmpCasesFile
fi



