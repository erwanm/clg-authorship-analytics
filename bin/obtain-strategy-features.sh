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
#readFromParamFile "$resourcesOptionsFile" "resourcesAccess"  "$progName,$LINENO: "

dieIfNoSuchDir "$datasetResourcesPath"  "$progName,$LINENO: "

readFromParamFile "$configFile" "strategy" "$progName,$LINENO: "
if [ "$strategy" == "meta" ]; then
	# TODO VERY DIRTY
	# remark: $inputDir = dir/prepared-data, plus it's a link so ../ doesn't work
    myInputDir=$(dirname "$inputDataDir")
    evalSafe "meta-training-extract-scores.pl \"$casesFile\" \"$myInputDir\" \"$configFile\"" "$progName,$LINENO: "
else
    if [ "$strategy" == "DUMMYSTRATEGY" ]; then  # any other strategy goes here
	echo "$progName error: invalid value for parameter 'strategy': '$strategy'" 1>&2
	exit 1
    fi
#    verifParams="-i $resourcesAccess -v '$vocabResources' -d '$datasetResourcesPath/' "
    verifParams=" -v '$vocabResources' -d '$datasetResourcesPath/' "
    if [ "$useCountFiles" == "1" ]; then
	verifParams="-c $verifParams"
    fi
    tmpCasesFile=$(mktemp  --tmpdir  "$progName.main.XXXXXXXXX")
    cut -f 1 "$casesFile" | while read caseId; do
	if [ -d "$inputDataDir/$caseId" ]; then # PAN dir structure format
	    knownDocsList=$(find "$inputDataDir/$caseId" -name "known*.txt" | tr '\n' ':')
	    knownDocsList=${knownDocsList%:}
	    #	echo "DEBUG caseId='$caseId'; knownDocsList='$knownDocsList'" 1>&2
	    echo "$knownDocsList $inputDataDir/$caseId/unknown.txt"
	else
	    set -- $caseId
	    if [ $# -eq 2 ]; then # plain filenames: the two groups are separated by a space and the filenames in a group are separated by colons ':'
		# transforms a string of filenames separated by colons: file1:file2:file3 into prefix/file1:prefix/file2:prefix/file3:
		files1withColon=$(echo ":$1" | sed "s|:|:$inputDataDir/|g")
		files2withColon=$(echo ":$2" | sed "s|:|:$inputDataDir/|g")
		echo "${files1withColon:1} ${files2withColon:1}"
	    else
		echo "$progName: error, the format of the input cases file '$casesFile' seems to be neither PAN directory structure not plain filenames." 1>&2
		exit 1
	    fi
	fi
    done >"$tmpCasesFile"
#    echo "DEBUG cases for verif-author = $tmpCasesFile" 1>&2
    command="cat '$tmpCasesFile' | verif-author.pl  $verifParams '$configFile' "
#   echo "DEBUG: command='$command'" 1>&2
    evalSafe "$command" "$progName,$LINENO: "
    rm -f $tmpCasesFile
fi



