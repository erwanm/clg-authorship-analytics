#!/bin/bash

source common-lib.sh
source file-lib.sh

progName="copy-prepared-to-tmp-if-needed.sh"



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

dieIfNoSuchDir "$sourceDir" "$progName,$LINENO: "
dieIfNoSuchDir "$targetDir" "$progName,$LINENO: "

if [ ! -d "$targetDir/input" ] || [ ! -d "$targetDir/resources" ]; then
    dieIfNoSuchFile "$sourceDir/input.tar.bz2" "$progName,$LINENO: "
    dieIfNoSuchFile "$sourceDir/resources.tar.bz2" "$progName,$LINENO: "
    cp "$sourceDir/input.tar.bz2" "$sourceDir/resources.tar.bz2" "$targetDir"
    pushd "$targetDir" >/dev/null
    tar xfj "input.tar.bz2"
    tar xfj "resources.tar.bz2"
    popd >/dev/null
fi
