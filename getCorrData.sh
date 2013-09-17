#!/bin/bash

TopDir="/home/t2k/public_html/post/gpsgroup/ptdata/organizedData/"
recvList="PT00 PT01 TOKA PT04"
#recvList="PT00"
#pathGrps="GPSData_Internal GPSData_External ND280"
FileList="/tmp/corrDataFileList.tmp${$}"
FileNameTemplate='${id}.${typ}.yr${yr}.day${day}'
finalFileTemplate='${marker}.${dataType}.${dates}.dat'
zProg="gzip"
zExt=".gz"
erex=".*"
clobber="yes"
rebuild="no"
dryrun="no"
logLevel=3
tmpFile='getCorrData.tmp${$}'

function logMsg() {
    case "${@}" in 
      DEBUG:* ) [ ${logLevel} -lt 3 ] && return 0 ;;
      NOTICE:* ) [ ${logLevel} -lt 2 ] && return 0 ;;
      WARNING:* ) [ ${logLevel} -lt 1 ] && return 0 ;;
    esac
    echo "$@" 1>&2
}

function findFiles() {
local extraRegex="${1}"
local marker="${2}"
local day="${3}"
logMsg "DEBUG: finding Corrections Data files for marker ${marker}, day NOTYETIMPLIMENTED..."

    if [ ! -d "${TopDir}" ]; then {
      logMsg "ERROR: cannot find top directory ${TopDir}"
      exit 1
    } fi
    # find all files matching extraRegex
    ( /usr/bin/find ${TopDir}/ \
        -type f -name "*${marker}*day*.dat*" \
        2>/dev/null \
        | egrep -i "${extraRegex}" \
        | sort \
    )

}

function decompFile () {
  local file=${1}; shift
  local rval=1
  logMsg "DEBUG: trying to decompress file ${file}"
  if [[ ${file} =~ \.lzo ]]; then {
    lzop -dc ${file}
    rval=0
  } fi
  if [[ ${file} =~ \.gz ]]; then {
    gzip -dc ${file}
    rval=0
  } fi

  return ${rval}
}

function isBestFile() {
  # check file for duplicates, choose most recently procced one (only applies to csrs-pp)
  local file="${1}"
  local daysDone="${2}"
  local thisday="${3}"
  local fList="${4}"
  logMsg "DEBUG: isBestFile: ..."
  #logMsg "DEBUG: isBestFile: file ${file}"
  #logMsg "DEBUG: isBestFile: days done ${daysDone}"
  #logMsg "DEBUG: isBestFile: day ${thisday}"

  local base="$(basename ${file})"
  local dir="$(dirname ${file})"
  local suffix=${file##*day???.}
  local prefix=${file%%.${suffix}}

  # have we done this day before?
  local day=
  for day in ${daysDone}; do {
    if [[ ${day} == ${thisday} ]]; then {
      # already done it
      logMsg "DEBUG: already did day:${thisday}, should skip"
      return 1
    } fi
  } done

  # see how many other files there are for this day.
  local thisDayList=$(echo "${fList}" | grep "${thisday}" 2>/dev/null )
  logMsg "DEBUG: isBestFile: ${thisday} list: ${thisDayList}"

  local wc=$(echo "${thisDayList}"|wc -l)
  logMsg "DEBUG: isBestFile: wc: ${wc}"
  if [ ${wc} -eq 1 ]; then {
    logMsg "DEBUG: isBestFile: only file is best file"
    return 0
  } elif [ ${wc} -gt 1 ]; then {
    logMsg "DEBUG: isBestFile: not the only file..."
    local suffixList=''
    local fname=
    for fname in ${thisDayList}; do {
      local newSuffix=${fname##*.pp}
      #logMsg "DEBUG: isBestFile: building sortable list: newSuffix=${newSuffix}"
      suffixList="${suffixList} ${newSuffix}"
    } done
    #logMsg "DEBUG: isBestFile: suffix list: ${suffixList}"
    local bestSuffix=$( echo ${suffixList} | awk '{print $1}' )
    #logMsg "DEBUG: isBestFile: initial suffix: ${bestSuffix}"
    local suf
    for suf in ${suffixList}; do {
      if [[ $suf > ${bestSuffix} ]]; then {
        bestSuffix=${suf}
        #logMsg "DEBUG: isBestFile: found better suffix: ${bestSuffix}"
      } else {
        #logMsg "DEBUG: isBestFile: comparison failed, no better suffix: ${bestSuffix}"
        :
      } fi
    } done
    logMsg "DEBUG: isBestFile: final best suffix: ${bestSuffix}"

    local ppSuffix=${file##*.pp}
    if [[ ${bestSuffix} == ${ppSuffix} ]]; then {
      return 0
    } fi

  } fi
  return 1
}

function chkUniq() {
  # Make sure that the file doesn't contain duplicates
  local buildFile="${1}"
  local currFile="${2}"
  local prevFile="${3}"
  logMsg "DEBUG: chkUniq..."

  local notUniq=chkUniq1.tmp
  local uniqFile=chkUniq2.tmp
  cat "${buildFile}" | cut -d',' -f1 | egrep -v '^#|[a-df-zA-DF-SU-Z]' | sort > ${notUniq}
  cat "${notUniq}" | uniq > ${uniqFile}

  sumNotUniq=$(cksum ${notUniq} | awk '{print $1}' ) 
  sumUniq=$(cksum ${uniqFile} | awk '{print $1}' ) 
  if [[ ${sumNotUniq} == ${sumUniq} ]]; then {
    : # not different, okay
    rm ${notUniq} ${uniqFile}
    logMsg "DEBUG: chkUniq: okay  ${sumNotUniq} == ${sumUniq}...done"
    return 0
  } else {
    # different, means recently added file contains duplicate
    logMsg "ERROR: current file contains duplicate timestamps"
    logMsg "ERROR: prevFile: ${prevFile}"
    logMsg "ERROR: currFile: ${currFile}"
    diff ${notUniq} ${uniqFile} |head
    exit 1
  } fi

}

function doit() {

  local marker="${1}"
  # find start and end days
  #set $(echo "${dates}" | sed -e 's/-/ /' )
  #startDay=${1}
  #endDay=${2}
  #shift; shift;

  # find files for each day

  # find all files
  findFiles "${erex}" "${marker}" > "${FileList}"

  # for each type of data, gather up the correction data in to a single file
  local dataTypeList="csrs-pp xPPSOffset pvtGeo"
  for dataType in ${dataTypeList}; do {
    # select files for particular data type
    logMsg "DEBUG: working on data type ${dataType}"
    local dataFileList=$(egrep "${dataType}" ${FileList})
    if [ -z "${dataFileList}" ]; then {
      logMsg "WARNING: couldn't find any data files of type ${dataType} for ${marker}, skipping marker"
      return 1
    } fi

    logMsg "DEBUG: all files for ${datatype}: ${dataFileList}"

    local tmpFile="${dataType}.tmp${$}"

    local daysDone=""
    local prevFile=""
    # for each file, pull out data and make a single file
    for file in ${dataFileList}; do {
      local basename=$( basename "${file}")
      local dir=$( dirname "${file}")
      logMsg "DEBUG: dir=${dir}"
      logMsg "DEBUG: basename=${basename}"
      local dayOnFile=$( echo ${basename} | sed 's/.*day\(...\).*/\1/' )
      logMsg "DEBUG: dayOnFile=${dayOnFile}"

      # check to make sure we have the right file
      if [[ ${dataType} == csrs-pp ]]; then {
        isBestFile "${file}" "${daysDone}" "${dayOnFile}" "${dataFileList}"; local isBest=${?}
        if [ ! 0 -eq ${isBest} ]; then {
          logMsg "WARNING: file ${file} is not the best choice, skipping"
          continue
        } fi
      } fi

      daysDone="${daysDone} ${dayOnFile}"
      
      if [ "${dryrun}" = "yes" ]; then {
        logMsg "NOTICE: dry run, skipping processing"
        continue
      } fi

      # decompress file & store data in temp file
      decompFile "${file}" >> "${tmpFile}"
      # check to see if the data has been ruined by duplicate times
      chkUniq "${tmpFile}" "${file}" "${prevFile}"
      local rval="${?}"
      if [ ! ${rval} -eq 0 ]; then {
        logMsg "WARNING: file didn't decompress, continuing assuming it's not compressed"
        # couldn't decompress 
        cat "${file}" >> "${tmpFile}"
      } fi

      prevFile="${file}"
    } done

    local tmpFile2="${tmpFile}.2"
    > "${tmpFile2}"
    # check for headers
#    logMsg "DEBUG: checking for headers"
#    local header=$( egrep '[a-df-zA-DF-SU-Z]' "${tmpFile}" | uniq )
#    local numHeaders=$(echo "${header}"|wc -l)
#    if [ ${numHeaders} -gt 1 ]; then {
#      logMsg "ERROR: found more than one type of header in file:"
#      echo ${header}
#      exit 1
#    } else {
#      # create new file with header
#      # this should also execute if there isn't any header
#
#      # disabled headers, for now
#      #echo "${header}" > "${tmpFile2}"
#      :
#    } fi

    # sort all data of this type into new file with just one header
    logMsg "DEBUG: sorting file w/o headers"
    eval local finalFile="${finalFileTemplate}"
    cat "${tmpFile}" | egrep -v '^#|[a-df-zA-DF-SU-Z]'| sort -t ',' -k1 >> "${tmpFile2}"
    mv "${tmpFile2}" "${finalFile}"
    chgrp tof "${finalFile}"

    logMsg "NOTICE: completed work on data type ${dataType}: ${finalFile}"

    #rm "${tmpFile}" "${tmpFile2}"
    rm "${tmpFile}"
  } done
  # done with filelist
  rm "${FileList}" 

  # combine files of different data types
  # offset + rxClkBias
  local xPPSandClkBias="${marker}.utc,unixtime,xPPSOffset,rxClkBias.${dates}.dat"
  > "${xPPSandClkBias}"
  logMsg "NOTICE: Combining all data for types xPPSOffset and RxClkBias..."
  join --check-order -t ',' -e '' -j 1 -o "1.1,1.3,1.2,2.7" "${marker}.xPPSOffset.${dates}.dat" "${marker}.pvtGeo.${dates}.dat" >> "${xPPSandClkBias}"
  rval=${?}; if [ ! ${rval} -eq 0 ]; then {
    logMsg "WARNING: join failed: code=${rval}, unable to complete first join, skipping others."
    exit 1
  } else {
    logMsg "NOTICE: Combining all data for types xPPSOffset and RxClkBias...done"

    local resultFile="${marker}.utc,unixtime,xPPSOffset,rxClkBias,rx_clk_ns.${dates}.dat"
    > ${resultFile}
    # prefix header line
    #echo "#utc_iso8601,unixtime,xPPSOffset,rxClkBias,rx_clk_ns" > "${resultFile}"

    # offset + rxClkBias + rx_clk_ns
    logMsg "NOTICE: Combining all data for types xPPSOffset,RxClkBias and rx_clk_ns..."
    join --check-order -t ',' -e '' -j 1 -o "1.1,1.2,1.3,1.4,2.2" "${xPPSandClkBias}" "${marker}.csrs-pp.${dates}.dat" >> "${resultFile}"
    rval=${?}; if [ ! ${rval} -eq 0 ]; then {
      logMsg "WARNING: join failed: code=${rval}, unable to complete final join"
      exit 1
    } else {
      logMsg "NOTICE: Combining all data for types xPPSOffset,RxClkBias and rx_clk_ns...done"
    } fi

    sort ${resultFile} > ${resultFile}.tmp
    mv ${resultFile}.tmp ${resultFile}

  } fi

  rm "${xPPSandClkBias}"
  for dataType in ${dataTypeList}; do {
    eval local finalFile="${finalFileTemplate}"
    rm "${finalFile}"
  } done
}

## MAIN ##
renice 20 -p $$ >/dev/null 2>&1

logMsg "DEBUG: checking invocation parameters @=${@}"
while [[ ! -z "${@}" ]]; do {
    logMsg "DEBUG: parameter 1=${1}"
    #logMsg "DEBUG: checking invocation parameters @=${@}"
    opt="${1}"
    shift
    case "${opt}" in 
        dry*|--dry*)           dryrun="yes"; logMsg "DEBUG: DRY-RUN selected";;
        dir*|--dir*)           TopDir="${1}"; logMsg "DEBUG: TopDir=${TopDir}"; shift;;
        lz*|--lz*)             zProg="lzop"; zExt=".lzo"; logMsg "DEBUG: lzo compression selected";;
        gz*|--gz*)             zProg="gzip"; zExt=".gz";  logMsg "DEBUG: gzip compression selected";;
        gz*|--gz*)             zProg="gzip"; zExt=".gz";  logMsg "DEBUG: gzip compression selected";;
        dates|--dates)         dates="${1}"; logMsg "DEBUG: got date ranges";;
        filter|--filter)       erex="${1}"; logMsg "DEBUG: got filter";;
        *)                     dates="${opt}"; logMsg "DEBUG: got dates"; [ ! -z "${1}" ] && erex="${1}" ; shift;;
    esac
    #logMsg "DEBUG: checking invocation parameters 1=${1}"
    #logMsg "DEBUG: checking invocation parameters @=${@}"
} done

# for now, require dates, even though they don't work
if [ -z "${dates}" ]; then {
  logMsg "ERROR: need dates string"
  exit 1
} fi
logMsg "DEBUG: checking invocation parameters...done"

#logMsg DEBUG: $PWD
for marker in ${recvList}; do {
  logMsg "NOTICE: working on receiver marker ${marker}..."
  doit ${marker}
  logMsg "NOTICE: working on receiver marker ${marker}...done"
} done
