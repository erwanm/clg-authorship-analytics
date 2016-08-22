#!/bin/bash

source common-lib.sh
source file-lib.sh

progName="run-std-training-multiple-datasets.sh"


sleepTime=100s

runParams=""
preferedDataLocation=""
parallelPrefix=""
resuming=0
runMasterTasksInBackground=1
confDir="conf"

function usage {
  echo
  echo "Usage: $progName [options] <work dir>"
  echo
  echo "  Starts the whole training process in a 'standard' way for multiple"
  echo "  datasets. The datasets are read from STDIN with the following format:"
  echo
  echo "  <source dir>[:<id>] [impostors option]"
  echo
  echo "  where [impostors options] is transmitted via '-i' to run-std-training.sh."
  echo
  echo "  Caution: if using -M, all paths must be absolute, including in"
  echo "           [impostors options]."
  echo
  echo "  Assumes the following:"
  echo "  - the current dir contains a subdir 'conf' containing the multi-conf parts,"
  echo "    unless using option '-c' (see below)."
  echo
  echo
  echo "  Options:"
  echo "    -h this help"
  echo "    -c <conf directory> default: '$confDir'."
  echo "    -f force overwriting the destination directory if it is not empty;"
  echo "       default: error and exit (to avoid deleting stuff accidentally)."
  echo "       (option for run-std-training.sh)."
  echo "    -a add to existing data in destination directory if it is not empty;"
  echo "       default: error and exit (to avoid deleting stuff accidentally)."
  echo "       (option for run-std-training.sh)."
  echo "    -o <train-cv options> options to transmit to train-cv.sh, e.g. '-c -s'."
  echo "       (option for run-std-training.sh)."
  echo "    -L <prefered input/resources location>"
  echo "       If the genetic process is going to run on a cluster and the regular"
  echo "       <work dir> is mounted from the nodes, making access to input/resources"
  echo "       too slow, this option allows to specify a 'prefered location'"
  echo "       where directories 'input' and 'resources' can be found (typically"
  echo "       on the local filesystem for every node). This script will:"
  echo "         (1) generate archives of 'input' and 'resources';"
  echo "         (2) transmit the option appropriately to the other scripts;"
  echo "       BUT the step of copying/extracting the archives and mounting them"
  echo "       is left to be performed independently."
  echo "    -P <parallel prefix> TODO"
  echo "    -r resume previously started process if existing: for every dataset,"
  echo "       if the script restart-top-level.sh exists then it is called. In"
  echo "       other words, skip all the preparation of the dataset if it has been"  
  echo "       done previously."
  echo "    -M run master tasks as regular tasks instead of as background daemons."
  echo "       ignored if -P is not enabled."
  echo
}



OPTIND=1
while getopts 'hc:fao:P:L:rM' option ; do
    case $option in
	"c" ) confDir="$OPTARG";;
        "f" ) runParams="$runParams -f";;
        "a" ) runParams="$runParams -a";;
        "P" ) parallelPrefix="$OPTARG";;
        "o" ) runParams="$runParams -o \"$OPTARG\"";; 
	"L" ) preferedDataLocation="$OPTARG";;
	"r" ) resuming=1;;
	"M" ) runMasterTasksInBackground=0
	    runParams="$runParams -M";;
        "h" ) usage
              exit 0;;
        "?" )
            echo "Error, unknow option." 1>&2
            printHelp=1;;
    esac
done
shift $(($OPTIND - 1))
if [ $# -ne 1 ]; then
    echo "Error: expecting 1 arg." 1>&2
    printHelp=1
fi
if [ ! -z "$printHelp" ]; then
    usage 1>&2
    exit 1
fi

workDir=$(absolutePath "$1")
confDir=$(absolutePath "$confDir")

runParams="$runParams -c \"$confDir\""

mkdirSafe "$workDir"  "$progName:$LINENO: "
rm -f "$workDir/datasets.list"
while read inputLine; do 
    set -- $inputLine
    dirId="$1"
    impOpt="$2"
#    echo "DEBUG: inputLine='$inputLine', dirId='$dirId', impOpt='$impOpt'" 1>&2
    dir=${dirId%:*}
    if [ "$dir" != "$dirId" ]; then # two parts
	id=${dirId#*:}
    else
	id=$(basename "$dir")
    fi
    if [ -d "$dir" ]; then
	dir=$(absolutePath "$dir")
	if [ $resuming -ne 0 ] && [ -f "$workDir/$id/restart-top-level.sh" ]; then
	    echo "$progName: restarting process for dataset '$id', dir = '$dir'"
	    eval "$workDir/$id/restart-top-level.sh >\"$workDir/$id.main-process.out\" 2>\"$workDir/$id.main-process.err\"" &
	else
	    echo "$progName: starting process for dataset '$id', dir = '$dir'"
	    mkdirSafe "$workDir/$id"   "$progName:$LINENO: "
	    thisParams="$runParams"
	    if [ ! -z "$preferedDataLocation" ]; then
		thisParams="$thisParams -L \"$preferedDataLocation/$id\""
	    fi
	    if [ ! -z "$parallelPrefix" ]; then
		thisParams="$thisParams -P \"$parallelPrefix.$id\""
	    fi
	    if [ ! -z "$impOpt" ]; then
		thisParams="$thisParams -i \"$impOpt\""
	    fi
	    command="run-std-training.sh $thisParams \"$dir\" \"$workDir/$id\" >\"$workDir/$id.main-process.out\" 2>\"$workDir/$id.main-process.err\""
	    if [ $runMasterTasksInBackground -eq 1 ] || [ -z "$parallelPrefix" ]; then
		eval  "$command" &
	    else # use the task distrib daemon
		taskFile=$(evalSafe "mktemp  $parallelPrefix.$id.run-std.XXXXXXXXX" "$progName,$LINENO: ")
		echo "$command" >"$taskFile"
	    fi
	fi
	echo "$id" >>"$workDir/datasets.list"
    else
	echo "$progName: source dir '$dir' for dataset '$id' doesn't exist, ignoring." 1>&2
    fi
done

echo "$progName: all processes started, waiting $sleepTime"
sleep $sleepTime

cat "$workDir/datasets.list" | while read dataset; do
    dir="$workDir/$dataset"
    if [ -d "$dir" ]; then
	id=$(basename "$dir")
	echo "$progName: showing first 10 lines of stderr for process '$id':"
	head "$workDir/$id.main-process.err"
    fi
done

echo "$progName: done"
