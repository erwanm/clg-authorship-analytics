#!/bin/bash

# EM April 16


# TODO
# - -r option
# - parallel processing??
# + impostors similarities

source common-lib.sh
source file-lib.sh
source pan-utils.sh

currentDir=$(pwd)
progName="prepare-input-data.sh"
force=0
addToExisting=0
resourcesDir=""
impostorsData=""
impostorsParam="GI.impostors"

basicTokensObsType="WORD.T.lc1.sl1.mf2"



function usage {
  echo
  echo "TODO recheck everything"
  echo 
  echo "Usage: $progName [options] <original input dir> <dest dir>"
  echo
  echo "  Reads a list of multi-config files from <STDIN>, stores them in"
  echo "  <dest dir>/multi-conf-files/*.multi-conf, and prepares the input data"
  echo "  accordingly. The input data is one dataset (unique language, at least)."
  echo "  Preparation of the author verification cases includes:"
  echo "    - tokenization and POS tagging (if needed)"
  echo "    - counting observations"
#  echo "    - for known files: merges counts, computes stats and distrib files"
#  echo "    - if provided, uses the ref data to compute 'distinctiveness'"
#  echo "      values; otherwise,  creates a subdir 'reference' and extracts"
#  echo "      reference data from all the input cases (computes stats etc.)."
#  echo "      If provided, the ref data stats must have been generated with"
#  echo "      the appropriate parameters. And since there is only one version"
#  echo "      of the ref data in this case (as opposed to generated from the"
#  echo "      input data), it can be used only in testing mode with a single"
#  echo "      config file (or several but with the same preparation parameters)"
  echo 
  echo "  The general principle is to generate 'prepared data' for a given"
  echo "  combination of parameters only if this combination is possible in one"
  echo "  of the multi-config files. A combination for which data was already"
  echo "  prepared is not done again, by checking if the corresponding directory"
  echo "  exists. But the observation types are an exception: the full set of"
  echo "  possible types is extracted from all the files at first, and all cases"
  echo "  for other parameters will contain all observation types versions."
  echo
  echo "  Remark: for each multi-config file, all the combinations of the specified"
  echo "  preparation parameters are proceeded, but not between two distinct"
  echo "  multi-config files (i.e. disjunction of cartesian products)"
  echo
  echo "  every multi-config file contains lines of the form <key>=<value>;"
  echo "  it must contain the following:"
  echo "    - obsType.<obs type id>=[0|1|0 1] observation types"
  echo "    - minDocFreq= min nb of docs in which an observation must"
  echo "      appear to be taken into account; can be a proportion 0<p<1."
#  echo "    - minRefDocsByObs= min nb of reference docs in which an observation must"
#  echo "      appear to be taken into account; can be a proportion 0<p<1. Remark:"
#  echo "      used only if the reference data is not provided."
  echo "    TODO: many other parameters needed!"
  echo
  echo "  Options:"
  echo "    -h this help"
  echo "    -f force overwriting the destination directory if it is not empty;"
  echo "       default: error and exit (to avoid deleting stuff accidentally)." 
  echo "    -a add to existing data in destination directory if it is not empty;"
  echo "       default: error and exit (to avoid deleting stuff accidentally)."
  echo "    -r <resources data dir> a dir which must contain these 3 subdirs:"
#  echo "       -'reference' must have been 'prepared', with .stats, .relfreqs"
#  echo "        and .histo files"
  echo "       - 'stop-words' must have been prepared"
  echo "       - 'impostors' must have been prepared"
  echo "       If this option is supplied, only the input data is 'prepared', and"
  echo "       possibly the web impostors (depending on parameters)"
# now POS tagging is done only if required by observation types
#  echo "    -n do not tokenize and tag POS (tokenization with TreeTagger only needed"
#  echo "       for POS tagging; n-grams tokenized in another way)"
  echo "    -i <id:path[;id2:path2...]> specify where to find additional impostors"
  echo "       documents; these will be used if the config parameter 'impostors'"
  echo "       contains the corresponding id(s)." #special id 'web' is reserved."
  echo "       This option is ignored if '-r' is supplied."
#  echo "    -s <stop words directory> provide path to stop words directory:"
  echo "       "
  echo
}


#
# reads config files from STDIN
#
function readParamFromMultipleConfigFilesFailOnDiff {
    local paramName="$1"

    local res=""
    while read mcFile; do
	readFromParamFile  "$mcFile" "$paramName" "$progName,$LINENO: " "" 0 NA "tmpVar"
	if [ "$tmpVar" != "NA" ]; then
	    if [ -z "$res" ]; then
		res="$tmpVar"
	    else
		if [ "$res" != "$tmpVar" ]; then
		    echo "$progName warning: different values found in multi-config files for parameter '$paramName'" 1>&2
		fi
	    fi
	fi
    done
    echo "$res"
}


#
# reads config files from STDIN
#
function readParamFromMultipleConfigFilesListUnion {
    local paramName="$1"
    local sepa="$2"

    local res=""
    while read mcFile; do
	readFromParamFile  "$mcFile" "$paramName" "$progName,$LINENO: " "" 0 NA "tmpVar"
#	echo "DEBUG: mcFile=$mcFile; tmpVar=$tmpVar" 1>&2
	if [ "$tmpVar" != "NA" ]; then
	    echo "$tmpVar" | sed "s/$sepa/\n/g"
	fi
    done | sort -u
}



#
# obs types as args, space separated
#
function extractStopWordsLimitFromObsTypes {
    local stopWordsLimits=""
    while [ ! -z "$1" ]; do
	if [ "${1:0:4}" == "WORD" ]; then
	    suffix=$(echo "$1" | sed 's/^.*\.sl[01]//g')
	    swPart=$(echo "${suffix%.mf[0-9]*}")
	    if [ ! -z "$swPart" ]; then
		echo "${swPart:1}" # remove first char = '.'
	    fi
	fi
	shift
    done | sort -u -n | tr '\n' ' '
}


#
# args = targetImpId impId1:impPath1 impId2:ipmpPath2 ...
#
function getImpostorsDir {
    local impId="$1"
    shift

    while [ ! -z "$1" ]; do
	if [ "${1%:*}" == "$impId" ]; then
	    echo "${1#*:}"
	    return
	fi
	shift
    done
    echo "$progName: error, no path found for impostors dataset '$impId'" 1>&2
    exit 4
 }


while getopts 'hfar:i:' option ; do 
    case $option in
	"f" ) force=1;;
	"a" ) echo "$progName: adding mode is ON"
	      addToExisting=1;;
	"r" ) resourcesDir="$OPTARG";;
	"i" ) impostorsData=$(echo "$OPTARG" | tr ';' ' ');;
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
sourceDir="$1"
destDir="$2"

if [ ! -z "$printHelp" ]; then
    usage 1>&2
    exit 1
fi



# check if valid directories, prepare dest dir
dieIfNoSuchDir "$sourceDir" "$progName:$LINENO: "
dieIfNoSuchFile "$sourceDir/contents.json"  "$progName:$LINENO: " # extract language
if [ $force -ne 0 ]; then
    rm -rf "$destDir"
fi
mkdirSafe "$destDir"  "$progName:$LINENO: "
nbEntries=$(ls "$destDir" | wc -l)
if [ $nbEntries -ne 0 ]; then
    if [ $addToExisting -ne 0 ]; then
	echo "$progName warning: adding data to non empty dest dir '$destDir'" 1>&2
    else
	echo "$progName error: dest dir '$destDir' not empty. use -f to force overwriting, -a to add to existing data" 1>&2
	exit 2
    fi
fi

if [ ! -z "$resourcesDir" ]; then
    dieIfNoSuchDir "$resourcesDir" "$progName:$LINENO: " 
fi

# extract language from json description file
language=$(grep language "$sourceDir/contents.json" | cut -d '"' -f 4)
language=$(echo "$language" | tr '[:upper:]' '[:lower:]')
echo "$progName: language is '$language'"
echo $language >"$destDir/id.language"


# stores multi-config files and check that at least one is supplied
mkdirSafe "$destDir"/multi-conf-files  "$progName:$LINENO: "
while read mcFile; do
    cat "$mcFile" > "$destDir/multi-conf-files/$(basename "$mcFile")"
done
n=$(ls "$destDir"/multi-conf-files/*.multi-conf 2>/dev/null| wc -l)
if [ $n -eq 0 ]; then
    echo "$progName error: no multi-conf file found in '$destDir/multi-conf-files'" 1>&2
    exit 3
fi

# first pass on multi-config files, only to extract all the possible obs types,
# and save the list for second pass.
possibleObsTypes=$(ls "$destDir"/multi-conf-files/*.multi-conf | extractPossibleObsTypes)
obsTypesColonSep=$(echo "$possibleObsTypes" | sed 's/ /:/g')


# checks whether POS tagging is needed
noPOSParam=""
tokAndPOS=1
#echo "DEBUG: possible obs types = $possibleObsTypes" 1>&2
requiresPOSTags $possibleObsTypes
if [ $? -eq 0 ]; then
    noPOSParam="-n"
    tokAndPOS=0 # TODO two different variables for the same purpose, confusing.
    echo "   $progName: no TreeTagger tokenization/POS tagging needed"
fi




mkdirSafe "$destDir/input"  "$progName:$LINENO: "
mkdirSafe "$destDir/resources"  "$progName:$LINENO: "

echo "$progName init: copying input data"
cloneDir "$sourceDir" "$destDir/input"
listDocFiles "$destDir/input" >"$destDir/input/all-data.files" 

# find formatting options in config files
formatting=$(ls "$destDir"/multi-conf-files/*.multi-conf | readParamFromMultipleConfigFilesFailOnDiff "formatting")
wordTokenization=$(ls "$destDir"/multi-conf-files/*.multi-conf | readParamFromMultipleConfigFilesFailOnDiff "wordTokenization")
#echo "DEBUG $progName: fomatting='$formatting' wordTokenization='$wordTokenization'" 1>&2

paramsDataset=""
if [ ! -z "$formatting" ]; then
    paramsDataset="$paramsDataset -s $formatting"
fi
if [ ! -z "$wordTokenization" ] && [ "$wordTokenization" == 0 ] ; then
    paramsDataset="$paramsDataset -t"
fi

stopWordsLimits=$(extractStopWordsLimitFromObsTypes $possibleObsTypes)
if [ -z "$resourcesDir" ]; then

    echo "$progName: stop words: generating count files, tokens only"
    evalSafe "count-obs-dataset.sh -i '$destDir/input/all-data.files' -o '-g $paramsDataset' $language $basicTokensObsType" "$progName:$LINENO: "

    mkdirSafe "$destDir/resources/stop-words" "$progName:$LINENO: "
    vocabResources=""
    for stopWordLimit in $stopWordsLimits; do
	evalSafe "sort -r -n +1 -2 \"$destDir/input/global.$basicTokensObsType.count\" | cut -f 1 | head -n $stopWordLimit >\"$destDir/resources/stop-words/$stopWordLimit.stop-list\" " "$progName:$LINENO: "
	vocabResources="$vocabResources;$stopWordLimit:$destDir/resources/stop-words/$stopWordLimit.stop-list"
    done
else
    dieIfNoSuchDir "$resourcesDir/stop-words" "$progName,$LINENO: "
    rm -f "$destDir/resources/stop-words"
    linkAbsolutePath "$destDir/resources" "$resourcesDir/stop-words"
    for stopWordLimit in $stopWordsLimits; do
	dieIfNoSuchFile "$destDir/resources/stop-words/$stopWordLimit.stop-list"  "$progName:$LINENO: "
	vocabResources="$vocabResources;$stopWordLimit:$destDir/resources/stop-words/$stopWordLimit.stop-list"
    done
fi
vocabResources=${vocabResources:1}
#echo "DEBUG $progName: vocabResources='$vocabResources'" 1>&2

echo "$progName: input data, generating count files for all obs types"
paramsDataset="$paramsDataset -r '$vocabResources'"
evalSafe "count-obs-dataset.sh -i \"$destDir/input/all-data.files\" -o \"$paramsDataset\" $language $basicTokensObsType:$obsTypesColonSep" "$progName:$LINENO: "


echo "$progName: input data, preparing impostors data"
usedImpostorsIds=$(ls "$destDir"/multi-conf-files/*.multi-conf | readParamFromMultipleConfigFilesListUnion "$impostorsParam" ";")
echo "$progName DEBUG: usedImpostorsIds='$usedImpostorsIds'" 1>&2
mkdirSafe "$destDir/resources/impostors/" "$progName,$LINENO: "

for impId in $usedImpostorsIds; do

    if [ -z "$resourcesDir" ]; then
	impPath=$(getImpostorsDir "$impId" $impostorsData)
	echo "$progName DEBUG: imp path='$impPath'" 1>&2

	echo "$progName, impostors dataset '$impId' copying impostors file"
	mkdirSafe "$destDir/resources/impostors/$impId" "$progName,$LINENO: "
	cloneDir "$impPath" "$destDir/resources/impostors/$impId"
	listDocFiles "$destDir/resources/impostors/$impId" >"$destDir/resources/impostors/$impId/all-data.files" 

	echo "$progName, impostors dataset '$impId': generating count files for all obs types"
	evalSafe "count-obs-dataset.sh -i \"$destDir/resources/impostors/$impId/all-data.files\" -o \"$paramsDataset\" $language $basicTokensObsType:$obsTypesColonSep" "$progName:$LINENO: "
    else
	dieIfNoSuchDir "$resourcesDir/impostors/$impId" "$progName,$LINENO: "
        rm -f "$destDir/resources/impostors/$impId"
        linkAbsolutePath "$destDir/resources/impostors" "$resourcesDir/impostors/$impId"
    fi

    echo "$progName, impostors dataset '$impId': computing pre-similarity values against all probe files"
    evalSafe "sim-collections-doc-by-doc.pl -o '$basicTokensObsType' $paramsDataset $basicTokensObsType:$obsTypesColonSep \"$destDir/input/all-data.files\" \"$destDir/resources/impostors/$impId/all-data.files\"" "$progName:$LINENO: "

done

echo "$progName: done."



