#!/bin/bash

source common-lib.sh
source file-lib.sh

progName="copy-prepared-to-tmp-if-needed.sh"

sleepTime=2m
maxTimeLock=10000 # if the lock timestamp is older than this duration in secs, remove it (probably interrupted process)
inputFile=""

function usage {
  echo
  echo "Usage: $progName [options] <source prepared dir> <target dir>"
  echo
  echo "  If directories <target dir>/input and <target dir>/resources don't exist,"
  echo "  copy archives input.tar.bz2 and resources.tar.bz2 from <source prepared dir> to"
  echo "  <target dir>, then uncompress them."
  echo "  If -i option is used, no arguments are needed."
  echo
  echo "  Options:"
  echo "    -h this help"
  echo "    -i <input file> input file containing on each line one the source and target"
  echo "       dir for one dataset. in this case there should be no argument at all on the"
  echo "       command line."
  echo
}



function doTheJob {
    local sourceDir="$1"
    local targetDir="$2"

    echo "$progName: copy archives"
    dieIfNoSuchFile "$sourceDir/input.tar.bz2" "$progName,$LINENO: "
    dieIfNoSuchFile "$sourceDir/resources.tar.bz2" "$progName,$LINENO: "
    rm -rf "$targetDir/input.tar.bz2" "$targetDir/resources.tar.bz2"  "$targetDir/input" "$targetDir/resources"
    cp "$sourceDir/input.tar.bz2" "$sourceDir/resources.tar.bz2" "$targetDir"
    cat "$sourceDir/resources-options.conf" | sed "s:$sourceDir:$targetDir:g" >"$targetDir/resources-options.conf"
    pushd "$targetDir" >/dev/null
    tar xfj "input.tar.bz2"
    tar xfj "resources.tar.bz2"
    popd >/dev/null
}


function tryLocking {
    local sourceDir="$1"
    local targetDir="$2"

    echo "DEBUG $$: creating lock with my PID" 1>&2
    echo "$$" > "$targetDir/lock"
    sleep 10s
    x=$(cat "$targetDir/lock")
    if [ "$x" ==  "$$" ]; then # ok, job for current process
	echo "DEBUG $$: I got the job, doing it" 1>&2
	doTheJob "$sourceDir" "$targetDir"
	echo "DEBUG $$: job done, removing lock" 1>&2
	rm -f "$targetDir/lock"
	return 0 # job done
    else
	echo "DEBUG $$: didn't get the job" 1>&2
	return 1 # job in progress
    fi
}


function oneDataset {
    sourceDir="$1" 
    targetDir="$2"

    mkdirSafe "$targetDir" "$progName,$LINENO: "
    if [ ! -d "$sourceDir" ]; then # if source dir doesn't exist, echo warning and consider done (pointless to wait)
	echo "$progName $$: warning, no source directory '$sourceDir', ignoring" 1>&2
	return 0
    fi
    if [ ! -d "$targetDir/input" ] || [ ! -d "$targetDir/resources" ] || [ ! -s "$targetDir/resources-options.conf" ] || [ -f "$targetDir/lock" ]; then
	echo "DEBUG $$: target data not found" 1>&2
        # if the lock is too old then there was a problem (probably interrupted process), remove it and redo the process
	if [ -f "$targetDir/lock" ]; then
	    lockTime=$(stat -c %Y "$targetDir/lock")
	    currentTime=$(date +%s)
	    lockAge=$(( $currentTime - $lockTime ))
	    echo "DEBUG $$: lock exists, checking timestamp = $lockAge" 1>&2
	    if [ $lockAge -ge $maxTimeLock ]; then
		echo "DEBUG $$: replacing lock" 1>&2
		tryLocking "$sourceDir" "$targetDir"
		return $? # don't think it's needed
	    else
		echo "DEBUG $$: recent lock, assuming work in progress" 1>&2
		return 1
	    fi
	else
	    echo "DEBUG $$: no lock found, trying to lock" 1>&2
	    tryLocking "$sourceDir" "$targetDir"
	    return $? # don't think it's needed
	fi
    else
	echo "DEBUG $$: target data already there, nothing to do" 1>&2
	return 0
    fi
}




OPTIND=1
while getopts 'hi:' option ; do
    case $option in
	"i" ) inputFile="$OPTARG";;
        "h" ) usage
              exit 0;;
        "?" )
            echo "Error, unknow option." 1>&2
            printHelp=1;;
    esac
done
shift $(($OPTIND - 1))
if [ $# -ne 2 ] && [ -z "$inputFile" ] ; then
    echo "Error: expecting 2 args or option '-i'." 1>&2
    printHelp=1
elif [ ! -z "$inputFile" ] && [ $# -ne 0 ] ; then
    echo "Error: expecting 0 args when using option '-i'." 1>&2
    printHelp=1
fi
if [ ! -z "$printHelp" ]; then
    usage 1>&2
    exit 1
fi

notDoneFile=$(mktemp --tmpdir "$progName.not-done.XXXXXXXX")
echo "let's do this" > "$notDoneFile"
echo "DEBUG $$: before loop, notDoneFile=$notDoneFile, inputFile='$inputFile'" 1>&2
while [ -s "$notDoneFile" ]; do
    echo "DEBUG $$: inside loop" 1>&2
    rm -f "$notDoneFile"
    if [ -z "$inputFile" ]; then
#    sourceDir="$1" 
#    targetDir="$2"
	echo "DEBUG $$: oneDataset \"$1\" \"$2\"" 1>&2
	oneDataset "$1" "$2"
	if [ $? -ne 0 ]; then
	    echo "DEBUG $$: sourceDir=$1, not done" 1>&2
	    echo "$sourceDir" >> "$notDoneFile"
	fi
    else
	if [ ! -s "$inputFile" ]; then
	    echo "$progName $$: error, no input file '$inputFile'" 1>&2
	    exit 2
	fi
	cat "$inputFile" | while read line; do
	    set -- $line
	    echo "DEBUG $$: oneDataset \"$1\" \"$2\"" 1>&2
	    oneDataset "$1" "$2"
	    if [ $? -ne 0 ]; then
		echo "DEBUG $$: sourceDir=$1, not done" 1>&2
		echo "$sourceDir" >> "$notDoneFile"
	    fi
	done
    fi
    if [ -s  "$notDoneFile" ]; then
	echo "DEBUG $$: sleeping" 1>&2
	sleep $sleepTime
    fi
done
rm -f "$notDoneFile"





