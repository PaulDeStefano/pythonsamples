#!/bin/bash


#sbfTopDir="/home/t2k/public_html/post/gpsgroup/ptdata"
sbfTopDir="/data-scratch"
recvList="PT00 PT01 TOKA PT04"
pathGrps="GPSData_Internal GPSData_External ND280"
rinexTopDir="/home/pdestefa/public_html/organizedData/rinex"
rinexDir='${rinexTopDir}/${id}/${element}'
cggTopDir="/home/pdestefa/public_html/organizedData/cggtts"
cggParam="paramCGGTTS.dat"
sbf2rinProg="/usr/local/RxTools/bin/sbf2rin"
rin2cggProg="/usr/local/RxTools/bin/rin2cgg"
rinFileName='${id}${day}'
sbf2offsetProg="/home/pdestefa/local/src/samples/sbf2offset.py"
offsetTopDir="/home/pdestefa/public_html/organizedData/xPPSOffsets/"
offsetDir='${offsetTopDir}/${id}/${element}'
offsetFileName='xppsoffset.${id}.${typ}.yr${yr}.day${day}.part${part}.dat'
sbf2pvtGeoProg="/home/pdestefa/local/src/samples/sbf2PVTGeo.py"
pvtGeoTopDir="/home/pdestefa/public_html/organizedData/pvtGeodetic/"
pvtGeoDir='${pvtGeoTopDir}/${id}/${element}'
pvtGeoFileName='pvtGeo.${id}.${typ}.yr${yr}.day${day}.part${part}.dat'
sbfFileList="/tmp/sbfFileList"
zProg="lzop"
zExt="lzo"
erex=".13_"
clobber="yes"
rebuild="no"
doRIN="yes"
doCGG="yes"
doOff="yes"
doGEO="yes"
dryrun="no"

function logMsg() {
    echo "$@" 1>&2
}

function getSBF() {
    local element=${1}
    local id=$2
    local extraRegex=${3}
    logMsg "NOTICE: working on element ${element}"

    # find SBF files
    ( /usr/bin/find ${sbfTopDir}/sukrnh5/DATA ${sbfTopDir}/gpsptnu1 ${sbfTopDir}/triptgsc/nd280data ${sbfTopDir}/traveller-box \
        -type f -iwholename "*${element}*${id}*.??_*" \
        2>/dev/null \
        | egrep -i "${extraRegex}" \
        | sort \
    )

}

function mkRin() {
    local sbf=${1}
    local rin=${2}

    if [[ ! "yes" = ${doRIN} ]]; then logMsg "NOTICE: skipping RINEX production."; return 0; fi

    if [ -z "${rin}" ]; then logMsg ERROR: need output name for RINEX data; exit 1; fi
    logMsg "NOTICE: processing SBF data into RINEX files..."

    ${sbf2rinProg} -v -f "${sbf}" -o "${rin}" -R210 >/dev/null
    ${sbf2rinProg} -v -f "${sbf}" -o "${rin%O}N" -n N -R210 >/dev/null
    ${sbf2rinProg} -v -f "${sbf}" -o "${rin%O}G" -n G -R210 >/dev/null
    if [ ! ${?} -eq 0 ]; then {
        logMsg "ERROR: failed to process SBF data to RINEX."
        exit 1
    } fi
    logMsg "NOTICE: done." 

}

function mkCGG() {
    local prev=${1}
    local curr=${2}
    local id=${3}
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
    local cggParamFile="${cggTopDir}/${cggParam}.${id}" 
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
        local cggFile="${cggTopDir}/${id}/${subDir}/CGGTTS.${id}.${typ}.yr${yr}.day${day}.mjd${mjd}"
        local cggStoreDir=$(dirname ${cggFile})
        if [ ! -d ${cggStoreDir} ]; then mkdir --parents ${cggStoreDir}; fi
        logMsg "NOTICE: ...Done"
        [[ -f CGGTTS.gps ]] && mv CGGTTS.gps "${cggFile}.gps"
        [[ -f CGGTTS.out ]] && mv CGGTTS.out "${cggFile}.out"
        [[ -f CGGTTS.log ]] && mv CGGTTS.log "${cggFile}.log"
    else
        logMsg "ERROR: failed to process RINEX data to CGGTTS"
        cat CGGTTS.log 1>&2
        rm rinex_*
        rm ${cggParam}
        exit 1
    fi

    logMsg "NOTICE: compressing CGGTTS data..."
    gzip -c ${cggFile}.gps >${cggFile}.gps.gz
    rm ${cggFile}.gps
    gzip -c ${cggFile}.log >${cggFile}.log.gz
    rm ${cggFile}.log
    logMsg "NOTICE: ...done."

    rm rinex_*
    rm CGGTTS.*
    rm ${cggParam}

}

function mkOffset() {
  local sbfFile="${1}"
  local id=${2}
  local element=${3}
  local typ=${4}
  local yr=${5}
  local day=${6}
  local part=${7}

  if [[ ! "yes" = ${doOff} ]]; then logMsg "NOTICE: skipping xPPSOffset production."; return 0; fi
  logMsg "NOTICE: extracting xPPSOffset data"
  eval local offsetfile="${offsetFileName}"
  offsetfile="$( echo ${offsetfile} | sed 's/\.part0//')"
  /usr/local/bin/python2.7 "${sbf2offsetProg}" "${sbfFile}" >"${offsetfile}"
  eval local offsetFinalDir="${offsetDir}"
  if [[ ! -d ${offsetFinalDir} ]]; then mkdir --parents ${offsetFinalDir}; fi
  logMsg "DEBUG: moving offset data to ${offsetFinalDir}/${offsetfile}.${zExt}"
  ${zProg} -c "${offsetfile}" >${offsetfile}.${zExt}
  mv  "${offsetfile}.${zExt}" "${offsetFinalDir}"/.
  rm "${offsetfile}"
}

function mkPVTGeo() {
  local sbfFile="${1}"
  local id=${2}
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
  /usr/local/bin/python2.7 "${sbf2pvtGeoProg}" "${sbfFile}" >"${pvtGeoFile}"
  if [[ ! -d ${pvtGeoFinalDir} ]]; then mkdir --parents ${pvtGeoFinalDir}; fi
  logMsg "DEBUG: moving PVTGeodetic data to ${pvtGeoFinalDir}/${pvtGeoFile}.${zExt}"
  ${zProg} -c "${pvtGeoFile}" >${pvtGeoFile}.${zExt}
  mv  "${pvtGeoFile}.${zExt}" "${pvtGeoFinalDir}"/.
  rm "${pvtGeoFile}"
}

function processSBF() {
    id=${1}
    top=$PWD
    #cd ${id}
    set +e

    logMsg "working on id=" ${id}

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

            logMsg "DEBUG: basename=${basename},unzipped=${unzipped},currSBF=${currSBF},rinexFile=${rinexFile},element=${element},typ=${typ},day=${day},part=${part},yr=${yr}"
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
                echo -n . 1>&2
                rinZ=${rinfile}.gz
                eval rinStoreDir="${rinexTopDir}/${id}/${element}"
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
        noGEO*|NOGEO*|--nogeo* )      doGEO="no"; shift;;
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
