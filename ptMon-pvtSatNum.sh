#!/bin/bash
#===============================================================================
#
#          FILE:  ptMon-pvtSatNum.sh
# 
#         USAGE:  ./ptMon-pvtSatNum.sh <outputDir> NU1|Super-K|Trav|ND280 live|daily|weekly
# 
#   DESCRIPTION:  plot raw live DAQ data
# 
#       OPTIONS:  ---
#  REQUIREMENTS:  ---
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR:  Paul R. DeStefano (), paul (dot) destefano (ta)willamettealumni (dot) com.none
#       COMPANY:  
#       VERSION:  1.0
#       CREATED:  04/08/2014 01:43:30 PM PDT
#      REVISION:  ---
#       LICENSE: GPLv3
#
#   Copyright (C) 2014 Paul R. DeStefano
# 
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#===============================================================================

outputDir=${1}
siteName=${2}
cycle=${3}

# force process to run nice
renice 20 -p ${$} >/dev/null

# Mapping from PT site installation names to data directories
commonRoot=/home/t2k/public_html/post/gpsgroup/ptdata/organizedData
typeDir=pvtGeodetic
siteList="NU1:${commonRoot}/${typeDir}/NU1SeptentrioGPS-PT00
Super-K:${commonRoot}/${typeDir}/KenkyutoSeptentrioGPS-PT01
ND280:${commonRoot}/${typeDir}/ND280SeptentrioGPS-TOKA
Trav:${commonRoot}/${typeDir}/TravSeptentrioGPS-PT04
"
daqFileNameExp='*pvtGeo*.dat.*'
daqFileExclude='^ISO'
pltType=pvtGeo
tmpDir=$(mktemp -d '/tmp/ptMon-tmp.XXXXX')
fileList=${tmpDir}/ptMon-filelist.$$
unixTimeColumn=2
dataColumn=9
useCSV="CSV"
loadAvgLimit=11

DEBUG=no
origWD=${PWD}

# clean up working files on interupt or hangup
trap '[[ -d ${tmpDir} ]] && rm -rf "${tmpDir}" ' EXIT 0

function logMsg() {
  # do not print DEBUG messages if DEBUG=no
  [[ ${DEBUG} == no && ${1} =~ ^DEBUG: ]] && return 0
  echo "$@" 1>&2
}

function getLeastFiles()
{
  local fileList=$1       # ordered list of files to check
  local startTime=$2      # oldest value to search for
  local col=$3            # column to check

  logMsg "NOTICE: pruning files..."
  #local tmpFile=${tmpDir}/ptMon-tmp.$$

  local filesToPlot=""
  for daqFile in $( cat ${fileList} ); do {
    # go through each file in reverse chronological order.  Stop on the newest
    # file that preceeds the start time.  Note all files between then and now.

    #local fileStartTime=$( head -n 3 ${daqFile} | tail -n -1 | awk '{print $'${col}'}' )
    local fileStartTime=
    if [ ${useCSV} == "CSV" ]; then {
      fileStartTime=$( head -n 3 ${daqFile} | tail -n 1 | awk -F',' '{print $'${col}'}' )
    } else {
      fileStartTime=$( head -n 3 ${daqFile} | tail -n 1 | awk '{print $'${col}'}' )
    } fi
    logMsg "DEBUG: file start time: ${fileStartTime}"
    if [[ -z ${fileStartTime} ]]; then {
      logMsg "ERROR: cannot find start time in DAQ file: ${daqFile}"; exit 1
    } fi

    # add to list of plot files
    filesToPlot="${filesToPlot} ${daqFile}"

    if [[ ${fileStartTime} -gt ${startTime} ]]; then {
      # all data in file is newer, need more history
      #logMsg "DEBUG: beginning of file is after start time, going for more..."
      :
    } else {
      # start of file is older than we need, stop looking for more history
      #logMsg "DEBUG: ...beginning of file is earlier than start time, done."
      break
    } fi

  } done

  local f2=""
  # empty old file
  > "${fileList}"
  for f2 in ${filesToPlot}; do echo ${f2} >> ${fileList}; done
  #logMsg "DEBUG: new filelist:" $(cat $fileList)

  logMsg "NOTICE: ...done."
}

function getLeastFilesByName()
{
  # reduce files by name conventions
  local fileList=$1       # ordered list of files to check
  local startTime=$2      # oldest value to search for

  local startDay=$(date --date="@${startTime}" +%j)
  local startYear=$(date --date="@${startTime}" +%y)

  local newFileList="${tmpDir}/newList.$$"
  for file in $( cat ${fileList} ); do {
    local fileYear=$( echo "${file}" | sed -r 's/.*yr(..).*/\1/' )
    local fileDay=$( echo "${file}" |  sed -r 's/.*day(..).*/\1/' )
    if expr ${fileDay} '>=' ${startDay} >/dev/null && ${fileYear} -eq ${startYear} ; then {
      echo "${file}" >> "${newFileList}"
    } fi

  } done

}

function getDAQFileList() {
  # file DAQ files for the specified site, store in specified file
  local siteName=$1
  local file=$2

  # dereference site to directory
  local dir=""
  for word in ${siteList}; do {
    if [[ ${word} =~ ^${siteName} ]]; then {
      dir=${word##*:}
      break
    } fi
  } done
  #logMsg "DEBUG: data dir: ${dir}"
  if [ ! -d "${dir}" ]; then {
    logMsg "WARNING: cannot find dir: ${dir}, trying original working dir: ${origWD}"
    dir=${origWD}
  } fi

  # find DAQ files in the directory
  #ls -t $( find ${dir} -name "${daqFileNameExp}" -type f -mtime ${mtimeSpec} ) > ${file}
  find ${dir} -name "${daqFileNameExp}" -type f -mtime ${mtimeSpec} | sort > ${file}
}

function deCompress() {
  # use appropriate utility to un-compress data file
  local fileList=${1}

  # file to replace FileList after decompression
  local newList="${tmpDir}/deCompList"

  for file in $( cat "${fileList}" ); do {

    # assume filename typing
    local base=$(basename ${file})
    local ext="${base##*.}"
    local origName="${base%.${ext}}"
    local outFile="${tmpDir}/${origName}"

    # choose decompression comand
    local cmd=""
    case ${ext} in
      lzo*)       cmd="$(which lzop) -dc ${file}" ;;
      gz*)        cmd="$(which gzip) -dc ${file}" ;;
      zip*)       cmd="$(which zip) -c ${file} ${origName}" ;;
    esac

    logMsg "DEBUG: decompressing: ${file} -> ${outFile} ..."
    eval ${cmd} | egrep -v "${daqFileExclude}" > "${outFile}"
    logMsg "DEBUG: head of file: $(head -n 1 ${outFile})"
    if [ ${?} -ge 1 ]; then logMsg "ERROR: unable to decompress file: ${file}"; exit 1; fi
    logMsg "DEBUG: ...done."

    # store file
    echo "${outFile}" >> "${newList}"

  } done

  mv "${newList}" "${fileList}"

}

function mkPlots()
{
  local mtimeSpec=$1       # find mtime specification
  local startSpec=$2      # date specification
  local endSpec=$3      # date specification
  local site=$4      # date specification

  getDAQFileList "${site}" "${fileList}"
  logMsg "DEBUG: " $(head -n 3 ${fileList})
  if [ -z "$(head -n 1 ${fileList})" ]; then {
    # no files, failure
    logMsg "ERROR: unable to find any ${pltType} files in directory ${dir}, skipping"
    return 1
  } else {
    logMsg "NOTICE: found ${pltType} files."
  } fi

  # get the UNIXtime at the start and end of the target period
  [[ ! -z ${startSpec} ]] && local startTime=$( date --date="${startSpec}" --utc +%s )
  [[ ! -z ${endSpec} ]] && local endTime=$( date --date="${endSpec}" --utc +%s )
  # reduce file list using naming rules
  getLeastFilesByName ${fileList} ${startTime}
  deCompress ${fileList}
  # pair down the list of files by datestamps inside the files
  #getLeastFiles ${fileList} ${startTime} ${unixTimeColumn}
  local filesToPlot=$( cat ${fileList} )

  logMsg "NOTICE: $(date --rfc-3339=seconds): making plots...: ${startSpec} -- ${endSpec}"
  # make datfile from file list
  local datFileName="${tmpDir}/tempDatFile.$$"
  # pick put fields and exclude first line as it is probably header
  cat ${fileList} | xargs -n 1 tail -n +1 | awk -F',' '{print $'${unixTimeColumn}',$'${dataColumn}'}' > ${datFileName}
  logMsg "DEBUG: head+tail of partially rebuilt datafile: $(head -n 3 ${datFileName}; tail -n 3 ${datFileName})"
  # find minimal data by exluding data before and after
  beginLine=$(grep --max-count=2 --line-number "^${startTime}" "${datFileName}" | cut -d':' -f1)
  endLine=$(grep --max-count=2 --line-number "^$((${endTime}-16))" "${datFileName}" | cut -d':' -f1)
  # TODO check to see if more then one number is returned
  if [[ -z "${beginLine}" ]]; then logMsg "ERROR: data doesn't include startTime: ${startTime}"; exit 1; fi
  local newDatFile=${tmpDir}/newDatFile
  # rebuild file
  if [[ -z "${endLine}" ]]; then 
    logMsg "NOTICE: data doensn't include endTime: ${endTime}"; 
    tail -n "+${beginLine}" "${datFileName}" >${newDatFile}
  else
    head -n "${endLine}" | tail -n "+${beginLine}" ${datFileName} >${newDatFile}
  fi
  mv "${newDatFile}" "${datFileName}"
  logMsg "DEBUG: head of rebuilt datafile: $(head -n 3 ${datFileName}; tail -n 3 ${datFileName})"

  #local currTime=$( date --utc --iso-8601=minutes)
  local currTime=$( date --utc )
  local pltTitle="Precise Time GPS Receiver (${site}), Satellites in PVT: ${startSpec} -- ${endSpec} (UTC)\nplot created ${currTime}"
  local style="points pointtype 2 linewidth 1 linecolor 2"
  # run plotter
  local gptCmds=''
  [[ ! -z ${startSpec} ]] && gptCmds=${gptCmds}'startTime="'${startTime}'";'
  [[ ! -z ${endSpec} ]] && gptCmds=${gptCmds}'endTime="'${endTime}'";'
  gptCmds=${gptCmds}'outFile="'${tmpDir}/outfile'";'
  gptCmds=${gptCmds}'pltCmd="1:2";'
  gptCmds=${gptCmds}'pltTitle="'${pltTitle}'";'
  gptCmds=${gptCmds}'fileList="'${datFileName}'";'
  gptCmds=${gptCmds}'styleExt="'${style}'";'
  gptCmds=${gptCmds}'set yrange [ 0 : * ];'
  gptCmds=${gptCmds}'yTitle="Satellites";'
  #gptCmds=${gptCmds}'useCSV="CSV";'
  gptCmds=${gptCmds}'doHist="yes";'
  logMsg "DEBUG: using gnuplot comands: " "${gptCmds}"
  ${pltProg} -e "${gptCmds}" pt-plotgen.gpt
  # add plot type to list
  pltTypeList="${pltTypeList} ."

  # make histogram
  gptCmds=''
  pltTitle="PTGPS (${site}), Sats in PVT: histogram\n ${startSpec} -- ${endSpec} (UTC)"
  gptCmds=${gptCmds}'pltTitle="'${pltTitle}'";'
  #gptCmds=${gptCmds}'datCol=1;'
  gptCmds=${gptCmds}'datFile="'${datFileName}'";'
  gptCmds=${gptCmds}'outFile="'${tmpDir}/outfile.hist'";'
  gptCmds=${gptCmds}'Min=0;'
  gptCmds=${gptCmds}'Max=30;'
  gptCmds=${gptCmds}'n=30;'
  #gptCmds=${gptCmds}'useStats="yes";'
  logMsg "NOTICE: making histograms: ${pltTitle}"
  logMsg "DEBUG: using gnuplot comands: " "${gptCmds}"
  ${pltProg} -e "${gptCmds}" pt-histgen.gpt
  # add histogram to list
  pltTypeList="${pltTypeList} .hist."

  ## clean up
  rm ${fileList}
  logMsg "NOTICE: $(date --rfc-3339=seconds): ...done"
}

function storeResults() {
  # Move files to final locations
  timeRange=${1}
    for filePltType in ${pltTypeList}; do
      moveFile="outfile${filePltType}png"
      if [[ ! -r "${tmpDir}/${moveFile}" ]]; then logMsg "WARNING: cannot find file to move, skipping: ${moveFile}"; continue; fi
      destFile="ptMon.${siteName}.${pltType}.${timeRange}${filePltType}png"
      mv "${tmpDir}/${moveFile}" "${outputDir}/${destFile}"
    done
}

function mk48h() {
  pltTypeList=
  mkPlots "-3" "00:00 2 days ago" "00:00 today" "${siteName}"
  storeResults "48hours"
}

function mk7day() {
  pltTypeList=
  mkPlots "-8" "00:00 7 days ago" "00:00 today" "${siteName}"
  storeResults "8days"
}

function mk30day() {
  pltTypeList=
  mkPlots "-31" "00:00 30 days ago" "00:00 today" "${siteName}"
  storeResults "30days"
}

## MAIN ##

# Configuration && Checks
set -e
if [ -z "${cycle}" ]; then logMsg "ERROR: third parameter, cycle, required but missing."; exit 1; fi
if [ -z "${siteName}" ]; then logMsg "ERROR: second parameter, site name, required but missing."; exit 1; fi
if [ -z "${outputDir}" ]; then logMsg "ERROR: first parameter, output directory, required but missing."; exit 1; fi
if [ ! -d "${outputDir}" ]; then logMsg "ERROR: cannot find output directory: ${outputDir}"; exit 1; fi
pltProg="$(which gnuplot)"
if [ ! -e ${pltProg} ]; then logMsg "ERROR: cannot find gnuplot in PATH"; exit 1; fi

if [[ -z "${GNUPLOT_LIB}" ]]; then
  #GNUPLOT_LIB=${GNUPLOT_LIB}:/home/t2k/ptgps-processing/scripts/pythonsamples/gnuplot.d; export GNUPLOT_LIB
  GNUPLOT_LIB=/home/t2k/ptgps-processing/scripts/pythonsamples/gnuplot.d; export GNUPLOT_LIB
  logMsg "WARNING: GNUPLOT_LIB not set, using default: ${GNUPLOT_LIB}"
else
  for path in $(echo ${GNUPLOT_LIB}|tr : ' ' ); do
    if find ${path} -maxdepth 1 pt-plotgen.gpt >/dev/null 2>/dev/null; then
      gnuPlotPathOK=yes
    fi
  done
  if [[ ! -z ${gnuPlotPathOK} ]]; then logMsg "ERROR: cannot find pt-plotgen.gpt in GNUPLOT_LIB path."; exit 1; fi
fi

loadAvg=$(uptime | awk '{print $(NF-2)}' |sed 's/,//')
if echo ${loadAvg} ${loadAvgLimit} | awk 'END { exit ( ! ($1 >= $2) ) }' ; then {
  # load average is too high
  logMsg "ERROR: load average is too high: ${loadAvg} >= ${loadAvgLimit}: aborting"
  exit 1
} fi

TZ=UTC; export TZ

set +e
case "${cycle}" in
  live|--live)        shift; mk48h ;;

  da*|--da*)          shift; mk48h; mk7day ;;

  week*|--week*)      shift; mk48h; mk7day; mk30day ;;
esac
