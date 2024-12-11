#!/bin/bash

set -x
set -e
set -o pipefail

function get_current_subpkgs {
  NEW_RPMS=$1
  RPMLIST=$(ls $NEW_RPMS)
  SUBPKGS=""
  for RPM in $RPMLIST; do
    SUBPKGS+=$(echo $RPM | rev | cut -f 3- -d'-' | rev)
    SUBPKGS+=","
  done
  echo $SUBPKGS
}

function get_set_version {
  SET_DIR=$1
  RPMLIST=($(ls $SET_DIR))
  echo ${RPMLIST[1]} | rev | cut -f -2 -d'-' | rev
}

function clean_installed_java {
  javas=`rpm -qa  --queryformat "%{NAME}-%{VERSION}-%{RELEASE}\n"  | grep -e "^java-[0-9]" -e "^java-gcj"`
  sudo rpm -e --nodeps $javas
}

function run_parallel_test {
  OLD_RPMS=$1
  NEW_RPMS=$2
  INSTALL_COMMAND=$3
  if [[ "x$INSTALL_COMMAND" = "x" ]]; then
    which dnf
      if [ $? -eq 0 ] ; then
        INSTALL_COMMAND="dnf -y install"
      else
        INSTALL_COMMAND="yum -y install"
      fi
  else
    INSTALL_COMMAND="rpm -i"
  fi
  YUM_CONF="/etc/yum.conf"
  sudo cp $YUM_CONF $YUM_CONF-copy
  echo "installonlypkgs=$(get_current_subpkgs $NEW_RPMS)" | sudo tee -a $YUM_CONF

  sudo $INSTALL_COMMAND $OLD_RPMS/*
  RES1=$?
  sudo $INSTALL_COMMAND $NEW_RPMS/*
  RES2=$?
  
  sudo rm $YUM_CONF
  sudo mv $YUM_CONF-copy $YUM_CONF
  clean_installed_java
  if [ $RES1 -eq 0 ] && [ $RES2 -eq 0 ]; then
    return 0
  fi
  return 1

}

RUNNING=false

if [[ ( x${BUILD_OS_NAME} == xel && ${BUILD_OS_VERSION} > 6 ) || x${BUILD_OS_NAME} == xf ]]; then
  RUNNING=true
fi

FAILED=0
PASSED=0
IGNORED=0
BODY=""


if [ "x$RFaT" == "x" ]; then
  readonly RFaT=`mktemp -d`
  git clone https://github.com/rh-openjdk/run-folder-as-tests.git ${RFaT} 1>&2
  ls -l ${RFaT}  1>&2
fi
source ${RFaT}/jtreg-shell-xml.sh

if [ "x$TMPRESULTS" == "x" ]; then
  TMPRESULTS=`pwd`
fi


echo "" > $TMPRESULTS/parallel_install_log.txt

let "PASSED+=1"
echo "Appending dummy test, so there is at elast one test always running in suite" >> $TMPRESULTS/parallel_install_log.txt
TEST=$(printXmlTest "tps" "dummyTestToPrventTotalFailure" "0" "" "")
BODY+="$TEST
" # new line to improve clarity, also is used in TPS/tesultsToJtregs.sh


if [[ $(get_set_version $1) == $(get_set_version $2) ]]; then
  echo "same versions of old and new rpms, skipping the test"
  RUNNING=false
fi
set +e
clean_installed_java
set -e
for COMMANDSTRING in YumDnf "Rpm"; do
  LOGFILE=$TMPRESULTS/parallelInstall$COMMANDSTRING.log
  echo "" > $LOGFILE
  if [ $RUNNING = false ]; then
    let "IGNORED+=1"
    echo "!skipped!" >> $LOGFILE
    TEST=$(printXmlTest "tps" "install$COMMANDSTRING" "0" "$LOGFILE" "")
    BODY+="$TEST
    " # new line to improve clarity, also is used in TPS/tesultsToJtregs.sh
    continue
  fi

  ARGUMENT=$COMMANDSTRING
  if [[ "YumDnf" == $COMMANDSTRING ]]; then
    ARGUMENT=""
  fi

  set +e
  run_parallel_test $1 $2 $ARGUMENT >> $LOGFILE 2>&1

  RES=$?
  set -e

  if [ $RES -eq 0 ]; then
    let "PASSED+=1"
    TEST=$(printXmlTest "tps" "install$COMMANDSTRING" "0")
    BODY+="$TEST
    " # new line to improve clarity, also is used in TPS/tesultsToJtregs.sh
    echo "install$COMMANDSTRING PASSED\n"
  else
    let "FAILED+=1"
    TEST=$(printXmlTest "tps" "install$COMMANDSTRING" "0" "$LOGFILE" "$LOGFILE")
    BODY+="$TEST
    " # new line to improve clarity, also is used in TPS/tesultsToJtregs.sh
    echo "install$COMMANDSTRING FAILED\n"
  fi
done

let "TESTS = $FAILED + $PASSED + $IGNORED"

XMLREPORT=$TMPRESULTS/parallelTestJtreg.jtr.xml
printXmlHeader $PASSED $FAILED $TESTS $IGNORED "parallelInstalls" > $XMLREPORT
echo "$BODY" >> $XMLREPORT
printXmlFooter >> $XMLREPORT


