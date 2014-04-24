#!/bin/bash

# force nice value of 19
renice 19 -p $$ >/dev/null 2>&1

export LD_LIBRARY_PATH=/usr/local/gcc-4.7.1/lib # req for sbfanalyzer
export DISPLAY='' # req for sbfanalyzer
export TZ=UTC

# DEFAULT configuration values
confErr=""
sbfTopDir="/data-scratch"
#sbfTopDir="/home/t2k/public_html/post/gpsgroup/ptdata"
resultsTopDir="/home/t2k/public_html/post/gpsgroup/ptdata/organizedData"
#resultsTopDir="./testTopDir"
recvList="PT00 PT01 TOKA PT04"
pathGrps="GPSData_Internal GPSData_External ND280"
consolidateToolsDir=~gurfler/newgps/consolidata
consolidataDir="/data-scratch/paul/consolidataTestDir"

zProg="lzop"
zExt="lzo"
erex=".13_"
clobber="yes"
rebuild="no"
doRIN="yes"
doCGG="yes"
dooffset="yes"
dopvtGeo="yes"
dorxStat="yes"
dodop="yes"
doGLOtime="yes"
doPVTSat="no"
dryrun="no"
doReport1="no" # GPS Performance Report (incomplete)
do3day="yes" # additional 3-day combination RINEX files
doDailyConsol="yes" # consolidate data into daily consolidata files
century=20
beginTime=
endTime=
DEBUG=no

# extra configuration
function doConfig() {

  if [ ! -d "${resultsTopDir}" ]; then confErr=0; logMsg "ERROR: cannot find top dir: ${resultsTopDir}"; fi
  if [ ! -d "${sbfTopDir}" ]; then confErr=0; logMsg "ERROR: cannot find SBF source dir: ${sbfTopDir}"; fi
  if [ ! -d "${consolidateToolsDir}" ]; then confErr=0; logMsg "ERROR: cannot find consolidateToolsDir: ${consolidateToolsDir}"; fi
  if [ ! -d "${consolidataDir}" ]; then confErr=0; logMsg "ERROR: cannot find consolidataDir : ${consolidataDir}"; fi

  rinexTopDir="${resultsTopDir}/rinex"
  rinexDir='${rinexTopDir}/${rxName}/${element}'
  cggTopDir="${resultsTopDir}/cggtts"
  cggParam="paramCGGTTS.dat"
  if ! sbf2rinProg="$(which sbf2rin)"; then confErr=0 ; echo "ERROR: cannot find sbf2rin" 1>&2; fi
  if ! rin2cggProg="$(which rin2cgg)"; then confErr=0 ; echo "ERROR: cannot find rin2cgg" 1>&2; fi
  rinFileName='${id}${day}'
  if ! sbf2offset="$(which sbf2offset.py)"; then confErr=0; echo "ERROR: cannot find sbf2PVTGeo.py" 1>&2; fi
  offsetTopDir="${resultsTopDir}/xPPSOffsets"
  offsetDir='${offsetTopDir}/${rxName}/${element}'
  offsetFileName='xppsoffset.${id}.${typ}.yr${yr}.day${day}.part${part}.dat'
  if ! sbf2pvtGeo="$(which sbf2PVTGeo.py)"; then confErr=0; echo "ERROR: cannot find sbf2PVTGeo.py" 1>&2; fi
  pvtGeoTopDir="${resultsTopDir}/pvtGeodetic"
  pvtGeoDir='${pvtGeoTopDir}/${rxName}/${element}'
  pvtGeoFileName='pvtGeo.${id}.${typ}.yr${yr}.day${day}.part${part}.dat'
  if ! sbf2rxStat="$(which sbf2status.py)"; then confErr=0; echo "ERROR: cannot find sbf2status.py" 1>&2; fi
  rxStatTopDir="${resultsTopDir}/rxStatus"
  rxStatDir='${rxStatTopDir}/${rxName}/${element}'
  rxStatFileName='rxStatus.${id}.${typ}.yr${yr}.day${day}.part${part}.dat'
  if ! sbf2dop="$(which sbf2dop.py)"; then confErr=0; echo "ERROR: cannot find sbf2dop.py" 1>&2; fi
  dopTopDir="${resultsTopDir}/rxDOP"
  dopDir='${dopTopDir}/${rxName}/${element}'
  dopFileName='rxDOP.${id}.${typ}.yr${yr}.day${day}.part${part}.dat'
  if ! sbf2GLOtime="$(which sbf2GLOtime.py)"; then confErr=0; echo "ERROR: cannot find sbf2GLOtime.py" 1>&2; fi
  GLOtimeTopDir="${resultsTopDir}/GLOtime"
  GLOtimeDir='${GLOtimeTopDir}/${rxName}/${element}'
  GLOtimeFileName='GLOtime.${id}.${typ}.yr${yr}.day${day}.part${part}.dat'
  #sbf2PVTSat="/home/pdestefa/local/src/samples/sbf2PVTSat.py"
  if ! sbf2PVTSat="$(which sbf2PVTSat.py)"; then confErr=0; echo "ERROR: cannot find sbf2PVTSat.py" 1>&2; fi
  PVTSatTopDir="${resultsTopDir}/pvtSatCart"
  PVTSatDir='${PVTSatTopDir}/${rxName}/${element}'
  PVTSatFileName='pvtSat.${id}.${typ}.yr${yr}.day${day}.part${part}.dat'
  #reportProg="/usr/local/RxTools/bin/sbfanalyzer"
  if ! reportProg="$(which sbfanalyzer)"; then confErr=0; echo "ERROR: cannot find sbfanalyzer" 1>&2; fi
  report1TopDir="${resultsTopDir}/sbfReport-GPSPerf"
  report1Dir='${report1TopDir}/${rxName}/${element}'
  report1Template='~pdestefa/local/src/samples/t2k.PPperformance.ppl'
  report1FileName='gpsPerf.${id}.${typ}.yr${yr}.day${day}.part${part}.pdf'
  if ! gpstkbin="$(dirname $(which EditRinex) )"; then confErr=0; echo "ERROR: cannot find gtstkbin" 1>&2; fi

  # bail if something was flagged
  if [ ${confErr} ]; then logMsg "ERROR: configuration error, quiting"; exit 1; fi
}

function logMsg() {
    if [[ no == ${DEBUG} && ${1} =~ ^DEBUG ]]; then return 1; fi
    echo "$@" 1>&2
}

function getRxName() {
  local id=${1}
  local yr=${2}
  local day=${3}
  #logMsg "DEBUG: yr${yr} day${day}"

  if [ -z "${day}" ]; then { logMsg "ERROR: getRxName requires 3rd parameter"; exit 1; } fi
  
  # check RnHut vs Kenkyuto (Date moved: 2014.01.28)
  if [ $yr -lt 14 ] || ( [ $day -le 028 ] && [ $yr -eq 14 ] ); then {
    # should be RnHut
    #logMsg "DEBUG: Before move from RadonHut"
recvNiceNameList="PT00:NU1SeptentrioGPS-PT00
PT01:RnHutSeptentrioGPS-PT01
TOKA:NM-ND280SeptentrioGPS-TOKA
PT04:TravelerGPS-PT04"
  } else {
    # should be Kenkyuto
    #logMsg "DEBUG: After move to Kenkyuto"
recvNiceNameList="PT00:NU1SeptentrioGPS-PT00
PT01:KenkyutoSeptentrioGPS-PT01
TOKA:NM-ND280SeptentrioGPS-TOKA
PT04:TravelerGPS-PT04"
  } fi

  local value=""
  for pair in ${recvNiceNameList}; do {
    if [[ ${pair} =~ ${id}.* ]]; then {
      value=$( echo ${pair} | sed 's/.*://' )
      if [ ! -z "${value}" ]; then break; fi
    } fi
  } done
  if [ -z "${value}" ]; then logMsg "ERROR: couldn't find match for ${id}"; exit 1; fi
  echo "${value}"
}

function getSBF() {
    local element=${1}
    local id=$2
    local extraRegex=${3}
    local beginT=${4}
    local endT=${5}
    logMsg "NOTICE: working on element ${element}"

    # create comparison files for find
    beginFile="${tmpDir}/beginFile"
    endFile="${tmpDir}/endFile"
    touch --date="@0" "${beginFile}" >/dev/null 2>&1
    touch --date="tomorrow" "${endFile}" >/dev/null 2>&1
    if [[ ! -z "${beginT}" ]]; then touch -t "${beginT}" "${beginFile}"; fi
    if [[ ! -z "${endT}" ]]; then touch -t "${endT}" "${endFile}"; fi
    logMsg "DEBUG: begin time: $(date --reference=${beginFile}), end time: $(date --reference=${endFile})"

    # find SBF files
    ( /usr/bin/find ${sbfTopDir}/sukrnh5/DATA ${sbfTopDir}/gpsptnu1/DATA ${sbfTopDir}/triptgsc/nd280data ${sbfTopDir}/traveller-box \
        -type f \
        -iwholename "*${element}*${id}*.??_*" \
        -newer "${beginFile}" -a \! -newer "${endFile}" \
        2>/dev/null \
        | egrep -i "${extraRegex}" \
        | fgrep -v /old/ \
        | sort \
    )

}

function fakeTime() {
  # fake the modification time of a file
  local file="${1}"
  local refFile="${2}"

  logMsg "DEBUG: reference file time: "$(date --reference="${refFile}")
  touch -m --reference="${refFile}" "${file}" >/dev/null 2>&1
  logMsg "DEBUG: new file time:"$(date --reference=${file})
}
function nudgeTime() {
  # move the modification time of a file forward one minute
  local file="${1}"
  local oldTime=$(date --reference="${file}")
  logMsg "DEBUG: old file time: ${oldTime}"
  touch -m --date="${oldTime} + 1 minute" "${file}" >/dev/null 2>&1
  logMsg "DEBUG: new file time:"$(date --reference=${file})
}

function mkRin() {
    local sbf=${1}
    local rin=${2}

    if [[ ! "yes" = ${doRIN} ]]; then logMsg "NOTICE: skipping RINEX production."; return 0; fi

    if [ -z "${rin}" ]; then logMsg "ERROR: need output name for RINEX data"; exit 1; fi
    logMsg "NOTICE: processing SBF data into RINEX files..."

    ${sbf2rinProg} -v -f "${sbf}" -o "${rin}" -R210 >/dev/null 2>${rin}.log
    ${sbf2rinProg} -v -f "${sbf}" -o "${rin%O}N" -n N -R210 >/dev/null 2>${rin%O}N.log
    ${sbf2rinProg} -v -f "${sbf}" -o "${rin%O}G" -n G -R210 >/dev/null 2>${rin%O}G.log
    if [ ! ${?} -eq 0 ]; then {
        logMsg "WARNING: failed to process SBF data to RINEX."
    } fi
    logMsg "NOTICE: done." 

}

function getMJD() {
  local yr=${1}
  if [[ $yr -lt 12 || $yr -gt 50 ]]; then logMsg "ERROR: current year, 20$yr, is not in my MJD tables."; return 1; fi

    # mtch year with MJD
    case ${yr} in
        12)         __yrMJD=55927;;
        13)         __yrMJD=56293;;
        14)         __yrMJD=56658;;
        15)         __yrMJD=57023;;
        16)         __yrMJD=57388;;
        17)         __yrMJD=57754;;
        18)         __yrMJD=58119;;
        19)         __yrMJD=58484;;
        20)         __yrMJD=58849;;
        21)         __yrMJD=59215;;
        22)         __yrMJD=59580;;
        23)         __yrMJD=59945;;
        24)         __yrMJD=60310;;
        25)         __yrMJD=60676;;
        26)         __yrMJD=61041;;
        27)         __yrMJD=61406;;
        28)         __yrMJD=61771;;
        29)         __yrMJD=62137;;
        30)         __yrMJD=62502;;
        31)         __yrMJD=62867;;
        32)         __yrMJD=63232;;
        33)         __yrMJD=63598;;
        34)         __yrMJD=63963;;
        35)         __yrMJD=64328;;
        36)         __yrMJD=64693;;
        37)         __yrMJD=65059;;
        38)         __yrMJD=65424;;
        39)         __yrMJD=65789;;
        40)         __yrMJD=66154;;
        41)         __yrMJD=66520;;
        42)         __yrMJD=66885;;
        43)         __yrMJD=67250;;
        44)         __yrMJD=67615;;
        45)         __yrMJD=67981;;
        46)         __yrMJD=68346;;
        47)         __yrMJD=68711;;
        48)         __yrMJD=69076;;
        49)         __yrMJD=69442;;
        50)         __yrMJD=69807;;
    esac

}

function mkCGG() {
    local prev=${1}
    local curr=${2}
    local id=${3}
    local rxName=$( getRxName "${id}" ${yr} ${day} )
    local subDir=${4}
    local typ=${5}
    local day=${6}
    local yr=${7}

    if [[ ! "yes" = ${doCGG} ]]; then logMsg "NOTICE: skipping CGGTTS production."; return 0; fi
    #logMsg "NOTICE: Working on RINEX/CGGTTS data for id ${id}, day ${day}, year 20${yr}"

    local yrMJD=0
    getMJD ${yr}
    if [[ ! $? -eq 0 ]]; then logMsg "WARNING: skipping CGGTTS production, MJD lookup failed."; return 0; fi
    yrMJD=$__yrMJD
    getMJD $(( ${yr} - 1 ))  # check the previous year
    lastYrMJD=$__yrMJD
    mjdDiff=$(( $yrMJD - $lastYrMJD )) 
    if [[ ${mjdDiff} -eq 365 || ${mjdDiff} -eq 366 ]]; then {
      : # everything seems okay
    } else {
      logMsg "ERROR: something is wrong with MJD lookup.  Consecutive January 1st's differ by ${mjdDiff}"
      logMsg "WARNING: skipping CGGTTS production, MJD lookup failed."
      return 0
    } fi

    # add day, must eliminate leady zeros to do math
    local dday=$( echo ${day} | sed -e 's/0*//' )
    local yesterday=$((${dday}-1))
    if ! [[ ${prev} =~ ${yesterday} ]] ; then {
      echo "WARNING: files ${prev} and ${curr} are not consecuitive days, skipping CGGTTS production"
      return 0
    } fi
    # calculate mjd for *yesterday*
    local mjd=$((${yrMJD} + ${yesterday} -1 ))

    ln -s --force "${prev}" rinex_obs
    ln -s --force "${prev%O}N" rinex_nav
    ln -s --force "${prev%O}G" rinex_glo
    ln -s --force "${curr}" rinex_obs_p
    ln -s --force "${curr%O}N" rinex_nav_p
    ln -s --force "${curr%O}G" rinex_glo_p

    set +e
    logMsg "NOTICE: Generating CGGTTS file for day ${yesterday}, MJD $mjd..."
    eval local cggParamFile="${cggTopDir}/${cggParam}.${id}" 
    if [ ! -e "${cggParamFile}" ] ; then {
        logMsg "ERROR: cannot create CGGTTS, cannot find parameters: ${cggParamFile}"
        rm rinex_*
        return 1
    } fi
    ln -s --force "${cggParamFile}" ${cggParam}
    echo ${mjd} | ${rin2cggProg} >/dev/null
    eCode=$?
    logMsg "DEBUG: rin2ccg exit Code: ${eCode}"
    local cggFile=
    if [[ ${eCode} -eq 0 && -f CGGTTS.gps ]]; then
        cggFile="${cggTopDir}/${rxName}/${subDir}/CGGTTS.${id}.${typ}.yr${yr}.day${day}.mjd${mjd}"
        local cggStoreDir=$(dirname ${cggFile})
        if [ ! -d ${cggStoreDir} ]; then mkdir --parents ${cggStoreDir}; fi
        logMsg "NOTICE: ...Done"
        [[ -f CGGTTS.gps ]] && mv CGGTTS.gps "${cggFile}.gps"
        [[ -f CGGTTS.out ]] && mv CGGTTS.out "${cggFile}.out"
        [[ -f CGGTTS.log ]] && mv CGGTTS.log "${cggFile}.log"

        logMsg "NOTICE: compressing CGGTTS data..."
        gzip -c ${cggFile}.gps >${cggFile}.gps.gz
        rm ${cggFile}.gps
        gzip -c ${cggFile}.log >${cggFile}.log.gz
        rm ${cggFile}.log
    else
        logMsg "WARNING: failed to process RINEX data to CGGTTS for day ${day}"
        cat CGGTTS.log 1>&2
        #[[ -f CGGTTS.gps ]] && rm CGGTTS.gps
        #[[ -f CGGTTS.out ]] && rm CGGTTS.out
        #[[ -f CGGTTS.log ]] && rm CGGTTS.log
        rm rinex_*
        rm ${cggParam}
    fi

    logMsg "NOTICE: ...done."

    rmList=$(ls rinex_* CGGTTS.* ${cggParam} 2>/dev/null)
    echo Removing files: ${rmList}
    rm ${rmList}
}

# puts extracted data into the final archive location
function storeData() {
  local dataFile="${1}"
  local logFile="${2}"
  local sbfFile="${3}"
  local archiveFullName="${4}"

  local finalDir=$(dirname "${archiveFullName}")  # deduce directory
  if [[ -e ${finalDir}/${dataFile}.${zExt} && "no" == "${clobber}" ]]; then {
    # clobber disabled, but file exists, bail
    logMsg "WARNING: Refused to overwrite ${finalDir}/${dataFile}.${zExt}.  (--noclobber used)"
    return 0
  } fi

  if [[ -e ${finalDir}/${dataFile}.${zExt} ]]; then {
    # file already exists in archive directory
    # overwrite archive file
    # but first, overload mtime, force extracted data to have mtime just
    # a bit more advanced than the previously archived data file
    fakeTime "${dataFile}" "${finalDir}/${dataFile}.${zExt}"  # set the same
    nudgeTime "${dataFile}" # then nudge it
    logMsg "DEBUG: archive exists, nudging extraction mtime: "$(date --reference="${dataFile}")
  } else {
    # new archive file
    fakeTime "${dataFile}" "${sbfFile}" # force extracted data to have mtime of source
    logMsg "DEBUG: new archive file, forced time of extraction: "$(date --reference="${dataFile}")
  } fi

  # compress file
  ${zProg} "${dataFile}"
  ${zProg} "${logFile}"
  logMsg "DEBUG: forced time of compressed file: "$(date --reference="${dataFile}.${zExt}")

  if [[ ! -d ${finalDir} ]]; then mkdir --parents ${finalDir}; fi

  mv  "${dataFile}.${zExt}" "${finalDir}"/.
  mv  "${logFile}.${zExt}" "${finalDir}"/.
}

# generic extraction using given python script
function sbfExtract() {
  local sbfFile="${1}"
  local id=${2}
  local rxName=$( getRxName "${id}" ${yr} ${day} )
  local element=${3}
  local typ=${4}
  local yr=${5}
  local day=${6}
  local part=${7}
  local blkType=${8}

  local doType="do${blkType}"
  local progType="sbf2${blkType}"
  local extractProg="${!progType}"
  logMsg "DEBUG: extractProg=${extractProg}"
  logMsg "DEBUG: doType=${doType} !doType=${!doType}"

  if [[ ! yes = ${!doType} ]]; then logMsg "NOTICE: skipping ${blkType} extraction."; return 0; fi
  logMsg "NOTICE: extracting ${blkType} data with program ${extractProg}"
  local typeFile="${blkType}FileName"
  eval local outfile="${!typeFile}"
  outfile="$( echo ${outfile} | sed 's/\.part0//')"
  local errfile="${outfile%%dat}log"
  logMsg "DEBUG: outfile=${outfile} errfile=${errfile}"
  local dirType="${blkType}Dir"
  eval local finalDir="${!dirType}"
  logMsg "DEBUG: finalDir=${finalDir}"
  #exit 10 # DEBUG
  python2.7 "${extractProg}" "${sbfFile}" >"${outfile}" 2>"${errfile}"
  storeData "${outfile}" "${errfile}" "${sbfFile}" "${finalDir}/${outfile}"
  [[ -e "${outfile}" ]] && rm "${outfile}"
  [[ -e "${errfile}" ]] && rm "${errfile}"
  #exit 10 # DEBUG
}

function mkReport() {
# make a report using the sbfanalyzer program and templates
  local sbfFile="${1}"
  local id=${2}
  local rxName=$( getRxName "${id}" ${yr} ${day} )
  local element=${3}
  local typ=${4}
  local yr=${5}
  local day=${6}
  local part=${7}
  local reportTemplate=${8}
  local reportDir=${9}
  local reportFileName=${10}
  local doReport=${11}

  if [[ ! "yes" = ${doReport} ]]; then logMsg "NOTICE: skipping report generation."; return 0; fi
  logMsg "NOTICE: running report ${reportTemplate##*/}"
  eval local outfile="${reportFileName}"
  outfile="$( echo ${outfile} | sed 's/\.part0//')"
  eval local finalDir="${reportDir}"
  local errfile="${outfile%%pdf}log"
  logMsg "DEBUG: outfile=${outfile} errfile=${errfile}"
  ${reportProg} -f "${sbfFile}" --layoutfile "${reportTemplate}" \
                --silent --logfile ${errfile} -o ${outfile}
  if [[ ! -d ${finalDir} ]]; then mkdir --parents ${finalDir}; fi
  logMsg "DEBUG: moving report file to ${finalDir}/${outfile}"
  if [[ "yes" = "${clobber}" || ! -e ${finalDir}/${outfile} ]]; then {
    mv  "${outfile}" "${finalDir}"/.
    ${zProg} -c "${errfile}" >${errfile}.${zExt}
    mv  "${errfile}.${zExt}" "${finalDir}"/.
  } else {
    logMsg "WARNING: Refused to overwrite ${finalDir}/${outfile}.  (--noclobber used)"
  } fi
  #rm "${outfile}"
  rm "${errfile}"
}

function mk3day() {
# make a combination RINEX file from three consecutive day RINEX files
  local old="${1}"
  local prev="${2}"
  local curr="${3}"
  local id=${4}
  local element=${5}
  local typ=${6}
  local day=${7}
  local yr=${8}
  local part=${9}
  local doThis=${10}

  if [[ ! "yes" = ${doThis} ]]; then logMsg "NOTICE: skipping 3-day combo RINEX production"; return 0; fi

  # TODO: check consecutive days
  local prevDay=$(expr ${day} - 1 )   # the output date will be the previous day, middle of three files passed
  local prevPrevDay=$(expr ${day} - 2 )   # the output date will be the previous day, middle of three files passed
  if [[ ${curr} =~ ${id}${day} && ${prev} =~ ${id}${prevDay} && ${prev} =~ ${id}${prevDay} ]]; then {
    logMsg "WARNING: skipping 3-day RINEX production, last 3 files are not in sequence";  return 0
  } fi
  
  # choose the correct directory for consolidata/ using Nick's convention
  local subDir=""
  case ${id} in
    ??00)             subDir=NU1;;
    ??01)             subDir=SK;;
    TOKA)             subDir=ND280;;
    ??04)             subDir=Trav;;
  esac

  logMsg "NOTICE: running 3-day RINEX"
  local dayDir=$(date --date="1 Jan ${century}${yr} + ${prevDay} days - 1 day" +%Y%m%d) # -1 day for not counting 1 Jan
  eval local finalDir="${consolidataDir}/${subDir}/${dayDir}"
  eval local outfile=${id}${prevDay}${part}c.${yr}O
  local errfile="${outfile}.log"
  logMsg "DEBUG: outfile=${outfile} errfile=${errfile} finalDir=${finalDir}"

  # pick the start and end time for the first/oldest of three days: last 2 hours
  local st=$(date --date="22:00:00 1 Jan ${century}${yr} + ${day} days - 2 days - 1 day" +%Y,%m,%d,%H,%M,%S) # -2 days before current day, as passed in; -1 extra day for January 1
  local et=$(date --date="23:59:59 1 Jan ${century}${yr} + ${day} days - 2 days - 1 day" +%Y,%m,%d,%H,%M,%S)
  $gpstkbin/EditRinex -IF"${oldRINEX}" \
                      -OF"${oldRINEX}-3day" \
                      -l"${oldRINEX}-3day.log" \
                      -DST -DSS \
                      -TB${st} -TE${et}
  # take all of the second/previous day, this is the day we're working on
  $gpstkbin/EditRinex -IF"${prevRINEX}" \
                      -OF"${prevRINEX}-3day" \
                      -l"${prevRINEX}-3day.log" \
                      -DST -DSS
  # take just the first 16 seconds of the thrid/current day
  local st=$(date --date="00:00:00 1 Jan ${century}${yr} + ${day} days - 1 day" +%Y,%m,%d,%H,%M,%S)
  local et=$(date --date="00:00:15 1 Jan ${century}${yr} + ${day} days - 1 day" +%Y,%m,%d,%H,%M,%S)
  $gpstkbin/EditRinex -IF"${currRINEX}" \
                      -OF"${currRINEX}-3day" \
                      -l"${currRINEX}-3day.log" \
                      -DST -DSS \
                      -TB${st} -TE${et}

  $gpstkbin/mergeRinObs -i "${oldRINEX}-3day" \
                        -i "${prevRINEX}-3day" \
                        -i "${currRINEX}-3day" \
                        -o "${outfile}-tmp"
                        #-o "${prevRINEX%%${day}}c.${yr}O"

  # ???
  cat "${outfile}-tmp" | /home/gurfler/newgps/RNXCMP_4.0.5_Linux_x86_32bit/bin/RNX2CRX > ${outfile}
  # make a log file out of all previous logs
  cat *-3day*.log > ${errfile}

  if [[ ! -d ${finalDir} ]]; then mkdir --parents ${finalDir}; fi
  logMsg "DEBUG: moving 3-day combined RINEX file to ${finalDir}/${outfile}"
  if [[ "yes" = "${clobber}" || ! -e ${finalDir}/${outfile} ]]; then {
    ${zProg} -c "${outfile}" >${outfile}.${zExt}
    mv  "${outfile}.${zExt}" "${finalDir}"/.
    ${zProg} -c "${errfile}" >${errfile}.${zExt}
    mv  "${errfile}.${zExt}" "${finalDir}"/.
  } else {
    logMsg "WARNING: Refused to overwrite ${finalDir}/${outfile}.  (--noclobber used)"
  } fi

  # clean up
  for rmFile in *-3day* "${outfile}-tmp" ${outfile} ${errfile} ; do {
    [ -e "${rmFile}" ] && rm "${rmFile}"
  } done
}

function processSBF() {
    id=${1}
    top=$PWD
    set +e

    logMsg "working on id=${id}"

    for element in ${pathGrps}; do {
        currSBF="currSBF"
        prevRINEX=""
        oldRINEX=""

        getSBF ${element} ${id} "${erex}" "${beginTime}" "${endTime}" > "${sbfFileList}"
        while read file; do {
            logMsg "NOTICE: working on SBF file: ${file}"

            # parse filename
            local typ="int"
            [[ ${element} =~ External ]] && typ="ext"
            [[ ${element} =~ ND280 ]] && typ="int"
            local dir=$(dirname "${file}")
            local basename=$(basename "${file}")
            local unzipped="${basename%%.gz}"
            currSBF="${id}.${typ}.${unzipped}"
            rinexFile="$( echo ${unzipped%_}O|tr '[:lower:]' '[:upper:]' )"

            local values=$(echo ${unzipped}| sed 's/\(....\)\(...\)\(.\)\.\(..\)./\1 \2 \3 \4/')
            if [[ -z ${values} ]]; then logMsg "ERROR: couldn't understand filename, ${unzipped}, as an SBF file"; exit 1 ; fi
            set ${values}
            local day=${2}
            local part=${3}
            local yr=${4}

            local rxName=$( getRxName "${id}" ${yr} ${day} ${yr} ${day} )
            logMsg "DEBUG: basename=${basename},unzipped=${unzipped},currSBF=${currSBF},rinexFile=${rinexFile},element=${element},id=${id},rxName=${rxName},typ=${typ},day=${day},part=${part},yr=${yr}"
            if [[ "yes" = "${dryrun}" ]]; then logMsg "NOTICE: DRY-RUN, skipping processing."; continue; fi

            if [[ ! -e ${currSBF} ]]; then {
              if [[ ${file} =~ \\.gz ]]; then {
                # file is gz compressed
                logMsg "NOTICE: uncompressing SBF file ${currSBF}..."
                gzip -dc "${file}" > "${currSBF}"
                logMsg "NOTICE: ...done"
              } else {
                ln -s "${file}" "${currSBF}"
              } fi
            } fi 

            # extract xPPSOffset data
            sbfExtract "${currSBF}" "${id}" "${element}" "${typ}" "${yr}" "${day}" "${part}" offset

            # extract PVTGeodetic data
            sbfExtract "${currSBF}" "${id}" "${element}" "${typ}" "${yr}" "${day}" "${part}" pvtGeo

            # extract rxStatus data
            sbfExtract "${currSBF}" "${id}" "${element}" "${typ}" "${yr}" "${day}" "${part}" rxStat

            # extract DOP data
            sbfExtract "${currSBF}" "${id}" "${element}" "${typ}" "${yr}" "${day}" "${part}" dop

            # extract GLOtime data
            sbfExtract "${currSBF}" "${id}" "${element}" "${typ}" "${yr}" "${day}" "${part}" GLOtime

            # extract GLOtime data
            sbfExtract "${currSBF}" "${id}" "${element}" "${typ}" "${yr}" "${day}" "${part}" PVTSat

            # extract SBF GPS Performace Report
            mkReport "${currSBF}" "${id}" "${element}" "${typ}" "${yr}" "${day}" "${part}" "${report1Template}" "${report1Dir}" "${report1FileName}" "${doReport1}"

            # make RINEX
            currRINEX="${rinexFile}"
            eval rinStoreDir="${rinexDir}"
            oldStoreFile="${rinStoreDir}/${currRINEX}.gz"
            if [[ -f "${oldStoreFile}" && no = ${rebuild} ]]; then {
              # pull copy form existing rinex datastore
              logMsg "WARNING: retrieving RINEX file from storage: ${oldStoreFile}, not recreateing, rebuild=no"
              gzip -dc ${oldStoreFile} > ${currRINEX}
            } fi
            if [[ ! -e "${currRINEX}" || "yes" = "${rebuild}" ]]; then {
                mkRin ${currSBF} ${currRINEX}
            } else {
                logMsg "WARNING: ${currRINEX} exists, not recreateing"
            } fi

            # make CGGTTS
            if [[ ! -z "${prevRINEX}" && -e "${prevRINEX}" ]]; then {
               mkCGG ${prevRINEX} ${currRINEX} ${id} ${element} ${typ} ${day} ${yr}
            } fi

            # make 3-day RINEX
            if [[ ! -z "${oldRINEX}" && -e "${oldRINEX}" ]]; then {
              mk3day ${oldRINEX} ${prevRINEX} ${currRINEX} ${id} ${element} ${typ} ${day} ${yr} ${part} ${do3day}
            } fi

            # put RINEX file in organized location
            logMsg "NOTICE: compressing and storing RINEX data"
            for rinfile in ${rinexFile%O}*; do {
                if [ ! -f "${rinfile}" ]; then {
                  logMsg "WARNING: cannot find RINEX file ${rinfile}, mkRin failed??"
                  continue
                } fi
                echo -n . 1>&2
                rinZ="${rinfile}.gz"
                #eval rinStoreDir="${rinexDir}"
                storeFile="${rinStoreDir}/${rinZ}"
                if [ ! -d ${rinStoreDir} ]; then mkdir --parents ${rinStoreDir}; fi
                if [[ "yes" = "${clobber}" || ! -e ${storeFile} ]]; then {
                    gzip -c ${rinfile} >${rinZ}
                    mv  ${rinZ} ${storeFile}
                } else {
                    logMsg "WARNING: Refused to overwrite ${storeFile}.  (--noclobber used)"
                } fi
            } done
            logMsg "NOTICE: done."

            # rotate RINEX pointers to keep 3 days worth
            if [[ ! -z "${oldRINEX%O}" ]]; then [ -f ${oldRINEX} ] && rm ${oldRINEX%O}*; fi
            oldRINEX="${prevRINEX}"
            prevRINEX="${currRINEX}"

        } done < "${sbfFileList}"

        # clean up
        [[ -e "${sbfFileList}" ]] && rm "${sbfFileList}"
        for pattrn in ${currSBF} '*????????.??[_ONG]*' ; do {
            if [[ ! -z "${pattrn}" ]]; then {
                for oldfile in ${pattrn}; do {
                    [[ -e ${oldfile} ]] && rm "${oldfile}"
                } done
            } fi
        } done

    } done

    cd ${top}

}

## MAIN ##

# parse command line options
while [[ ${#} -gt 0 ]] 
do
    case ${1} in 
        allon|--allon  )        doRIN="yes";doCGG="yes";dooffset="yes";dopvtGeo="yes";dorxStat="yes";dodop="yes";doGLOtime="yes";doPVTSat="yes";do3day="yes"; shift;;
        alloff|--alloff )       doRIN="no";doCGG="no";dooffset="no";dopvtGeo="no";dorxStat="no";dodop="no";doGLOtime="no";doPVTSat="no";do3day="no"; shift;;

        nocl*|noCL*|--nocl* )   clobber="no"; shift;;
        reb*|REB*|--reb* )      rebuild="yes"; shift;;
        rin*|RIN*|--rin* )      doRIN="yes"; shift;;
        cgg*|CGG*|--cgg* )      doCGG="yes"; doRIN="yes"; shift;;
        off*|OFF*|--off* )      dooffset="yes"; shift;;
        xpps*|XPPS*|--xpps* )   dooffset="yes"; shift;;
        xpps*|XPPS*|--xpps* )   dooffset="yes"; shift;;
        geo*|GEO*|--geo* )      dopvtGeo="yes"; shift;;
        stat*|STAT*|--stat* )   dorxStat="yes"; shift;;
        DOP*|DOP*|--dop* )      dodop="yes"; shift;;
        GLO*|GLO*|--glo* )      doGLOtime="yes"; shift;;
        rep1|REP1|--rep1)       doReport1="yes"; shift;; 
        sats|SATS|--sats)       doPVTSat="yes"; shift;; # constellation breakdown
        3day|3DAY|--3day)       do3day="yes"; shift;; # 3-day combo RINEX files

        norin*|NORIN*|--norin* )      doRIN="no"; doCGG="no"; shift;;
        nocgg*|NOCGG*|--nocgg* )      doCGG="no"; shift;;
        nooff*|NOOFF*|--nooff* )      dooffset="no"; shift;;
        noxpps*|NOXPPS*|--noxpps* )   dooffset="no"; shift;;
        nogeo*|NOGEO*|--nogeo* )      dopvtGeo="no"; shift;;
        nostat*|NOSTAT*|--nostat* )   dorxStat="no"; shift;;
        noDOP*|NODOP*|--nodop* )      dodop="no"; shift;;
        noGLO*|NOGLO*|--noglo* )      doGLOtime="no"; shift;;
        norep1|NOREP1|--norep1)       doReport1="no"; shift;; #GPS Performance Report
        nosats|NOSATS|--nosats)       doPVTSat="no"; shift;; # constellation breakdown
        no3day|NO3DAY|--no3day)       do3day="no"; shift;; # 3-day combo RINEX files

        --dir*|--top* )         shift; eval resultsTopDir=\"$(readlink -m "${1}")\"; shift;;
        --sbf*)                 shift; eval sbfTopDir=\"$(readlink -m "${1}")\"; shift;;
        --ctools*)              shift; eval consolidateToolsDir=\"$(readlink -m "${1}")\"; shift;;
        --consol*)              shift; eval consolidataDir=\"$(readlink -m "${1}")\"; shift;;

        --begin*)               shift; eval beginTime="$(date --date="${1}" --utc +%Y%m%d%H%M)"; shift;;
        --end*)                 shift; eval endTime="$(date --date="${1}" --utc +%Y%m%d%H%M)"; shift;;

        dry*|--dry* )           dryrun="yes"; logMsg "NOTICE: dry-run, processing will be skipped"; shift;;
        debug*|--debug* )       DEBUG="yes"; shift;;
        lz*|--lz* )             zProg="lzop"; zExt=".lzo" shift;;
        gz*|--gz* )             zProg="gzip"; zExt=".gz" shift;;
        *)                      erex=${1}; shift;;
    esac
done

doConfig # configure extra things & do some checks

logMsg "DEBUG: DEBUG enabled"
logMsg DEBUG: clobber = ${clobber}
logMsg DEBUG: erex = ${erex}
logMsg DEBUG: rebuild = ${rebuild}
logMsg "DEBUG: resultsTopDir = ${resultsTopDir}"
logMsg "DEBUG: sbfTopDir = ${sbfTopDir}"

# use good temporary directory
origWD="${PWD}"
tmpDir=$(mktemp -d /tmp/mkRINEX.XXXXX)
sbfFileList="/${tmpDir}/sbfFileList.$$"

# trap exit for cleanup
trapCmd="cd \"${origWD}\"; rm -rf \"${tmpDir}\""
trap "${trapCmd}" EXIT
logMsg "DEBUG: traps : " && trap -p

cd "${tmpDir}"

#exit 9 #DEBUG
for id in ${recvList}
do
    set -e 
    #logMsg DEBUG: $PWD
    processSBF ${id}
done
