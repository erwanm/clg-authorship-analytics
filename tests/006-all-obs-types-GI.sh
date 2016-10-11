#!/bin/bash

vocabResources="stop-eng50:tests/data/stop-words/english/50.list;stop-eng200:tests/data/stop-words/english/200.list"
scoresDir="/tmp/scores-tables"
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
if [ ! -d "$scoresDir" ]; then
    mkdir "$scoresDir"
    if [ $? -ne 0 ]; then
	echo "Error cannot create dir '$scoresDir'" 1>&2
    fi
fi
eval "verif-author.pl -v '$vocabResources' $logOpt -p $scoresDir -d tests/data/pan14.impostors tests/005-multi-GI.conf tests/data/english-20-cases/EN001/known01.txt tests/data/english-20-cases/EN001/unknown.txt"

