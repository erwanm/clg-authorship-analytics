#!/bin/bash

source common-lib.sh
source file-lib.sh

progName="run-std-training.sh"


force=0
addToExisting=0
prepareParams=""
trainingParams=""
trainCVParams=""
preferedDataLocation=""
confDir="./conf"

function usage {
  echo
  echo "Usage: $progName [options] <input data dir> <work dir>"
  echo
  echo "  Starts the whole training process in a 'standard' way (simplified parameters)."
  echo "  Assumes the following:"
  echo "  - the current dir contains a subdir 'conf' containing the multi-conf parts,"
  echo "    unless using option '-c' (see below)."
  echo
  echo "  Remark: this script generates the multi-conf files based on the content of "
  echo "          'conf' directory and the language; if the language is supported by"
  echo "          TreeTagger, then POS tags observations can be used."
  echo
  echo
  echo "  Options:"
  echo "    -h this help"
  echo "    -c <conf directory> default: '$confDir'."
  echo "    -f force overwriting the destination directory if it is not empty;"
  echo "       default: error and exit (to avoid deleting stuff accidentally)."
  echo "    -a add to existing data in destination directory if it is not empty;"
  echo "       default: error and exit (to avoid deleting stuff accidentally)."
  echo "    -i <id:path[;id2:path2...]> specify where to find additional impostors"
  echo "       documents; these will be used if the config parameter 'impostors'"
  echo "       contains the corresponding id(s). see also below." 
  echo "    -i <impostors path> same as above but assuming all impostors datasets"
  echo "       are located as subdirs of <impostors path>."
  echo "    -o <train-cv options> options to transmit to train-cv.sh, e.g. '-c -s'."
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
  echo "    -M run master tasks as regular tasks instead of as background daemons."
  echo "       ignored if -P is not enabled."
  echo
}



OPTIND=1
while getopts 'hfai:o:P:L:c:M' option ; do
    case $option in
	"c" ) confDir="$OPTARG";;
        "f" ) force=1;;
        "a" ) addToExisting=1;;
        "i" ) prepareParams="$prepareParams -i \"$OPTARG\"";;
        "P" ) parallelPrefix="$OPTARG"
	      trainingParams="$trainingParams -P \"$parallelPrefix\"";;
        "o" ) trainCVParams="$trainCVParams $OPTARG";;
	"L" ) preferedDataLocation="$OPTARG";;
	"M" ) trainingParams="$trainingParams -M";;
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
workDir="$2"

dieIfNoSuchDir "$sourceDir" "$progName,$LINENO: "
dieIfNoSuchFile "$sourceDir/contents.json" "$progName,$LINENO: "


if [ $force -ne 0 ]; then
    rm -rf "$workDir"
fi
mkdirSafe "$workDir"  "$progName:$LINENO: "
nbEntries=$(ls "$workDir" | wc -l)
if [ $nbEntries -ne 0 ]; then
    if [ $addToExisting -ne 0 ]; then
        echo "$progName warning: adding data to non empty dest dir '$workDir'" 1>&2
    else
        echo "$progName error: dest dir '$workDir' not empty. use -f to force overwriting, -a to add to existing data" 1>&2
        exit 2
    fi
fi


language=$(grep language "$sourceDir/contents.json" | cut -d '"' -f 4)
language=$(echo "$language" | tr '[:upper:]' '[:lower:]')
echo "$progName: language is '$language'"

ttValidLang=$(tree-tagger-POS-wrapper.sh -h | grep "Valid language" | grep "$language")
if [ -z "$ttValidLang" ]; then
    withPOS=0
else
    withPOS=1
fi
echo "$progName: withPOS = $withPOS"


# generating multi-config
evalSafe "generate-multi-conf.sh -d '$confDir' $withPOS '$workDir/'" "$progName, $LINENO: "

cat "$confDir/meta-template.std.multi-conf"> "$workDir/meta-template.multi-conf"
dieIfNoSuchFile "$workDir/multi-conf-files/basic.multi-conf" "$progName, $LINENO: "
dieIfNoSuchFile "$workDir/meta-template.multi-conf" "$progName, $LINENO: "



# prepare
evalSafe "ls $workDir/*.multi-conf | prepare-input-data.sh $prepareParams '$sourceDir' '$workDir'" "$progName, $LINENO: "
if [ ! -f "$workDir/resources-options.conf" ]; then
    echo "$progName error: no file '$workDir/resources-options.conf' after preparing data." 1>&2
fi



# generate archives if preferedDataLocation is set (very long!!!)
if [ ! -z "$preferedDataLocation" ]; then
    echo "$progName: redirecting 'input' and 'resources' to '$preferedDataLocation'"
    if [ ! -f "$workDir/input.tar.bz2" ] || [ ! -f "$workDir/resources.tar.bz2" ]; then
	echo "$progName: archives not found or option 'force' enabled, generating (very long!)"
	pushd "$workDir" >/dev/null
	evalSafe "tar cfj input.tar.bz2 input" "$progName, $LINENO: "
	evalSafe "tar cfj resources.tar.bz2 resources" "$progName, $LINENO: "
	popd  >/dev/null
    fi
    trainCVParams="$trainCVParams -L $preferedDataLocation"
fi



# run
if [ $addToExisting -ne 0 ] && [ -d "$workDir/outerCV-folds" ] ; then
    trainingParams="$trainingParams -r"
fi
trainingParams="$trainingParams -o \"$trainCVParams\""
echo "train-top-level.sh -r $trainingParams '$workDir'" >"$workDir/restart-top-level.sh"
chmod a+x "$workDir/restart-top-level.sh"
evalSafe "train-top-level.sh $trainingParams '$workDir'" "$progName, $LINENO: "




