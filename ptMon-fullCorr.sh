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

outputDir="${1}"
siteName="${2}"
cycle="${3}"

# force process to run nice
renice 20 -p ${$} >/dev/null

# Mapping from PT site installation names to data directories
pltType=pt-ot
commonRoot=/home/t2k/public_html/post/gpsgroup/ptdata
typeDir=csrs-pp
siteList="NU1:NU1SeptentrioGPS-PT00
Super-K:KenkyutoSeptentrioGPS-PT01
ND280:NM-ND280SeptentrioGPS-TOKA
Trav:TravSeptentrioGPS-PT04
"
siteListDAQDir="NU1:GPSPTNU1/*TIC/.
Super-K:SUKRNH5/*TIC/.
Trav:TRAVELLER-BOX/*TIC/.
"

# fake associative arrays
dataTypeList=('xpps' 'rxclk' 'sttnClk' 'daq')
for (( dtIndx=0;dtIndx<=3;dtIndx++ )); do iName=${dataTypeList[$dtIndx]}; eval "${iName}=$dtIndx" ; done
#xpps=0; rxclk=1; sttnClk=2; daq=3
# xPPSOffset data
DataExtractDir[xpps]='organizedData/xPPSOffsets'
FileNameDataType[xpps]='xppsoffset'
FileNameDataSubTypeList[xpps]='.'
FileEGrepOpts[xpps]='.*'
FileHeaderLen[xpps]=1
unixTimeColumn[xpps]=3
dataColumn[xpps]=2
#useCSV[xpps]="CSV"
awkCmd[xpps]="-F, '{print(int(\$3),\$2)}'"
# rxClkBias data
DataExtractDir[rxclk]='organizedData/pvtGeodetic'
FileNameDataType[rxclk]='pvtGeo'
FileNameDataSubTypeList[rxclk]='.'
FileEGrepOpts[rxclk]='.*'
FileHeaderLen[rxclk]=1
unixTimeColumn[rxclk]=3
dataColumn[rxclk]=2
#useCSV[rxclk]="CSV"
awkCmd[rxclk]="-F, '{print(int(\$2),sprintf(\"%.3f\",(\$7*10**6)))}'"
# station clock offset (sttnClk_ns) data
# station clock offset (sttnClk_ns) data
DataExtractDir[sttnClk]='organizedData/csrs-pp'
FileNameDataType[sttnClk]='inhouse-pp'
FileNameDataSubTypeList[sttnClk]='ESA-rapid IGS-rapid ESA-rapid ESA-final IGS-final EMR-final'
fileBrcXpr=$( echo ${FileNameDataSubTypeList[sttnClk]} | sed -r 's/ +/,/g' )  # required to propogate precidence of PPP results all the way to plotting, later data overplots ealier data
FileEGrepOpts[sttnClk]='.*'
FileHeaderLen[sttnClk]=8
#useCSV[sttnClk]="no"
#awkCmd[sttnClk]='{date=\$5;gsub("-"," ",date);hms=substr(\$6,1,8);gsub(":"," ",hms); tm=mktime(date " " hms);print(tm,\$14)}'
# raw TIC data
FileNameDataType[daq]='OT-PT'
FileNameDataSubTypeList[daq]='.'
FileEGrepOpts[daq]='.*'
FileHeaderLen[daq]=0
unixTimeColumn[daq]=3
dataColumn[daq]=2
#useCSV[daq]="no"
#awkCmd[daq]="'{print(\$3,(\$2*10**9))}'"

#for iName in ${dataTypeList[*]}; do echo "DEBUG: $iName-->${FileNameDataType[$iName]}"; done #DEBUG
#exit 1 #DEBUG

tmpDir=$(mktemp -d '/tmp/ptMon-tmp.XXXXXXXXX')
if [ ! $? -eq 0 ]; then
  echo "ERROR: cannot create temporary directory with mktemp"
  exit 1
fi
fileList=${tmpDir}/ptMon-filelist.$$
loadAvgLimit=11

DEBUG=no
origWD=${PWD}

# clean up working files on interupt or hangup
trap '[[ -d ${tmpDir} ]] && rm -rf "${tmpDir}"' EXIT 0

function logMsg() {
  # do not print DEBUG messages if DEBUG=no
  [[ ${DEBUG} == no && ${1} =~ ^DEBUG: ]] && return 0
  if [[ ${1} =~ ^NOTICE: ]]; then 
    echo "$@"
  else
    echo "$@" 1>&2
  fi
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
  logMsg "DEBUG: siteNameToDir: found marker name: site=${siteName},marker=${marker}"
  eval "$retVar=\${marker}"
}

function siteNameToDAQDir() {
  local retVar="${1}"
  local siteName="${2}"

  for word in ${siteListDAQDir}; do {
    if [[ ${word} =~ ^${siteName} ]]; then {
      dir=${word##*:}
      break
    } fi
  } done

  logMsg "DEBUG: siteNameToDAQDir: found directory: site=${siteName},dir=${dir}"
  eval "$retVar=\${dir}"
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

function findFiles() {
  local findDir="${1}"
  local startSpec="${2}"
  local endSpec="${3}"
  local findOpts="${4}"
  local grepFilter="${5}"
  local retFile="${6}"

# convert time specs to UNIX time and reference files for 'find'
  local UNIXstart=$(date --date="${startSpec}" +%s)
  local UNIXend=$(date --date="${endSpec}" +%s)
  touch --date="@${UNIXstart}" "startTimeFile"
  touch --date="@${UNIXend}" "endTimeFile"

# Use find first
  #DEBUG eval find ${findDir} ${findOpts} 2>/dev/null | \
  eval find ${findDir} -newer startTimeFile -a ! -newer endTimeFile ${findOpts} 2>/dev/null | \
  egrep "${grepFilter}" | \
  cat > "${retFile}"
}

function getDAQFileList() {
  # file DAQ files for the specified site, store in specified file
  local siteName="$1"
  local file="$2"
  local startSpec="${3}"
  local endSpec="${4}"

  # dereference site to directory
  local dir=""
  siteNameToDAQDir dir "${siteName}"
  dir="./cRoot/${dir}"
  logMsg "DEBUG: data dir: ${dir}"

  findFiles "${dir}" "${startSpec}" "${endSpec}" "-name \*OT-PT\*.dat" '.*' "${file}"
  if [ ! -s "${file}" ]; then logMsg "WARNING: findFiles returned zero files"; return 1; fi
}

function deCompress() {
  # use appropriate utility to un-compress data file
  local fileList=${1}
  logMsg "DEBUG: deCompress: working on files in ${fileList}, first file: $(head -n 1 ${fileList})"

  # file to replace FileList after decompression
  local newList="${tmpDir}/deCompList"

  local file= base= ext= cmd= tgt=
  for file in $( cat "${fileList}" ); do {

    # assume filename typing
    base=$(basename ${file})
    ext="${base##*.}"
    tgt="${base%%.${ext}}"
    
    if [ -s "${tgt}" ]; then 
      logMsg "DEBUG: deCompress: decompressed file already exists:${tgt}, skipping"
      echo "${tgt}" >> "${newList}"
      continue
    fi
    if [ ! -e "./${base}" ]; then ln -s "${file}" "${base}"; fi # make a fast copy of file in CWD
    # choose decompression comand
    case ${ext} in
      lzo*)       cmd="$(which lzop) -d \"${base}\"" ;;
      gz*)        cmd="$(which gzip) -dc \"${base}\" >${tgt}" ;;
      zip*)       cmd="$(which zip) -d \"${base}\"" ;;
      dat*)       logMsg "NOTICE: deCompress: extension:${ext}, matches dat*, skipping decompression"; continue ;;
      *)          logMsg "ERROR: deCompress: unrecognized extention ${ext}"; return 1 ;;
    esac

    logMsg "DEBUG: decompressing:${base},cmd:${cmd},tgt:${tgt}..."
    eval ${cmd}
    if [ ${?} -ge 1 -o ! -r "${tgt}" ]; then logMsg "ERROR: unable to decompress file: ${file}"; continue; fi
    logMsg "DEBUG: ...done."
    echo "${tgt}" >> "${newList}"
  } done

  [ -s "${newList}" ] && mv --force "${newList}" "${fileList}"
}

function getDAQfiles() {
  local site="${1}"
  local startSpec="${2}"
  local endSpec="${3}"
  local datFile="${4}"

  local fileList="getDAQfiles.list"
  >"${fileList}"
  getDAQFileList "${site}" "${fileList}" "${startSpec}" "${endSpec}"
  logMsg "DEBUG: getDAQfiles: head of filelist: $(head -n 1 ${fileList})"
  if [ ! -s "${fileList}" ]; then {
    # no files, failure
    logMsg "ERROR: getDAQfiles: unable to find any DAQ files, returning early"
    return 1
  } fi

  local file=
  >getDAQ.dat
  for file in $(cat "${fileList}" ); do
    eval awk "'{print(\$${unixTimeColumn[daq]},\$${dataColumn[daq]}*10**9)}'" <"${file}" >>getDAQ.dat
    #eval awk "'\$${dataColumn[daq]} <= 0.9{print(\$${unixTimeColumn[daq]},\$${dataColumn[daq]}*10**9)}'" <"${file}" >>getDAQ.dat
  done
  sort -n -k 1 getDAQ.dat >"${datFile}"
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
    #style="points pointtype 1 linewidth 2 linecolor 3"
    style="style2"
  else
    style="${styleSpec}"
  fi

  #style="points pt 12 pointsize 0.5" # debug
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
  gptCmds=${gptCmds}'pltCmd="'${xCol}':'${yCol}':(10)";'
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
      mv --force "${tmpDir}/${moveFile}" "${outputDir}/${destFile}"
      chmod 444 "${outputDir}/${destFile}"
    done
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

function getSttnClkOffset() {
  local startSpec="${1}"
  local endSpec="${2}"
  local siteName="${3}"
  local retFile="${4}"

  local d= mark= dayList= dayNum= yrList= yr= pppType=
  siteNameToDir d "${siteName}"
  siteNameToMarker mark "${siteName}"
  timeSpecToDayAndYearNums dayList yrList "${startSpec}" "${endSpec}"
  logMsg "DEBUG: getSttnClkOffset: #dayList=${#dayList[*]}"
  logMsg "DEBUG: getSttnClkOffset: FileNameDataSubTypeList:"${FileNameDataSubTypeList[sttnClk]}
  for pppType in ${FileNameDataSubTypeList[sttnClk]}; do
    >${pppType} # reset
    if [[ "${finalOnly}" = yes && "${pppType}" != *final ]]
    then 
      logMsg "DEBUG: skipping non-final results: finalOnly=${finalOnly}"
      continue
    fi
    for ((i=0;i<${#dayList[*]};i++))
    do
      dayNum="${dayList[i]}"
      yr="${yrList[i]}"
      yr=${yr:2:2}
      # for label in labelList; do
      ls ./cRoot/organizedData/csrs-pp/${d}/GPSData_Internal/inhouse-pp*src${pppType}*${mark}*.yr*${yr}.day${dayNum}* 2>/dev/null >> "${pppType}"
      #ls ./cRoot/organizedData/csrs-pp/${d}/GPSData_Internal/inhouse-pp*${pppType}*${mark}*yr*${yr}*day${dayNum}* >> "${pppType}" ##DEBUG
    done

    if [ ! -s "${pppType}" ]; then
      logMsg "DEBUG: no ${pppType} PPP files found for range ${startSpec} -- ${endSpec}"
      continue
    fi
    logMsg "DEBUG: first in ${pppType} list: $(head -n 1 ${pppType})"
    logMsg "DEBUG: last in ${pppType} list: $(tail -n 1 ${pppType})"

    # decompress files
    for file in $(cat ${pppType}); do
      tar zxf "${file}" "*.pos" "*.sum" pppTimeOfLastMaintenance
    done
    # extract data bits
    tail -n +9 *.pos | \
    grep ^BWD | \
    awk '{date=$5;gsub("-"," ",date);hms=substr($6,1,8);gsub(":"," ",hms); tm=mktime(date " " hms);print(tm,$14)}' | \
    sort -n -k 1 > $pppType.clkns
    logMsg "DEBUG: head of ${pppType}.clkns file: $(head -n 1 ${pppType}.clkns)"
    # TODO: pull last update of yrly file
    # TODO: pull estimated position from .sum file

    # push data up to caller
    mv "${pppType}.clkns" "${retFile}.${pppType}"

    # clean up
    local file=
    for file in *.pos *.sum pppTimeOfLastMaintenance ${pppType} ; do
      [ -e "${file}" ] && rm "${file}"
    done
  done # end loop over rapid/final
}

function getTOFDataFiles() {
  local startSpec="${1}"
  local endSpec="${2}"
  local siteName="${3}"
  local dataType="${4}"
  local retFile="${5}"

  # check Required Configuration
  local value
  for var in DataExtractDir FileNameDataSubTypeList FileNameDataType FileHeaderLen FileEGrepOpts awkCmd ; do
    value=
    eval "value=\${${var}[${dataType}]}"
    if [[ -z $value ]]; then logMsg "ERROR: getTOFDataFiles: file empty: ${var[$dataType]} is empty"; return 1; fi
  done

  local subTypeList="${FileNameDataSubTypeList[${dataType}]}"
  logMsg "DEBUG: getTOFDataFiles: processing dataType:${dataType}, subtypes:${subTypeList}"
  local d= mark= dayList= dayNum= yrList= yr=
  siteNameToDir d "${siteName}"
  siteNameToMarker mark "${siteName}"
  timeSpecToDayAndYearNums dayList yrList "${startSpec}" "${endSpec}"
  logMsg "DEBUG: getTOFDataFiles: #dayList=${#dayList[*]}"

  local dataSubType= datfile=getTOF.dat f= list=getTOFDataFiles.list tmplist="${list}.tmp"
  local rmListFile=getTOF.rmlist fileGlob=
  >"${rmListFile}"
  for dataSubType in ${subTypeList}; do
    >"$list" # reset the file list
    >"${tmplist}"
    # for each data subtype...
    logMsg "DEBUG: getTOFDataFiles: working on type:${dataType} dataSubType:${dataSubType}"
    for ((i=0;i<${#dayList[*]};i++))
    do # for very day in the date range
      dayNum="${dayList[i]}"
      yr="${yrList[i]}"
      yr=${yr:2:2}
      # add the data file for that day, filtered by subtype, to the file list
      eval "fileGlob=./cRoot/${DataExtractDir[${dataType}]}/${d}/GPSData_Internal/${FileNameDataType[${dataType}]}*${dataSubType}*${mark}*.yr*${yr}.day${dayNum}*dat*"
      logMsg "DEBUG: getTOFDataFiles: finding files matchiing ${fileGlob}"
      #ls ${fileGlob} #DEBUG
      ls ${fileGlob} 2>/dev/null >> "${list}"
    done
    logMsg "DEBUG: getTOFDataFiles: found type:${dataType} files, first: $(head -n 1 ${list})" 
    logMsg "DEBUG: getTOFDataFiles: found type:${dataType} files, last: $(tail -n 1 ${list})" 
    logMsg "DEBUG: getTOFDataFiles: convert to local symlinks, type:${dataType}, first file: $(head -n 1 ${list})" 
    # now we have a file list for this data type and subtype, make local links
    local baseName=
    for f in $(cat "${list}"); do 
      bName=$(basename ${f})
      if [ ! -s "${bName})" ]; then
        ln -s --force ${f} ${bName}; echo ${bName} >>"${tmplist}"
      else
        echo ${bName} >>"${tmplist}"
      fi
    done
    mv "${tmplist}" "${list}"
    # decompress all the data files in the list, if necesary
    deCompress "${list}"
    # now pull the data out of the files and organize it for plotting
    >"${datfile}"
    for f in $(cat "${list}" )
    do
      tail -n +$((${FileHeaderLen[${dataType}]}+1)) ${f} | \
      egrep "${FileEGrepOpts[${dataType}]}" | \
      eval awk ${awkCmd[${dataType}]} | \
      cat >> "${datfile}"
    done
    logMsg "DEBUG: getTOFDataFiles: done collecting data for type:${dataType}, first data line: $(head -n 1 ${datfile})" 
    cat "${list}" >>"${rmListFile}"  # keep track of files to clean-up

    # push data up to caller
    mv "${datfile}" "${retFile}.${dataSubType}"
  done

  # clean up
  for f in $( cat "${rmListFile}" ); do
    [ -e "${file}" ] && rm "${f}"
  done
}

function mergeAllFiles() {
  local retFile="${1}"; shift
  local firstFile="${1}"; shift
  cp -p "${firstFile}" resultFile
  local fileList="${@}"

  logMsg "DEBUG: mergeAllFiles: merging files:${firstFile},${fileList} "
  local f=
  for f in ${fileList}; do
    logMsg "DEBUG: mergeAllFiles: head of resultFile: $(head -n 1 resultFile)"
    logMsg "DEBUG: mergeAllFiles: head of ${f}: $(head -n 1 ${f})"
    #join -j 1 resultFile "${f}"  |head #DEBUG
    join -j 1 resultFile "${f}" >mergeTempFile
    if [ ! $? -eq 0 -o ! -s mergeTempFile ]; then
      logMsg "ERROR: mergeAllFiles: join failed on file:${f},output head:$(head -n 1 mergeTempFile)"
      >resultFile
      return 1
    else
      mv mergeTempFile resultFile
      logMsg "DEBUG: mergeAllFiles: head of merged file: $(head -n 1 resultFile)"
    fi
  done
  mv resultFile "${retFile}"
}

function calcFullCorr() {
  local retFile="${1}"
  local datFile="${2}"
  local siteName="${3}"

  cblDelayDiff['Super-K']=-22.02  # before Kenkyuto Move
  cblDelayDiff['Super-K']=-14.77  # after Kenkyuto Move
  cblDelayDiff['NU1']=-18.23      # before 2014-2-4
  cblDelayDiff['NU1']=-19.86      # after 2014-2-4
  arbitraryShift=-300.0           # PT time retarded by 300ns to force TIC measurements away from zero

  logMsg "DEBUG: starting full correction calculations: cblDelayDiff=${cblDelayDiff[${siteName}]}, shift=${arbitraryShift}..."
  # assume datFile order is unixtime,TICraw,xPPSOffset,rxClkBias,SttnClkOffset
  local cblDD=cblDelayDiff[${siteName}]
  local shft=${arbitraryShift}
  local setUpCmd="unix=\$1;tic=\$2;xpps=\$3;rcb=\$4;sco=\$5;shft=${shft}"
  #eval fcCmd="'{${setUpCmd};fcorr=tic-(xpps)-(shft)-(cblDD)+(rcb)-(sco);print(unix,fcorr,tic,xpps,rcb,sco,cblDD,shft)}'"
  #/usr/bin/echo "#UNIXtime fullcorr TICmeas xPPSOff RxClkBias SttnClkOff" >"${retFile}"
  eval fcCmd="'{${setUpCmd};fcorr=tic+(shft)-(xpps)-(cblDD)+(rcb)-(sco);print(unix,fcorr)}'"

  awk "${fcCmd}" <"${datFile}" >"${retFile}"
  logMsg "DEBUG: ...done"
}

function mkPlots() {
  local startSpec="${1}"
  local endSpec="${2}"
  local siteName="${3}"

  #reset list of result plots
  pltTypeList=

  # get PPP data
  getSttnClkOffset "${startSpec}" "${endSpec}" "${siteName}" sttnClk.dat
  ##  plot just station clock value, while we have the data right here
  local subType= labels= file=
  for file in $(eval echo sttnClk.dat.{${fileBrcXpr}}) ; do
    [ ! -s "${file}" ] && continue
    logMsg "DEBUG: mkPlots: got sttnClk file: ${file}"
    logMsg "DEBUG: mkPlots: sttnclk head: $(head -n 1 ${file})"
    subType=${file##*.}
    ln --force "${file}" "${subType}.dat"
    # setup filenames that mach label names for sending to gnuplot, see pt-plotgen.plt
    labels="${labels} ${subType}"
    logMsg "DEBUG: found labels: ${labels}"
  done
  if [[ -z ${labels} ]]; then logMsg "ERROR coun't find any PPP data at all"; return 1; fi
  #local currTime=$( date --utc --iso-8601=minutes)
  local currTime=$( date --utc )
  pltTitle="PT GPS (${siteName}), Rb - PPP GNSS Time: ${startSpec} -- ${endSpec} (UTC)\nplot created ${currTime}"
  mkPlotsFromFile "${labels}" "${startSpec}" "${endSpec}" "${pltTitle}" 1 2 "points pointsize 0.5" "no" "yes"
  mv outfile.png outfile.clkns.png
  pltTypeList="clkns"
  rm *.dat # clean up copies made to sent to gnuplot
  
  # check for ND280, no point in going further
  if [ "${siteName}" = "ND280" ]; then logMsg "NOTICE: skipping more work on ND280, no corrections can be calculated"; return 0 ; fi

  # get xpps offset data
  getTOFDataFiles "${startSpec}" "${endSpec}" "${siteName}" xpps XPPS.dat
  if [ ! $? -eq 0 ]; then logMsg "ERROR: mkPlots: getting xPPSOffset data failed; cannot continue"; return 1; fi
  logMsg "DEBUG: got head of XPPS: $(head -n 1 XPPS.dat..)"

  # get rxClkBias data
  getTOFDataFiles "${startSpec}" "${endSpec}" "${siteName}" rxclk rxClkBias.dat
  if [ ! $? -eq 0 ]; then logMsg "ERROR: mkPlots: getting rxClkBias data failed; cannot continue"; return 1; fi
  logMsg "DEBUG: got head of rxclk: $(head -n 1 rxClkBias.dat..)"

  # get DAQ data
  getDAQfiles "${siteName}" "${startSpec}" "${endSpec}" DAQ.dat
  if [ ! $? -eq 0 -a -s DAQ.dat ]; then logMsg "ERROR: mkPlots: getting DAQ data failed; cannot continue"; return 1; fi
  logMsg "DEBUG: got head of DAQ: $(head -n 1 DAQ.dat)"

  local lbl= fullCorrLabelList=
  for lbl in ${labels}; do
    # combine
    logMsg "DEBUG: got head of DAQ: $(head -n 1 DAQ.dat)"
    logMsg "DEBUG: got head of XPPS: $(head -n 1 XPPS.dat..)"
    logMsg "DEBUG: got head of rxclk: $(head -n 1 rxClkBias.dat..)"
    logMsg "DEBUG: got head of sttnClk: $(head -n 1 sttnClk.dat.${lbl})"
    >merged.dat
    mergeAllFiles merged.dat DAQ.dat XPPS.dat.. rxClkBias.dat.. "sttnClk.dat.${lbl}"
    if [ ! $? -eq 0 -o ! -s merged.dat ]; then logMsg "ERROR: data merge failed for group l:${lbl}"; continue; fi
    logMsg "DEBUG: finished merging data, head: $(head -n 1 merged.dat) "
    # calculate
    >"fullCorr.dat.${lbl}"
    calcFullCorr "fullCorr.dat.${lbl}" merged.dat
    if [ ! -s "fullCorr.dat.${lbl}" ]; then logMsg "ERROR: data final calculations failed for group l:${lbl}"; continue; fi
    ln -s "fullCorr.dat.${lbl}" "${lbl}.dat"
    #cp -p fullCorr.dat.${lbl} /home/pdestefa/public_html/ptmon_test/. #DEBUG
    fullCorrLabelList="${fullCorrLabelList} ${lbl}"   # success, save label to pass to plotter, label
  done

  # plot all fully corrected results
  logMsg "NOTICE: plotting the following list of Post-Processing results: ${fullCorrLabelList}"
  pltTitle="PT GPS (${siteName}), PT - OT (fully corrected): ${startSpec} -- ${endSpec} (UTC)\nplot created ${currTime}"
  mkPlotsFromFile "${fullCorrLabelList}" "${startSpec}" "${endSpec}" "${pltTitle}" 1 2 "points pointsize 0.5" "no" "yes"
  mv outfile.png outfile.fullCorr.png
  pltTypeList="${pltTypeList} fullCorr"

  # clean up
  for file in sttnClk.dat.* *.dat; do
    [ ! -z "${file}" -a -e "${file}" ] && rm "${file}"
  done
}

function mkLevel1() {
  mkPlots "00:00 5 days ago" "00:00 3 days ago" "${siteName}"
  storeResults "shrtRng"
}

function mkLevel2() {
  mkPlots "00:00 9 days ago" "00:00 3 days ago" "${siteName}"
  storeResults "medRng"
}

function mkLevel3() {
  #finalOnly=yes
  mkPlots "00:00 5 weeks ago" "00:00 3 weeks ago" "${siteName}"
  storeResults "lngRng"
  #finalOnly=no
}

## MAIN ##

# Configuration && Checks
set -e
if [ -z "${outputDir}" ]; then logMsg "ERROR: first parameter, output directory, required but missing."; exit 1; fi
if [ ! -d "${outputDir}" ]; then logMsg "ERROR: cannot find output directory: ${outputDir}"; exit 1; fi
if [ -z "${siteName}" ]; then logMsg "ERROR: second parameter, site name, required but missing."; exit 1; fi
if [ -z "${cycle}" ]; then logMsg "ERROR: third parameter, cycle, required but missing."; exit 1; fi
pltProg="$(which gnuplot)"
if [ ! -e "${pltProg}" ]; then logMsg "ERROR: cannot find gnuplot in PATH"; exit 1; fi

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

# week*|--week*)      mkLevel3;; #DEBUG
esac
