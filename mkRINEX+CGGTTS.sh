#!/bin/bash


sbfTopDir="/home/t2k/public_html/post/gpsgroup/ptdata"
recvList="PT00 PT01"
pathGrps="GPSData_Internal GPSData_External"
rinexTopDir="./rinex"
cggTopDir="./cggtts"
cggParam="paramCGGTTS.dat"
sbf2rinProg="/usr/local/RxTools/bin/sbf2rin"
rin2cggProg="/usr/local/RxTools/bin/rin2cgg"
erex=".13_"
clobber="yes"
rebuild="no"

function logMsg() {
    echo "$@" 1>&2
}

function getSBF() {
    element=${1}
    id=$2
    extraRegex=${3}
    logMsg "NOTICE: working on element ${element}"

    # find SBF files
    ( /usr/bin/find -L ${sbfTopDir} \
        -type f -name "*.??_" \
        2>/dev/null \
        | egrep -i "${element}.*${id}" \
        | egrep -i "${extraRegex}" \
        | sort \
    )

}

function mkRin() {
    sbf=${1}
    rin=${2}

    if [ -z "${rin}" ]; then logMsg ERROR: need output name for RINEX data; exit 1; fi
    logMsg "NOTICE: processing SBF to RINEX data"

    ${sbf2rinProg} -v -f "${sbf}" -o "${rin}" -R210 >/dev/null
    ${sbf2rinProg} -v -f "${sbf}" -o "${rin%O}N" -n N -R210 >/dev/null
    ${sbf2rinProg} -v -f "${sbf}" -o "${rin%O}G" -n G -R210 >/dev/null
    if [ ! ${?} -eq 0 ]; then {
        logMsg "ERROR: failed to process SBF data to RINEX."
        exit 1
    } fi

}

function mkCGG() {
    local prev=${1}
    local curr=${2}
    local id=${3}
    local prevName=${prev}

    # example PT001710.13O
    # example PT00 171 0 . 13 O
    local values=$(echo ${prevName}| sed 's/\(....\)\(...\).\.\(..\)./\1 \2 \3/')
    set ${values}
    local day=${2}
    local yr=${3}

    logMsg "NOTICE: Working on RINEX/CGGTTS data for id ${id}, day ${day}, year 20${yr}"

    # mtch year with MJD
    case ${yr} in
        12)         yrMJD=55927;;
        13)         yrMJD=56293;;
        14)         yrMJD=56658;;
    esac

    # add day
    dday=$( echo ${day} | sed -e 's/0*//' )
    local mjd=$((${yrMJD} + ${dday} - 1 ))

    ln -s --force "${prev}" rinex_obs
    ln -s --force "${prev%O}N" rinex_nav
    ln -s --force "${prev%O}G" rinex_glo
    ln -s --force "${curr}" rinex_obs_p
    ln -s --force "${curr%O}N" rinex_nav_p
    ln -s --force "${curr%O}G" rinex_glo_p

    logMsg "NOTICE: Generating CGGTTS file for MJD $mjd..."
    local cggParamFile="${cggTopDir}/${cggParam}.${id}" 
    if [ ! -e "${cggParamFile}" ] ; then {
        logMsg "ERROR: cannot create CGGTTS, cannot find parameters: ${cggParamFile}"
        rm rinex_*
        return 1
    } fi
    ln -s --force "${cggParamFile}" ${cggParam}
    #echo ${mjd} | ( ${rin2cggProg} 1> /dev/null 2>/dev/null )
    echo ${mjd} | ${rin2cggProg} >/dev/null
    if [[ $? -eq 0 && -f CGGTTS.log ]]; then
        local cggFile="${cggTopDir}/${id}/${mjd}.cggtts"
        local cggStoreDir=$(dirname ${cggFile})
        if [ ! -d ${cggStoreDir} ]; then mkdir --parents ${cggStoreDir}; fi
        logMsg "NOTICE: ...Done"
        [[ -f CGGTTS.gps ]] && mv CGGTTS.gps "${cggFile}.gps"
        [[ -f CGGTTS.out ]] && mv CGGTTS.out "${cggFile}.out"
        [[ -f CGGTTS.log ]] && mv CGGTTS.log "${cggFile}.log"
    else
        logMsg "ERROR: failed to process RINEX data to CGGTTS" 1>&2
        rm rinex_*
        rm ${cggParam}
        exit 1
    fi

    rm rinex_*
    rm ${cggParam}

}

function processSBF() {
    id=${1}
    top=$PWD
    #cd ${id}

    logMsg "working on id=" ${id}

    for element in ${pathGrps}; do {
        currSBF="currSBF"

        getSBF ${element} ${id} ${erex} \
        | while read file; do {
            logMsg "NOTICE: working on SBF file: ${file}"
            # parse filename
            dir=$(dirname "${file}")
            basename=$(basename "${file}")
            currSBF="currSBF"
            rinexFile="$( echo ${basename%_}O|tr '[:lower:]' '[:upper:]' )"

            if [[ -e ${currSBF} ]]; then rm ${currSBF}; fi
            ln -s ${file} ${currSBF}

            # run rin2sbf
            currRINEX="${rinexFile}"
            if [[ ! -e "${currRINEX}" || "yes" = "${rebuild}" ]]; then {
                mkRin ${currSBF} ${currRINEX}
            } else {
                logMsg "WARNING: ${currRINEX} exists, not recreateing"
            } fi

            # make CGGTTS
            if [[ ! -z "${prevRINEX}" && -e "${prevRINEX}" ]]; then {
               mkCGG ${prevRINEX} ${currRINEX} ${id}
            } fi

            # put RINEX file in organized location
            logMsg "NOTICE: compressing and storing RINEX data"
            for file in ${rinexFile%O}*; do {
                echo -n . 1>&2
                rinZ=${file}.gz
                eval rinStoreDir="${rinexTopDir}/${id}/${element}"
                storeFile=${rinStoreDir}/${rinZ}
                if [ ! -d ${rinStoreDir} ]; then mkdir --parents ${rinStoreDir}; fi
                if [[ "yes" = "${clobber}" || ! -e ${storeFile} ]]; then {
                    gzip <${file} >${rinZ}
                    mv ${rinZ} ${storeFile}
                } else {
                    logMsg "WARNING: Refused to overwrite ${storeFile}.  (--noclobber used)"
                } fi
            } done

            if [[ ! -z "${prevRINEX%O}" ]]; then rm ${prevRINEX%O}*; fi
            prevRINEX="${currRINEX}"

        } done

        # clean up
        for prefix in ${currSBF} '???????0.??[_ONG]'; do {
            if [[ ! -z "${prefix}" ]]; then {
                for file in ${prefix}*; do {
                    [[ -e ${file} ]] && rm ${file}
                } done
            } fi
        } done

    } done

    cd ${top}

}

## MAIN ##

while [[ ${#} -gt 0 ]]; do {
    case ${1} in 
        noc*|noC*|--no* )       clobber="no"; shift;;
        reb*|REB*|--reb* )      rebuild="yes"; shift;;
        *)                      erex=${1}; shift;;
    esac
} done

logMsg DEBUG: clobber = ${clobber}
logMsg DEBUG: erex = ${erex}
logMsg DEBUG: rebuild = ${rebuild}

renice 20 -p $$ >/dev/null 2>&1

for id in ${recvList}; do {
    set -e 
    logMsg DEBUG: $PWD
    processSBF ${id}
} done
