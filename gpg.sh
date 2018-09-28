#!/bin/bash

set -eu

usage() {
cat << EOF
GnuPG integration with Helm

This provides integration with 'gpg', the command line tool for working with
GnuPG.

Available Commands:
  sign    Sign a chart archive (tgz file) with a GPG key
  verify  Verify a chart archive (tgz + tgz.prov) with your GPG keyring

EOF
}

sign_usage() {
cat << EOF
Sign a chart using GnuPG credentials.

This is an alternative to 'helm sign'. It uses your gpg credentials
to sign a chart.

Example:
    $ helm gpg sign foo-0.1.0.tgz

EOF
}

verify_usage() {
cat << EOF
Verify a chart

This is an alternative to 'helm verify'. It uses your gpg credentials
to verify a chart.

Example:
    $ helm gpg verify foo-0.1.0.tgz

In typical usage, use 'helm fetch --prov' to fetch a chart:

    $ helm fetch --prov upstream/wordpress
    $ helm gpg verify wordpress-1.2.3.tgz
    $ helm install ./wordpress-1.2.3.tgz

EOF
}

is_help() {
  case "$1" in
  "-h")
    return 0
    ;;
  "--help")
    return 0
    ;;
  "help")
    return 0
    ;;
  *)
    return 1
    ;;
esac
}

sign() {
  if is_help $1 ; then
    sign_usage
    return
  fi
  chart=$chart
  echo "Signing $chart"
  shasum=$(openssl sha256 -sha256 $chart| awk '{ print $2 }')
  chartyaml=$(tar -zxf $chart --wildcards --exclude 'charts/' -O '*/Chart.yaml')
c=$(cat << EOF
$chartyaml

...
files:
  $chart: sha256:$shasum
EOF
)
  modearguments=""
  pinentrymode=""
  if [ "$interactive" == "0" ]; then
      version=$(gpg --version | grep 'gpg (GnuPG)' | cut -d ' ' -f 3 | cut -d '.' -f 1)
      if [ "$version" == "2" ]; then
        pinentrymode=" --pinentry-mode loopback"
      fi
      modearguments="--quiet --batch"
  fi
  keyuser=""
  passphrasetouse=""
  if [ "$passphrase" != "" ]; then
    passphrasetouse="--passphrase $passphrase"
  fi
  if [ "$keyname" != "" ]; then
    keyuser=(-u "$keyname")
  fi
  echo "$c" | gpg --clearsign $modearguments $passphrasetouse $pinentrymode -o "$chart.prov" "${keyuser[@]}"
}

verify() {
  if is_help $1 ; then
    verify_usage
    return
  fi
  chart=$1
  gpg --verify ${chart}.prov

  # verify checksum
  sha=$(shasum $chart)
  set +e
  grep "$chart: sha256:$sha" ${chart}.prov > /dev/null
  if [ $? -ne 0 ]; then
    echo "ERROR SHA verify error: sha256:$sha does not match ${chart}.prov"
    return 3
  fi
  set -e
  echo "plugin: Chart SHA verified. sha256:$sha"
}

shasum() {
  openssl sha256 -sha256 "$1" | awk '{ print $2 }'
}

if [[ $# < 1 ]]; then
  usage
  exit 1
fi

if ! type "gpg" > /dev/null; then
  echo "Command like 'gpg' client must be installed"
  exit 1
fi

case "${1:-"help"}" in
  "sign"):
    if [[ $# < 2 ]]; then
      push_usage
      echo "Error: Chart package required."
      exit 1
    fi
    shift
    chart="$1"
    shift
    interactive="0"
    keyname=""
    passphrase=""
    while [ "$1" != "" ]; do
      case $1 in
        -i)
          interactive=1;
          ;;
        --passphrase)
          shift
          passphrase="$1"
          echo "Setting passphrase"
          ;;
        -u | --local-user)
          keyname="$2"
          echo "Setting keyname to $keyname"
          break
          ;;
        *)
          ;;
      esac
     shift
    done

    sign $chart $interactive $passphrase $keyname
    ;;
  "verify"):
    if [[ $# < 2 ]]; then
      verify_usage
      echo "Error: Chart package required."
      exit 1
    fi
    verify $2
    ;;
  "help")
    usage
    ;;
  "--help")
    usage
    ;;
  "-h")
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac

exit 0
