#!/bin/bash

vocabResources="stop-eng50:tests/data/stop-words/english/50.list;stop-eng200:tests/data/stop-words/english/200.list"
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

workDir=$(mktemp -d)
echo "$0 info: dest dir = '$workDir'"
scoresDir="$workDir/scores-tables"
mkdir "$scoresDir"
echo "$0 info: printing scores tables to dir '$scoresDir'"
cp -R tests/data/english-20-cases "$workDir"

echo "$0: computing pre-similiarties"
ls $workDir/english-20-cases/*/*.txt >$workDir/english-20-cases.list
eval "sim-collections-doc-by-doc.pl $logOpt -R BASENAME  -r '$vocabResources' -o WORD.T.lc1.sl1.mf3 WORD.T.lc1.sl1.mf3 probe:$workDir/english-20-cases.list english:tests/data/pan14.impostors/english"


echo "$0: apply impostors strategy"
for d in "$workDir"/english-20-cases/*/; do 
    echo "$d/known01.txt $d/unknown.txt"
done | eval "verif-author.pl -c -v '$vocabResources' $logOpt -p $scoresDir -d tests/data/pan14.impostors tests/005-multi-GI.conf"

