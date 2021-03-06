#!/usr/bin/env bash

fatal()
{
  echo "fatal: $1" 1>&2
  exit 1
}

buildspec=$1
if [ -z "${buildspec}" ]
then
  fatal "usage: buildspec"
fi

# known limitation: can't rebuild Windows reference artifact
# because we need to do Git checkout with Windows newlines (at least for pom.xml)

echo "Rebuilding from spec ${buildspec}"

. ${buildspec} || fatal "could not source ${buildspec}"

echo "- groupId: ${groupId}"
echo "- artifactId: ${artifactId}"
echo "- version: ${version}"
echo "- gitRepo: ${gitRepo}"
echo "- gitTag: ${gitTag}"
echo "- jdk: ${jdk}"
echo "- newline: ${newline}"
echo "- command: ${command}"
echo "- buildinfo: ${buildinfo}"

base="$PWD"

pushd `dirname ${buildspec}` >/dev/null || fatal "could not move into ${buildspec}"

# prepare source, using provided Git repository and tag
# TODO: support svn, support getting source-release.zip
[ -d target ] || mkdir target
cd target
[ -d ${artifactId} ] || git clone ${gitRepo} ${artifactId} || fatal "failed to clone ${artifactId}"
cd ${artifactId}
git fetch || fatal "failed to git fetch"
git checkout ${gitTag} || fatal "failed to git checkout ${gitTag}"

pwd

# the effective rebuild command, adding buildinfo plugin to compare with central content
mvn_rebuild="${command} -V -e buildinfo:buildinfo -Dreference.repo=central -Dreference.compare.save"

mvnBuildDocker() {
  local mvnCommand mvnImage
  mvnCommand="$1"
  # select Docker image to match required JDK version
  case ${jdk} in
    6 | 7)
      mvnImage=maven:3.6.1-jdk-${jdk}-alpine
      ;;
    9)
      mvnImage=maven:3-jdk-${jdk}-slim
      ;;
    *)
      mvnImage=maven:3.6.3-jdk-${jdk}-slim
  esac

  echo "Rebuilding using Docker image ${mvnImage}"
  local docker_command="docker run -it --rm --name rebuild-central -v $PWD:/var/maven/app -v $base:/var/maven/.m2 -u $(id -u ${USER}):$(id -g ${USER}) -e MAVEN_CONFIG=/var/maven/.m2 -w /var/maven/app"
  local mvn_docker_params="-Duser.home=/var/maven"
  if [ "${newline}" == "crlf" ]
  then
    ${docker_command} ${mvnImage} ${mvnCommand} ${mvn_docker_params} -Dline.separator=$'\r\n'
  else
    ${docker_command} ${mvnImage} ${mvnCommand} ${mvn_docker_params}
  fi
}

# TODO not tested
mvnBuildLocal() {
  local mvnCommand="$1"

  echo "Rebuilding using local JDK ${jdk}"
  # TODO need to define settings with ${base}/repository local repository to avoid mixing reproducible-central dependencies with day to day builds
  if [ "${newline}" == "crlf" ]
  then
    ${mvnCommand} -Dline.separator=$'\r\n'
  else
    ${mvnCommand}
  fi
}

# by default, build with Docker
# TODO: on parameter, use instead mvnBuildLocal after selecting JDK
#   jenv shell ${jdk}
#   sdk use java ${jdk}
mvnBuildDocker "${mvn_rebuild}" || fatal "failed to build"

cp ${buildinfo}* ../.. || fatal "failed to copy buildinfo artifacts"

popd > /dev/null
