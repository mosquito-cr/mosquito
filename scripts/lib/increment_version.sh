#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

print_help () {
  cat <<HELP
$0: increments a version number.

Usage: $0 -h x.y.z (major|minor|patch)

  x.y.z            The current version number. Eg. 56.02.17

  -h               Help.        Print this help and exit.

  major            Increment the major portion of the release, expressed as 'x' above.
  minor            Increment the minor portion of the release, expressed as 'y' above.
  patch            Increment the patch portion of the release, expressed as 'z' above.

  One of major, minor, or patch must be specified.

HELP

  exit 1
}

while getopts "h" opt; do
  case $opt in
    h) print_help ;;
  esac
done

shift $(($OPTIND - 1))
current_version=${1:-bad}
release_edition=${2:-bad}

case "$release_edition" in
  major|minor|patch) ;;
  *)
    echo "Error: could not increment by '$release_edition'."
    echo
    print_help
    ;;
esac

major=$( echo "$current_version" | awk -F. '{ print $1 }')
minor=$( echo "$current_version" | awk -F. '{ print $2 }')
patch=$( echo "$current_version" | awk -F. '{ print $3 }')

case "$release_edition" in
  major)
    major=$((major + 1))
    minor=0
    patch=0
    ;;

  minor)
    minor=$((minor + 1))
    patch=0
    ;;

  patch)
    patch=$((patch + 1))
    ;;

esac

new_version="$major.$minor.$patch"
echo "$new_version"
