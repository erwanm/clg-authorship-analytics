#!/bin/bash

# EM May 15

source common-lib.sh
source file-lib.sh
source pan-utils.sh

progName=$(basename "$BASH_SOURCE")

constantParams=""
parallelPrefix=""
nbFoldsOuterCV=2
resume=0
sleepTime=1m
applyMultiConfigsParams="-p -s 5s"

function usage {
  echo
  echo "Usage: $progName [options] <input/output dir>"
  echo
#  echo "  the data must have been prepared in <input/output dir>/prepared-data."
  echo "  Reads the multi-config files in <input/output dir>/multi-conf-files/*.multi-conf"
  echo "  For each multi-conf file (strategy), a full training process is launched."
  echo "  '<input/output dir>/meta-template.multi-conf' must exist."
  echo "  ''"
  echo "TODO"
  echo
  echo "  Options:"
  echo "    -h this help"
#  echo "    -s fail safe model for train-cv.sh  (do not abort on error)."
  echo "    -o <train-cv options> options to transmit to train-cv.sh, e.g. '-c -s'."
  echo "    -r resume previous process"
#  echo "       remark: recomputes generation <num> and following if existing"
  echo "    -P <parallel prefix> TODO"
#  echo "    -f <first gen configs list file> use a list of individual configs"
#  echo "       to initiate the genetic process (reads only the first column"
#  echo "       of the file)"
#  echo "    -e exhaustive generation of configurations for the first generation;"
#  echo "       Can be used with trainingNbGenerations=1 in order to only"
#  echo "       compute the result of a given set of regular configs provided"
#  echo "       instead of the multi-configs (don't forget to set the parameter"
#  echo "       at least in the first config file)."
#  echo "       Warning: do not use if the multi-conf files contain billions"
#  echo "                of possibilities!"
  echo
}



OPTIND=1
while getopts 'hP:o:r' option ; do 
    case $option in
	"h" ) usage
 	      exit 0;;
	"P" ) parallelPrefix="$OPTARG"
              applyMultiConfigsParams="$applyMultiConfigsParams -P \"$parallelPrefix\"";;
        "o" ) constantParams="$constantParams -o \"$OPTARG\"";;
	"r" ) resume=1
              applyMultiConfigsParams="$applyMultiConfigsParams -r"
	      constantParams="$constantParams -r";;
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
outputDir="$1"


dieIfNoSuchDir "$outputDir" "$progName,$LINENO: "
dieIfNoSuchDir "$outputDir/multi-conf-files" "$progName,$LINENO: "
#dieIfNoSuchDir "$outputDir/prepared-data" "$progName,$LINENO: "
dieIfNoSuchFile "$outputDir/meta-template.multi-conf" "$progName,$LINENO: "
dieIfNoSuchFile "$outputDir/resources-options.conf"  "$progName,$LINENO: "


truthFile="$outputDir/input/truth.txt"
dieIfNoSuchFile "$truthFile"  "$progName,$LINENO: "
nbCases=$(cat "$truthFile" | wc -l)

if [ -d "$outputDir/outerCV-folds" ]; then
    if [ $resume -eq 0 ]; then # checking -r was not forgotten by mistake
	echo "$progName: Error: there is already a directory 'outerCV-folds' in '$outputDir'" 1>&2
	echo "$progName: aborting process, remove the directory or use -r to resume an existing process" 1>&2
	exit 4
    else
	echo "$progName: resume mode, using existing outer folds"
    fi
else
    echo "$progName: generating outer folds"
    mkdir "$outputDir/outerCV-folds"
    evalSafe "generate-random-cross-fold-ids.pl $nbFoldsOuterCV $nbCases \"$outputDir/outerCV-folds/fold\"" "$progName,$LINENO: "
    for foldIndexesFile in "$outputDir/outerCV-folds"/fold*.indexes; do
	evalSafe "cat \"$truthFile\" | select-lines-nos.pl \"$foldIndexesFile\" 1 >\"${foldIndexesFile%.indexes}.cases\""  "$progName,$LINENO: "
    done
fi

waitFile=$(mktemp --tmpdir "$progName.main.wait.XXXXXXXXX")
for foldIndexesFile in "$outputDir/outerCV-folds"/*.train.indexes; do
    foldPrefix=${foldIndexesFile%.train.indexes}
    foldId=$(basename "$foldPrefix")
    mkdirSafe "$outputDir/$foldId"
    rm -f "$outputDir/$foldId/best-meta-configs.list"
    # remove symlink prepared-data in case the dir structure has changed, and link back to the (possibly new) good dir/link
    # remark: in the unlikely event that this would be a real dir, it wouldn't be removed because rm -f (no -r)
    rm -f "$outputDir/$foldId/input" "$outputDir/$foldId/resources-options.conf"
    linkAbsolutePath  "$outputDir/$foldId" "$outputDir/input" "$outputDir/resources-options.conf"
    cat "$outputDir/meta-template.multi-conf" >"$outputDir/$foldId/meta-template.multi-conf"
    echo "$progName: calling train-outerCV-1fold.sh for fold $foldId in $outputDir/$foldId"
    rm -f "$outputDir/$foldId/best-meta-configs.list"
    if [ -z "$parallelPrefix" ]; then
	evalSafe "train-outerCV-1fold.sh $constantParams \"$outputDir/$foldId\" \"$foldPrefix.train.cases\" \"$foldPrefix.test.cases\" \"$outputDir/multi-conf-files\"" "$progName,$LINENO: "
    else
	eval "train-outerCV-1fold.sh -P \"$parallelPrefix.${foldId}\" $constantParams \"$outputDir/$foldId\" \"$foldPrefix.train.cases\" \"$foldPrefix.test.cases\" \"$outputDir/multi-conf-files\" >\"$outputDir/$foldId.out\" 2>\"$outputDir/$foldId.err\"" &
    fi
    evalSafe "echo \"$outputDir/$foldId/best-meta-configs.list\" >>\"$waitFile\"" "$progName,$LINENO: "
done
waitFilesList "$progName: main process in progress for '$outputDir'..." "$waitFile" $sleepTime
rm -f  "$waitFile"


echo "$progName: extracting configs and models from both folds (and renaming)"
rm -rf "$outputDir/selected-meta-configs" # to be safe
mkdir "$outputDir/selected-meta-configs"

rm -rf "$outputDir/selected-strategy-configs"
mkdir  "$outputDir/selected-strategy-configs"

rm -rf "$outputDir/apply-strategy-configs"
mkdir  "$outputDir/apply-strategy-configs"

rm -f "$outputDir/selected-meta-prefixes.list"
rm -f "$outputDir/bagging-meta-test-fold-all.stats"
for foldIndexesFile in "$outputDir/outerCV-folds"/*.train.indexes; do
    foldPrefix=${foldIndexesFile%.train.indexes}
    foldId=$(basename "$foldPrefix")
    foldDir="$outputDir/$foldId"

	# 1. copy (and rename) model, including required strategy models
        # 2. link appropriate strategy results for global 'apply-strategy-configs' (using existing ones in order to always use predictions obtained with CV, and not using the model retrained on the whole data)

    cat "$foldDir/best-meta-configs.list" | while read oldMetaPrefix; do
	oldMetaId=$(basename "$oldMetaPrefix")
	newMetaId="$foldId.$oldMetaId"
#	echo "DEBUG newMetaId=$newMetaId" 1>&2
	destMetaPrefix="$outputDir/selected-meta-configs/$newMetaId"
#	echo "DEBUG destMetaPrefix=$destMetaPrefix" 1>&2
	echo "$destMetaPrefix" >>"$outputDir/selected-meta-prefixes.list"
	# remark: normally if it's a strategy config it works: model and conf are copied, conf does not contain any "^indivConf_"
	cp -R "$oldMetaPrefix.model" "$destMetaPrefix.model"
	cat "$oldMetaPrefix.conf" | grep -v "^indivConf_" > "$destMetaPrefix.conf"
	mkdir "$destMetaPrefix.model/strategy-configs"
	cat "$oldMetaPrefix.conf" | grep "^indivConf_.*=1" | sed 's/^indivConf_//g' | sed 's/=1//g' | while read oldStrategyPrefix; do
	    strategyConfNewName="$foldId.$oldStrategyPrefix"
	    destStrategyPrefix="$outputDir/selected-strategy-configs/$strategyConfNewName"
#	    echo "  DEBUG oldStrategyPrefix=$oldStrategyPrefix; strategyConfNewName=$strategyConfNewName; destStrategyPrefix=$destStrategyPrefix" 1>&2
	    echo "indivConf_${strategyConfNewName}=1" >> "$destMetaPrefix.conf" # renamed strategy conf
	    if [ ! -d "$destStrategyPrefix.model" ] || [ ! -f "$destStrategyPrefix.conf" ] || [ ! -f "$outputDir/apply-strategy-configs/$strategyConfNewName.answers" ]; then # several meta-configs can contain the same strategy config
		originalPrefix=$(grep "^$oldStrategyPrefix" "$foldDir/selected-strategy-configs.list" | cut -f 2)
		cp -R "$originalPrefix.model" "$destStrategyPrefix.model"
		cat "$originalPrefix.conf" > "$destStrategyPrefix.conf"
		cat "$foldDir/apply-strategy-configs/$oldStrategyPrefix.answers" > "$outputDir/apply-strategy-configs/$strategyConfNewName.answers"
	    fi
	    # for convenience when extracting the best meta-config later:
	    cp -R  "$destStrategyPrefix.model" "$destMetaPrefix.model/strategy-configs/$strategyConfNewName.model"
	    cp "$destStrategyPrefix.conf" "$destMetaPrefix.model/strategy-configs/$strategyConfNewName.conf"
#	    echo "$strategyConfNewName" >>"$destMetaPrefix.model/strategy-configs.list"
	done
	if [ $? -ne 0 ]; then
	    echo "$progName: bug line $LINENO" 1>&2
	    exit 4
	fi
	# also copy and filter the stats file obtained from meta-test fold, for final perf avg
	echo -en "$destMetaPrefix\t" >>"$outputDir/bagging-meta-test-fold-all.stats"
	grep "$oldMetaPrefix" "$foldDir/bagging-meta-test-fold/runs.stats" | cut -f 2- >>"$outputDir/bagging-meta-test-fold-all.stats"
    done
    if [ $? -ne 0 ]; then
	echo "$progName: bug line $LINENO" 1>&2
	exit 4
    fi


done


# final-final bagging from both folds

baggingDir="$outputDir/final-bagging"
mkdirSafe "$baggingDir"

readFromParamFile "$outputDir/meta-template.multi-conf" "final_bagging_nbRuns" "$progName,$LINENO: "
readFromParamFile "$outputDir/meta-template.multi-conf" "final_bagging_returnNbBest" "$progName,$LINENO: "


resumeParam=""
if [ $resume -ne 0 ]; then
    resumeParam="-r"
fi
evalSafe "apply-bagging.sh $resumeParam -o \"$applyMultiConfigsParams -m $outputDir\" \"$final_bagging_nbRuns\" \"$outputDir/selected-meta-prefixes.list\" \"$truthFile\" \"$baggingDir\"" "$progName,$LINENO: "

# final-final-final selection: average mean perf on meta-test fold (real unseen test set) + all data (all configs applied to the same data and more instances)

cat "$baggingDir/runs.stats" | while read line; do
    name=$(echo "$line" | cut -f 1)
    meanPerfAll=$(echo "$line" | cut -f 2)
    meanPerfMetaTestSet=$(grep "^$name" "$outputDir/bagging-meta-test-fold-all.stats" | cut -f 2)
    avg=$(perl -e " print (($meanPerfAll + $meanPerfMetaTestSet) /2); ")
#    echo "DEBUG: avg( $meanPerfAll , $meanPerfMetaTestSet ) = $avg" 1>&2
    echo -e "$name\t$meanPerfAll\t$meanPerfMetaTestSet\t$avg"
done | sort -r -g +3 -4 >"$outputDir/best.results"
if [ $? -ne 0 ]; then
    echo "$progName: bug line $LINENO" 1>&2
    exit 4
fi

echo "$progName: best meta-config found below, see '$outputDir/best.results' for more details"
head -n 1 "$outputDir/best.results"

echo "$progName: done."
