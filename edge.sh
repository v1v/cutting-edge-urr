#!/bin/bash
# NAME
#       edge - the stupid cutting edge script
#
# SYNOPSIS
#       edge -s <file> -o <file> -xa <file> -xg <file> -(N)X -(N)I -(N)S
#
# DESCRIPTION
#       Edge retrieves each pom dependency based on some exclude filters then:
#
#		1) checkout
#		2) build with or without tests
#		3) install the new snapshot locally
#		4) create a PME file to be injected in the parent pom.
#		5) generate a html/json report with the status of each dependency.
#
# ARGUMENTS
#       -s/--settings <file>
#           Settings.xml file to be used, file path based.
#
#       -o/--override <file>
#           Override file whcih contains a key=value uples which will override the URLs. Default: override.properties
#           This file is _ONLY_ relative to the root folder.
#
#       -xa/--exclude-artifacts <file>
#           File based on comma separated list of ArtifactId Names to exclude. Default: excludeArtifactIds.properties
#           This file can be either relative to the root folder or absolute path.
#
#       -xg/--exclude-artifacts <file>
#           File based on comma separated list of GroupId Names to exclude. Default: excludeGroupIds.properties
#           This file can be either relative to the root folder or absolute path.
#
#       -(N)X/--(no-)skip-test
#			Whether to skip run tests when running maven install goal.  Default: true
#
#       -(N)I/--(no-)incremental
#			Whether to clean the target folder or reuse the existing generated reports.  Default: true
#
#       -(N)S/--(no-)ssh
#			Whether to convert git+https urls to git+ssh in order to allow git clone from private repositories using git+ssh agents. Default: true
#
# OUTPUT:
#
#       ./target/pom.xml.pme
#			The PME file to be used when running URR with the latest versions
#
#       ./target/${dependency}.log
#			Build output of each dependency
#
#       ./target/${dependency_repo}/.status.flag
#			Flag file to let know whether that project has been built previously and its status (passed, failed). This more related to multimodule maven projects.
#
#       ./target/dependencies.json
#			JSON file format with the status of each dependency
#
#       ./target/dependencies.html
#			HTML report
#
# NOTE:
#
#		Output folder is related to the ${session.executionRootDirectory}
#
# DEPENDENCY STATUS:
#		+ WARNING      -> It means something went wrong
#		 - NO_SCM      -> POM without a valid scm section
#		 - UNREACHABLE -> SCM cannot be reachable
#		+ INFO         -> It means the depedency was found/downlaoded and built
#		 - SUCCESS     -> Dependency was installed in .m2 correctly
#		 - FAILED      -> Dependency failed when installing (build/test phase issues)
#
# REQUIREMENTS:
#
#		utils.sh
#		URR Repository
#		xmlstarlet binary
#		maven 3.3+
#		git 2+
#
# KNOWN ISSUES:
#
#		Master branch of some dependencies might be broken
#

## Load utils library (which included templates and some other utilities)
source "$( dirname "${BASH_SOURCE[0]}" )/utils.sh"
source "$( dirname "${BASH_SOURCE[0]}" )/helper.sh"

## Variables
CURRENT=$(pwd)
EDGE=${CURRENT}/target/edge
PME=${CURRENT}/target/pom.xml.pme
JSON=${CURRENT}/target/dependencies.json
HTML=${CURRENT}/target/dependencies.html
UNIQUE_POMS=${EDGE}/poms
export MAVEN_OPTS="-XX:+TieredCompilation -XX:TieredStopAtLevel=1"

## Arguments
display_help() {
    echo "Usage: $0 [option...]" >&2
    echo
    echo "   -s,  --settings           Maven settings.xml file fullpath based."
    echo "   -o,  --override           Override scm urls file based on key=value tuples."
    echo "   -xa, --exclude-artifacts  File based on comma separated list of ArtifactId Names to exclude."
    echo "   -xg, --exclude-groups     File based on comma separated list of GroupId Names to exclude."
    echo "   -(N)X,  --(no-)skip-test          Whether to skip tests when installing those dependencies locally."
    echo "   -(N)I,  --(no-)incremental        Whether to clean or start from the previous execution."
    echo "   -(N)S,  --(no-)ssh                Whether to transform git urls to git+ssh to allow access to private repos."
    echo "   -h,  --help               Help."
    echo
    exit 0
}

validate_arguments() {
    if [ ! -e $OVERRIDE_FILE ]; then
        echo "WRONG: override file doesn't exist" ; exit 1
    fi
    if [ ! -e $SETTINGS ]; then
        echo "WRONG: settings file doesn't exist" ; exit 1
    fi
    if [ ! -e $EXCLUDE_ARTIFACTS_FILE ]; then
        echo "WRONG: excludeArtifactIds file doesn't exist" ; exit 1
    fi
    if [ ! -e $EXCLUDE_GROUPS_FILE ]; then
        echo "WRONG: excludeGroupIds file doesn't exist" ; exit 1
    fi
}

# Public: Maven settings.xml file to be used, file path based.
SETTINGS=settings.xml
# Public: Properties file with a list of key=url tuples (key -> groupId.artifactId=https://)
OVERRIDE_FILE=override.properties
# Public: File based on comma separated list of ArtifactId Names to exclude.
EXCLUDE_ARTIFACTS_FILE=excludeArtifactIds.properties
# Public: File based on comma separated list of GroupId Names to exclude.
EXCLUDE_GROUPS_FILE=excludeGroupIds.properties
# Public: Whether to skip tests when installing those plugins locally.
SKIP_TESTS=true
# Public: Whether to clean or start from the last execution.
INCREMENTAL=true
# Public: Whether to use git+ssh rather than git+https. This is required to use Pipeline within the CloudBees organisation.
SSH_GIT=true

if [ "$#" -eq 0 ]; then
    echo "INFO: Using default values"
fi

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"
case $key in
    -h|--help) display_help ;;
    -s|--settings) SETTINGS="$2"; shift 2;;
    -o|--override) OVERRIDE_FILE="$2"; shift 2;;
    -xa|--exclude-artifacts) EXCLUDE_ARTIFACTS_FILE="$2"; shift 2;;
    -xg|--exclude-groups) EXCLUDE_GROUPS_FILE="$2"; shift 2;;
    -X|--skip-test) SKIP_TESTS=true; shift 1;;
    -I|--incremental) INCREMENTAL=true; shift 1;;
    -S|--ssh) SSH_GIT=true; shift 1;;
    -NX|--no-skip-test) SKIP_TESTS=false; shift 1;;
    -NI|--no-incremental) INCREMENTAL=false; shift 1;;
    -NS|--no-ssh) SSH_GIT=false; shift 1;;
    *) # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

validate_arguments

###############################################################################

function initialise {

    # Clean and retrieve POM files
    if [ $INCREMENTAL != true ] ; then

        excludeArtifacts=""
        excludeGroups=""
        if [ -e $EXCLUDE_ARTIFACTS_FILE ] ; then
            excludeArtifacts=$(cat $EXCLUDE_ARTIFACTS_FILE)
            if [ -n "${excludeArtifacts}" ] ; then
                excludeArtifacts=-DexcludeArtifactIds=${excludeArtifacts}
            fi
        fi
        if [ -e $EXCLUDE_GROUPS_FILE ] ; then
            excludeGroups=$(cat $EXCLUDE_GROUPS_FILE)
            if [ -n "${excludeGroups}" ] ; then
                excludeGroups=-DexcludeGroupIds=${excludeGroups}
            fi
        fi

        echo "Getting hpi dependencies..."
        mvn -B -V -s ${SETTINGS} clean org.apache.maven.plugins:maven-dependency-plugin:3.0.2:copy-dependencies \
                    -Dmdep.copyPom \
                    -DincludeTypes=hpi \
                    ${excludeArtifacts} \
                    ${excludeGroups} > /dev/null

        # Remove unused artifacts
        find . -name *.hpi -delete

        # In some cases the root target folder is not created when using some exclude options
        mkdir -p ${EDGE}

        echo "Preparing reports..."
        openHTML ${HTML}
        openJSON ${JSON}
        openPME  ${PME}
    fi

}

################################################################################
################################# MAIN #########################################

initialise

# Let's remove duplicated dependencies by using a temp folder
mkdir -p ${UNIQUE_POMS}
find . -name *.pom -type f -not -path "./target/**/src/*" | while read -r i; do cp "$i" ${UNIQUE_POMS}; done
total=$(find ${UNIQUE_POMS} -name *.pom -type f | sort | uniq | wc -l | sed 's# ##g')

echo "There are: $(find . -name *.pom -type f -not -path "./target/**/src/*" | sort | wc -l | sed 's# ##g') pom files"
echo "There are: ${total} dependencies to cutting the edge ..."

index=1
# Per unique dependency then let's build with latest
find ${UNIQUE_POMS} -name *.pom -type f | sort | while read pom
do
    echo "\t${index} of ${total} unique pom files (${pom})"
    cd ${CURRENT}
    repo="${EDGE}/$(basename ${pom})"
    effective=${pom}.effective
    newVersion=${CTE_NONE}

    # Get URL
    url=$(getURL ${pom} ${effective} "${repo}" "${OVERRIDE_FILE}" "${SETTINGS}")
    echo "\t\t getURL stage - ${url}"
    # If it's found then
    if [ "$url" != "${CTE_UNREACHABLE}" -a "$url" != "${CTE_SCM}" ] ; then
        # Transform URL to be able to use it within rosie and also support multimodule maven projects
        url=$(transform $url)
        echo "\t\t transform stage - ${url}"
        repo="${EDGE}/$(basename ${url})"
        download=$(download ${url} ${repo})
        echo "\t\t download stage - ${download}"
        if [ "${download}" != "${CTE_UNREACHABLE}" ] ; then
            build_log=${repo}.log
            description=$(buildDependency ${repo} ${build_log} ${SKIP_TESTS} ${SETTINGS} ${MAVEN_FLAGS})
            echo "\t\t buildDependency stage - ${description}"
            newVersion=$(get ${repo}/pom.xml "project.version" ${SETTINGS})
            [ "${description}" == "${CTE_PASSED}" ] && state=${CTE_SUCCESS} || state=${CTE_WARNING}
        else
            description=${CTE_UNREACHABLE}
            state=${CTE_DANGER}
        fi
    else
        description=${url}
        state=${CTE_DANGER}
    fi

    # Get GAVC
    groupId=$(get ${effective} "project.groupId" ${SETTINGS})
    artifactId=$(get ${effective} "project.artifactId" ${SETTINGS})
    version=$(get ${effective} "project.version" ${SETTINGS})

    notify ${groupId} ${artifactId} ${version} ${newVersion} "${url}" ${state} ${description} ${HTML} ${JSON} ${PME}
    echo "\t\t notify stage - ${state}"
    echo "\t\t 'old GAV' - ${groupId}:${artifactId}:${version} 'new GAV' - ${groupId}:${artifactId}:${newVersion}"
    let "index++"
done

closeHTML ${HTML}
closeJSON ${JSON}
closePME  ${PME}
