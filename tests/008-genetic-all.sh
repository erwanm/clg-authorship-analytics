#!/bin/bash


#
# IMPORTANT: this script runs the genetic process for all the strategies without the
#            '-s' (failsafe) option. As a consequence, any error causes the program
#            to fail. It is sometimes normal that a particular run of a strategy fails
#            due to a particular randomization of the data, which is why there is a 
#            failsafe mode. The failsafe mode makes the main process continue and
#            ignore a failed run in the genetic process.
#
#

source common-lib.sh
source file-lib.sh

progName="008-genetic-all.sh"

mcFile=""
inputData="tests/data/english-20-cases/"
vocabResources="50:tests/data/stop-words/english/50.list;200:tests/data/stop-words/english/200.list"
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


targetDir=$(mktemp -d --tmpdir "$progName.XXXXXX")
echo "$0 info: target dir = $targetDir"

inputDataDir=$(absolutePath "$inputData")
pushd "$targetDir" >/dev/null
ln -s "$inputDataDir" input
popd >/dev/null


# generating multi-config
evalSafe "generate-multi-conf.sh -c common.std.multi-conf.part -g genetic.TEST.multi-conf.part 1 '$targetDir/'" "$progName, $LINENO: "
rm -f "$targetDir/meta-template.multi-conf"
cp "conf/meta-template.TEST.multi-conf" "$targetDir/meta-template.multi-conf"
dieIfNoSuchFile "$targetDir/multi-conf-files/basic.multi-conf" "$progName, $LINENO: "
dieIfNoSuchFile "$targetDir/meta-template.multi-conf" "$progName, $LINENO: "


# writing resources options file
echo >"$targetDir/$resourcesOptionsFilename"
echo "vocabResources=$vocabResources" >>"$targetDir/$resourcesOptionsFilename"
echo "useCountFiles=$useCountFiles" >>"$targetDir/$resourcesOptionsFilename"
echo "datasetResourcesPath=$datasetResourcesPath" >>"$targetDir/$resourcesOptionsFilename"
echo "resourcesAccess=$resourcesAccess" >>"$targetDir/$resourcesOptionsFilename"

# run
evalSafe "train-top-level.sh '$targetDir'" "$progName, $LINENO: "


