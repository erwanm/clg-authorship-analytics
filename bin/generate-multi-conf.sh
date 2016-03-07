#!/bin/bash

# EM April 15, update march 16

source file-lib.sh

progName=$(basename "$BASH_SOURCE")

dirName="multi-conf-files"
strategies="basic GI univ"
configDir="conf/"
geneticPartFile="genetic.std.multi-conf.part"
commonPartFile="common.std.multi-conf.part"

function usage {
  echo
  echo "Usage: $progName [options] <with POS?> <output dir>"
  echo
  echo "  assembles the multi-config files and write them to"
  echo "  <output dir>/$dirName."
  echo "  For each strategy, concatenates the genetic part, the common"
  echo "  part and the specific strategy part, in this order; the last"
  echo "  occurence of a parameter always overrides the others if several."
  echo "  the strategy part is supposed to be named"
  echo "   <conf dir>/<strategy>.multi-conf.part"
  echo "  generates the no-POS variant if <with POS> = 0."
  echo
  echo "  Options:"
  echo "    -h this help"
  echo "    -d <config dir>; default='$configDir'"
  echo "    -s <strategies ids>; default='$strategies'"
  echo "    -g <genetic part file> genetic parameters file; default='$geneticPartFile'"
  echo "    -c <common part file> common parameters file; default='$commonPartFile'"
  echo
}





OPTIND=1
while getopts 'hd:s:g:c:' option ; do 
    case $option in
	"h" ) usage
 	      exit 0;;
	"d" ) configDir="$OPTARG";;
	"s" ) strategies="$OPTARG";;
	"g" ) geneticPartFile="$OPTARG";;
	"c" ) commonPartFile="$OPTARG";;
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
withPOS="$1"
outputDir="$2"

dieIfNoSuchDir "$configDir" "$progName,$LINENO"
dieIfNoSuchFile "$configDir/$commonPartFile" "$progName,$LINENO"
dieIfNoSuchFile "$configDir/$geneticPartFile" "$progName,$LINENO"
mkdirSafe "$outputDir" "$progName,$LINENO"
destDir="$outputDir/$dirName"
mkdirSafe "$destDir" "$progName,$LINENO"
rm -f "$destDir"/*
for s in $strategies; do
    echo -n  "$progName: Strategy '$s' " 1>&2
    file="$configDir/$s.multi-conf.part"
    dieIfNoSuchFile "$file" "$progName,$LINENO"    
    posFilter=""
    if [ $withPOS -ne 1 ]; then
	posFilter=" | grep -v 'obsType\.POS\..*='"
	echo "(no POS)"
    else
	echo "(with POS)"
    fi
    evalSafe "cat \"$configDir/$geneticPartFile\" \"$configDir/$commonPartFile\" \"$file\" $posFilter >\"$destDir/$s.multi-conf\"" "$progName,$LINENO"
done
