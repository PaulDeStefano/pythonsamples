#!/bin/bash

TopDir="/home/t2k/public_html/post/gpsgroup/ptdata/organizedData/"
recvList="PT00 PT01 TOKA PT04"
#recvList="PT00"
#pathGrps="GPSData_Internal GPSData_External ND280"
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
  local fileList="${4}"
  logMsg "DEBUG: isBestFile ..."

  local base="$(basename ${file})"
  local dir="$(dirname ${file})"
  local suffix=${file##*day???}
  local prefix=${file%%${suffix}}

  # have we done this day before?
  if expr "${daysDone}" : ".*${thisday}" >/dev/null 2>&1 ; then {
    # already done it
    logMsg "DEBUG: already did day:${thisday}, should skip"
    return 1
  } fi

  # is it from an external GPS log file?
  if [[ ${base} =~ .+\.ext\..+ ]] ; then {
    # yes, external file, not preffered.
    # is there an internal file for the same day?
    local filesForThisDay=$( echo "${fileList}" | egrep "\.int\..*day${thisday}" 2>/dev/null | sort )
    if [ ! -z "${filesForThisDay}" ]; then {
      # yes, there is at least one internal file for that day
      # what is the best internal file?
      local bestInt=$(echo "${filesForThisDay}" | tail --lines=1 )
      # is that newer than this one?
      local suffixBestInt="${bestInt##*day???.}"
      if [[ ${suffix} < ${suffixBestInt} ]]; then {
        # this file sorts lexically before the best, so no good
        logMsg "DEBUG: isBestFile: ext file suffix:${suffix} < suffix:${suffixBestInt}, skip"
        return 1
      } else {
        # this file sorts lexically after the best internal file, use it!
        logMsg "DEBUG: isBestFile: ext file suffix:${suffix} > suffix:${suffixBestInt}, good!"
        return 0
      } fi

    } fi
    # no, no internal files, which are preferred, cannot exclude
  } fi
  # okay, it must be from an internal GPS log, which is preffered
  # or there isn't another internal file that is prefferred, continue
  # other external-log-based files should get caught below

  local list=$(ls ${prefix}*)
  logMsg "DEBUG: isBestFile: list: ${list}"
  local wc=$(echo "${list}"|wc -l)
  logMsg "DEBUG: isBestFile: wc: ${wc}"
  if [ ${wc} -eq 1 ]; then {
    logMsg "DEBUG: isBestFile: only file is best file"
    return 0
  } elif [ ${wc} -gt 1 ]; then {
    # have to do something
    echo "${list}" | egrep 'pp20......\.dat' >/dev/null 2>&1
    if [ $? -eq 0 ]; then {
      # recent PP files exist, do not use any file without such suffix
      if expr "${file}" : '.*pp20......\.dat' ; then {
        # this file has the suffix, just need to find the find the latest one
        local best=$(ls ${prefix}.pp20* | sort|tail --lines=1 )
        logMsg "DEBUG: isBestFile: best: ${best}"
        if [ "${file}" == "${best}" ]; then {
          logMsg "DEBUG: isBestFile: file is most recent file with pp date"
          return 0
        } fi
      } else {
        # file dosen't have the extension, but such files exist, probably shouldn't use
        logMsg "DEBUG: isBestFile: PP files exists, but this isn't one, ignore"
        :
      } fi
    } else {
      # no PP files exist, must be parts
      ls ${prefix}*part* | egrep part >/dev/null 2>&1
      if [ 0 -eq $? ]; then {
        # found parts
        logMsg "DEBUG: isBestFile: parts files exists, okay"
        return 0
      } else {
        # unkonwn condition
        logMsg "ERROR: isBestFile: unexpected condition"
        exit 1
      } fi
      local suffix=${file}##
    } fi
  } fi
  logMsg "DEBUG: isBestFile: no, done"
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
    return 0
  } else {
    # different, means recently added file contains duplicate
    logMsg "ERROR: current file contains duplicate timestamps"
    logMsg "ERROR: prevFile: ${prevFile}"
    logMsg "ERROR: currFile: ${currFile}"
    diff ${notUniq} ${uniqFile} |head
    exit 1
  } fi
  logMsg "DEBUG: chkUniq..."

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
    local dataFileList=$(egrep "${dataType}" ${FileList})
    if [ -z "${dataFileList}" ]; then {
      logMsg "WARNING: couldn't find any data files of type ${dataType} for ${marker}, skipping marker"
      return 1
    } fi

    local tmpFile="${dataType}.tmp${$}"
    > "${tmpFile}"

    local daysDone=""
    local prevFile=""
    # for each file, pull out data and make a single file
    for file in ${dataFileList}; do {
      local basename=$( basename "${file}")
      local dir=$( dirname "${file}")
      logMsg "DEBUG: dir=${dir}"
      logMsg "DEBUG: basename=${basename}"
      local dayOnFile=$( echo ${basename} | sed 's/.*day\(...\).*/\1/' )

      # check to make sure we have the right file
      isBestFile "${file}" "${daysDone}" "${dayOnFile}" "${dataFileList}"; local isBest=${?}
      if [ ! 0 -eq ${isBest} ]; then {
        logMsg "WARNING: file ${file} is not the best choice, skipping"
        continue
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

    if [ "${dryrun}" = "yes" ]; then {
      logMsg "NOTICE: dry run, skipping processing"
      continue
    } fi

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

  if [ "${dryrun}" = "yes" ]; then {
    logMsg "NOTICE: dry run, skipping processing"
    continue
  } fi
  
  # combine files of different data types
  # offset + rxClkBias
  local xPPSandClkBias="${marker}.utc,unixtime,xPPSOffset,rxClkBias.${dates}.dat"
  > "${xPPSandClkBias}"
  logMsg "NOTICE: Combining all data for types xPPSOffset and RxClkBias..."
  join -t ',' -e '' -j 1 -o "1.1,1.3,1.2,2.7" "${marker}.xPPSOffset.${dates}.dat" "${marker}.pvtGeo.${dates}.dat" >> "${xPPSandClkBias}"
  rval=${?}; if [ ! ${rval} -eq 0 ]; then {
    logMsg "WARNING: join failed: code=${rval}, unable to complete first join, skipping others."
    exit 1
  } else {
    logMsg "NOTICE: Combining all data for types xPPSOffset and RxClkBias...done"

    local resultFile="${marker}.utc,unixtime,xPPSOffset,rxClkBias,rx_clk_ns.${dates}.dat"
    # prefix header line
    #echo "#utc_iso8601,unixtime,xPPSOffset,rxClkBias,rx_clk_ns" > "${resultFile}"

    # offset + rxClkBias + rx_clk_ns
    logMsg "NOTICE: Combining all data for types xPPSOffset,RxClkBias and rx_clk_ns..."
    join -t ',' -e '' -j 1 -o "1.1,1.2,1.3,1.4,2.2" "${xPPSandClkBias}" "${marker}.csrs-pp.${dates}.dat" >> "${resultFile}"
    rval=${?}; if [ ! ${rval} -eq 0 ]; then {
      logMsg "WARNING: join failed: code=${rval}, unable to complete final join"
      exit 1
    } else {
      logMsg "NOTICE: Combining all data for types xPPSOffset,RxClkBias and rx_clk_ns...done"
    } fi
  } fi


  rm "${xPPSandClkBias}"
  for dataType in ${dataTypeList}; do {
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
