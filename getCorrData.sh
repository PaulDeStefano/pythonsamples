#!/bin/bash

TopDir="/home/t2k/public_html/post/gpsgroup/ptdata/organizedData/"
recvList="PT00 PT01 TOKA PT04"
pathGrps="GPSData_Internal GPSData_External ND280"
FileList="/tmp/corrDataFileList"
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
    # find all files matching extraRegex
    ( /usr/bin/find ${TopDir}/*/${marker} \
        -type f -name "*day*.dat*" \
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
  local dataTypeList="xPPSOffset pvtGeo csrs-pp"
  for dataType in ${dataTypeList}; do {
    # select files for particular data type
    logMsg "DEBUG: working on data type ${dataType}"
    local tmpFile="${dataType}.tmp${$}"
    local dataFileList=$(grep "${dataType}" ${FileList})
    if [ -z "${dataFileList}" ]; then {
      logMsg "WARNING: couldn't find any data files of type ${dataType} for ${marker}, skipping marker"
      break
    } fi

    # for each file, pull out data and make a single file
    for file in ${dataFileList}; do {
      local basename=$( basename "${file}")
      local dir=$( dirname "${file}")
      logMsg "DEBUG: dir=${dir}"
      logMsg "DEBUG: basename=${basename}"
      
      if [ "${dryrun}" = "yes" ]; then {
        logMsg "NOTICE: dry run, skipping processing"
        continue
      } fi

      # decompress file & store data in temp file
      decompFile "${file}" >> "${tmpFile}"
      local rval="${?}"
      if [ ! ${rval} -eq 0 ]; then {
        logMsg "WARNING: file didn't decompress, continuing assuming it's not compressed"
        # couldn't decompress 
        cat "${file}" >> "${tmpFile}"
      } fi

    } done

    if [ "${dryrun}" = "yes" ]; then {
      logMsg "NOTICE: dry run, skipping processing"
      continue
    } fi

    local tmpFile2="${tmpFile}.2"
    # check for headers
    logMsg "DEBUG: checking for headers"
    local header=$( grep '[a-df-zA-DF-SU-Z]' "${tmpFile}" | uniq )
    local numHeaders=$(echo "${header}"|wc -l)
    if [ ${numHeaders} -gt 1 ]; then {
      logMsg "ERROR: found more than one type of header in file:"
      echo ${header}
      exit 1
    } else {
      # create new file with header
      # this should also execute if there isn't any header

      # disabled headers, for now
      echo "${header}" > "${tmpFile2}"
      :
    } fi

    # sort all data of this type into new file with just one header
    logMsg "DEBUG: sorting file w/o headers"
    eval local finalFile="${finalFileTemplate}"
    cat "${tmpFile}" | grep -v '[a-df-zA-DF-SU-Z]'| sort -k1 -t ',' >> "${tmpFile2}"
    mv "${tmpFile2}" "${finalFile}"
    chgrp tof "${finalFile}"

    logMsg "NOTICE: completed work on data type ${dataType}: ${finalFile}"

    #rm "${tmpFile}" "${tmpFile2}"
    rm "${tmpFile}"
  } done

  if [ "${dryrun}" = "yes" ]; then {
    logMsg "NOTICE: dry run, skipping processing"
    continue
  } fi
  
  # combine files of different data types
  # offset + rxClkBias
  local xPPSandClkBias="${marker}.utc,xPPSOffset,rxClkBias.${dates}.dat"
  logMsg "NOTICE: Combining all data for types xPPSOffset and RxClkBias..."
  join -t ',' -j 1 -o "1.1,1.3,1.2,2.7" "${marker}.xPPSOffset.${dates}.dat" "${marker}.pvtGeo.${dates}.dat" >> "${xPPSandClkBias}"
  logMsg "NOTICE: Combining all data for types xPPSOffset and RxClkBias...done"

  local resultFile="${marker}.utc,xPPSOffset,rxClkBias,rx_clk_ns.${dates}.dat"
  # prefix header line
  echo "#utc_iso8600,unixtime,xPPSOffset,rxClkBias,rx_clk_ns" > "${resultFile}"

  # offset + rxClkBias + rx_clk_ns
  logMsg "NOTICE: Combining all data for types xPPSOffset,RxClkBias and rx_clk_ns..."
  join -t ',' -j 1 -o "1.1,1.2,1.3,1.4,2.2" "${xPPSandClkBias}" "${marker}.csrs-pp.${dates}.dat" >> "${resultFile}"
  logMsg "NOTICE: Combining all data for types xPPSOffset,RxClkBias and rx_clk_ns...done"


  rm "${xPPSandClkBias}"
  for dtype in "${dataTypeList}"; do {
    eval local finalFile="${finalFileTemplate}"
    rm "${finalFile}"
  } done
  rm "${FileList}"
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
