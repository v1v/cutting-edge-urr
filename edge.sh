#!/bin/bash
# NAME
#       edge - the stupid cutting edge script
#
# SYNOPSIS
#       edge -s <file> -o <file> -xa <file> -xg <file> -r <folder> -(N)X -(N)I -(N)S
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
#           Override file whcih contains a key=value uples which will override the URLs.
#           This file is _ONLY_ relative to the root folder.
#
#       -xa/--exclude-artifacts <file>
#           File based on comma separated list of ArtifactId Names to exclude.
#           This file can be either relative to the root folder or absolute path.
#
#       -xg/--exclude-artifacts <file>
#           File based on comma separated list of GroupId Names to exclude.
#           This file can be either relative to the root folder or absolute path.
#
#       -r,  --recipes  <folder
#           Folder with the build recipes to be override if required.
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
#       ./target/edge/report/pom.xml.pme
#			The PME file to be used when running URR with the latest versions
#
#       ./target/edge/${dependency}.log
#			Build output of each dependency
#
#       ./target/edge/${dependency_repo}/.status.flag
#			Flag file to let know whether that project has been built previously and its status (passed, failed). This more related to multimodule maven projects.
#
#       ./target/edge/report/dependencies.json
#			JSON file format with the status of each dependency
#
#       ./target/edge/report/dependencies.html
#			HTML report with the status of all the dependencies
#
#       ./target/edge/report/verify.txt
#			Plain text file with the status of the verify of each validated dependency
#
#       ./target/edge/report/diff.html
#			HTML report with the diff of each pom transformation
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
#		jq
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
REPORT=${EDGE}/report
UNIQUE_POMS=${EDGE}/poms
PME=${REPORT}/pom.xml.pme
JSON=${REPORT}/dependencies.json
HTML=${REPORT}/dependencies.html
VERIFY=${REPORT}/verify.txt
DIFF=${REPORT}/diff.html
export MAVEN_OPTS="-XX:+TieredCompilation -XX:TieredStopAtLevel=1"

## Arguments
display_help() {
    echo "Usage: $0 [option...]" >&2
    echo
    echo "   -s,  --settings           Maven settings.xml file fullpath based."
    echo "   -o,  --override           Override scm urls file based on key=value tuples."
    echo "   -xa, --exclude-artifacts  File based on comma separated list of ArtifactId Names to exclude."
    echo "   -xg, --exclude-groups     File based on comma separated list of GroupId Names to exclude."
    echo "   -r,  --recipes            Folder with the build recipes to be override if required."
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
    else
        if [ -n "$EXCLUDE_ARTIFACTS_FILE" ] ; then
            if [ `cat $EXCLUDE_ARTIFACTS_FILE | wc -l` -gt 1 ] ; then
                echo "WRONG: excludeArtifactIds file cannot contains multilines" ; exit 1
            fi
        fi
    fi
    if [ ! -e $EXCLUDE_GROUPS_FILE ]; then
        echo "WRONG: excludeGroupIds file doesn't exist" ; exit 1
    else
        if [ -n "$EXCLUDE_GROUPS_FILE" ] ; then
            if [ `cat $EXCLUDE_GROUPS_FILE | wc -l` -gt 1  ] ; then
                echo "WRONG: excludeGroupIds file cannot contains multilines" ; exit 1
            fi
        fi
    fi
    if [ ! -d $RECIPES_FOLDER ]; then
        echo "WRONG: recipes folder doesn't exist" ; exit 1
    fi
}

validate_dependencies() {
    for tool in jq java mvn git xmlstarlet; do
        if ! command -v ${tool} >/dev/null ; then
            echo "MISSING ${tool}"
            exit 1
        fi
    done
}

# Public: Maven settings.xml file to be used, file path based.
SETTINGS=
# Public: Properties file with a list of key=url tuples (key -> groupId.artifactId=https://)
OVERRIDE_FILE=
# Public: File based on comma separated list of ArtifactId Names to exclude.
EXCLUDE_ARTIFACTS_FILE=
# Public: File based on comma separated list of GroupId Names to exclude.
EXCLUDE_GROUPS_FILE=
# Public: Folder with the recipes to be used when declared=.
RECIPES_FOLDER=
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
    -r|--recipes) RECIPES_FOLDER="$2"; shift 2;;
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
validate_dependencies
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
        mkdir -p ${REPORT}

        echo "Preparing reports..."
        openHTML ${HTML}
        openJSON ${JSON}
        openPME  ${PME}
    else
        # Forcing to create the report folder in case the incremental execution didn't go through it yet
        mkdir -p ${REPORT}
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
    echo "  ${index} of ${total} unique pom files (${pom})"
    cd ${CURRENT}
    repo="${EDGE}/$(basename ${pom})"
    effective=${pom}.effective
    newVersion=${CTE_NONE}
    envelope=${CTE_NONE}
    message=${CTE_NONE}

    # Get URL
    url=$(getURL ${pom} ${effective} "${repo}" "${SSH_GIT}" "${OVERRIDE_FILE}" "${SETTINGS}")
    echo "     getURL stage - ${url}"

    groupId=$(getPomProperty ${effective} "project.groupId" ${SETTINGS})
    artifactId=$(getPomProperty ${effective} "project.artifactId" ${SETTINGS})

    # If it's found then
    if [ "$url" != "${CTE_UNREACHABLE}" -a "$url" != "${CTE_SCM}" ] ; then
        # Transform URL to be able to use it within rosie and also support multimodule maven projects
        url=$(transform $url)
        echo "     transform stage - ${url}"
        repo="${EDGE}/$(basename ${url})"

        download=$(download ${url} ${repo})
        echo "     download stage - ${download}"
        if [ "${download}" != "${CTE_UNREACHABLE}" ] ; then
            build_log=${repo}.log
            description=$(buildDependency ${repo} ${build_log} ${SETTINGS} ${SKIP_TESTS} "${RECIPES_FOLDER}")
            newVersion=$(getBuildProperty  ${repo} "project.version" "version" "${SETTINGS}")
            echo "     buildDependency stage - ${description}"
            if [ "${description}" == "${CTE_PASSED}" ] ; then
                state=${CTE_SUCCESS}
                validate_log=${build_log}.validate
                envelope=$(validate ${groupId}:${artifactId} ${newVersion} ${validate_log} ${CURRENT} "${SETTINGS}")
                echo "     validate envelope stage - ${envelope}"
                if [ "${envelope}" == "${CTE_SUCCESS}" ] ; then
                    message="validated"
                else
                    message=$(analyseTopological ${validate_log})
                fi
            else
                state=${CTE_WARNING}
            fi
        else
            description=${CTE_UNREACHABLE}
            state=${CTE_DANGER}
        fi
    else
        description=${url}
        state=${CTE_DANGER}
    fi

    # Get GAVC
    version=$(getPomProperty ${effective} "project.version" ${SETTINGS})

    notify "${groupId}" "${artifactId}" "${version}" "${newVersion}" "${url}" "${state}" "${description}" "${envelope}" "${message}" "${HTML}" "${JSON}" "${PME}"
    echo "     notify stage - ${state}"
    echo "     'old GAV' - ${groupId}:${artifactId}:${version} 'new GAV' - ${groupId}:${artifactId}:${newVersion}"
    let "index++"
done

closeHTML ${HTML}
closeJSON ${JSON}
closePME  ${PME}

# Run the PME stuff
status=$(pme ${CURRENT} ${PME} "${REPORT}/pme.log" "${DIFF}" ${SETTINGS})
pme=$?
echo "Final PME stage - ${status}"

# Verify PME vs each Envelope only if PME execution was success
if [ $pme -eq 0 ] ; then
    skipNullable=true
    find . -name envelope.json -type f -not -path "**/generated-resources/*" -not -path "**/test/resource/*" | sort | while read file
    do
        verify ${JSON} ${file} ${skipNullable} ${VERIFY}
        if [ $? -ne 0 ] ; then
            pme=1
            echo "     Verifying $file - failed"
        else
            echo "     Verifying $file - passed"
        fi
    done
fi

echo "Verify stage - ${pme}"
exit $pme

