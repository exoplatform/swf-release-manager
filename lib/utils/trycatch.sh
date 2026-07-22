#!/bin/bash -eu

function try()
{
    if [[ $- = *e* ]]; then SAVED_OPT_E=1; set +e; else SAVED_OPT_E=0; fi
}

function throw()
{
    exit "$1"
}

function catch()
{
    export ex_code=$?
    (( SAVED_OPT_E )) && set -e
    return $ex_code
}

function throwErrors()
{
    set -e
}

function ignoreErrors()
{
    set +e
}
