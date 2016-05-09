#!/bin/bash

# EM April 14

source common-lib.sh
source file-lib.sh


#
# tests only if file exists with -e; file can be a directory
#
function countExistingFilesFromList {
    local list="$1"
    
    cat "$list" | while read f; do
	if [ -e "$f" ]; then
#		nb=$(( $nb + 1 )) # pbm: subprocess -> nb=0 outside
	    echo "1"
	fi
    done | wc -l
}

#
# tests only if file exists with -e; file can be a directory
#
function waitFilesList {
    local msg="$1"
    local listFile="$2"
    local sleepTime="$3"
    local removeListFile="$4" # if not empty, listFile is deleted at the end

    total=$(cat "$listFile" | wc -l)
    nb=$(countExistingFilesFromList "$listFile")
#    echo "DEBUG pan-utils, waitFilesList: listFile=$listFile; total=$total; nb=$nb" 1>&2
    while [ $nb -lt $total ]; do
	if [ ! -z "$msg" ]; then
            now=$(date +"%Y-%m-%d %H:%M")
	    echo "$msg $now: $nb/$total done"
	fi
	echo
	sleep $sleepTime
	nb=$(countExistingFilesFromList "$listFile")
    done
    if [ ! -z "$removeListFile" ]; then
	rm -f "$listFile"
    fi
}




#
# inputDir contains the <input> subdir
# writes two columns
#
function generateTruthCasesFile {
    local inputDir="$1"
    local targetCasesFile="$2"
    local officialFormatAndSorted="$3" # 0 or 1
    local selectLinesCommandWithPipe="$4" # optional
    local truthFile="$5" # optional; if not defined, uses the official truth file with Y/N and all cases

    if [ -z "$truthFile" ]; then
	truthFile=$(ls "$inputDir"/input/truth.txt | head -n 1)
	if [ -z "$truthFile" ]; then
	    echo "$progName error: could not find any file 'truth.txt' in $inputDir/input/*/data/truth.txt" 1>&2
	    exit 1
	fi
    else
	dieIfNoSuchFile "$truthFile" "$progName,$LINENO (pan-utils.sh): "
    fi
    # sed used to remove the (possible) BOM marker
    if [ $officialFormatAndSorted -ne 0 ]; then # sorted for CV evaluation + space sep and Y/N for official eval script
#	echo "DEBUG generateTruthCasesFile: 'cat \"$truthFile\" | sed 's/^\xEF\xBB\xBF//'  $selectLinesCommandWithPipe  | sort +0 -1 >\"$targetCasesFile\"'" 1>&2
	evalSafe "cat \"$truthFile\" | tr -d '\r' | sed 's/^\xEF\xBB\xBF//'  $selectLinesCommandWithPipe  | sort +0 -1 >\"$targetCasesFile\""  "$progName: "
    else # replace Y/N with 1/0 only in the 2nd col
	tmp1=$(mktemp --tmpdir "tmp.pan-utils.sh.generateTruthCasesFile1.XXXXXXXXX")
	tmp2=$(mktemp --tmpdir "tmp.pan-utils.sh.generateTruthCasesFile2.XXXXXXXXX")
#	echo "DEBUG generateTruthCasesFile: 'cat \"$truthFile\" | sed 's/^\xEF\xBB\xBF//'  $selectLinesCommandWithPipe | cut -d \" \" -f 1 >\"$tmp1\"'" 1>&2
	evalSafe "cat \"$truthFile\" | tr -d '\r' | sed 's/^\xEF\xBB\xBF//'  $selectLinesCommandWithPipe | cut -d \" \" -f 1 >\"$tmp1\"" "$progName: "
	evalSafe "cat \"$truthFile\" | tr -d '\r' | sed 's/^\xEF\xBB\xBF//'  $selectLinesCommandWithPipe | cut -d \" \" -f 2 | tr YN 10 >\"$tmp2\"" "$progName: "
	evalSafe "paste \"$tmp1\" \"$tmp2\" > \"$targetCasesFile\"" "$progName: "
	rm -f "$tmp1" "$tmp2"
    fi
}


#
# inputDir is prepared-data/<prepa-param> (contains the data directly)
# writes 1 column
#
function generateTestCasesFile {
    local inputDir="$1"
    local targetCasesFile="$2"
    for caseDir in "$inputDir"/*; do
	if [ -f "$caseDir/unknown.txt" ]; then # check that this is a case dir
	    echo $(basename "$caseDir")
	fi
    done >"$targetCasesFile"
}


# OBSOLETE???
#
# input: list of obs types as multiple arguments (space separated)
#
function requiresPOSTags {
    while [ ! -z "$1" ]; do
        local obsType="$1"
	local isPOS=$(echo "$obsType" | grep "^POS")
#	echo "DEBUG: obs type = '$obsType', isPOS='$isPOS'" 1>&2
#        local containsOnlyPTS=$(echo "$obsType" | tr -d "PTS")
        if [ ! -z "$isPOS" ]; then
            return 1
        fi
        shift
    done
    return 0
}



#
# reads from STDIN
# echoes space separated string
#
function extractPossibleObsTypes {
    local prefix="${1:-obsType.}"
 #   echo "DEBUG prefix='$prefix'" 1>&2
    local res=$(
    while read file; do
#	echo "DEBUG file='$file'" 1>&2
	grep "^$prefix" "$file" |  while read line; do
#	    echo "DEBUG grep line='$line'" 1>&2
	    local obsType=${line#$prefix}
	    local values=${obsType#*=}
	    memberList "1" "$values"
	    if [ $? -eq 0 ]; then # 1 in possible values => possible type
		obsType=${obsType%=*}
		echo "$obsType"
	    fi
	done 
    done | sort -u | tr '\n' ' ')
 #   echo "DEBUG extractPossibleObsTypes done" 1>&2
    echo ${res% } # remove trailing space
    return 0
}




function listDocFiles {
    local dir="$1"

    # probably not the best way to get txt files but not directories
    find "$dir" -name "*.txt" | grep -v "truth.txt" | while read entry; do
	if [ -f "$entry" ]; then
	    echo "$entry"
	fi
    done
}


# reads a list of multi-config filenames from STDIN, extracts <paramName> value
# and returns the max of these values
function getMaxParamConfigFiles {
    local paramName="$1"
    maxVal=""
    while read paramFile; do
	readFromParamFile "$paramFile" "$paramName" "$progName,$LINENO: "
	eval "values=$(echo \$$paramName)"
	for v in $values; do
	    if [ -z "$maxVal" ] || [ $v -gt $maxVal ]; then
		maxVal=$v
	    fi
	done
    done
    echo "$maxVal"
}


# NEVER TESTED (OR USED)
# reads a list of multi-config filenames in $listParamsFilesFile, extracts <paramName> value
# and returns any common value defined in all multi-sets, or empty otherwise
function getCommonParamConfigFiles {
    local paramName="$1"
    local listParamsFilesFile="$2"
    
    paramFile=$(head -n 1 "$listParamsFilesFile")
    readFromParamFile "$paramFile" "$paramName" "$progName,$LINENO: "
    eval "values0=$(echo \$$paramName)"
    for val in $values0; do
	common=1
	for paramFile in $(cat "$listParamsFilesFile"); do
	    readFromParamFile "$paramFile" "$paramName" "$progName,$LINENO: "
	    eval "values=$(echo \$$paramName)"
	    member "$val" "$values"
	    if [ $? -ne 0 ]; then
		common=0
		break
	    fi
	done
	if [ $common -eq 1 ]; then
	    echo "$common"
	    break
	fi
    done
}


function checkResourcesDir {
    local dir="$1"
    local msg="$2"

    dieIfNoSuchDir "$dir" "$msg"
    dieIfNoSuchDir "$dir/reference" "$msg"
    dieIfNoSuchDir "$dir/stop-words" "$msg"
    dieIfNoSuchDir "$dir/impostors-data" "$msg"

}
