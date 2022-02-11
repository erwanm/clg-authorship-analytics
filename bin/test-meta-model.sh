#!/bin/bash


# EM  Feb 22

source common-lib.sh
source file-lib.sh
source pan-utils.sh

progName=$(basename "$BASH_SOURCE")

applyMCOptions=""

function usage {
  echo
  echo "Usage: $progName [options] <meta-model prefix> <test cases file> <input dir> <output dir>"
  echo
  echo "  Applies a meta-config model to some test cases:"
  echo "    - Meta-model read from file <meta-model prefix>.conf and  dir <meta-model prefix>.model."
  echo "    - <input dir> contains:"
  echo "        - the dir 'input' which contains the already prepared test data files."
  echo "        - file resources-options.conf (for impostors and stop words)"
  echo
  echo "  Options:"
  echo "    -h this help"
  echo "    -p compute performance (requires gold answer in the cases file)"
  echo
}




OPTIND=1
while getopts 'hp' option ; do 
    case $option in
	"h" ) usage
 	      exit 0;;
	"p" ) applyMCOptions="$applyMCOptions -p";;
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
metaConfPrefix="$1"
testCasesFile="$2"
inputDir="$3"
outputDir="$4"

dieIfNoSuchFile "$metaConfPrefix.conf" "$progName,$LINENO: "
dieIfNoSuchDir "$metaConfPrefix.model" "$progName,$LINENO: "
dieIfNoSuchFile "$testCasesFile" "$progName,$LINENO: "
dieIfNoSuchDir "$inputDir" "$progName,$LINENO: "
dieIfNoSuchDir "$inputDir/input" "$progName,$LINENO: "
dieIfNoSuchFile "$inputDir/resources-options.conf" "$progName,$LINENO: "
mkdirSafe "$outputDir"  "$progName,$LINENO: "


ls "$metaConfPrefix.model/strategy-configs"/*.conf | sed 's/.conf$//' > "$outputDir"/indiv-strategies.prefix-list
echo "$metaConfPrefix" > "$outputDir"/meta-config.prefix-list
linkAbsolutePath "$outputDir" "$inputDir/input" "$inputDir/resources-options.conf"
evalSafe "apply-multi-configs.sh $applyMCOptions -i \"$outputDir/indiv-strategies.prefix-list\" \"$outputDir/meta-config.prefix-list\" \"$testCasesFile\" \"$outputDir\""

echo "$progName: done."


