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
#  echo " <input/output dir> must contain prepared-data."
  echo
  echo "  By default, does a 10x2 train/test validation, i.e. does 10 runs of"
  echo "  a 2 folds CV of all the configs as input. Returns stats for each individual config."
  echo
  echo
  echo "TODO, DEPRECATED!"
  echo "  Reads multi-conf files in <output dir>/multi-conf-files, or from STDIN "
  echo "  the directory does not exist"
  echo "  High level training script which runs the training process with multiple"
  echo "  configurations of parameters. <input dir> is the input (raw) data;"
  echo "  a list of multi-config files is read from STDIN; in these files "
  echo "  each parameter can have several values separated by spaces, e.g.:"
  echo "    key=val1 val2 \"val 3\" ..."
  echo
  echo "  Remark: observation types is a special case; each such type must be"
  echo "  specified as:"
  echo "    obsTypeActive.<obs type>=<values>"
  echo "  where <values>='0', '1', or '0 1'." 
  echo
  echo "  Returns the optimal config+model (including ref data), which is"
  echo "  written to <output dir>."
  echo
  echo "  Options:"
  echo "    -h this help"
  echo "    -o <train-cv options> options to transmit to train-cv.sh, e.g. '-c -s'."
  echo "    -f <nb folds>, default = $nbFolds"
  echo "    -x <nb runs>, default = $nbRuns"
  echo "    -b <nb best to return> default=all"
  echo "    -r resume process (don't overwrite preveious results)"
##  echo "    -s fail safe model for train-cv.sh  (do not abort on error)."
#  echo "    -r resume previous process at first incomplete generation found"
##  echo "    -r <num> resume previous process at generation <num>"
#  echo "       remark: recomputes generation <num> and following if existing"
  echo "    -P <parallel prefix> TODO"
#  echo "    -f <first gen configs list file> use a list of individual configs"
#  echo "       to initiate the genetic process (reads only the first column"
#  echo "       of the file)"
#  echo "    -e exhaustive generation of configurations for the first generation;"
#  echo "       Can be used with trainingNbGenerations=1 in order to only"
#  echo "       compute the result of a given set of regular configs provided"
#  echo "       instead of the multi-configs (don't forget to set the parameter"
#  echo "       at least in the first config file)."
#  echo "       Warning: do not use if the multi-conf files contain billions"
#  echo "                of possibilities!"
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
evalSafe "num-stats.pl -s \"mean median stdDev\" -c 2 \"$outputDir/runs/runs.perf\" | sort +0 -1 > \"$outputDir/runs/runs.stats\"" "$progName,$LINENO: "
evalSafe "cat \"$outputDir/runs/runs.stats\" | rank-with-ties.pl 2 rev | cut -f 1,5 | sort +0 -1 >\"$outputDir/runs/runs.mean.rank\"" "$progName,$LINENO: "
evalSafe "cat \"$outputDir/runs/runs.stats\" | rank-with-ties.pl 3 rev | cut -f 1,5 | sort +0 -1 >\"$outputDir/runs/runs.median.rank\"" "$progName,$LINENO: "
evalSafe "cat \"$outputDir/runs/runs.stats\" | rank-with-ties.pl 4 | cut -f 1,5 | sort +0 -1 >\"$outputDir/runs/runs.stdDev.rank\"" "$progName,$LINENO: "

headPart=""
if [ ! -z "$nbBest" ]; then
    headPart=" | head -n $nbBest"
fi
# remark: lowest rank = best config
evalSafe "cat \"$outputDir\"/runs/runs.*.rank | avg-by-group.pl -g 0 -e 3 1 | sort -g +1 -2 $headPart >\"$outputDir/runs/runs.final-rank\"" "$progName,$LINENO: "
echo "$progName: done."
