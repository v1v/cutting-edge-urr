#!/bin/bash
# NAME
#       urr - the post cutting edge actions to generate a list of war files
#
# SYNOPSIS

## Load utils library (which included templates and some other utilities)
source "$( dirname "${BASH_SOURCE[0]}" )/utils.sh"
source "$( dirname "${BASH_SOURCE[0]}" )/helper.sh"

    export TEMP_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export EFFECTIVE_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export TEMP_DIR=$(mktemp -d /tmp/bats.XXXXXXXXXX)
    export OVERRIDE_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export NO_SCM_POM_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export CONNECTION_POM_FILE=$(mktemp /tmp/bats.XXXXXXXXXX)
    export TEMP_DIR_NEW=${TEMP_DIR}.new
    cat <<EOT > $OVERRIDE_FILE
[url]
    ant = overrided_url
EOT

    cat <<EOT > $NO_SCM_POM_FILE
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>group</groupId>
  <artifactId>artifact</artifactId>
  <version>1.0</version>
  <packaging>hpi</packaging>
</project>
EOT

    cat <<EOT > $CONNECTION_POM_FILE
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>org.jenkins-ci.plugins</groupId>
  <artifactId>gradle</artifactId>
  <version>1.26</version>
  <packaging>hpi</packaging>
  <scm>
    <connection>scm:git:git://github.com/jenkinsci/gradle-plugin.git</connection>
  </scm>
</project>
EOT

download https://github.com/dantheman213/java-hello-world-maven.git "${TEMP_DIR_NEW}"
buildDependency "${TEMP_DIR_NEW}" "${TEMP_FILE}" "${HOME}/.m2/settings.xml" true

echo "passed" > "${TEMP_DIR_NEW}/.status.flag"
buildDependency "${TEMP_DIR_NEW}" "${TEMP_FILE}" "${HOME}/.m2/settings.xml" true

echo "failed" > "${TEMP_DIR_NEW}/.status.flag"
cat "${TEMP_DIR_NEW}/.status.flag"
buildDependency "${TEMP_DIR_NEW}" "${TEMP_FILE}" "${HOME}/.m2/settings.xml" true
cat "${TEMP_DIR_NEW}/.status.flag"

rm ${TEMP_FILE}
rm -rf ${TEMP_DIR}
rm -rf ${TEMP_DIR_NEW}
rm ${OVERRIDE_FILE}
rm ${NO_SCM_POM_FILE}
rm ${CONNECTION_POM_FILE}
rm $EFFECTIVE_FILE
