#!/bin/bash


#sbfTopDir="/home/t2k/public_html/post/gpsgroup/ptdata"
sbfTopDir="/data-scratch"
#resultsTopDir="./testTopDir"
resultsTopDir="/home/t2k/public_html/post/gpsgroup/ptdata/organizedData"
recvList="PT00 PT01 TOKA PT04"
#recvNiceName[PT00]="NU1SeptentrioGPS-PT00"
#recvNiceName[PT01]="RnHutSeptentrioGPS-PT01"
#recvNiceName[TOKA]="NM-ND280SeptentrioGPS-TOKA"
#recvNiceName[PT04]="TravelerGPS-PT04"
recvNiceNameList="PT00:NU1SeptentrioGPS-PT00
PT01:RnHutSeptentrioGPS-PT01
TOKA:NM-ND280SeptentrioGPS-TOKA
PT04:TravelerGPS-PT04"
pathGrps="GPSData_Internal GPSData_External ND280"
rinexTopDir="${resultsTopDir}/rinex"
rinexDir='${rinexTopDir}/${rxName}/${element}'
cggTopDir="${resultsTopDir}/cggtts"
cggParam="paramCGGTTS.dat"
sbf2rinProg="/usr/local/RxTools/bin/sbf2rin"
rin2cggProg="/usr/local/RxTools/bin/rin2cgg"
rinFileName='${id}${day}'
sbf2offsetProg="/home/pdestefa/local/src/samples/sbf2offset.py"
offsetTopDir="${resultsTopDir}/xPPSOffsets"
offsetDir='${offsetTopDir}/${rxName}/${element}'
offsetFileName='xppsoffset.${id}.${typ}.yr${yr}.day${day}.part${part}.dat'
sbf2pvtGeoProg="/home/pdestefa/local/src/samples/sbf2PVTGeo.py"
pvtGeoTopDir="${resultsTopDir}/pvtGeodetic"
pvtGeoDir='${pvtGeoTopDir}/${rxName}/${element}'
pvtGeoFileName='pvtGeo.${id}.${typ}.yr${yr}.day${day}.part${part}.dat'
sbf2statProg="/home/pdestefa/local/src/samples/sbf2status.py"
rxStatTopDir="${resultsTopDir}/rxStatus"
rxStatDir='${rxStatTopDir}/${rxName}/${element}'
rxStatFileName='rxStatus.${id}.${typ}.yr${yr}.day${day}.part${part}.dat'
sbf2dopProg="/home/pdestefa/local/src/samples/sbf2dop.py"
dopTopDir="${resultsTopDir}/rxDOP"
dopDir='${dopTopDir}/${rxName}/${element}'
dopFileName='rxDOP.${id}.${typ}.yr${yr}.day${day}.part${part}.dat'
sbf2GLOtime="/home/pdestefa/local/src/samples/sbf2GLOtime.py"
GLOtimeTopDir="${resultsTopDir}/GLOtime"
GLOtimeDir='${GLOtimeTopDir}/${rxName}/${element}'
GLOtimeFileName='GLOtime.${id}.${typ}.yr${yr}.day${day}.part${part}.dat'
sbfFileList="/tmp/sbfFileList.$$"
zProg="lzop"
zExt="lzo"
erex=".13_"
clobber="yes"
rebuild="no"
doRIN="yes"
doCGG="yes"
doOff="yes"
doGEO="yes"
doStat="yes"
doDOP="yes"
doGLOtime="yes"
dryrun="no"

trap '[[ -e "${sbfFileList}" ]] && rm "${sbfFileList}"' EXIT 0

function logMsg() {
    echo "$@" 1>&2
}

function getRxName() {
  local id=${1}
  
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
    #local rxName=${recvNiceName[${id}]}
    local rxName=$( getRxName ${id} )
    local extraRegex=${3}
    logMsg "NOTICE: working on element ${element}"

    # find SBF files
    ( /usr/bin/find ${sbfTopDir}/sukrnh5/DATA ${sbfTopDir}/gpsptnu1 ${sbfTopDir}/triptgsc/nd280data ${sbfTopDir}/traveller-box \
        -type f -iwholename "*${element}*${id}*.??_*" \
        2>/dev/null \
        | egrep -i "${extraRegex}" \
        | fgrep -v /old/ \
        | sort \
    )

}

function mkRin() {
    local sbf=${1}
    local rin=${2}

    if [[ ! "yes" = ${doRIN} ]]; then logMsg "NOTICE: skipping RINEX production."; return 0; fi

    if [ -z "${rin}" ]; then logMsg ERROR: need output name for RINEX data; exit 1; fi
    logMsg "NOTICE: processing SBF data into RINEX files..."

    ${sbf2rinProg} -v -f "${sbf}" -o "${rin}" -R210 >/dev/null 2>/${rin}.log
    ${sbf2rinProg} -v -f "${sbf}" -o "${rin%O}N" -n N -R210 >/dev/null 2>/${rin}.log
    ${sbf2rinProg} -v -f "${sbf}" -o "${rin%O}G" -n G -R210 >/dev/null 2>/${rin}.log
    if [ ! ${?} -eq 0 ]; then {
        logMsg "WARNING: failed to process SBF data to RINEX."
    } fi
    logMsg "NOTICE: done." 

}

function mkCGG() {
    local prev=${1}
    local curr=${2}
    local id=${3}
    #local rxName=${recvNiceName[${id}]}
    local rxName=$( getRxName "${id}" )
    local subDir=${4}
    local typ=${5}
    local day=${6}
    local yr=${7}

    if [[ ! "yes" = ${doCGG} ]]; then logMsg "NOTICE: skipping CGGTTS production."; return 0; fi
    #logMsg "NOTICE: Working on RINEX/CGGTTS data for id ${id}, day ${day}, year 20${yr}"

    # mtch year with MJD
    case ${yr} in
        12)         yrMJD=55927;;
        13)         yrMJD=56293;;
        14)         yrMJD=56658;;
    esac

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
    #echo ${mjd} | ( ${rin2cggProg} 1> /dev/null 2>/dev/null )
    echo ${mjd} | ${rin2cggProg} >/dev/null
    eCode=$?
    logMsg "DEBUG: rin2ccg exit Code: ${eCode}"
    if [[ ${eCode} -eq 0 && -f CGGTTS.gps ]]; then
        eval local cggFile="${cggTopDir}/${rxName}/${subDir}/CGGTTS.${id}.${typ}.yr${yr}.day${day}.mjd${mjd}"
        local cggStoreDir=$(dirname ${cggFile})
        if [ ! -d ${cggStoreDir} ]; then mkdir --parents ${cggStoreDir}; fi
        logMsg "NOTICE: ...Done"
        [[ -f CGGTTS.gps ]] && mv CGGTTS.gps "${cggFile}.gps"
        [[ -f CGGTTS.out ]] && mv CGGTTS.out "${cggFile}.out"
        [[ -f CGGTTS.log ]] && mv CGGTTS.log "${cggFile}.log"
    else
        logMsg "WARNING: failed to process RINEX data to CGGTTS for day ${day}"
        cat CGGTTS.log 1>&2
        rm rinex_*
        rm ${cggParam}
    fi

    logMsg "NOTICE: compressing CGGTTS data..."
    gzip -c ${cggFile}.gps >${cggFile}.gps.gz
    rm ${cggFile}.gps
    gzip -c ${cggFile}.log >${cggFile}.log.gz
    rm ${cggFile}.log
    logMsg "NOTICE: ...done."

    rmList=$(ls rinex_* CGGTTS.* ${cggParam} 2>/dev/null)
    echo Removing files: ${rmList}
    rm ${rmList}
}

function mkOffset() {
  local sbfFile="${1}"
  local id=${2}
  #local rxName=${recvNiceName[${id}]}
  local rxName=$( getRxName "${id}" )
  local element=${3}
  local typ=${4}
  local yr=${5}
  local day=${6}
  local part=${7}

  if [[ ! "yes" = ${doOff} ]]; then logMsg "NOTICE: skipping xPPSOffset production."; return 0; fi
  logMsg "NOTICE: extracting xPPSOffset data"
  eval local offsetfile="${offsetFileName}"
  offsetfile="$( echo ${offsetfile} | sed 's/\.part0//')"
  local errfile="${offsetfile%%dat}log"
  logMsg "DEBUG: outfile=${offsetfile} errfile=${errfile}"
  /usr/local/bin/python2.7 "${sbf2offsetProg}" "${sbfFile}" >"${offsetfile}" 2>"${errfile}"
  eval local offsetFinalDir="${offsetDir}"
  if [[ ! -d ${offsetFinalDir} ]]; then mkdir --parents ${offsetFinalDir}; fi
  logMsg "DEBUG: moving offset data to ${offsetFinalDir}/${offsetfile}.${zExt}"
  ${zProg} -c "${offsetfile}" >${offsetfile}.${zExt}
  mv  "${offsetfile}.${zExt}" "${offsetFinalDir}"/.
  rm "${offsetfile}"
  ${zProg} -c "${errfile}" >${errfile}.${zExt}
  mv  "${errfile}.${zExt}" "${offsetFinalDir}"/.
  rm "${errfile}"
}

function mkPVTGeo() {
  local sbfFile="${1}"
  local id=${2}
  #local rxName=${recvNiceName[${id}]}
  local rxName=$( getRxName "${id}" )
  local element=${3}
  local typ=${4}
  local yr=${5}
  local day=${6}
  local part=${7}

  if [[ ! "yes" = ${doGEO} ]]; then logMsg "NOTICE: skipping CGGTTS production."; return 0; fi
  logMsg "NOTICE: extracting PVTGeodetic data"
  eval local pvtGeoFile="${pvtGeoFileName}"
  pvtGeoFile="$( echo ${pvtGeoFile} | sed 's/\.part0//')"
  eval local pvtGeoFinalDir="${pvtGeoDir}"
  local errfile="${pvtGeoFile%%dat}log"
  logMsg "DEBUG: outfile=${pvtGeoFile} errfile=${errfile}"
  /usr/local/bin/python2.7 "${sbf2pvtGeoProg}" "${sbfFile}" >"${pvtGeoFile}" 2>"${errfile}"
  if [[ ! -d ${pvtGeoFinalDir} ]]; then mkdir --parents ${pvtGeoFinalDir}; fi
  logMsg "DEBUG: moving PVTGeodetic data to ${pvtGeoFinalDir}/${pvtGeoFile}.${zExt}"
  ${zProg} -c "${pvtGeoFile}" >${pvtGeoFile}.${zExt}
  mv  "${pvtGeoFile}.${zExt}" "${pvtGeoFinalDir}"/.
  rm "${pvtGeoFile}"
  ${zProg} -c "${errfile}" >${errfile}.${zExt}
  mv  "${errfile}.${zExt}" "${pvtGeoFinalDir}"/.
  rm "${errfile}"
}

function mkRxSatus() {
  local sbfFile="${1}"
  local id=${2}
  local rxName=$( getRxName "${id}" )
  local element=${3}
  local typ=${4}
  local yr=${5}
  local day=${6}
  local part=${7}

  if [[ ! "yes" = ${doStat} ]]; then logMsg "NOTICE: skipping RxStatus production."; return 0; fi
  logMsg "NOTICE: extracting RxStatus data"
  eval local outfile="${rxStatFileName}"
  outfile="$( echo ${outfile} | sed 's/\.part0//')"
  eval local finalDir="${rxStatDir}"
  local errfile="${outfile%%dat}log"
  logMsg "DEBUG: outfile=${outfile} errfile=${errfile}"
  /usr/local/bin/python2.7 "${sbf2statProg}" "${sbfFile}" >"${outfile}" 2>"${outfile%%dat}log"
  if [[ ! -d ${finalDir} ]]; then mkdir --parents ${finalDir}; fi
  logMsg "DEBUG: moving PVTGeodetic data to ${finalDir}/${outfile}.${zExt}"
  ${zProg} -c "${outfile}" >${outfile}.${zExt}
  mv  "${outfile}.${zExt}" "${finalDir}"/.
  rm "${outfile}"
  ${zProg} -c "${errfile}" >${errfile}.${zExt}
  mv  "${errfile}.${zExt}" "${finalDir}"/.
  rm "${errfile}"
}

function mkDOP() {
  local sbfFile="${1}"
  local id=${2}
  local rxName=$( getRxName "${id}" )
  local element=${3}
  local typ=${4}
  local yr=${5}
  local day=${6}
  local part=${7}

  if [[ ! "yes" = ${doDOP} ]]; then logMsg "NOTICE: skipping DOP production."; return 0; fi
  logMsg "NOTICE: extracting DOP data"
  eval local outfile="${dopFileName}"
  outfile="$( echo ${outfile} | sed 's/\.part0//')"
  eval local finalDir="${dopDir}"
  local errfile="${outfile%%dat}log"
  logMsg "DEBUG: outfile=${outfile} errfile=${errfile}"
  /usr/local/bin/python2.7 "${sbf2dopProg}" "${sbfFile}" >"${outfile}" 2>"${outfile%%dat}log"
  if [[ ! -d ${finalDir} ]]; then mkdir --parents ${finalDir}; fi
  logMsg "DEBUG: moving PVTGeodetic data to ${finalDir}/${outfile}.${zExt}"
  ${zProg} -c "${outfile}" >${outfile}.${zExt}
  mv  "${outfile}.${zExt}" "${finalDir}"/.
  rm "${outfile}"
  ${zProg} -c "${errfile}" >${errfile}.${zExt}
  mv  "${errfile}.${zExt}" "${finalDir}"/.
  rm "${errfile}"
}

function sbfExtract() {
  local sbfFile="${1}"
  local id=${2}
  local rxName=$( getRxName "${id}" )
  local element=${3}
  local typ=${4}
  local yr=${5}
  local day=${6}
  local part=${7}
  local blkType=${8}

  local doType="do${blkType}"
  local progType="sbf2${blkType}"
  local extractProg="${!progType}"
  #logMsg "DEBUG: extractProg=${extractProg}"
  #logMsg "DEBUG: doType=${doType} !doType=${!doType}"

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
  /usr/local/bin/python2.7 "${extractProg}" "${sbfFile}" >"${outfile}" 2>"${errfile}"
  if [[ ! -d ${finalDir} ]]; then mkdir --parents ${finalDir}; fi
  logMsg "DEBUG: moving PVTGeodetic data to ${finalDir}/${outfile}.${zExt}"
  ${zProg} -c "${outfile}" >${outfile}.${zExt}
  mv  "${outfile}.${zExt}" "${finalDir}"/.
  rm "${outfile}"
  ${zProg} -c "${errfile}" >${errfile}.${zExt}
  mv  "${errfile}.${zExt}" "${finalDir}"/.
  rm "${errfile}"
  #exit 10 # DEBUG
}

function processSBF() {
    id=${1}
    #local rxName=${recvNiceName["${id}"]}
    local rxName=$( getRxName "${id}" )
    top=$PWD
    #cd ${id}
    set +e

    logMsg "working on id=${id},rxName=${rxName}"

    for element in ${pathGrps}; do {
        currSBF="currSBF"
        prevRINEX=""

        getSBF ${element} ${id} ${erex} > "${sbfFileList}"
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
            mkOffset "${currSBF}" "${id}" "${element}" "${typ}" "${yr}" "${day}" "${part}"

            # extract PVTGeodetic data
            mkPVTGeo "${currSBF}" "${id}" "${element}" "${typ}" "${yr}" "${day}" "${part}"

            # extract rxStatus data
            mkRxSatus "${currSBF}" "${id}" "${element}" "${typ}" "${yr}" "${day}" "${part}"

            # extract DOP data
            mkDOP "${currSBF}" "${id}" "${element}" "${typ}" "${yr}" "${day}" "${part}"

            # extract GLOtime data
            sbfExtract "${currSBF}" "${id}" "${element}" "${typ}" "${yr}" "${day}" "${part}" GLOtime

            # make RINEX
            currRINEX="${rinexFile}"
            if [[ ! -e "${currRINEX}" || "yes" = "${rebuild}" ]]; then {
                mkRin ${currSBF} ${currRINEX}
            } else {
                logMsg "WARNING: ${currRINEX} exists, not recreateing"
            } fi

            # make CGGTTS
            if [[ ! -z "${prevRINEX}" && -e "${prevRINEX}" ]]; then {
               mkCGG ${prevRINEX} ${currRINEX} ${id} ${element} ${typ} ${day} ${yr}
            } fi

            # put RINEX file in organized location
            logMsg "NOTICE: compressing and storing RINEX data"
            for rinfile in ${rinexFile%O}*; do {
                if [ ! -f "${rinfile}" ]; then {
                  logMsg "WARNING: cannot find RINEX file ${rinfile}, mkRin failed??"
                  continue
                } fi
                echo -n . 1>&2
                rinZ=${rinfile}.gz
                #eval rinStoreDir="${rinexTopDir}/${id}/${element}"
                eval rinStoreDir="${rinexDir}"
                storeFile=${rinStoreDir}/${rinZ}
                if [ ! -d ${rinStoreDir} ]; then mkdir --parents ${rinStoreDir}; fi
                if [[ "yes" = "${clobber}" || ! -e ${storeFile} ]]; then {
                    gzip -c ${rinfile} >${rinZ}
                    mv  ${rinZ} ${storeFile}
                } else {
                    logMsg "WARNING: Refused to overwrite ${storeFile}.  (--noclobber used)"
                } fi
            } done
            logMsg "NOTICE: done."

            if [[ ! -z "${prevRINEX%O}" ]]; then [ -f ${prevRINEX} ] && rm ${prevRINEX%O}*; fi
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

while [[ ${#} -gt 0 ]]; do {
    case ${1} in 
        nocl*|noCL*|--nocl* )      clobber="no"; shift;;
        reb*|REB*|--reb* )      rebuild="yes"; shift;;
        rin*|RIN*|--rin* )      doRIN="yes"; shift;;
        cgg*|CGG*|--cgg* )      doCGG="yes"; doRIN="yes"; shift;;
        off*|OFF*|--off* )      doOff="yes"; shift;;
        norin*|NORIN*|--norin* )      doRIN="no"; doCGG="no"; shift;;
        nocgg*|NOCGG*|--nocgg* )      doCGG="no"; shift;;
        nooff*|NOOFF*|--nooff* )      doOff="no"; shift;;
        noxpps*|NOXPPS*|--noxpps* )   doOff="no"; shift;;
        noGEO*|NOGEO*|--nogeo* )      doGEO="no"; shift;;
        nostat*|NOSTAT*|--nostat* )   doStat="no"; shift;;
        noDOP*|NODOP*|--nodop* )      doDOP="no"; shift;;
        noGLO*|NOGLO*|--noglo* )      doGLOtime="no"; shift;;
        dry*|--dry* )           dryrun="yes"; shift;;
        lz*|--lz* )             zProg="lzop"; zExt=".lzo" shift;;
        gz*|--gz* )             zProg="gzip"; zExt=".gz" shift;;
        *)                      erex=${1}; shift;;
    esac
} done

#logMsg DEBUG: clobber = ${clobber}
#logMsg DEBUG: erex = ${erex}
#logMsg DEBUG: rebuild = ${rebuild}

renice 20 -p $$ >/dev/null 2>&1

for id in ${recvList}; do {
    set -e 
    #logMsg DEBUG: $PWD
    processSBF ${id}
} done
