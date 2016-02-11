#!/bin/bash


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
eval "verif-author.pl $logOpt -d tests/data/pan14.impostors tests/004-GI.conf tests/data/english-20-cases/EN001/known01.txt tests/data/english-20-cases/EN001/unknown.txt"

