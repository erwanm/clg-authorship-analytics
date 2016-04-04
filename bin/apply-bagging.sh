#!/bin/bash

# EM  May 15

source common-lib.sh
source file-lib.sh
source pan-utils.sh

progName=$(basename "$BASH_SOURCE")

nbDigits=4

resume=0
applyMCParams=""
#nbBest=""

function usage {
  echo
  echo "Usage: $progName [options] <N> <config prefixes list> <cases file> <dest dir>"
  echo
  echo "  apply the set of configs N times to a (different) 50% random subset of cases" 
  echo "   and computes perf stats."
  echo "  <cases file > must contain a 2nd column with Y/N gold answers (space sep)."
  echo
  echo "  the configs can be meta-configs or strategy configs or both:"
  echo "  - if there are meta-configs, <dest dir> must contain a subdir"
  echo "    'apply-strategy-configs' containing the answers provided by the"
  echo "    individual strategy configs (see also -i, -m)"
  echo "  - if there are individual configs, <dest dir> must contain a subdir"
  echo "    'prepared-data' containing the (properly initialized) data (see also"
  echo "    -m)"
  echo
  echo "  Options:"
  echo "    -h this help"
  echo "    -o <options for apply-multi-configs> e.g. -P, -s, -m"
#  echo "    -n <nb best>: return only the <nb best> best configs in <dest dir>/runs.final-rank"
  echo "    -r resume "
  echo
}


OPTIND=1
while getopts 'ho:r' option ; do 
    case $option in
	"h" ) usage
 	      exit 0;;
	"o" ) applyMCParams="$OPTARG";;
	"r" ) resume=1;;
#	"n" ) nbBest="$OPTARG";;
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
nbRuns="$1"
configsListFile="$2"
goldFile="$3"
destDir="$4"

dieIfNoSuchFile "$configsListFile" "$progName,$LINENO: "
dieIfNoSuchFile "$goldFile" "$progName,$LINENO: "
mkdirSafe "$destDir" "$progName,$LINENO: "
echo "$progName: nbRuns=$nbRuns"

if [ $resume -ne 0 ]; then
    applyMCParams="$applyMCParams -r"
fi

#casesFile=$(mktemp --tmpdir "tmp.$progName.cases.XXXXXXXXX")
#evalSafe "cut -f 1 -d \" \" \"$goldFile\" >$casesFile"
nbCases=$(cat "$goldFile" | wc -l)

if [ $resume -ne 0 ]; then
    resumeParam="-r"
fi

tmp=$(mktemp --tmpdir "tmp.$progName.main.XXXXXXXXX")
evalSafe "cut -f 1 \"$configsListFile\" >\"$destDir/runs.perf\"" "$progName,$LINENO: "
for runNo in $(seq 1 $nbRuns); do
    runNoStr=$(printf "%0${nbDigits}d" $runNo)
    runDir="$destDir/$runNoStr"
    mkdirSafe "$runDir"
    thisRunPerf=$(mktemp --tmpdir "tmp.$progName.main.XXXXXXXXX")

    if [ $resume -eq 0 ] || [ ! -s "$runDir/random.cases" ]; then
	rm -rf "$runDir/folds" # remove previous folds (especially if previous nbFolds > current nbFolds!!)
	mkdirSafe "$runDir/folds"
	evalSafe "generate-random-cross-fold-ids.pl 2 \"$nbCases\" \"$runDir/folds/fold\"" "$progName: "
	evalSafe "cat \"$goldFile\" | select-lines-nos.pl \"$runDir/folds/fold.1.train.indexes\" 1 > \"$runDir/random.cases\"" "$progName,$LINENO: "
	rm -rf  "$runDir/folds"
    fi
    evalSafe "apply-multi-configs.sh $resumeParam -p $applyMCParams \"$configsListFile\" \"$runDir/random.cases\" \"$runDir\"" "$progName,$LINENO: "

    cat "$configsListFile" | while read prefix; do
	id=$(basename "$prefix")
#	dieIfNoSuchFile "$runDir/$id.perf" "$progName,$LINENO: "
	evalSafe "cut -f 1 \"$runDir/$id.perf\" >>\"$thisRunPerf\"" # column containg all perf scores (all configs)
    done
    if [ $? -ne 0 ]; then
	echo "$progName error $LINENO" 1>&2
	exit 5
    fi
    evalSafe "cat \"$destDir/runs.perf\" >\"$tmp\"" "$progName,$LINENO: "
    evalSafe "paste \"$tmp\" \"$thisRunPerf\" >\"$destDir/runs.perf\" " "$progName,$LINENO: "
    rm -f "$thisRunPerf"
done
rm -f "$tmp"

echo "$progName: main loop done, extracting stats"
# sort to make sure the values are sorted by config id before computing ranks
evalSafe "num-stats.pl -s \"mean median stdDev meanMinusStdDev\" -c 2 \"$destDir/runs.perf\" | sort +0 -1 > \"$destDir/runs.stats\"" "$progName,$LINENO: "
#evalSafe "cat \"$destDir/runs.stats\" | rank-with-ties.pl 2 rev | cut -f 1,5 | sort +0 -1 >\"$destDir/runs.mean.rank\"" "$progName,$LINENO: "
#evalSafe "cat \"$destDir/runs.stats\" | rank-with-ties.pl 3 rev | cut -f 1,5 | sort +0 -1 >\"$destDir/runs.median.rank\"" "$progName,$LINENO: "
#evalSafe "cat \"$destDir/runs.stats\" | rank-with-ties.pl 4 | cut -f 1,5 | sort +0 -1 >\"$destDir/runs.stdDev.rank\"" "$progName,$LINENO: "

#headPart=""
#if [ ! -z "$nbBest" ]; then
#    headPart=" | head -n $nbBest"
#fi
# remark: lowest rank = best config
#evalSafe "cat \"$destDir\"/runs.*.rank | avg-by-group.pl -g 0 -e 3 1 | sort -g +1 -2 $headPart >\"$destDir/runs.final-rank\"" "$progName,$LINENO: "
#echo "$progName: done."
