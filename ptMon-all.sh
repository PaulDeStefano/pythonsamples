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

  # make "live" DAQ (raw, uncorrected PT-OT) plots
  echo "Running pltDAQ for NU1..."
  local site="NU1"
  local outputDir="${outputTopDir}/NU1"
  local logFile="${outputDir}/ptMon.${site}.rawDAQ.log"
  ptMon-pltDAQ.sh "${outputDir}" "NU1" "${cycle}" >"${logFile}" 2>&1 &

  echo "Running pltDAQ for Super-K..."
  site="Super-K"
  outputDir="${outputTopDir}/SK"
  logFile="${outputDir}/ptMon.${site}.rawDAQ.log"
  ptMon-pltDAQ.sh "${outputDir}" "Super-K" "${cycle}" >"${logFile}" 2>&1 &

  echo "...waiting..."
  wait
  echo "...done: exit code: $?"
}

function mkSatPlots() {

  # don't run live cycles for this data
  if [[ ${cycle} == live ]]; then return 0; fi
  
  # make plots of numbers of satellites used in PVT
  echo "Running SV in PVT Plots for NU1..."
  local site="NU1"
  local outputDir="${outputTopDir}/NU1"
  local logFile="${outputDir}/ptMon.${site}.pvtSat.log"
  ptMon-pvtSatNum.sh "${outputDir}" "NU1" "${cycle}" >"${logFile}" 2>&1 &

  echo "Running SV in PVT Plots for Super-K..."
  site="Super-K"
  outputDir="${outputTopDir}/SK"
  logFile="${outputDir}/ptMon.${site}.pvtSat.log"
  ptMon-pvtSatNum.sh "${outputDir}" "Super-K" "${cycle}" >"${logFile}" 2>&1 &

  echo "...waiting..."
  wait
  echo "...done: exit code: $?"
}

function mkBiasPlots() {

  # don't run live cycles for this data
  if [[ ${cycle} == live ]]; then return 0; fi
  
  # make plots of numbers of satellites used in PVT
  echo "Running rxClkBias Plots for NU1..."
  local site="NU1"
  local outputDir="${outputTopDir}/NU1"
  local logFile="${outputDir}/ptMon.${site}.rxClkBias.log"
  ptMon-clkBias.sh "${outputDir}" "NU1" "${cycle}" >"${logFile}" 2>&1 &

  echo "Running rxClkBias plots for Super-K..."
  site="Super-K"
  outputDir="${outputTopDir}/SK"
  logFile="${outputDir}/ptMon.${site}.rxClkBias.log"
  ptMon-clkBias.sh "${outputDir}" "Super-K" "${cycle}" >"${logFile}" 2>&1 &

  echo "...waiting..."
  wait
  echo "...done: exit code: $?"
}

function mkRxLogs() {
  # pull receiver logs and store them with the plots
  # don't run live cycles for this data
  if [[ ${cycle} == live ]]; then return 0; fi
  local fileType="fetchLog"

  local siteName="NU1"
  echo "Pulling Receiver Logs for ${siteName} ..."
  local outputDir="${outputTopDir}/NU1"
  local logFile="${outputDir}/ptMon.${siteName}.${fileType}.log"
  ptMon-fetchRxLog.sh "${outputDir}" "${siteName}" "${cycle}" >"${logFile}" 2>&1 &

  siteName="Super-K"
  echo "Pulling Receiver Logs for ${siteName} ..."
  outputDir="${outputTopDir}/SK"
  logFile="${outputDir}/ptMon.${siteName}.${fileType}.log"
  ptMon-fetchRxLog.sh "${outputDir}" "${siteName}" "${cycle}" >"${logFile}" 2>&1 &

  echo "...waiting..."
  wait
  echo "...done: exit code: $?"
}

## Configuration ##

if [ -z "${cycle}" ]; then echo "ERROR: parameter #2 required, cycle type" 1>&2; exit 1; fi
if [ -z "${outputTopDir}" ]; then echo "ERROR: parameter #1 required, output directory" 1>&2; exit 1; fi
if [ ! -d "${outputTopDir}" ]; then echo "ERROR: cannot find log directory: ${outputTopDir}" 1>&2; exit 1; fi

#if [[ -z "$GNUPLOT_LIB" ]]; then GNUPLOT_LIB=/home/t2k/ptgps-processing/scripts/pythonsamples/gnuplot.d; export GNUPLOT_LIB ; fi  # default GNUPLOT search path
if ! which ptMon-pltDAQ.sh >/dev/null 2>&1 ; then echo "ERROR: cannot find ptMon-pltDAQ.sh" 1>&2; exit 1; fi

## MAIN ##
mkDAQplots # live, raw DAQ data (raw, uncorrected PT-OT measurements)
mkSatPlots # PVT satellite numbers
mkBiasPlots # RxClkBias
mkRxLogs # Receiver Logs (i.e. PVTGeodetic Block Errors)
