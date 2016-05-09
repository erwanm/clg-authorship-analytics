#!/bin/bash

# EM April 16

source common-lib.sh
source file-lib.sh
source pan-utils.sh

currentDir=$(pwd)
progName="prepare-input-data.sh"
force=0
addToExisting=0
resourcesDir=""
impostorsData=""

basicTokensObsType="WORD.T.lc1.sl1.mf3"



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
  echo "       documents; these will be used if the config parameter impostorsDataIds"
  echo "       contains the corresponding id(s)." #special id 'web' is reserved."
  echo "       This option is ignored if '-r' is supplied."
#  echo "    -s <stop words directory> provide path to stop words directory:"
  echo "       "
  echo
}


#
# reads config files from STDIN
#
function readParamFromMultipleConfigFiles {
    local paramName="$1"

    res=""
    while read mcFile; do
	readFromParamFile  "$mcFile" "$paramName" "$progName,$LINENO: " 0 NA "tmpVar"
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
    done | sort -u -n
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

echo "$progName init: copying input data"
cloneDir "$sourceDir" "$destDir"
listDocFiles "$destDir" >"$destDir/all-data.files" 

# find formatting options in config files
formatting=$(ls "$destDir"/multi-conf-files/*.multi-conf | readParamFromMultipleConfigFiles "formatting")
wordTokenization=$(ls "$destDir"/multi-conf-files/*.multi-conf | readParamFromMultipleConfigFiles "wordTokenization")
paramsDataset="-g"
if [ ! -z "$formatting" ]; then
    paramsDataset="$paramsDataset -s $formatting"
fi
if [ ! -z "$wordTokenization" ] && [ "$wordTokenization" == 0 ] ; then
    paramsDataset="$paramsDataset -t"
fi

echo "$progName: generating count files pass 1: tokens only (for stop words)"
evalSafe "count-obs-dataset.sh -i '$destDir/all-data.files' -o '$paramsDataset' $language $basicTokensObsType" "$progName:$LINENO: "

mkdirSafe "$destDir/stop-words" "$progName:$LINENO: "
stopWordsLimits=$(extractStopWordsLimitFromObsTypes $possibleObsTypes)
vocabResources=""
for stopWordLimit in $stopWordsLimits; do
    evalSafe "sort -r -n +1 -2 \"$destDir/global.$basicTokensObsType.count\" | head -n $stopWordLimit >\"$destDir/stop-words/$stopWordLimit.stop-list\" " "$progName:$LINENO: "
    vocabResources="$vocabResources:$stopWordLimit:$destDir/stop-words/$stopWordLimit.stop-list"
done
vocabResources=${vocabResources:1}

echo "$progName: generating count files pass 2: all obs types"
paramsDataset="$paramsDataset -r '$vocabResources'"
evalSafe "count-obs-dataset.sh -i '$destDir/all-data.files' -o '$paramsDataset' $language $obsTypesColonSep" "$progName:$LINENO: "



#todo
# - generate stop words
# - case where -r is used (testing, stop words etc provided)
#

echo "DEBUG: not finished yet...." 1>&2
exit 1












function getImpostorsDataDirById {
    local targetId="$1"
#    echo "DEBUG targetId='$targetId'" 1>&2
    for idPath in $impostorsData; do
	id=${idPath%:*}
#	echo "DEBUG id='$id'" 1>&2
	if [ "$id" == "$targetId" ]; then
	    echo "${idPath#*:}"
	    return 0
	fi
    done
    # not found: don't print anything
}





function getUniqueImpostorsDataIds {
    local paramsFile="$1"
    readFromParamFile  "$paramsFile" "impostorsDataIds" "$progName,$LINENO: "
    neededIds=""
    for dataIdGroup in $impostorsDataIds; do
	for dataId in $(echo "$dataIdGroup" | tr ':' ' '); do
	    memberList "$dataId" "$neededIds" 
	    if [ $? -ne 0 ]; then # not found
		neededIds="$neededIds $dataId"
	    fi
	done
    done
    echo "$neededIds"
}




function impSimilarity {
    local destDir="$1"
    local impDataPath="$2"
    local obsType="$3"
    local optionalParam="$4"

    echo "$progName: computing basic similarities (cosine) for cartesian product documents x impostors for impostors dataset $impDataPath" 
    evalSafe "sim-all-cosine.pl $optionalParam -p \"$destDir/impostors-similarities/$impDataPath/\" \"$destDir/input/docSize.0/data/all-data.files\" \"$destDir/impostors-data/$impDataPath/docSize.0/data/all-data.files\" \".$obsType.count\" \".similarities\"" "$progName,$LINENO: "
}





function prepareImpostorsDir {
    local impSourceDir="$1"
    local rootDestDir="$2"
    local impPath="$3"
    local configFile="$4"
    local noPOSParam="$5"
    local language="$6"

    impDestDir="$rootDestDir/impostors-data/$impPath"
    impSimDir="$rootDestDir/impostors-similarities/$impPath"
    mkdirSafe "$impDestDir" "$progName,$LINENO: "
    mkdirSafe "$impSimDir" "$progName,$LINENO: "
    readFromParamFile "$configFile" "impostorsPrepaSimObs" "$progName,$LINENO: "
    readFromParamFile "$configFile" "maxMostSimilarImpostorsByDataset" "$progName,$LINENO: "
    generateTokensDocSize0 "$impSourceDir" "$impDestDir" "tokens"
    impSimilarity "$rootDestDir" "$impPath" "$impostorsPrepaSimObs" "-m $maxMostSimilarImpostorsByDataset"
    mv "$impDestDir/docSize.0/data/all-data.files" "$impDestDir/docSize.0/data/all-data.files.before-pruning"
    evalSafe "cat \"$impSimDir\"/*/*.similarities | cut -f 1 | sort -u | sed \"s:^:$impDestDir/docSize.0/data/:g\" >\"$impDestDir/docSize.0/data/all-data.files\"" "$progName,$LINENO: "
    if [ $(cat "$impDestDir/docSize.0/data/all-data.files" | wc -l) -ne $(cat "$impDestDir/docSize.0/data/all-data.files.before-pruning" | wc -l) ]; then
	evalSafe "cat  \"$impDestDir/docSize.0/data/all-data.files.before-pruning\" | filter-column.pl -n \"$impDestDir/docSize.0/data/all-data.files\" 1 1 | xargs rm " "$progName,$LINENO: "
    fi
    #################################################################
    # May 27 2015 - BUG HERE
    # introduced in commit e5440ceb1ff8e2bbc4ebe876abe4a3f6ce8b0efe, probably when I was coding the optimizations in prepare-subdir.
    # Below is the original line with its original comment; the comment is the reason I don't remove the line: although I can't see today
    # what will not be re-generated and how a different docSize would be impacted by the existence of these count files, I assume
    # it could cause some issues to remove it.
    # But this is still a bug, because the count files are needed if the prepared dir is used later as a resources for another
    # input data (typically in test mode), against which the similarities have to be computed (remark: this function is called only
    # if no resources were provided).
    #
    # remark: re-generated the count files externally this time
    #
    rm -f "$impDestDir/docSize.0/data"/*.count* # otherwise it will not be re-generated with different docSize
    evalSafe "prepare-subdir-input-data.sh -s \"$rootDestDir/stop-words/\" $noPOSParam \"$impDestDir/docSize.0/data\" \"$impDestDir\" $language \"$configFile\" $obsTypesColonSep" "$progName,$LINENO: "
}




while getopts 'hfar:ni:' option ; do 
    case $option in
	"f" ) force=1;;
	"a" ) echo "$progName: adding mode is ON"
	      addToExisting=1;;
	"r" ) resourcesDir="$OPTARG";;
	"n" ) tokenizeAndPOS=0;;
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


# first pass on multi-config files, only to extract all the possible obs types,
# and save the list for second pass.
possibleObsTypes=$(tee "$destDir/multi-config-files.list" | extractPossibleObsTypes)
obsTypesColonSep=$(echo "$possibleObsTypes" | sed 's/ /:/g')


# checks whether POS tagging is needed
noPOSParam=""
tokAndPOS=1
requiresPOSTags $possibleObsTypes
if [ $? -eq 0 ]; then
    noPOSParam="-n"
    tokAndPOS=0 # TODO two different variables for the same purpose, confusing.
    echo "   $progName: no TreeTagger tokenization/POS tagging needed"
fi

mkdirSafe "$destDir/input"  "$progName:$LINENO: "

echo "$progName init: copying input data"
generateTokensDocSize0 "$sourceDir" "$destDir/input" "tokens"
if [ -z "$resourcesDir" ]; then
    echo "$progName init: generating global vocabulary for stop words"
    mkdirSafe "$destDir/stop-words"
    evalSafe "cat \"$inputDir0\"/all-data.files | count-ngrams-pattern.pl -l -s -m 3 1 \"$destDir\"/stop-words/all.tokens.count >/dev/null"    "$progName:$LINENO: "
fi


# 2nd pass on the multi-config files: proceed with preparing required data
# IN THIS LOOP, ALWAYS CHECK IF THE DATA HAS BEEN ALREADY GENERATED
cat "$destDir/multi-config-files.list" | while read multiConfigFile; do

    readFromParamFile "$multiConfigFile" "web_enableWebQueries" "$progName,$LINENO: "
    impDataIds=$(getUniqueImpostorsDataIds "$multiConfigFile")
    echo "Unique impostors datasets ids = $impDataIds"

    # stop words nb words + LDA (topics) input data (special format)
    if [ -z "$resourcesDir" ]; then
	echo "$progName: no stop words data provided, generating from input data" 
	readFromParamFile "$multiConfigFile" "nbStopWords" "$progName,$LINENO: "
	for nb in $nbStopWords; do
	    if [ ! -f "$destDir"/stop-words/$nb.list ]; then
	    # generate stop-words lists from global tokens count files
		sort -r -n +1 -2 "$destDir"/stop-words/all.tokens.count | head -n $nb | cut -f 1 >"$destDir"/stop-words/$nb.list
	    fi
	    readFromParamFile "$multiConfigFile" "strategy" "$progName,$LINENO: "
	    memberList "topics" "$strategy" 
	    if [ $? -eq 0 ]; then # found
		obsTypes=$(echo "$multiConfigFile" | extractPossibleObsTypes)
		generateLDAInputData "$destDir" $nb "$obsTypes"
	    fi
	done
    else
	dieIfNoSuchDir "$resourcesDir/stop-words" "$progName,$LINENO: "
	rm -f "$destDir/stop-words"
	linkAbsolutePath "$destDir/" "$resourcesDir/stop-words"
	readFromParamFile "$multiConfigFile" "nbStopWords" "$progName,$LINENO: "
	for nb in $nbStopWords; do
	    dieIfNoSuchFile "$destDir/stop-words/$nb.list"
	    readFromParamFile "$multiConfigFile" "strategy" "$progName,$LINENO: "
	    memberList "topics" "$strategy" 
	    if [ $? -eq 0 ]; then # found
		obsTypes=$(echo "$multiConfigFile" | extractPossibleObsTypes)
		generateLDAInputData "$destDir" $nb "$obsTypes"
	    fi
	done
    fi

    # input data, all parameters
    if [ -z "$resourcesDir" ]; then
	echo "$progName: no reference data provided, will compute stats for ref data using all input data" 
	if [ ! -d "$destDir/reference" ]; then
	    pushd "$destDir" >/dev/null
	    ln -s "input/reference"  # the target dir might not exist yet, but it doesn't matter
	    popd >/dev/null
	fi
	paramRefProvided=""
    else
	dieIfNoSuchDir "$resourcesDir/reference" "$progName,$LINENO: "
	rm -f "$destDir/reference"
	linkAbsolutePath "$destDir/" "$resourcesDir/reference"
	paramRefProvided="-r \"$destDir/reference\""
    fi
    stopDir="$destDir/stop-words/"
    # option -r for input data only
    evalSafe "prepare-subdir-input-data.sh -k $paramRefProvided -s \"$stopDir\" $noPOSParam \"$sourceDir\" \"$destDir/input\" \"$language\" \"$multiConfigFile\" $obsTypesColonSep" "$progName,$LINENO: "

    # TODO all the impostors data part is terribly designed

    # impostors datasets
    for dataId in $impDataIds; do
	mkdirSafe "$destDir/impostors-data"
	mkdirSafe "$destDir/impostors-similarities"
	if [ ! -z "$resourcesDir" ]; then
	    dieIfNoSuchDir "$resourcesDir/impostors-data" "$progName,$LINENO: "
	    dieIfNoSuchDir "$resourcesDir/impostors-data/$dataId" "$progName,$LINENO: "
	    mkdirSafe "$destDir/impostors-data"
	    rm -f "$destDir/impostors-data/$dataId"
	    linkAbsolutePath "$destDir/impostors-data" "$resourcesDir/impostors-data/$dataId"
	    mkdirSafe "$destDir/impostors-similarities/$dataId"
	    readFromParamFile "$multiConfigFile" "impostorsPrepaSimObs" "$progName,$LINENO: "
	    if [ "$dataId" == "web" ]; then # TODO doesn't work if the multiconf contains several values for web_wordsByQuery
		readFromParamFile "$multiConfigFile" "web_wordsByQuery" "$progName,$LINENO: "
		dieIfNoSuchDir "$destDir/impostors-data/web/wordsByQuery.$web_wordsByQuery" "$progName,$LINENO: "
		mkdirSafe "$destDir/impostors-similarities/web/wordsByQuery.$web_wordsByQuery" "$progName,$LINENO: "
		impSimilarity "$destDir" "web/wordsByQuery.$web_wordsByQuery" "$impostorsPrepaSimObs"
	    else
		impSimilarity "$destDir" "$dataId" "$impostorsPrepaSimObs"
	    fi
	else
	    if [ "$dataId" == "web" ]; then
		if [ $web_enableWebQueries -eq 1 ]; then
		    evalSafe "prepare-web-impostors.sh $noPOSParam \"$destDir\" \"$multiConfigFile\" $language $obsTypesColonSep" "$progName,$LINENO: "
		    for d in "$destDir/web-queries"/*; do
			if [ -d "$d" ]; then # to be safe
			    dbase=$(basename "$d")
			    mkdirSafe "$destDir/impostors-data/web"
			    mkdirSafe "$destDir/impostors-similarities/web"
			    prepareImpostorsDir "$d" "$destDir" "web/$dbase" "$multiConfigFile" "$noPOSParam" "$language"
			fi
		    done
		else
		    echo "Warning: $progName: prepareImpostorsWebQueries: parameter web_enableWebQueries is 0 but impostor dataset 'web' is selected" 1>&2
		fi
	    else
		impostorsDataDir=$(getImpostorsDataDirById "$dataId")
		if [ -z "$impostorsDataDir" ]; then
		    echo "$progName:$LINENO error: no impostor id '$dataId' found in '-i' parameter" 1>&2
		    exit 4
		fi
		prepareImpostorsDir "$impostorsDataDir" "$destDir" "$dataId" "$multiConfigFile" "$noPOSParam" "$language"
	    fi
	fi

    done



done
if [ $? -ne 0 ]; then
    echo "$progName: an error happened in the main loop, aborting."
    exit 14
fi

echo "$progName: done."



