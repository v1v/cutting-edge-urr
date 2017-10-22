#!/bin/bash
# NAME
#       urr - the post cutting edge actions to generate a list of war files
#
# SYNOPSIS

## Load utils library (which included templates and some other utilities)
source "$( dirname "${BASH_SOURCE[0]}" )/utils.sh"
source "$( dirname "${BASH_SOURCE[0]}" )/helper.sh"

SETTINGS="$1"

PME=target/pom.xml.pme
OUTPUT=target/urr.log
if [ -e ${PME} ] ; then
    mvn install -f ${PME} | tee ${OUTPUT}

    groupId=$(get ${PME} "project.groupId" ${SETTINGS})
    artifactId=$(get ${PME} "project.artifactId" ${SETTINGS})
    version=$(get ${PME} "project.version" ${SETTINGS})

    mvn -B install \
        -DversionSuffix=edge \
        -Ddebug \
        -Denforcer.skip \
        -DdependencyManagement=${groupId}:${artifactId}:${version} | tee -a ${OUTPUT}

    build_status=$?

    # List missing dependencies from the envelope
    cat ${OUTPUT} | sed -Ene's#.*Dependency \[(.+)/(.+)\] not found.*\[(.+)\].*#\1 \2 \3#p' | while read line
    do
        echo $line
    done

    # List where that particular maven submodule failed
    pom=$(find products/$(basename `cat ${OUTPUT} | sed -Ene's#.*Working directory: (.+)#\1#p' | tail -n 1`) -name pom.xml)
    echo "It requires to fix the pom '${pom}' and 'pom.xml'"
fi

exit $build_status
