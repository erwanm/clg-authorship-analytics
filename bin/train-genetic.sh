#!/bin/bash

# EM April 14, modif May 15
# updated March 16

source common-lib.sh
source file-lib.sh
source pan-utils.sh

progName=$(basename "$BASH_SOURCE")

parallelPrefix=""
resume=0
firstGen=
nbDigits=4
trainCVParams=""

function usage {
  echo
  echo "Usage: $progName [options] <input/output dir> <cases file> <prefix genetic params>"
  echo
  echo " <input/output dir> must contain prepared-data."
  echo
  echo "TODO, DEPRECATED!"
  echo "  Reads multi-conf files from STDIN. "
  echo "  High level training script which runs the training process with multiple"
  echo "  configurations of parameters. <input dir> is the input (raw) data;"
  echo "  a list of multi-config files is read from STDIN; in these files "
  echo "  each parameter can have several values separated by spaces, e.g.:"
  echo "    key=val1 val2 \"val 3\" ..."
  echo
  echo "  Returns the optimal config+model, which is written to <output dir>."
  echo
  echo "  Options:"
  echo "    -h this help"
  echo "    -o <train-cv options> options to transmit to train-cv.sh, e.g. '-c -s'."
  echo "    -r resume previous process at first incomplete generation found"
  echo "    -P <parallel prefix> TODO"
  echo "    -f <first gen configs list file> use a list of individual configs"
  echo "       to initiate the genetic process (reads only the first column"
  echo "       of the file)"
#  echo "    -e exhaustive generation of configurations for the first generation;"
#  echo "       Can be used with trainingNbGenerations=1 in order to only"
#  echo "       compute the result of a given set of regular configs provided"
#  echo "       instead of the multi-configs (don't forget to set the parameter"
#  echo "       at least in the first config file)."
#  echo "       Warning: do not use if the multi-conf files contain billions"
#  echo "                of possibilities!"
  echo
}




function findPrevGenDir {
    local genDir="$1"
    local genNo="$2"
    local nbDigits="$3"
    local prevGenNo=$(( $genNo - 1 ))
    local prevGenStr=$(printf "%0${nbDigits}d" $prevGenNo)
    local originalStr="$prevGenStr"
    while [ ! -d "$genDir/$prevGenStr" ] && [ $nbDigits -gt 0 ]; do
	nbDigits=$(( $nbDigits - 1 ))
	prevGenStr=$(printf "%0${nbDigits}d" $prevGenNo)
    done
    if [ -d  "$genDir/$prevGenStr" ]; then
	echo "$genDir/$prevGenStr"
    else
	echo "$genDir/$originalStr" # will fail
    fi
}


function extractUniqueBestConfigs {
    local outputDir="$1"
    local nbBest="$2"
    local outputFile="$3"

    evalSafe "cat \"$outputDir\"/generations/*/train/configs.results | sort -r -g +1 -2 >\"$outputDir/all-configs.results\"" "$progName,$LINENO: "
    rm -f "$outputFile"
    touch "$outputFile"
    duplicates=$(cat "$outputDir/all-configs.results" | while read configLine; do
	file1=$(echo "$configLine" | cut -f 1)
	nbDiff=$(cut -f 1 "$outputFile" | while read file2; do
	    cmp "$file1" "$file2" >/dev/null 2>/dev/null
	    if [ $? -eq 0 ]; then # identical files
#		echo "$progName debug: $file1 = $file2" 1>&2
		break
	    else
		echo 1
	    fi
	done | wc -l)
	size=$(cat "$outputFile" | wc -l)
	if [ $nbDiff -eq  $size ]; then
	    echo "$configLine" >>"$outputFile"
	    size=$(( $size + 1 ))
	    if [ $size -ge $nbBest ]; then
		break
	    fi
	else
	    echo 1
	fi
    done | wc -l)
    if [ $? -ne 0 ]; then
	echo "$progName: something went wrong when removing duplicates for best configs" 1>&2
	exit 4
    fi
    size=$(cat "$outputFile" | wc -l)
    echo "$progName: returning $size best configs (removed $duplicates duplicates)"
}


OPTIND=1
while getopts 'hP:ro:f:' option ; do 
    case $option in
	"h" ) usage
 	      exit 0;;
	"P" ) parallelPrefix="$OPTARG";;
	"f" ) firstGen="$OPTARG";;
#	"e" ) randomFirstGen=0;;
	"r" ) resume=1;;
        "o" ) trainCVParams="$OPTARG";;
 	"?" ) 
	    echo "Error, unknow option." 1>&2
            printHelp=1;;
    esac
done
shift $(($OPTIND - 1))
if [ $# -ne 3 ]; then
    echo "Error: expecting 3 args." 1>&2
    printHelp=1
fi
if [ ! -z "$printHelp" ]; then
    usage 1>&2
    exit 1
fi
outputDir="$1"
casesFile="$2"
prefixGeneticParams="$3"

mkdirSafe "$outputDir"
#rm -f  "$outputDir/best-configs.res"

mcDir="$outputDir/multi-conf-files"
rm -rf "$mcDir"
echo "$progName: reading multi-config files from STDIN"
mkdir "$mcDir"
while read file; do # don't know how to make it more simple, doesn't matter
    dieIfNoSuchFile "$file" "$progName: "
    cp "$file" "$mcDir"
done

config1=$(ls "$mcDir"/*  | head -n 1)
echo "$progName: preparing genetic process"
readFromParamFile "$config1" "${prefixGeneticParams}population" "$progName,$LINENO: " "" "" "" "population"
readFromParamFile "$config1" "${prefixGeneticParams}stopCriterionNbWindows" "$progName,$LINENO: " "" "" "" "stopCriterionNbWindows"
readFromParamFile "$config1" "${prefixGeneticParams}stopCriterionNbGenerationsByWindow" "$progName,$LINENO: " "" "" "" "stopCriterionNbGenerationsByWindow"
readFromParamFile "$config1" "${prefixGeneticParams}geneticParams" "$progName,$LINENO: " "" "" "" "geneticParams"
readFromParamFile "$config1" "${prefixGeneticParams}perfCriterion" "$progName,$LINENO: " "" "" "" "perfCriterion"
readFromParamFile "$config1" "${prefixGeneticParams}nbFoldsOrProp" "$progName,$LINENO: " "" "" "" "nbFoldsOrProp"
readFromParamFile "$config1" "${prefixGeneticParams}returnNbBest" "$progName,$LINENO: " "" "" "" "returnNbBest"

# special case for meta-learning
readFromParamFile "$config1" "strategy" "$progName,$LINENO: "


stopLoop=0
if [ $resume -eq 0 ]; then
    if [ -d "$outputDir/generations" ]; then
	echo "$progName: Error: directory $outputDir/generations already exists! " 1>&2
	echo "$progName: aborting process to be safe; remove the directory or use -r to resume existing process" 1>&2
	exit 3
    fi
    mkdir "$outputDir/generations"
    startAtGen=1
else
    mkdirSafe "$outputDir/generations" "$progName,$LINENO: "
    # stop criterion evaluated in case nothing to do
#    echo "DEBUG: 'ls \"$outputDir/generations\"/*/train/configs.results 2>/dev/null | stop-criterion.pl -c 2 \"$population\" \"$stopCriterionNbWindows\" \"$stopCriterionNbGenerationsByWindow\"'" 1>&2
    stopLoop=$(evalSafe "ls \"$outputDir/generations\"/*/train/configs.results 2>/dev/null | stop-criterion.pl -c 2 \"$population\" \"$stopCriterionNbWindows\" \"$stopCriterionNbGenerationsByWindow\"" "$progName,$LINENO: ")
#    echo $stopLoop
    if [ $stopLoop -ne 0 ]; then
	echo "$progName: stop criterion already met, not entering genetic loop."
    else
	startAtGen=""
	genNo=1
	while [ -z "$startAtGen" ]; do
	    genNoStr=$(printf "%0${nbDigits}d" $genNo)
	    genDir="$outputDir/generations/$genNoStr"
	    if [ ! -s "$genDir/configs.list" ]; then
		startAtGen=$genNo
	    else
		nbConfigs=$(cat "$genDir/configs.list" | wc -l)
		if [ $nbConfigs -lt $population ]; then
		    startAtGen=$genNo
		else
		    if [ ! -s "$genDir/train/configs.results" ]; then
			startAtGen=$genNo
		    else
			n=$(cat "$genDir/train/configs.results" | wc -l)
			if [ $n -lt $nbConfigs ]; then
			    startAtGen=$genNo
			fi
		    fi
		fi
	    fi
	    genNo=$(( $genNo + 1 ))
	done
	echo "$progName: resuming genetic process at generation $genNoStr in '$genDir'"
#	rm -rf "$genDir"
    fi
fi

genNo=$startAtGen
while [ $stopLoop -eq 0 ]; do
    genNoStr=$(printf "%0${nbDigits}d" $genNo)
    genDir="$outputDir/generations/$genNoStr"
    mkdirSafe "$genDir" "$progName,$LINENO: "
    mkdirSafe "$genDir/configs" "$progName,$LINENO: "
    mkdirSafe "$genDir/train" "$progName,$LINENO: "
    evalSafe "cat \"$casesFile\" >\"$genDir/train/cases.list\""  "$progName,$LINENO: "
    if [ $genNo -eq 1 ]; then
	if [ -z "$firstGen" ]; then # random first generation
	    echo "$progName, gen $genNoStr: generating $population random config files"
	    evalSafe "ls \"$mcDir\"/* | expand-multi-config.pl -r $population -p \"$genDir/configs/\" >\"$genDir/configs.list\"" "$progName,$LINENO: "
	else # specific list of individual configs
	    rm -f "$genDir/configs"/* "$genDir/configs.list"
	    nbDigitsConf=${#population}
	    confNo=0
	    cat "$firstGen" | cut -f 1 | while read f; do
		confNoStr=$(printf "%0${nbDigitsConf}d" $confNo)
		cp "$f" "$genDir/configs/$confNoStr.conf"
		echo "$genDir/configs/$confNoStr.conf" >>"$genDir/configs.list"
		confNo=$(( $confNo + 1 ))
	    done
	fi
    else
	prevGenDir=$(findPrevGenDir "$outputDir/generations/" $genNo ${nbDigits})
	dieIfNoSuchFile "$prevGenDir/train/configs.results" "$progName,$LINENO: "
	echo "$progName, gen $genNoStr: generating $population config files by genetic crossover"
	evalSafe "ls \"$mcDir\"/* | expand-multi-config.pl -g \"$prevGenDir/train/configs.results:$population:$geneticParams\" -p \"$genDir/configs/\" >\"$genDir/configs.list\"" "$progName,$LINENO: "
    fi
    echo "$progName, gen $genNoStr: evaluating configs; perfCriterion=$perfCriterion; nbFolds=$nbFoldsOrProp; prepared data=$outputDir/prepared-data; multi-config list is:"
    ls "$mcDir"/* 
    if [ ! -z "$parallelPrefix" ]; then
	params="-P \"$parallelPrefix.$genNoStr\""
    fi
    if [ $resume -ne 0 ]; then
	params="$params -r"
    fi
    # TODO: sleep time set to 20s for meta-training, should be much longer for strategy training
    evalSafe "train-generation.sh -s 20s -o  \"$trainCVParams\" $params -p $perfCriterion -f $nbFoldsOrProp \"$genDir/configs.list\" \"$outputDir/prepared-data\" \"$genDir/train\"" "$progName,$LINENO: "
    dieIfNoSuchFile "$genDir/train/configs.results" "$progName,$LINENO: "
    stopLoop=$(evalSafe "ls \"$outputDir/generations\"/*/train/configs.results | stop-criterion.pl -c 2 -l \"$genDir/stop-criterion.log\"  \"$population\" \"$stopCriterionNbWindows\" \"$stopCriterionNbGenerationsByWindow\"" "$progName,$LINENO: ")
    echo "INFO $progName: average perf for the $stopCriterionNbWindows last ${stopCriterionNbGenerationsByWindow}-long windows: "
    evalSafe "cat \"$genDir/stop-criterion.log\"" "$progName,$LINENO: "
    genNo=$(( $genNo + 1 ))
done

echo "$progName: genetic loop done, extracting $returnNbBest best configs (removing duplicates)"
rm -rf "$outputDir/best-configs"
mkdir "$outputDir/best-configs"
extractUniqueBestConfigs "$outputDir" "$returnNbBest" "$outputDir/best-configs.tmp"
confNo=1
echo "$progName: renaming best configs"
cut -f 1 "$outputDir/best-configs.tmp" | while read confFile; do
    confNoStr=$(printf "%0${nbDigits}d" $confNo)
    newName="$outputDir/best-configs/$confNoStr.conf"
#    echo cp "$confFile" "$newName" 1>&2
    cp "$confFile" "$newName"
    echo "$newName"
    confNo=$(( $confNo + 1 ))
done | paste - "$outputDir/best-configs.tmp" | cut -f 1,3 >"$outputDir/best-configs.res"
if [ $? -ne 0 ]; then
    echo "$progName: something wrong in final loop (extracting best configs)" 1>&2
    exit 7
fi
rm -f "$outputDir/best-configs.tmp"

echo "$progName: done."
