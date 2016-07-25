#!/bin/bash

source common-lib.sh
source file-lib.sh

progName="copy-prepared-to-tmp-if-needed.sh"
sleepTime=10m


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
    cp "$sourceDir/input.tar.bz2" "$sourceDir/resources.tar.bz2" "$targetDir"
    pushd "$targetDir" >/dev/null
    tar xfj "input.tar.bz2"
    tar xfj "resources.tar.bz2"
    popd >/dev/null
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

if [ ! -d "$targetDir/input" ] || [ ! -d "$targetDir/resources" ]; then
    mytemp=$(mktemp --tmpdir)
    if [ ! -f "$targetDir/lock" ]; then
	echo $mytemp > "$targetDir/lock"
	sleep 5s
	x=$(cat "$targetDir/lock")
	if [ "$x" ==  "$mytemp" ]; then # ok, job for current process
	    doTheJob "$sourceDir" "$targetDir"
	    rm -f "$targetDir/lock"
	fi
    fi
    # either the current job did the current process and removed the lock; or the lock was there; or there was no lock but the current process did not not get the job
    while [ -f "$targetDir/lock" ]; do # wait for preparation job to finish
	sleep $sleepTime
    done
    rm -f $mytemp 
else
    echo "$progName: archives already there, nothing to do"
fi




