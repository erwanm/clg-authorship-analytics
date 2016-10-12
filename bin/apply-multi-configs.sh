#!/bin/bash

# EM  May 15

source common-lib.sh
source file-lib.sh
source pan-utils.sh

progName=$(basename "$BASH_SOURCE")

resume=0
parallelPrefix=""
sleepTime=20s
preprocessStrategyConfigs=""
mainDir=""
outputIdPrefix=""
computePerf=0

function usage {
  echo
  echo "Usage: $progName [options] <config prefixes list> <cases file> <dest dir>"
  echo
  echo "  applies a set of configs/models to a set of cases. the configs can be"
  echo "  meta-configs or strategy configs or both:"
  echo "  - if there are meta-configs, <dest dir> must contain a subdir"
  echo "    'apply-strategy-configs' containing the answers provided by the"
  echo "    individual strategy configs (see also -i, -m)"
  echo "  - if there are individual configs, <dest dir> must contain a subdir"
  echo "    'prepared-data' containing the (properly initialized) data (see also"
  echo "    -m)"
  echo
  echo "  Options:"
  echo "    -h this help"
  echo "    -r resume previous process (i.e. don't overwrite if existing)"
  echo "    -P <parallel prefix> TODO"
  echo "    -s <sleep time> (no effect if no -P)"
  echo "    -m <main dir> direcotry containong 'prepared-data' and/or"
  echo "        'apply-strategy-configs', if not present in <dest dir>."
  echo "    -i <strategy configs prefixes list> applies this set of "
  echo "       strategy configs first, store them in "
  echo "       <dest dir>/apply-strategy-configs and then process the main"
  echo "       (meta-)configs list. (avoid calling this script twice)"
  echo "    -o <output id prefix> by default the results for one config"
  echo "       are written under its id, which is the basename of its "
  echo "       prefix. This option adds a prefix to each such id."
  echo "       (remark: not applied to subprocess if -i is supplied)."
  echo "    -p also compute the perf on all cases; in this case <cases file>"
  echo "       msut contain a 2nd column with Y/N gold answers (space sep)."
  echo
}


OPTIND=1
while getopts 'hP:rs:m:i:o:p' option ; do 
    case $option in
	"h" ) usage
 	      exit 0;;
	"P" ) parallelPrefix="$OPTARG";;
	"r" ) resume=1;;
        "s" ) sleepTime="$OPTARG";;
	"m" ) mainDir="$OPTARG";;
	"i" ) preprocessStrategyConfigs="$OPTARG";;
	"o" ) outputIdPrefix="$OPTARG";;
	"p" ) computePerf=1;;
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
configsListFile="$1"
casesFile="$2"
destDir="$3"

mkdirSafe "$destDir" "$progName,$LINENO: "
if [ -z "$mainDir" ]; then
    mainDir="$destDir"
fi

if [ ! -z "$preprocessStrategyConfigs" ]; then # calling self to compute strategy configs
    params=" -m \"$mainDir\" -s $sleepTime"
    if [ $resume -ne 0 ]; then
	params="$params -r"
    fi
    if [ ! -z "$parallelPrefix" ]; then
	params="$params -P \"$parallelPrefix\""
    fi
    if [ $computePerf -eq 1 ]; then
	params="$params -p "
    fi
    mkdirSafe 
    echo "$progName: calling self to apply strategy configs/models '$preprocessStrategyConfigs' first."
    # self call (not really recursive, possible only once)
    evalSafe "$progName $params \"$preprocessStrategyConfigs\" \"$casesFile\" \"$destDir/apply-strategy-configs\"" "$progName,$LINENO: "
fi

# computePerf=0 or 1, always cut the 2 column to be safe
onlyCasesFile=$(mktemp "$destDir/only-cases.tmp.XXXXXXXX")
evalSafe "cut -d \" \" -f 1 \"$casesFile\" > \"$onlyCasesFile\"" "$progName,$LINENO: " # written to the target dir because /tmp might be different!! (if running on cluster)

params=""
if [ $computePerf -ne 0 ]; then
    params="-g \"$casesFile\"" # original cases file, supposed to contain Y/N 2nd col
fi


# main part
waitFile=$(mktemp --tmpdir "$progName.main.wait.XXXXXXXXX")
#echo "DEBUG: $waitFile; computePerf=$computePerf" 1>&2
echo "$progName: applying configs/models '$configsListFile' to '$casesFile'; writing results to '$destDir'."
cat "$configsListFile" | while read prefix; do
    confId=$(basename "$prefix")
    id="${outputIdPrefix}${confId}"
    confDir="$destDir/$id"
    if [ $computePerf -eq 0 ]; then
	fileToCheck="$confDir.answers"
    else
	fileToCheck="$confDir.perf"
    fi
    if [ $resume -eq 0 ] || [ ! -s "$fileToCheck" ]; then
	command="apply-config.sh $params \"$prefix\" \"$onlyCasesFile\" \"$mainDir\" \"$confDir\""
	if [ -z "$parallelPrefix" ]; then
            evalSafe "$command"  "$progName,$LINENO: "
	else
            taskFile=$(evalSafe "mktemp $parallelPrefix.$id.XXXXXXXXX" "$progName,$LINENO: ")
            echo "$command >\"$confDir.log.out\" 2>\"$confDir.log.err\"" >"$taskFile"
	fi
    fi
    evalSafe "echo \"$fileToCheck\" >>\"$waitFile\"" "$progName,$LINENO: "

done
if [ $? -ne 0 ]; then
    echo "$progName error: something went wrong in the main loop." 1>&2
    exit 4
fi

waitFilesList "$progName: applying configs/models '$configsListFile' to '$casesFile'; writing results to '$destDir'." "$waitFile" $sleepTime
rm -f  "$waitFile" "$onlyCasesFile"

# copy the answers where they are expected by meta-training-extract-scores.pl (not too sure, see also apply-config.sh)
cat "$configsListFile" | while read prefix; do
    confId=$(basename "$prefix")
    id="${outputIdPrefix}${confId}"
    cat "$destDir/$id/predicted.answers" >"$destDir/$id.answers"
    rm -rf "$destDir/$id" # update oct 16: remove dir to save space
done

echo "$progName: done."


