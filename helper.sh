#!/bin/bash -x
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
# $1 - POM
# $2 - Effective POM
# $3 - Repo absolute folder
# $4 - Override properties
# $5 - Settings
#
# Examples
#
#   getURL "azure-pom.xml" "azure-pom-effective.xml" "./target/azure" "./override.properties" "~/m2/settings.xml"
#
# Returns the github URL/unreachable/scm
#
function getURL {
    pom=$1
    effective=$2
    repo=$3
    override=$4
    settings=$5

    # Validate mandatory ARGUMENTS
    if [ ! -f $pom ] ; then
        echo "error"
        exit 1
    fi

    build_log=${repo}.log

    # Normalise packaging issue
    normalisePackagingIssue ${pom}

    # Get effective-pom
    [ -f "${settings}" ] && SETTINGS="-s ${settings}" || SETTINGS=""
    mvn -B --quiet ${SETTINGS} -f ${pom} help:effective-pom -Doutput=${effective} >>${build_log} 2>&1

    # Get effective artifact
    artifactId=$(get ${effective} "project.artifactId" ${settings})

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
            if isReachable ${url} ${SSH_GIT} ; then  # Sometimes URLs are not reachable
                status=${url}
            else
                status=${CTE_UNREACHABLE}
            fi
        else
            status=${CTE_SCM}
        fi
    fi

    echo ${status}
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
}


# Private: Run build goals in the dependency
#
# $1 - repo folder
# $2 - build_log
# $3 - settings
# $4 - skip_tests
# $5 - artifactid
# $6 - recipes folder
#
# Uses CTE variables
#
# Examples
#
#   buildDependency "azure-cli-plugin" "azure-cli-plugin.log" "settings.xml" "true" "azure" "recipes"
#
# Returns the exit code of the last command executed.
#
function buildDependency {
    repo=$1
    build_log=$2
    settings=$3
    skip=$4
    artifactId=$5
    recipes=$6

    FLAG_FILE=".status.flag"
    MAVEN_FLAGS="-DskipTests=${skip} -Dfindbugs.skip=${skip} -Dmaven.test.skip=${skip} -Dmaven.javadoc.skip=true"
    cd ${repo}
    # Cache previous build executions
    if [ ! -e $FLAG_FILE ] ; then
        override_file="${recipes}/${artifactId}.build"
        if [ -e "${override_file}" ] ; then
            build_command=$(getOverridedProperty "${override_file}" build.command)
        else
            build_command="mvn -e -V -B -ff clean install ${MAVEN_FLAGS} -T 1C ${SETTINGS}"
        fi
        [ -f "${settings}" ] && SETTINGS="-s ${settings}" || SETTINGS=""
        ${build_command} >>${build_log} 2>&1
        [ $? -eq 0 ] && status=${CTE_PASSED} || status=${CTE_FAILED}
        echo $status > $FLAG_FILE
    fi
    cat $FLAG_FILE
}
