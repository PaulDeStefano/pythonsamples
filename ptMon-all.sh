#!/bin/bash
#===============================================================================
#
#          FILE:  ptMon-all.sh
# 
#         USAGE:  ./ptMon-all.sh 
# 
#   DESCRIPTION:  Wrapper for the Precise Time System monitoring web-site.  Runs
#                 all scritps for generating the PT monitor pages.
# 
#       OPTIONS:  ---
#  REQUIREMENTS:  ---
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR:  Paul R. DeStefano (), pdestefa (ta)uw (dot) edu.none
#       COMPANY:  
#       VERSION:  1.0
#       CREATED:  04/13/2014 10:15:16 AM PDT
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

outputTopDir=${1}
cycle=${2}

function mkDAQplots() {
  local site="${1}"

  echo "Running ${cycle} pltDAQ for ${site}..."
  local outputDir="${outputTopDir}/${site}"
  if [ ! -d "${outputDir}" ]; then mkdir -p "${outputDir}"; fi
  local logFile="${outputDir}/ptMon.${site}.rawDAQ.log"
  ptMon-pltDAQ.sh "${outputDir}" "${site}" "${cycle}" >"${logFile}" 2>&1 &

}

function mkSatPlots() {
  local site="${1}"

  # don't run live cycles for this data
  if [[ ${cycle} == live ]]; then return 0; fi
  
  # make plots of numbers of satellites used in PVT
  echo "Running SV in PVT Plots for ${site}..."
  local outputDir="${outputTopDir}/${site}"
  local logFile="${outputDir}/ptMon.${site}.pvtSat.log"
  ptMon-pvtSatNum.sh "${outputDir}" "${site}" "${cycle}" >"${logFile}" 2>&1 &

}

function mkBiasPlots() {
  local site="${1}"

  # don't run live cycles for this data
  if [[ ${cycle} == live ]]; then return 0; fi
  
  # make plots of numbers of satellites used in PVT
  echo "Running rxClkBias Plots for ${site}..."
  local outputDir="${outputTopDir}/${site}"
  local logFile="${outputDir}/ptMon.${site}.rxClkBias.log"
  ptMon-clkBias.sh "${outputDir}" "${site}" "${cycle}" >"${logFile}" 2>&1 &

}

function mkRxLogs() {
  local site="${1}"
  # pull receiver logs and store them with the plots
  # don't run live cycles for this data
  if [[ ${cycle} == live ]]; then return 0; fi
  local fileType="fetchLog"

  echo "Pulling Receiver Logs for ${site} ..."
  local outputDir="${outputTopDir}/${site}"
  local logFile="${outputDir}/ptMon.${site}.${fileType}.log"
  ptMon-fetchRxLog.sh "${outputDir}" "${site}" "${cycle}" >"${logFile}" 2>&1 &

}

## Configuration ##

if [ -z "${cycle}" ]; then echo "ERROR: parameter #2 required, cycle type" 1>&2; exit 1; fi
if [ -z "${outputTopDir}" ]; then echo "ERROR: parameter #1 required, output directory" 1>&2; exit 1; fi
if [ ! -d "${outputTopDir}" ]; then echo "ERROR: cannot find log directory: ${outputTopDir}" 1>&2; exit 1; fi

#if [[ -z "$GNUPLOT_LIB" ]]; then GNUPLOT_LIB=/home/t2k/ptgps-processing/scripts/pythonsamples/gnuplot.d; export GNUPLOT_LIB ; fi  # default GNUPLOT search path
if ! which ptMon-pltDAQ.sh >/dev/null 2>&1 ; then echo "ERROR: cannot find ptMon-pltDAQ.sh" 1>&2; exit 1; fi

renice 19 $$
## MAIN ##
for siteName in NU1 Super-K ND280; do
#for siteName in ND280; do
  mkDAQplots "${siteName}" # live, raw DAQ data (raw, uncorrected PT-OT measurements)
  mkSatPlots "${siteName}" # PVT satellite numbers
  mkBiasPlots "${siteName}" # RxClkBias
  mkRxLogs "${siteName}" # Receiver Logs (i.e. PVTGeodetic Block Errors)
  echo "...waiting..."
  wait
  echo "...done: exit code: $?"
done
