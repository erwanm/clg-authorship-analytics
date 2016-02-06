#!/bin/bash


if [ $# -eq 1 ]; then
    logOpt="-l $1"
    echo "$0 info: logging level = $1"
else
    echo "$0 info: no logging"
fi
eval "verif-author.pl $logOpt tests/004-GI.conf tests/data/english-20-cases/EN001/known01.txt tests/data/english-20-cases/EN001/unknown.txt"

