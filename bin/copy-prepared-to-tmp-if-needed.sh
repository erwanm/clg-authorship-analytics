#!/bin/bash

source common-lib.sh
source file-lib.sh

progName="copy-prepared-to-tmp-if-needed.sh"
sleepTime=2m
maxTimeLock=10000 # if the lock timestamp is older than this duration in secs, remove it (probably interrupted process)

function usage {
  echo
  echo "Usage: $progName [options] <source prepared dir> <target dir>"
  echo
  echo "  If directories <target dir>/input and <target dir>/resources don't exist,"
  echo "  copy archives input.tar.bz2 and resources.tar.bz2 from <source prepared dir> to"
  echo "  <target dir>, then uncompress them."
  echo
  echo "  Options:"
  echo "    -h this help"
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

    echo "DEBUG $$: creating lock with my PID"
    echo "$$" > "$targetDir/lock"
    sleep 10s
    x=$(cat "$targetDir/lock")
    if [ "$x" ==  "$$" ]; then # ok, job for current process
	echo "DEBUG $$: I got the job, doing it"
	doTheJob "$sourceDir" "$targetDir"
	echo "DEBUG $$: job done, removing lock"
	rm -f "$targetDir/lock"
    else
	echo "DEBUG $$: didn't get the job"
    fi
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
if [ $# -ne 2 ]; then
    echo "Error: expecting 2 args." 1>&2
    printHelp=1
fi
if [ ! -z "$printHelp" ]; then
    usage 1>&2
    exit 1
fi

sourceDir="$1"
targetDir="$2"

[ -d "$targetDir" ] || mkdir "$targetDir"
dieIfNoSuchDir "$sourceDir" "$progName,$LINENO: "
dieIfNoSuchDir "$targetDir" "$progName,$LINENO: "

echo "DEBUG $$: before loop"
while [ ! -d "$targetDir/input" ] || [ ! -d "$targetDir/resources" ] || [ ! -s "$targetDir/resources-options.conf" ] || [ -f "$targetDir/lock" ]; do
    echo "DEBUG $$: start loop"

    # if the lock is too old then there was a problem (probably interrupted process), remove it and redo the process
    if [ -f "$targetDir/lock" ]; then
	lockTime=$(stat -c %Y "$targetDir/lock")
	currentTime=$(date +%s)
	lockAge=$(( $currentTime - $lockTime ))
	echo "DEBUG $$: lock exists, checking timestamp = $lockAge"
	if [ $lockAge -ge $maxTimeLock ]; then
	    echo "DEBUG $$: replacing lock"
	    tryLocking "$sourceDir" "$targetDir"
	fi
    else
	tryLocking "$sourceDir" "$targetDir"
    fi
    echo "DEBUG $$: sleeping"
    sleep $sleepTime
done
echo "DEBUG $$: loop finished, bye"




