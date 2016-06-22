#!/bin/bash

#source common-lib.sh
#source file-lib.sh

progName="generate-tw-doc.sh"

wikiName="dummy-name"

function usage {
  echo
  echo "Usage: $progName [options] <html wiki file> "
  echo
  echo "  executable files read from STDIN"
  echo
  echo
  echo "  Options:"
  echo "    -h this help"
  echo
}


function writeCreatedTodayField {
    theDate=$(date +"%Y%m%d%H%M%S")
    echo "created: ${theDate}000"
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
if [ $# -ne 1 ]; then
    echo "Error: expecting 1 args." 1>&2
    printHelp=1
fi
if [ ! -z "$printHelp" ]; then
    usage 1>&2
    exit 1
fi

htmlWikiFile="$1"

workDir=$(mktemp -d)
echo "DEBUG: workDir = $workDir"  1>&2

pushd "$workDir" >/dev/null
tiddlywiki "$wikiName" --init server >/dev/null # create temporary node.js wiki 
tiddlywiki "$wikiName" --load "$htmlWikiFile" >/dev/null # convert standalone to tid files
popd >/dev/null

while read executableFile; do
    tiddlerName=$(basename "$executableFile")
    targetTiddler="$workDir/$wikiName/tiddlers/$tiddlerName.tid"
    writeCreatedTodayField >"$targetTiddler"
    echo "title: $tiddlerName" >>"$targetTiddler"
    echo "type: text/plain" >>"$targetTiddler"
    echo ""  >>"$targetTiddler"
    eval "$executableFile -h" >> "$targetTiddler"
done

pushd "$workDir" >/dev/null
tiddlywiki "$wikiName" --rendertiddler "$:/plugins/tiddlywiki/tiddlyweb/save/offline" "output.html" text/plain >/dev/null
popd >/dev/null

# rm -rf "$workDir"
