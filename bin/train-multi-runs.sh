#!/bin/bash

# EM May 15

source common-lib.sh
source file-lib.sh
source pan-utils.sh

progName=$(basename "$BASH_SOURCE")

parallelPrefix=""
nbDigits=4
trainCVParams=""
nbFolds=2
nbRuns=5
#nbRuns=10
resume=0
nbBest=""

function usage {
  echo
  echo "Usage: $progName [options] <input/output dir> <cases file> <configs file>"
  echo
  echo "  Does a 5x2 train/test validation, i.e. does 10 runs of a 2 folds CV of"
  echo "  all the configs as input. Returns stats for each individual config."
  echo "  Results are written in <dir>/runs.stats, with the following format:"
  echo "  <config file> <mean> <median> <std dev> <mean - std dev>"
  echo
  echo "  IN THEORY, the configs can be meta-configs or strategy configs or both:"
  echo "  - if there are meta-configs, <dest dir> must contain a subdir"
  echo "    'apply-strategy-configs' containing the answers provided by the"
  echo "    individual strategy configs (see also -i, -m)"
  echo "  - if there are individual configs, <dest dir> must contain a subdir"
  echo "    'prepared-data' containing the (properly initialized) data (see also"
  echo "    -m)"
  echo "  (... but I don't think the case of meta-configs has been tested!)"
  echo
  echo "  Options:"
  echo "    -h this help"
  echo "    -o <train-cv options> options to transmit to train-cv.sh, e.g. '-c -s'."
  echo "    -f <nb folds>, default = $nbFolds"
  echo "    -x <nb runs>, default = $nbRuns"
  echo "    -b <nb best to return> default=all"
  echo "    -r resume process (don't overwrite previous results)"
  echo "    -P <parallel prefix> TODO"
  echo
}








OPTIND=1
while getopts 'hP:ro:f:x:b:' option ; do 
    case $option in
	"h" ) usage
 	      exit 0;;
	"P" ) parallelPrefix="$OPTARG";;
        "o" ) trainCVParams="$OPTARG";;
	"r" ) resume=1;;
	"x" ) nbRuns="$OPTARG";;
	"f" ) nbFolds="$OPTARG";;
	"b" ) nbBest="$OPTARG";;
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
outputDir="$1"
casesFile="$2"
configsFile="$3"

mkdirSafe "$outputDir"

echo "$progName: nbFolds=$nbFolds; nbRuns=$nbRuns; resume mode=$resume"
mkdirSafe "$outputDir/runs" "$progName,$LINENO: "
evalSafe "cut -f 1 \"$configsFile\" > \"$outputDir/runs/configs.list\"" "$progName,$LINENO: "

tmp=$(mktemp --tmpdir "tmp.$progName.main.XXXXXXXXX")
evalSafe "cut -f 1 \"$outputDir/runs/configs.list\" >\"$outputDir/runs/runs.perf\"" "$progName,$LINENO: "
for runNo in $(seq 1 $nbRuns); do
    runNoStr=$(printf "%0${nbDigits}d" $runNo)
    runDir="$outputDir/runs/$runNoStr"
    if [ $resume -eq 0 ]; then 
	rm -rf "$runDir"
    fi
    mkdirSafe "$runDir"
    if [ $resume -eq 0 ] || [ ! -s "$runDir/configs.results" ]; then
	evalSafe "cat \"$casesFile\" > \"$runDir/cases.list\"" "$progName,$LINENO: "
	echo "$progName, run $runNoStr: evaluating configs; nbFolds=$nbFolds; "
	params=""
	if [ ! -z "$parallelPrefix" ]; then
	    params="-P \"$parallelPrefix.$runNoStr\""
	fi
 	# remark: -r (resume) ok even if resume=0, since without resume the dir has been removed
	evalSafe "train-generation.sh -s 10s -r $params -o \"$trainCVParams\" -f $nbFolds \"$outputDir/runs/configs.list\" \"$outputDir\" \"$runDir\"" "$progName,$LINENO: "
	dieIfNoSuchFile "$runDir/configs.results" "$progName,$LINENO: "
    else
	echo "$progName, run $runNoStr: using existing results"
    fi
    evalSafe "cat \"$outputDir/runs/runs.perf\" >\"$tmp\"" "$progName,$LINENO: "
    evalSafe "cut -f 2 \"$runDir/configs.results\" | paste \"$tmp\" - >\"$outputDir/runs/runs.perf\" " "$progName,$LINENO: "
done
rm -f "$tmp"

echo "$progName: main loop done, extracting stats"
# sort to make sure the values are sorted by config id before computing ranks
evalSafe "num-stats.pl -s \"mean median stdDev meanMinusStdDev\" -c 2 \"$outputDir/runs/runs.perf\" | sort +0 -1 > \"$outputDir/runs/runs.stats\"" "$progName,$LINENO: "

