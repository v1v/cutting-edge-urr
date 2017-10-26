#!/bin/bash
#
# Helper file which contains the functions used by the edge.sh file
#
# Main difference between utils and helper is the complexity of this one. while
# utils are just a set of more simplitist functions
#

## Load utils library (which included templates and some other utilities)
source "$( dirname "${BASH_SOURCE[0]}" )/utils.sh"

# Private: Transform dependency and return its github url
#
# $1 - Effective POM
# $2 - Repo absolute folder
# $3 - ssh git transformation
# $4 - Override properties
# $5 - Settings
#
# Examples
#
#   getURL  "azure-pom-effective.xml" "./target/azure" true "./override.properties" "~/m2/settings.xml"
#
# Returns the github URL/unreachable/scm and also the errorlevel
#
function getURL {
    effective=$1
    repo=$2
    ssh_git=$3
    override=$4
    settings=$5

    # Validate mandatory ARGUMENTS
    if [ ! -f $effective ] ; then
        echo $CTE_FAILED
        return 1
    fi

    build_log=${repo}.log

    [ -f "${settings}" ] && SETTINGS_="-s ${settings}" || SETTINGS_=""

    # Get effective artifact
    artifactId=$(getPomProperty ${effective} "project.artifactId" ${settings})

    # Override?
    url=$(getOverridedProperty ${override} url.${artifactId})

    if [ -n "${url}" ] ; then
        status=${url}
    else
        # Get url from effective
        url=$(getXMLProperty ${effective} "//project/scm/url")

        # Workaround to fix scm/url entries which are based on scm/connection @scm:git:git://github.com/
        if [ ! -n "${url}" ] ; then
            # scm/connection value format:
            #   <connection>scm:git:git://github.com/jenkinsci/ant-plugin.git</connection>
            #   <connection>scm:git:ssh://git@github.com/cloudbees/${project.artifactId}-plugin.git</connection>
            url=$(getXMLProperty ${effective} "//project/scm/connection" | cut -d':' -f3,4)
        fi

        if [ -n "${url}" ] ; then
            if isReachable ${url} ${ssh_git} ; then  # Sometimes URLs are not reachable
                status=${url}
            else
                status=${CTE_UNREACHABLE}
            fi
        else
            status=${CTE_SCM}
        fi
    fi
    echo ${status}
    [ "$status" == "${CTE_UNREACHABLE}" -o "$status" == "${CTE_SCM}" ] && return 1 || return 0

}

# Public: Get Effective POM
#
# $1 - POM
# $2 - Effective POM
# $3 - Repo absolute folder
# $4 - Settings
#
# Examples
#
#   getEffectivePom "azure-pom.xml" "azure-pom-effective.xml" "./target/azure" "~/m2/settings.xml"
#
# Returns the result of the last command
#
function getEffectivePom {
    pom=$1
    effective=$2
    repo=$3
    settings=$4

    # Validate mandatory ARGUMENTS
    if [ ! -f $pom ] ; then
        echo $CTE_FAILED
        return 1
    fi

    build_log=${repo}.log

    # Normalise packaging issue
    normalisePackagingIssue ${pom}

    # Get effective-pom
    [ -f "${settings}" ] && SETTINGS_="-s ${settings}" || SETTINGS_=""
    mvn -B --quiet ${SETTINGS_} -f ${pom} help:effective-pom -Doutput=${effective} >>${build_log} 2>&1
}

# Private: Transform github urls therefore private repos are accessible
#
# $1 - url
#
#   Effective poms within multimodules might concat module name within the parent SCM
#
# Examples
#
#   transform "https://github.com"
#
# Returns the transformed git URL
#
function transform {
    url=$1

    # Convert scm:git:git://github.com  and scm:git:git@github.com to https
    newurl=$(echo $url | sed -E 's#scm.*github.com(:|/)?#https://github.com/#')

    # Convert git+git repos to git+https
    newurl=$(echo $newurl | sed -E 's#git://github.com(:|/)?#https://github.com/#')

    # Convert repos to github.com/organisation/project
    newurl=$(echo $newurl | sed -Ene's#(.*github.com:?/?/?[^/]*/[^/]*).*#\1#p')

    # Convert to http to https
    newurl=$(echo $newurl | sed -E 's#http:/#https:/#')

    # Convert private organisations to ssh
    if echo "$newurl" | grep --quiet 'cloudbees/'; then
        newurl=$(convertHttps2Git $newurl)
    fi

    echo $newurl
}

# Private: Given a particular URL and repo ti will checkout
#
# $1 - url
# $2 - repo
#
#   Effective poms within multimodules might concat module name within the parent SCM
#
# Examples
#
#   download "https://github.com" "./target/folder"
#
# Returns the status (skipped, unreachable, passed) git URL
#
function download {
    url=$1
    repo=$2

    if [ -d "${repo}" ] ; then
        status=${CTE_SKIPPED}
    else
        git clone --quiet ${url} ${repo} 2> /dev/null
        if [ $? -eq 0 ] ; then
            status=${CTE_PASSED}
        else
            status=${CTE_UNREACHABLE}
        fi
    fi
    echo ${status}
    [ "$status" == "${CTE_UNREACHABLE}" ] && return 1 || return 0
}


# Private: Run build goals in the dependency
#
# $1 - repo folder
# $2 - build_log
# $3 - settings
# $4 - skip_tests
# $5 - recipes folder
#
# Uses CTE variables
#
# Examples
#
#   buildDependency "azure-cli-plugin" "azure-cli-plugin.log" "settings.xml" "true" "recipes"
#
# Returns the exit code of the build status and also print the status.
#
function buildDependency {
    repo=$1
    build_log=$2
    settings=$3
    skip=$4
    recipes=$5

    FLAG_FILE=".status.flag"
    cd ${repo}

    # Cache previous build executions
    if [ ! -e $FLAG_FILE ] ; then
        MAVEN_FLAGS="-DskipTests=${skip} -Dfindbugs.skip=${skip} -Dmaven.test.skip=${skip} -Dmaven.javadoc.skip=true"
        [ -e "${settings}" ] && SETTINGS_="-s ${settings}" || SETTINGS_=""

        artifactId=$(getBuildProperty  ${repo} "project.artifactId" "name" "${settings}")

        override_file="${recipes}/${artifactId}.build"
        if [ -e "${override_file}" ] ; then
            build_command=$(getOverridedProperty "${override_file}" build.command)
        else
            build_command="mvn -e -V -B -ff clean install ${MAVEN_FLAGS} -T 1C ${SETTINGS_}"
        fi
        ${build_command} >> ${build_log} 2>&1
        [ $? -eq 0 ] && status=${CTE_PASSED} || status=${CTE_FAILED}
        echo $status > $FLAG_FILE
    fi
    status=$(cat ${FLAG_FILE})
    echo $status
    [ "$status" == "${CTE_PASSED}" ] && return 0 || return 1
}

# Private: Query build properties independently what build system is used.
#           Supported Maven and Gradle so far
#
# $1 - repo folder
# $2 - pom property
# $3 - gradle property
# $4 - settings
#
# Examples
#
#   buildDependency "azure-cli-plugin" "azure-cli-plugin.log" "settings.xml" "true" "recipes"
#
# Returns the exit code of the last command executed.
#
function getBuildProperty {
    repo=$1
    pomproperty=$2
    gradleproperty=$3
    settings=$4

    if [ -e ${repo}/pom.xml ] ; then
        echo $(getPomProperty ${repo}/pom.xml ${pomproperty} ${settings})
    else
        if [ -e ${repo}/build.gradle ] ; then
            echo $(getGradleProperty ${repo} ${gradleproperty})
        fi
    fi
}

# Private: Validate envelope using the PME injection
#
# $1 - ga group:artifact
# $2 - version new version
# $3 - build_log
# $4 - root location
# $5 - settings
#
# Examples
#
#   validate "com.cloudbees:azure-cli" "1.2" "build.log" "./target" "settings.xml"
#
# Returns the exit code of the last command executed.
#
function validate {
    ga=$1
    version=$2
    build_log=$3
    location=$4
    settings=$5

    TARGET=${location}/target

    [ -e "${settings}" ] && SETTINGS_="-s ${settings}" || SETTINGS_=""

    cd $location

    mkdir -p $TARGET
    if [ ! -e $TARGET/pom-manipulation-cli-2.12.jar ] ; then
        wget -q http://central.maven.org/maven2/org/commonjava/maven/ext/pom-manipulation-cli/2.12/pom-manipulation-cli-2.12.jar  \
             -O $TARGET/pom-manipulation-cli-2.12.jar
    fi

    cleanLeftOvers "${TARGET}" "${build_log}"

    # Manipulate
    java -jar $TARGET/pom-manipulation-cli-2.12.jar \
            ${SETTINGS_} \
            -f pom.xml \
            -DdependencyOverride.${ga}@*=${version} > ${build_log} 2>&1

    # Validate envelope
    mvn envelope:validate ${SETTINGS_} >> ${build_log} 2>&1
    build_status=$?
    [ $build_status -eq 0 ] && status=${CTE_SUCCESS} || status=${CTE_WARNING}
    cleanLeftOvers "${TARGET}" "${build_log}"
    echo $status
    return $build_status
}

# Private: Validate envelope and generate WAR plus the html diff
#
# $1 - root location
# $2 - pme file
# $3 - build output
# $4 - html diff report
# $5 - settings
#
# Examples
#
#   pme "./" "pom.xml" "build.log" "settings.xml"
#
# Returns the exit code PME execution if PME file exists otherwise errorlevel 1
#
function pme {
    location=$1
    PME=$2
    output=$3
    report=$4
    settings=$5

    build_status=1

    target=${location}/target
    cd ${location}
    if [ -e ${PME} ] ; then

        # This is the way we skip running PME injection when no new dependencies
        if ! grep --quiet "<dependency>" ${PME} ; then
            echo ${CTE_SKIPPED}
            return 1
        fi

        [ -e "${settings}" ] && SETTINGS_="-s ${settings}" || SETTINGS_=""

        mvn install --fail-at-end -f ${PME} ${SETTINGS_} >> ${output} 2>&1

        groupId=$(getPomProperty ${PME} "project.groupId" ${SETTINGS_})
        artifactId=$(getPomProperty ${PME} "project.artifactId" ${SETTINGS_})
        version=$(getPomProperty ${PME} "project.version" ${SETTINGS_})

        cleanLeftOvers $target $output

        set -o pipefail
        mvn -B install \
            --fail-at-end \
            -DversionSuffix=edge \
            -Ddebug \
            -Denforcer.skip \
            -DdependencyManagement=${groupId}:${artifactId}:${version} \
            ${SETTINGS_} >> ${output} 2>&1

        build_status=$?

        # Generate html diff
        git diff -U9999999 -u . | pygmentize -l diff -f html -O full -o ${report} >> ${output} 2>&1

        cleanLeftOvers $target $output
    fi
    [ $build_status -eq 0 ] && echo ${CTE_SUCCESS} || echo ${CTE_WARNING}
    return $build_status
}

# Private: Remove PME generated files to allow rerun the same process without
#           cleaning the entire target folder
#
# $1 - target location (normally <root folder>/target)
# $2 - output file
#
function cleanLeftOvers {
    TARGET=$1
    OUTPUT=$2
    ## Clean leftovers
    git checkout -- pom.xml products/  >> ${OUTPUT} 2>&1
    rm ${TARGET}/pom-manip-ext-marker.*  >> ${OUTPUT} 2>&1 || true
    rm -rf ${TARGET}/manipulator-cache  >> ${OUTPUT} 2>&1 || true
}


# Public: Verify whether the final dependencies.json and envelope.json match.
#          Each element from the envelope.json should match with the dependencies.json
#           While each dependencies.json element might not match
#
# $1 - dependencies json
# $2 - envelope.json (root location: ./products/*/target/*/WEB-INF/plugins/envelope.json)
# $3 - verify.html generate html report
# $4 - whether to fail if nullable versions in the envelope
#
# Returns whether PME dependencies have been injected accordingly. Otherwise errorlevel 1 and
# echo each broken dependency
#
function verify {
    jsonFile=$1
    envelopeFile=$2
    report=${3}
    skipNullable=${4:-false}

    status=0
    if [ ! -e "$jsonFile" -o ! -e "$envelopeFile" ] ; then
        status=1
        echo $CTE_WARNING
    else
        # For each element in the dependencies.json file
        for row in $(cat ${jsonFile} | jq -r '.[] | @base64'); do
            _jq() {
                echo ${row} | base64 --decode | jq -r ${1}
            }
            envelope=$(_jq '.envelope')
            if [ "${envelope}" == "${CTE_SUCCESS}" ] ; then
                groupId=$(_jq '.groupId')
                artifactId=$(_jq '.artifactId')
                newVersion=$(_jq '.newVersion')
                envelopeVersion=$(getJsonPropertyFromEnvelope $artifactId 'version' $envelopeFile)
                if [ "${newVersion}" != "${envelopeVersion}" ] ; then
                    if [ "${envelopeVersion}" == "null" ] ; then
                        if [ $skipNullable != true ] ; then
                            status=1
                            echo "WARN: ${groupId}:${artifactId} envelope-version '${envelopeVersion}' doesn't match pme-version '${newVersion}' since it's nullable" | tee -a ${report}
                        else
                            echo "INFO: ${groupId}:${artifactId} envelope-version '${envelopeVersion}' doesn't match pme-version '${newVersion}' since it's nullable" >> ${report}
                        fi
                    else
                        status=1
                        echo "WARN: ${groupId}:${artifactId} envelope-version '${envelopeVersion}' doesn't match pme-version '${newVersion}'" | tee -a ${report}
                    fi
                else
                    echo "INFO: ${groupId}:${artifactId} envelope-version '${envelopeVersion}' matches pme-version '${newVersion}'" >> ${report}
                fi
            fi
        done
    fi
    return $status
}

# Private: Given a particular envelope.json file and artifactId gets that particular property
#          Each element from the envelope.json should match with the dependencies.json
#           While each dependencies.json element might not match
#
# $1 - artifactId
# #2 - property
# $3 - envelope.json
#
# Returns the exit code of the last command executed. And echo the property value
#
function getJsonPropertyFromEnvelope {
    artifactId=$1
    property=$2
    envelope=$3
    echo $(cat ${envelope} | jq ".plugins[\"${artifactId}\"].${property}") | sed 's#"##g'
}

# Public: Given a particular GA it returns the latest release version
#
# $1 - repository
# $2 - groupId
# $3 - artifactId
# #4 - settings
#
# Returns the latest version of a given GA
#
function getNewLightVersion {
    repo=$1
    groupId=$2
    artifactId=$3
    settings=$4

    new_pom=${repo}.light
    build_log=${repo}.log

    [ -e "${settings}" ] && SETTINGS_="-s ${settings}" || SETTINGS_=""

    mvn -B org.apache.maven.plugins:maven-dependency-plugin:2.8:get \
                    ${SETTINGS_} \
                    -Dartifact=${groupId}:${artifactId}:LATEST \
                    -Dpackaging=pom \
                    -Dtransitive=false \
                    -Ddest=${new_pom} >>${build_log} 2>&1

    normalisePackagingIssue ${new_pom}
    newVersion=$(getPomProperty ${new_pom} "project.version" ${settings})
    if [ $? -eq 0 ] ; then
        echo $newVersion
    else
        echo $CTE_NONE
        return 1
    fi
}

# Public: Copy dependencies
#
# $1 - excludeArtifacts
# $2 - excludeGroups
# $3 - settings
#
# Returns the result of the latest command
#
function copyDependencies {
    current=$1
    excludeArtifacts=$2
    excludeGroups=$3
    settings=$4

    cd $current
    [ -e "${settings}" ] && SETTINGS_="-s ${settings}" || SETTINGS_=""

    mvn -B ${SETTINGS_} clean org.apache.maven.plugins:maven-dependency-plugin:3.0.2:copy-dependencies \
                -Dmdep.copyPom \
                -DincludeTypes=hpi \
                ${excludeArtifacts} \
                ${excludeGroups} > /dev/null
}

# Public: Get the latest releases from the remote repos
#
# $1 - current
# $2 - settings
#
# Returns the result of the latest command
#
function getLatestReleases {
    current=$1
    settings=$2

    cd $current
    [ -e "${settings}" ] && SETTINGS_="-s ${settings}" || SETTINGS_=""

    mvn -B ${SETTINGS_} org.codehaus.mojo:versions-maven-plugin:2.5:use-latest-releases > /dev/null
    cleanLeftOvers $current "/dev/null"
}