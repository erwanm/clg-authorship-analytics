#!/bin/bash

source common-lib.sh

mcFile=""
inputData="tests/data/english-20-cases/"
vocabResources="stop-eng50=tests/data/stop-words/english/50.list;stop-eng200=tests/data/stop-words/english/200.list"
resourcesOptionsFilename="resources-options.conf"
useCountFiles=1
datasetResourcesPath="tests/data/pan14.impostors"
resourcesAccess=rw


if [ $# -eq 1 ]; then
    if [ -f "$1" ]; then
	logOpt="-l $1"
	echo "$0 info: logging config file = $1"
    else
	logOpt="-l $1"
	echo "$0 info: logging level = $1"
    fi
else
    echo "$0 info: no logging"
fi


targetDir=$(mktemp -d --tmpdir "007-genetic-basic.XXXXXX")
echo "$0 info: target dir = $targetDir"
inputDataDir=$(fullPathDir "$inputData")

pushd $targetDir >/dev/null
ln -s  "$inputDataDir" input
popd >/dev/null

# generating multi-config
evalSafe "generate-multi-conf.sh -s basic -c common.TEST.multi-conf.part -g genetic.TEST.multi-conf.part 1 '$targetDir'"

# writing resources options file
echo >"$targetDir/$resourcesOptionsFilename"
echo "vocabResources=$vocabResources" >>"$targetDir/$resourcesOptionsFilename"
echo "useCountFiles=$useCountFiles" >>"$targetDir/$resourcesOptionsFilename"
echo "datasetResourcesPath=$datasetResourcesPath" >>"$targetDir/$resourcesOptionsFilename"
echo "resourcesAccess=$resourcesAccess" >>"$targetDir/$resourcesOptionsFilename"

# run
evalSafe "ls '$targetDir'/multi-conf-files/*.multi-conf |  train-genetic.sh '$targetDir' '$targetDir/input/truth.txt' indivGenetic_1_"


