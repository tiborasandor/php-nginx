#!/bin/sh
case "$1" in
  Username*) printf '%s\n' "${GIT_USERNAME}" ;;
  Password*) printf '%s\n' "${GIT_PERSONAL_TOKEN}" ;;
esac
