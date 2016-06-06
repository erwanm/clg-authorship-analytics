#!/bin/bash

source common-lib.sh
source file-lib.sh

progName="run-std-training.sh"


force=0
addToExisting=0
prepareParams=""
trainingParams=""

mcFile=""
useCountFiles=1
resourcesAccess=r

function usage {
  echo
  echo "Usage: $progName [options] <input data dir> <work dir>"
  echo
  echo "  Starts the whole training process in a 'standard' way (simplified parameters)."
  echo "  Assumes the following:"
  echo "  - the current dir contains a subdir 'conf' containing the multi-conf parts."
  echo
  echo
  echo "  Options:"
  echo "    -h this help"
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
  echo "    -P <parallel prefix> TODO"
  echo
}



OPTIND=1
while getopts 'hfai:o:P:' option ; do
    case $option in
        "f" ) force=1;;
        "a" ) addToExisting=1;;
        "i" ) prepareParams="$prepareParams -i \"$OPTARG\"";;
        "P" ) parallelPrefix="$OPTARG"
	      trainingParams="$trainingParams -P \"$parallelPrefix\"";;
        "o" ) constantParams="$trainingParams -o \"$OPTARG\"";;
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

if [ ! -z "$resourcesDir" ]; then
    dieIfNoSuchDir "$resourcesDir" "$progName:$LINENO: "
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
evalSafe "generate-multi-conf.sh $withPOS '$workDir/'" "$progName, $LINENO: "

cat "conf/meta-template.std.multi-conf"> "$workDir/meta-template.multi-conf"
dieIfNoSuchFile "$workDir/multi-conf-files/basic.multi-conf" "$progName, $LINENO: "
dieIfNoSuchFile "$workDir/meta-template.multi-conf" "$progName, $LINENO: "



# prepare
evalSafe "ls $workDir/*.multi-conf | prepare-input-data.sh $prepareParams '$sourceDir' '$workDir'" "$progName, $LINENO: "

# run
if [ $addToExisting -ne 0 ] && [ -d "$workDir/outerCV-folds" ] ; then
    trainingParams="$trainingParams -r"
fi
echo "train-top-level.sh -r $trainingParams '$workDir'" >"$workDir/restart-top-level.sh"
chmod a+x "$workDir/restart-top-level.sh"
evalSafe "train-top-level.sh $trainingParams '$workDir'" "$progName, $LINENO: "


