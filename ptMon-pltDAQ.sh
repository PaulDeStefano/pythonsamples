#!/bin/bash
#===============================================================================
#
#          FILE:  ptMon-pltDAQ.sh
# 
#         USAGE:  ./ptMon-pltDAQ.sh 
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

# Mapping from PT site installation names to data directories
siteList="NU1:/home/pdestefa/tmp/t2kScratch/ptdata/gpsptnu1
Super-K:/home/pdestefa/tmp/t2kScratch/ptdata/sukrnh5
PT-Traveller:/home/pdestefa/tmp/t2kScratch/ptdata/traveller-box
ND280:/home/pdestefa/tmp/t2kScratch/ptdata/triptgsc
"
daqFileNameExp='*OT-PT*.dat'
tmpDir=/tmp
fileList=${tmpDir}/ptMon-filelist.$$
unixTimeColumn=3
dataColumn=2
gnuPlotDir=/home/pdestefa/local/src/t2k/samples/gnuplot.d

# clean up working files on interupt or hangup
trap '[[ -e ${fileList} ]] && rm "${fileList}" ' EXIT 0

function logMsg() {
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

    local fileStartTime=$( head -n 3 ${daqFile} | tail -n -1 | awk '{print $'${col}'}' )
    #logMsg "DEBUG: file start time: ${fileStartTime}"
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

  # find DAQ files in the directory
  ls -t $( find ${dir} -name "${daqFileNameExp}" -type f -mtime ${mtimeSpec} ) > ${file}
}

function mkPlots()
{
  local mtimeSpec=$1       # find mtime specification
  local dateSpec=$2      # date specification
  local site=$3      # date specification

  getDAQFileList "${site}" "${fileList}"
  #logMsg "DEBUG: " $(head -n 3 ${fileList})
  if [ -z "$(head -n 1 ${fileList})" ]; then {
    # no files, failure
    logMsg "ERROR: unable to find any DAQ files in directory ${dir}, skipping"
    return 1
  } else {
    logMsg "NOTICE: found DAQ files."
  } fi
  # get the UNIXtime 48 hours before right now, UTC
  local startTime=$( date --date="${dateSpec}" --utc +%s )
  # pair down the list of files by datestamps inside the files
  getLeastFiles ${fileList} ${startTime} ${unixTimeColumn}
  local filesToPlot=$( cat ${fileList} )

  local pltTitle="Precise Time - Official Time @ ${site}: ${dateSpec}"
  local style="points pointtype 1 linewidth 1 linecolor 1"
  # run plotter
  #gnuplot ${gnuPlotDir}/pt-plotgen.gpt ${startTime} ${tmpDir}/plot.png "using ${unixTimeColumn}:${dataColumn}" "test title" "${filesToPlot}"
  local gptCmds='startTime="'${startTime}'";'
  gptCmds=${gptCmds}'outFile="'${tmpDir}/outfile'";'
  gptCmds=${gptCmds}'pltCmd="'${unixTimeColumn}':($2 < 1.0 ? $'${dataColumn}'*10**9 : 1/0)";'
  gptCmds=${gptCmds}'pltTitle="'${pltTitle}'";'
  gptCmds=${gptCmds}'fileList="'${filesToPlot}'"'
  #gptCmds=${gptCmds}'styleExt="'${styleName}'"'
  #logMsg "DEBUG: using gnuplot comands: " "${gptCmds}"
  logMsg "NOTICE: making plots: ${site}: ${dateSpec}"
  gnuplot -e "${gptCmds}" ${gnuPlotDir}/pt-plotgen.gpt
  #gnuplot -e 'startTime="'${startTime}'";outFile="'${tmpDir}'";pltCmd="using '${unixTimeColumn}':$('${dataColumn}'*10**9)";pltTitle="test title";fileList="'$file'"' gnuplot.d/pt-plotgen.gpt

  ## clean up
  rm ${fileList}
}

## MAIN ##

if [ -z "${siteName}" ]; then logMsg "ERROR: second parameter, site name, required but missing."; exit 1; fi
if [ -z "${outputDir}" ]; then logMsg "ERROR: first parameter, output directory, required but missing."; exit 1; fi
if [ ! -d "${outputDir}" ]; then logMsg "ERROR: cannot find output directory: ${outputDir}"; exit 1; fi

# last 48 hours
mkPlots "-3" "now - 48 hours" "${siteName}"
mv ${tmpDir}/outfile.png ${tmpDir}/ptMon.${siteName}.48hours.png
mkPlots "-8" "today - 7 days" "${siteName}"
mv ${tmpDir}/outfile.png ${tmpDir}/ptMon.${siteName}.8days.png
mkPlots "-31" "today - 30 days" "${siteName}"
mv ${tmpDir}/outfile.png ${tmpDir}/ptMon.${siteName}.30days.png
