#!/bin/bash
#
# Utilities file which are used by the cutting_dger.sh file
#
# It has been documented based on https://github.com/mlafeldt/tomdoc.sh
#

CTE_SUCCESS="success"
CTE_WARNING="warning"
CTE_DANGER="danger"
CTE_PASSED="passed"
CTE_FAILED="failed"
CTE_NONE="none"
CTE_SCM="scm"
CTE_SKIPPED="skipped"
CTE_UNREACHABLE="unreachable"

# Public: Get a particular property of a given POM file.
#
# Takes an expression and it evaluates within a particular POM file..
#
# $1 - POM file.
# $2 - expression to be evaluated.
# $3 - Settings.
#
# Examples
#
#   getPomProperty "pom.xml" "project.version"
#
# Returns the exit code of the last command executed.
#
function getPomProperty {
    [ -f "$3" ] && SETTINGS="-s $3" || SETTINGS=""
    mvn -B help:evaluate -Dexpression=$2 -f $1 ${SETTINGS} | grep -e '^[^\[]' | grep -v 'INFO'
}


# Public: Get a particular property of a given Gradle repo.
#
# Takes an expression and it evaluates within a particular POM file..
#
# $1 - Gradle repo.
# $2 - expression to be evaluated.
#
# Examples
#
#   getGradleProperty "build.gradle" "version"
#
# Returns the exit code of the last command executed.
#
function getGradleProperty {
    repo=$1
    ${repo}/gradlew -b ${repo}/build.gradle properties | grep $2 | cut -d":" -f2 | tr -d " "
}

# Public: Get a particular XML property of a given POM file.
#
# Takes an expression and it evaluates within a particular POM file.
#
# $1 - POM file.
# $2 - expression to be evaluated.
#
# Examples
#
#   getXMLProperty "pom.xml" "scm/url"
#
# Returns the exit code of the last command executed.
#
function getXMLProperty {
    xmlstarlet pyx $1 | grep -v ^A | xmlstarlet p2x | xmlstarlet sel -t -v $2
}

# Public: Get the overrided property given a property files and the key.
#
# $1 - Properties file (git config based)
# $2 - property to be evaluated.
#
# Examples
#
#   getOverridedProperty "file.properties" "url.artifactId"
#
# Returns the exit code of the last command executed.
#
function getOverridedProperty {
    if [ -e $1 ] ; then
        git config --file=$1 --get $2
    fi
}

# Public: Notify other reporting functions
#
# $1 - groupId.
# $2 - artifactId.
# $3 - version.
# $4 - newVersion.
# $5 - url.
# $6 - status.
# $7 - description.
# $8 - envelope-status.
# $9 - envelope-message.
# $10 - html file
# $11 - json file.
# $12 - pem file.
#
# Examples
#
#   notify "com.cloudbees" "folder" "1.0" "2.0" "https://github.com" "success" "success" "dependencies.json"
#
# Returns the exit code of the last command executed.
#
function notify {
    li "$1:$2" "$3" "$4" "$6" "$7" "$8" "$9" "${10}"
    addJSONDependency "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${11}"
    if [ "$8" == "$CTE_SUCCESS" ] ; then
        addDependency "$1" "$2" "$4" "${12}"
    fi
}

# Public: Convert git+https to git+git protocol
#
# $1 - git url
#
# Examples
#
#   convertHttps2Git "git-https"
#
# Returns the exit code of the last command executed.
#
function convertHttps2Git {
    echo $1 | sed 's#.*github.com/#git@github.com:#g'
}

# Public: Check whether a particular URL is reachable using Curl
#
# $1 - URL
#
# Examples
#
#   isReachableWithCurl "https://github.com"
#
# Returns the exit code of the last command executed.
#
function isReachableWithCurl {
    if curl --connect-timeout 1 --silent --fail $1 --output /dev/null ; then
        return 0
    else
        return 1
    fi
}

# Public: Check whether a particular URL is reachable. It does try with different approaches:
#           curl git-https , git ls-remote git-https and git ls-remote git-ssh urls
# $1 - URL
# $2 - SSH_GIT flag
#
# Examples
#
#   isReachable "https://github.com" false
#
# Returns the exit code of the last command executed.
#
function isReachable {
    if isReachableWithCurl $1 ; then
        return 0
    else
        if git ls-remote --quiet --heads $1 &> /dev/null ; then
            return 0
        else
            if [ "$2" = true ] ; then
                ssh_url=$(convertHttps2Git $1)
                if git ls-remote --quiet --heads $ssh_url &> /dev/null ; then
                    return 0
                else
                    return 1
                fi
            else
                return 1
            fi
        fi
    fi
}

# Public: Open JSON file
#
# $1 - JSON
#
# Examples
#
#   openJSON "dependencies.json"
#
# Returns the exit code of the last command executed.
#
function openJSON {
    cat <<EOT > ${JSON}
[
EOT
}

# Public: Open PME file
#
# $1 - PME
#
# Examples
#
#   openPME "dependencies.pom.xml"
#
# Returns the exit code of the last command executed.
#
function openPME {
    cat <<EOT > $1
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.cloudbees</groupId>
  <artifactId>depMgmt</artifactId>
  <version>1.0-SNAPSHOT</version>
  <packaging>pom</packaging>
  <dependencyManagement>
    <dependencies>
EOT
}

# Public: Open HTML file
#
# $1 - HTML
#
# Examples
#
#   openHTML "dependencies.html"
#
# Returns the exit code of the last command executed.
#
function openHTML {
    cat <<"EOT" > $1
<!DOCTYPE html>
<html>
    <head>
        <meta charset="utf-8">
        <title>URR Cutting Edge Report</title>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">

        <script src="https://release-notes.cloudbees.com/js/handlebars.js"></script>
        <script src="https://release-notes.cloudbees.com/js/jquery.min.js"></script>
        <script src="https://release-notes.cloudbees.com/bootstrap-4/js/tether.min.js"></script>
        <script src="https://release-notes.cloudbees.com/bootstrap-4/js/bootstrap.min.js"></script>
        <script src="https://release-notes.cloudbees.com/highlight-js/highlight.pack.js"></script>

        <!-- The styles -->
        <link href="https://release-notes.cloudbees.com/bootstrap-4/css/bootstrap.min.css" rel="stylesheet">
        <link href="https://release-notes.cloudbees.com/bootstrap-4/css/font-awesome.min.css" rel="stylesheet">
        <link href="https://release-notes.cloudbees.com/highlight-js/default.css" rel="stylesheet">
        <link href="https://release-notes.cloudbees.com/css/cloudbees.css" rel="stylesheet">
        <script>hljs.initHighlightingOnLoad();</script>
        <script>
            $(function(){
                $('#search').keyup(function(){
                    var current_query = $('#search').val();
                    if (current_query !== "") {
                        $("#searchable-container li").hide();
                        $("#searchable-container li").each(function(){
                            var current_keyword = $(this).text();
                            if (current_keyword.indexOf(current_query) >=0) {
                                $(this).show();
                            };
                        });
                    } else {
                        $("#searchable-container li").show();
                    };
                });
            });
        </script>
        <script>
            $(function () {
                $('[data-toggle="tooltip"]').tooltip()
            })
        </script>
    </head>
    <body>
        <header>
            <div class="container-fluid">
                <div class="row-fluid">
                    <a class="navbar-brand" href="https://www.cloudbees.com/"><img src="https://release-notes.cloudbees.com/img/cloudbees-logo.png" alt="CloudBees, Inc."></a>
                </div>
            </div>
            <nav class="navbar navbar-toggleable-md navbar-light">
            </nav>
        </header>

        <div class="container-fluid max-width-centered">

        <section id="summary">
            <div class="row-fluid">
                <h1>URR Cutting Edge Report</h1>
                <div class="mt-3 mb-3">
                    <ul class="nav nav-tabs" id="myTab" role="tablist">
                        <li class="nav-item">
                            <a class="nav-link active" id="info-tab" data-toggle="tab" href="#info" role="tab" aria-controls="info" aria-expanded="true">
                                <i class="fa fa-info-circle" aria-hidden="true"></i> Badge legend
                            </a>
                        </li>
                    </ul>
                    <div class="tab-content">
                        <div id="info" role="tabpanel" class="tab-pane fade p-3 active show" aria-labelledby="info-tab" aria-expanded="true">
                            <div class="mb-1">
                                <span class="badge badge-pill badge-default ml-1" data-toggle="tooltip" data-placement="top" title="This is the current version installed">current version</span>
                                <span class="badge badge-pill badge-info ml-1" data-toggle="tooltip" data-placement="top" title="This is the new version to be installed">new version</span>
                                <span class="badge badge-pill badge-success ml-1" data-toggle="tooltip" data-placement="top" title="Whether the build was successful or somethine else happens">status</span>
                                <span class="badge badge-pill badge-info ml-1" data-toggle="tooltip" data-placement="top" title="Whether it has been validated from the envelope:validate goals">envelope</span>
                                <span class="badge badge-pill badge-warning ml-1" data-toggle="tooltip" data-placement="top" title="What dependencies are required to be able to use this plugin">dependencies</span>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <section id="list">
            <div class="input-group col-xs-12">
                <input id="search" type="text" class="form-control input-sm" placeholder="Search" />
            </div>
            <ul class="list-group mb-4" id="searchable-container">
EOT
}

# Public: Close JSON file
#
# $1 - JSON
#
# Examples
#
#   closeJSON "dependencies.json"
#
# Returns the exit code of the last command executed.
#
function closeJSON {
    cat <<EOT >> $1
]
EOT
}

# Public: Close PME file
#
# $1 - PME
#
# Examples
#
#   closePME "pom.pme.xml"
#
# Returns the exit code of the last command executed.
#
function closePME {
    cat <<EOT >> $1
    </dependencies>
  </dependencyManagement>
</project>
EOT
}

# Public: Close HTML file
#
# $1 - HTML
#
# Examples
#
#   closeHTML "dependencies.html"
#
# Returns the exit code of the last command executed.
#
function closeHTML {
    cat <<EOT >> $1
        </ul>
        </section>
            <footer>
                <div class="container-fluid max-width-centered">
                    <div class="row-fluid">
                        <div class="d-flex justify-content-between">
                            <span>CloudBees, Inc. 2017</span>
                        </div>
                    </div>
                </div>
            </footer>
        </body>
    </html>
EOT
}

# Public: Add HTML node dependency.
#
# Takes the GAVC arguments and append them to the output file. Output file it is
# also another argument.
#
# $1 - groupId:artifactId.
# $2 - version.
# $3 - newVersion.
# $4 - status.
# $5 - description.
# $6 - envelope.
# $7 - validate message.
# $8 - output. HTML file
#
# Examples
#
#   li "com.cloudbees:cloudbees-folder" "1.0" "1.1" "info" "passed" "ready" "dependencies.html"
#
# Returns the exit code of the last command executed.
#
function li {
    if [[ $8 == *.html ]] ; then
        artifact=$(echo "$1" | cut -d":" -f2)
        envelope=$(envelopeMessage "$artifact" "$6" "$7")
        cat <<EOT >> $8
        <li class="list-group-item justify-content-between ">
            $1
            <div class="hidden-xs-down">
                <span class="badge badge-pill badge-default">$2</span>
                <span class="badge badge-pill badge-info">$3</span>
                <span class="badge badge-pill badge-$4">$5</span>
                ${envelope}
            </div>
        </li>
EOT
    fi
}

# Private: Add envelope message
#
# $1 - artifactId
# $2 - status
# $3 - message.
#
# Examples
#
#   envelopeMessage "warning" "[nodejs]: Dependency [config-file-provider/2.16.0] not found in scope [fat] or lower"
#
# Returns the exit code of the last command executed.
#
function envelopeMessage {
    if [ "$2" == "$CTE_WARNING" ] ; then
        echo $(cat << EOT
        <span class="badge badge-pill badge-$2">envelope</span>
        <div class="card mb-3 mt-3 top-info-card">
            <div class="p-0" role="tab" id="envelopeHeading$1">
                <a id="envelope-button$1" data-toggle="collapse" href="#envelope$1" aria-expanded="false" aria-controls="envelope$1" class="btn btn-warning btn-sm w-0 m-0 collapsed">
                    <span class="ml-1">dependencies</span>
                </a>
            </div>
            <div id="envelope$1" class="collapse" role="tabpanel" aria-labelledby="envelopeHeading$1" aria-expanded="false" style="">
                <div class="card-block">
                    <div><code>$3</code></div>
                </div>
            </div>
        </div>
EOT
)
    else
        echo $(cat << EOT
        <span class="badge badge-pill badge-$2">$3</span>
EOT
)
    fi
}

# Public: Add XML node dependency.
#
# Takes the GAVC arguments and append them to the output file. Output file it is
# also another argument.
#
# $1 - groupId.
# $2 - artifactId.
# $3 - version.
# $4 - output.
#
# Examples
#
#   addDependency "com.cloudbees" "folder" "1.0" "target/pom.xml"
#
# Returns the exit code of the last command executed.
#
function addDependency {
    if [[ $4 == *.xml ]] ; then
        echo "<dependency><groupId>$1</groupId><artifactId>$2</artifactId><version>$3</version></dependency>" >> $4
    fi
}

# Public: Add JSON dependency.
#
# Takes the GAVC arguments and append them to the output file. Output file it is
# also another argument. CamelCase format
#
# $1 - groupId.
# $2 - artifactId.
# $3 - version.
# $4 - newVersion.
# $5 - url.
# $6 - status.
# $7 - description.
# $8 - envelope.
# $9 - validate message.
# $10 - output.
#
# Examples
#
#   addJSONDependency "com.cloudbees" "folder" "1.0" "2.0" "https://github.com" "INFO" "SUCCESS" "PASSED" "dependencies.json"
#
# Returns the exit code of the last command executed.
#
function addJSONDependency {
    if [[ ${10} == *.json ]] ; then
        cat <<EOT >> ${10}
    {
        "groupId": "$1",
        "artifactId": "$2",
        "version": "$3",
        "newVersion": "$4",
        "url": "$5",
        "status": "$6",
        "description": "$7",
        "envelope": "$8",
        "validate": "$9"
    },
EOT
    fi
}

# Public: Get rid of the packaging hpi issue when no parent POM
#
# $1 - pom.xml
#
# Examples
#
#   normalisePackagingIssue "pom.xml"
#
# Returns the exit code of the last command executed.
#
function normalisePackagingIssue {
    sed -i.bck 's#<packaging>hpi</packaging>##g' $1
}

# Public: Filter log output and gather all the topological error messages
#
# $1 - log.xml
#
# Examples
#
#   analyseTopological "build.log"
#
# Returns the grep of 'Error Plugin messages'
#
function analyseTopological {
    grep '\[ERROR\] Plugin' $1 | sed 's#.*Plugin##g' | cut -d":" -f2
}
