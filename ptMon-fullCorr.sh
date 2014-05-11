#!/bin/bash
#===============================================================================
#
#          FILE:  ptMon-fullCorr.sh
# 
#         USAGE:  ./ptMon-fullCorr.sh <outputDir> NU1|Super-K|ND280 daily|weekly
# 
#   DESCRIPTION:  plot fully corrected OT-PT times (w/ post-processing)
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
pltType=pt-ot
commonRoot=/home/t2k/public_html/post/gpsgroup/ptdata/organizedData
typeDir=csrs-pp
siteList="NU1:NU1SeptentrioGPS-PT00
Super-K:KenkyutoSeptentrioGPS-PT01
ND280:ND280SeptentrioGPS-TOKA
Trav:TravSeptentrioGPS-PT04
"

dataTypeList=('xpps' 'sttnClk' 'daq')
# xPPSOffset data
FileNameExp['xpps']='*xppsoffset*.int.*.dat.*'
FileExclude['xpps']='^ISO'
FileHeaderLen['xpps']=1
unixTimeColumn['xpps']=3
dataColumn['xpps']=2
useCSV['xpps']="CSV"
# station clock offset (sttnClk_ns) data
FileNameExp['sttnClk']='*{csrs,inhouse}-pp.*.int.*.tar.gz'
FileExclude['sttnClk']='^FWD'
FileHeaderLen['sttnClk']=8
unixTimeColumn['sttnClk']=3
dataColumn['sttnClk']=2
useCSV['sttnClk']="no"
# raw TIC data
FileNameExp['daq']='*OT-PT*.dat.*'
FileExclude['daq']=
FileHeaderLen['daq']=0
unixTimeColumn['daq']=3
dataColumn['daq']=2
useCSV['daq']="no"

tmpDir=$(mktemp -d '/tmp/ptMon-tmp.XXXXX')
fileList=${tmpDir}/ptMon-filelist.$$
loadAvgLimit=11

DEBUG=yes
origWD=${PWD}

# clean up working files on interupt or hangup
trap '[[ -d ${tmpDir} ]] && rm -rf "${tmpDir}"' EXIT 0

function logMsg() {
  # do not print DEBUG messages if DEBUG=no
  [[ ${DEBUG} == no && ${1} =~ ^DEBUG: ]] && return 0
  echo "$@" 1>&2
}

function siteNameToDir() {
  local retVar="${1}"
  local siteName="${2}"

  for word in ${siteList}; do {
    if [[ ${word} =~ ^${siteName} ]]; then {
      dir=${word##*:}
      break
    } fi
  } done

  logMsg "DEBUG: found directory: site=${siteName},dir=${dir}"
  eval "$retVar=\${dir}"
}

function siteNameToMarker() {
  local retVar="${1}"
  local siteName="${2}"

  local dir=
  siteNameToDir dir "${siteName}"
  local len=${#marker}
  local indx=$((${len} - 4))
  local marker="${dir:$indx:4}"
  logMsg "DEBUG: found marker name: site=${siteName},marker=${marker}"
  eval "$retVar=\${marker}"
}

function getLeastFiles()
{
  local fileList=$1       # list of files to check
  local startTime=$2      # oldest UNIXtime  to search for
  local endTime=$3      # newest UNIXtime to search for
  local col=$4            # column to check

  logMsg "NOTICE: pruning files..."
  #local tmpFile=${tmpDir}/ptMon-tmp.$$

  local filesToPlot=""
  for daqFile in $( cat ${fileList} ); do {
    # go each file.  pick only files that contain useful data

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
    local fileEndTime=
    if [ ${useCSV} == "CSV" ]; then {
      fileEndTime=$( tail -n 1 ${daqFile} | awk -F',' '{print $'${col}'}' )
    } else {
    fileEndTime=$( tail -n 1 ${daqFile} | awk '{print $'${col}'}' )
    } fi
    logMsg "DEBUG: file end time: ${fileEndTime}"
    if [[ -z ${fileEndTime} ]]; then {
      logMsg "ERROR: cannot find start time in DAQ file: ${daqFile}"; exit 1
    } fi

    if [[ ${fileStartTime} -gt ${endTime} ]]; then {
      # exclude file, too new
      continue
    } fi
    if [[ ${fileEndTime} -lt ${startTime} ]]; then {
      # exclde file, too old
      continue
    } fi
    
    # okay, add to list of plot files
    filesToPlot="${filesToPlot} ${daqFile}"
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
    logMsg "DEBUG: getLeastFilesByName: fileYear=${fileYear} fileDay=${fileDay}"
    if expr ${fileDay} '>=' ${startDay} >/dev/null && ${fileYear} -eq ${startYear} ; then {
      echo "${file}" >> "${newFileList}"
      logMsg "DEBUG: getLeastFilesByName: including file: ${file}"
    } fi

  } done

}

function getDAQFileList() {
  # file DAQ files for the specified site, store in specified file
  local siteName=$1
  local file=$2

  # dereference site to directory
  local dir=""
  siteNameToDir dir "${siteName}"
  logMsg "DEBUG: data dir: ${dir}"
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

function getDAQfiles() {
  getDAQFileList "${site}" "${fileList}"
  #logMsg "DEBUG: " $(head -n 3 ${fileList})
  if [ -z "$(head -n 1 ${fileList})" ]; then {
    # no files, failure
    logMsg "ERROR: unable to find any ${pltType} files in directory ${dir}, skipping"
    return 1
  } else {
    logMsg "NOTICE: found files for plotting ${pltType}."
  } fi
}

function mkPlotsFromFile()
{
  local fileList="$1"     # list of files to plot or label names
  local startSpec="$2"    # date specification
  local endSpec="$3"      # date specification
  local pltTitle="$4"     # title
  local xCol=$5           # column number for x
  local yCol=$6           # column number for y
  local styleSpec="$7"        # gnuplot style specification
  local useCSV="$8"       # 'CSV' means yes, tell gnuplot to assume CSV data files
  local listIsLabels="$9"     # 'yes' means plot muitple curves in one plot,
                              # each curve comes from a separate datafile assumed to 
                              # be named <name>.dat where <name> is the list of whitespace
                              # separated values in the string ${fileList}

  [[ ! -z ${startSpec} ]] && local startTime=$( date --date="${startSpec}" --utc +%s )
  [[ ! -z ${endSpec} ]] && local endTime=$( date --date="${endSpec}" --utc +%s )

  local filesToPlot=
  local style=
  if [ -z "${styleSpec}" ]; then 
    style="points pointtype 1 linewidth 2 linecolor 3"
  else
    style="${styleSpec}"
  fi
  # run plotter
  local gptCmds=''
  [[ ! -z ${startSpec} ]] && gptCmds=${gptCmds}'startTime="'${startTime}'";'
  [[ ! -z ${endSpec} ]] && gptCmds=${gptCmds}'endTime="'${endTime}'";'
  if [[ yes == ${listIsLabels} ]] ; then
    gptCmds=${gptCmds}'labelList="'${fileList}'";'
  else
    if [ -f "${fileList}" ]; then
      # assume fileList is a file containing names of files to plot
      filesToPlot=$(cat ${fileList})
    else
      filesToPlot="${fileList}"
    fi
    gptCmds=${gptCmds}'fileList="'${filesToPlot}'";'
  fi
  gptCmds=${gptCmds}'outFile="'${tmpDir}/outfile'";'
  gptCmds=${gptCmds}'pltCmd="'${xCol}':'${yCol}'";'
  gptCmds=${gptCmds}'pltTitle="'${pltTitle}'";'
  gptCmds=${gptCmds}'styleExt="'${style}'";'
  gptCmds=${gptCmds}'useCSV="'${useCSV}'";'
  logMsg "DEBUG: using gnuplot comands: " "${gptCmds}"
  logMsg "NOTICE: $(date --rfc-3339=seconds): making plots...: ${pltTitle}"
  ${pltProg} -e "${gptCmds}" pt-plotgen.gpt

  logMsg "NOTICE: $(date --rfc-3339=seconds): ...done"
}

function storeResults() {
  # Move files to final locations
  timeRange=${1}
    for filePltType in ${pltTypeList}; do
      moveFile="outfile.${filePltType}.png"
      if [[ ! -r "${tmpDir}/${moveFile}" ]]; then logMsg "WARNING: cannot find file to move, skipping: ${moveFile}"; continue; fi
      destFile="ptMon.${siteName}.${filePltType}.${timeRange}.png"
      mv "${tmpDir}/${moveFile}" "${outputDir}/${destFile}"
    done
}

function findFiles() {
  local findDir="${1}"
  local startSpec="${2}"
  local endSpec="${3}"
  local findOpts="${4}"
  local grepFilter="${5}"
  local sortOpt="${6}"

# convert time specs to UNIX time and reference files for 'find'
  local UNIXstart=$(date --date="${startSpec}" +%s)
  local UNIXend=$(date --date="${startSpec}" +%s)
  touch --date="@${UNIXstart}" "startTimeFile"
  touch --date="@${UNIXend}" "endTimeFile"

# Use find first
  find "${findDir}" -newer startTimeFile -a ! -newer endTimeFile ${findOpts} | \
  egrep "${grepFilter}" | \
  sort "${sortOpt}"
}

function timeSpecToDayAndYearNums() {
  local retDay_A="${1}"
  local retYr_A="${2}"
  local startSpec="${3}"
  local endSpec="${4}"

  local first=$(date --date="${startSpec}" +%j)
  local firstYear=$(date --date="${startSpec}" +%Y)
  local last=$(date --date="${endSpec}" +%j)
  local nums=${first} day= years=${firstYear} yr= i=0
  while [ ! "${last}" = "${day}" ]; do
    ((i++))
    day=$(date --date="${startSpec} + $i days" +%j)
    yr=$(date --date="${startSpec} + $i days" +%Y)
    nums="${nums} ${day}"
    years="${years} ${yr}"
    #break #DEBUG
  done

  logMsg "DEBUG: timeSpecToDayAndYearNums: got day numbers: first=${first},last=${last},nums=" ${nums}
  eval "$retDay_A=(\${nums})"
  eval "$retYr_A=(\${years})"
}

function getSttnClkoffset() {
  local startSpec="${1}"
  local endSpec="${2}"
  local siteName="${3}"
  local retFile="${4}"

#  findFiles "${commonRoot}/csrs-pp" "@0" "now" "-name inhouse-pp*${siteName}*yr${yr}*" > fileList
  local d= mark= dayList= dayNum= yrList= yr=
  siteNameToDir d "${siteName}"
  siteNameToMarker mark "${siteName}"
  timeSpecToDayAndYearNums dayList yrList "${startSpec}" "${endSpec}"
  logMsg "DEBUG: getSttnClkoffset: #dayList=${#dayList[*]}"
  >final # reset
  >rapid
  for ((i=0;i<${#dayList[*]};i++))
  do
    dayNum="${dayList[i]}"
    yr="${yrList[i]}"
    #ls ./cRoot/csrs-pp/${d}/GPSData_Internal/inhouse-pp*final*${mark}*yr${yr}*day${dayNum}* 2>/dev/null >> final
    ls ./cRoot/csrs-pp/${d}/GPSData_Internal/inhouse-pp*final*${mark}*yr${yr}*day${dayNum}* >> final ##DEBUG
    #ls ./cRoot/csrs-pp/${d}/GPSData_Internal/inhouse-pp*rapid*${mark}*yr${yr}*day${dayNum}* 2>/dev/null >> rapid
    ls ./cRoot/csrs-pp/${d}/GPSData_Internal/inhouse-pp*rapid*${mark}*yr${yr}*day${dayNum}* >> rapid ##DEBUG
  done

  logMsg "DEBUG: first in rapid list: $(head -n 1 rapid)"
  logMsg "DEBUG: first in final list: $(head -n 1 final)"

  # iterate over final and rapid
    #awk '{hms=substr($6,1,8); printf("%sT%s %.3f\n",$5,hms,$14)}' | \
  local FRU=
  for FRU in "rapid" "final"; do
    # check
    if [ ! -s "${FRU}" ]; then
      logMsg "DEBUG: no ${FRU} PPP files found for range ${startSpec} -- ${endSpec}"
      continue
    fi

    # decompress files
    for file in $(cat $FRU); do
      tar zxvf "${file}" "*.pos" "*.sum" pppTimeOfLastMaintenance
    done
    # extract data bits
    tail -n +9 *.pos | \
    grep ^BWD | \
    awk '{date=$5;gsub("-"," ",date);hms=substr($6,1,8);gsub(":"," ",hms); tm=mktime(date " " hms);print(tm,$14)}' | \
    sort -n -k 1 > $FRU.clkns
    logMsg "DEBUG: head of ${FRU}.clkns file: $(head -n 1 ${FRU}.clkns)"
    # TODO: pull last update of yrly file
    # TODO: pull estimated position from .sum file

    # push data up to caller
    mv "${FRU}.clkns" "${retFile}.${FRU}"

    # clean up
    local file=
    for file in *.pos *.sum pppTimeOfLastMaintenance ${FRU} ; do
      [ -e "${file}" ] && rm "${file}"
    done
  done # end loop over rapid/final
}

function mkPlots() {
  local startSpec="${1}"
  local endSpec="${2}"
  local siteName="${3}"

  # get PPP data
  getSttnClkoffset "${startSpec}" "${endSpec}" "${siteName}" sttnClk.dat
  ##  plot just station clock value, while we have the data right here
  local subType= labels= file=
  for file in sttnClk.dat*; do
    [ ! -s "${file}" ] && continue
    logMsg "DEBUG: mkPlots: got sttnClk file: ${file}"
    logMsg "DEBUG: mkPlots: sttnclk head: $(head -n 1 ${file})"
    subType=${file##*.}
    ln -s --force "${file}" "${subType}.dat"
    # setup filenames that mach label names for sending to gnuplot, see pt-plotgen.plt
    labels="${labels} ${subType}"
    logMsg "DEBUG: found labels: ${labels}"
  done
  if [[ -z ${labels} ]]; then logMsg "ERROR coun't find any PPP data at all"; return 1; fi
  #local currTime=$( date --utc --iso-8601=minutes)
  local currTime=$( date --utc )
  pltTitle="PT GPS (${site}), Rb - GNSS Time (PPP-${subType}): ${startSpec} -- ${endSpec} (UTC)\nplot created ${currTime}"
  mkPlotsFromFile "${labels}" "${startSpec}" "${endSpec}" "${pltTitle}" 1 2 "with points" "no" "yes"
  mv outfile.png outfile.clkns.png
  pltTypeList="clkns"
  
  # get xpps offset data
  # get DAQ data
# combine
# plot

  # clean up
  for file in sttnClk.dat.* *.dat; do
    [ ! -z "${file}" -a -e "${file}" ] && rm "${file}"
  done
}

function mkLevel1() {
  mkPlots "00:00 4 days ago" "00:00 2 days ago" "${siteName}"
  storeResults "shrtRng"
}

function mkLevel2() {
  mkPlots "00:00 9 days ago" "00:00 2 days ago" "${siteName}"
  storeResults "medRng"
}

function mkLevel3() {
  mkPlots "00:00 31 days ago" "00:00 2 days ago" "${siteName}"
  storeResults "lngRng"
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
cd "${tmpDir}"
ln -s "${commonRoot}" cRoot
logMsg "DEBUG: symlink to common root directory: $(ls -l cRoot)"
case "${cycle}" in
  live|--live)        mkLevel1 ;;

  da*|--da*)          mkLevel1; mkLevel2;;

  week*|--week*)      mkLevel1; mkLevel2; mkLevel3;;
esac
