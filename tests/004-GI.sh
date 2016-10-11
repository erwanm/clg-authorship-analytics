#!/bin/bash

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
echo "$0 info: printing scores tables to dir '$scoresDir'"
eval "verif-author.pl $logOpt -p $scoresDir -d tests/data/pan14.impostors tests/004-GI.conf tests/data/english-20-cases/EN001/known01.txt tests/data/english-20-cases/EN001/unknown.txt"

