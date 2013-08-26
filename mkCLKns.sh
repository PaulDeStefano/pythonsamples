#!/bin/bash


csrsTopDir="/home/t2k/public_html/post/gpsgroup/ptdata/organizedData/csrs-pp"
recvList="PT00 PT01 TOKA PT04"
pathGrps="GPSData_Internal GPSData_External ND280"
csrsFileList="/tmp/csrsFileList"
#csrsFileName='csrs-pp.${id}.${typ}.yr${yr}.day${day}.part${part}.dat'
csrsFileName='csrs-pp.${id}.${typ}.yr${yr}.day${day}.dat'
zProg="gzip"
zExt=".gz"
erex=".zip"
clobber="yes"
rebuild="no"
dryrun="no"
logLevel=3
tmpFile='${posFile}.tmp${$}'

function logMsg() {
    case "${@}" in 
      DEBUG:* ) [ ${logLevel} -lt 3 ] && return 0 ;;
      NOTICE:* ) [ ${logLevel} -lt 2 ] && return 0 ;;
      WARNING:* ) [ ${logLevel} -lt 1 ] && return 0 ;;
    esac
    echo "$@" 1>&2
}

function getCSRS() {
logMsg "NOTICE: finding CSRS files..."
extraRegex="${1}"
    # find CSRS PPP zip files
    ( /usr/bin/find ${csrsTopDir} \
        -type f -iwholename "*.zip" \
        2>/dev/null \
        | egrep -i "${extraRegex}" \
        | sort \
    )

}

function doit() {

  getCSRS "${erex}" > "${csrsFileList}"
  while read file; do {
    logMsg "NOTICE: working on csrs file: ${file}"
    local dir=$( dirname "${file}" )
    logMsg "DEBUG: dir=${dir}"
    local typ="int"
    [[ ${dir} =~ External ]] && typ="ext"
    local tgtFileGlob='*.pos'
    local posFile=$( zipinfo "${file}" "${tgtFileGlob}" 2>/dev/null | awk '{print $NF}' )
    eval local tmp="${tmpFile}"
    logMsg "DEBUG: extrating data from file: ${posFile}"
    logMsg "DEBUG: extrating data to tempfile: ${tmp}"
    if [ "no" = "${dryrun}" ]; then {
      unzip "${file}" "${tgtFileGlob}"
      tail --lines=+9 ${posFile} | awk 'BEGIN{print "utc,rx_clk_ns"};{utc=substr($5"T"$6,1,19); print utc","$14}' > "${tmp}"
      local yr=$(head --lines=2 "${tmp}" |tail --lines=1 | cut -c1-4)
      local id=$(echo "${tmp}" | cut -c1-4 | tr '[:lower:]' '[:upper:]' )
      local day=$(echo "${tmp}" | cut -c5-7)
      #local part=$(echo "${posFile}" | cut -c8)
      eval local destFile="${dir}/${csrsFileName}"
      logMsg "DEBUG: output file to ${destFile}${zExt}"
      "${zProg}" -c "${tmp}" > "${tmp}${zExt}"
      chgrp tof "${tmp}${zExt}"
      mv "${tmp}${zExt}" "${destFile}${zExt}"

      rm "${tmp}"
      rm "${posFile}"
    } fi

  } done < "${csrsFileList}"

  rm "${csrsFileList}"

}

## MAIN ##

logMsg "DEBUG: checking invocation parameters @=${@}"
while [[ ! -z "${@}" ]]; do {
    logMsg "DEBUG: parameter 1=${1}"
    #logMsg "DEBUG: checking invocation parameters @=${@}"
    opt="${1}"
    shift
    case "${opt}" in 
        dry*|--dry* )           dryrun="yes"; logMsg "DEBUG: DRY-RUN selected";;
        dir*|--dir* )           csrsTopDir="${1}"; logMsg "DEBUG: csrsTopDir=${csrsTopDir}"; shift;;
        lz*|--lz* )             zProg="lzop"; zExt=".lzo"; logMsg "DEBUG: lzo compression selected";;
        gz*|--gz* )             zProg="gzip"; zExt=".gz";  logMsg "DEBUG: gzip compression selected";;
        *)                      erex=${opt}; logMsg "DEBUG: RegEx=${erex}"; shift;;
    esac
    #logMsg "DEBUG: checking invocation parameters 1=${1}"
    #logMsg "DEBUG: checking invocation parameters @=${@}"
} done
logMsg "DEBUG: checking invocation parameters...done"

renice 20 -p $$ >/dev/null 2>&1

set -e 
#logMsg DEBUG: $PWD
doit
