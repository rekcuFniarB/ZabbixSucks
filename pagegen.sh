#!/bin/sh

SELF="$(basename $0)"

USAGE="Generate HTML status page.

USAGE
    -stats path
        Required. Directory with stats files.
    
    -help
        Print this help.

EXAMPLE
    $SELF -stats /var/log/sitesmonitor > /var/www/sitesmonitor/status.html

Written by BrainFucker."

## Print messages to stderr
errlog () {
    echo "$@" 1>&2
}

getfilemodified () {
    stat "$1" | grep 'Modify:' | sed 's/Modify://'
}

## Args parser
## Supported arg formats:
##     -arg --arg (both are identical)
##     -arg value
##     -arg=value
parse_args() {
    local ARG _PREV_ARG _ARG _VAR _VAL _ARGN SKIP
    for ARG in "$@"; do
        case "$ARG" in
            --) _PREV_ARG=''
                SKIP=1 ;;
            -*) if [ -z "$SKIP" ]; then
                    _ARG="$(echo -n "$ARG" | sed 's/^-\+//' | sed 's/-/_/g' | tr -d '\r' | tr '\t\v\n' ' ')"
                    case "$_ARG" in
                        *=*) _PREV_ARG=''
                             _VAR="$(echo -n "$_ARG" | sed 's/=.*//')"
                             _VAL="$(echo -n "$_ARG" | sed 's/.\+=//')"
                             if [ -z "$_VAL" ]; then
                                 _VAL=0
                             fi
                             eval "_arg_$_VAR=\$_VAL" ;;
                          *) _PREV_ARG="_arg_$_ARG"
                             eval "_arg_$_ARG=1" ;;
                    esac
                fi ;;
             *) if [ -n "$_PREV_ARG" ]; then
                    eval "$_PREV_ARG=\$ARG"
                    _PREV_ARG=''
                else
                    _ARGN=$((_ARGN+1))
                    eval "_arg$_ARGN=\$ARG"
                fi ;;
        esac
    done
} # parse_args()

parse_args "$@"

if [ -z "$1" ] || [ -n "$_arg_help" ] || [ -n "$_arg_h" ]; then
    errlog "$USAGE"
    exit 0
fi

if [ -z "$_arg_stats" ] || [ ! -d "$_arg_stats" ]; then
    errlog "No such directory '$_arg_stats'. Run '$SELF -help' to see usage."
    exit 1
fi

export LANG=C

echo '<!DOCTYPE html>
<html>
<head>
<title>Sites monitoring status</title>
<meta charset="UTF-8">
<style>
h2 {
    margin: 1em;
}
div.type {
    padding-left: 1em;
}
div.infoblock {
    border: 1px solid black;
    margin-bottom: 1em;
}
div.tbl {
    display: table;
    width: 100%;
    background-color: #c0c0c0;
}
div.tr {
    display: table-row;
}
div.td {
    display: table-cell;
}
div.time{
    text-align: right;
}
pre {
    background-color: #eeeeee;
    padding: 1em;
    margin: 0;
}
</style>
</head>
<body>'

for FILE in "$_arg_stats/TASK__"*
  do
    TASKNAME="$(basename "$FILE" | sed 's/TASK__//')"
    TIME="$(getfilemodified "$FILE")"
    echo '<div class="infoblock">'
    echo "<h2>$TASKNAME" | sed 's#\.err#</h2>\n<div class="tbl"><div class="tr"><div class="type td">stderr</div>%#' | \
    sed 's#\.out#</h2>\n<div class="tbl"><div class="tr"><div class="type td">stdout</div>%#' | \
    sed 's#\.status#</h2>\n<div class="tbl"><div class="tr"><div class="type td">status</div>%#' | \
    sed "s#%#<div class=\"time td\">$TIME</div></div></div>#"
    echo "<pre>"
    cat "$FILE"
    echo "</pre>"
    echo '</div>'
    echo ''
  done


echo '<div class="infoblock">'
echo '<h2>Last report</h2>'
echo '<div class="tbl"><div class="tr"><div class="type td">stderr</div><div class="time td">'
getfilemodified "$_arg_stats/REPORT.txt"
echo '</div></div></div>'
echo '<pre>'
if [ -f "$_arg_stats/REPORT.txt" ]; then
    cat "$_arg_stats/REPORT.txt"
else
    echo 'File not found'
fi
echo '</pre>'
echo '</div>'

echo ''

echo '<div class="infoblock">'
echo '<h2>Last stdout</h2>'
echo '<div class="tbl"><div class="tr"><div class="type td">stderr</div><div class="time td">'
getfilemodified "$_arg_stats/TASK.OUT"
echo '</div></div></div>'
echo '<pre>'
if [ -f "$_arg_stats/TASK.OUT" ]; then
    cat "$_arg_stats/TASK.OUT"
else
    echo 'File not found'
fi
echo '</pre>'
echo '</div>'

echo ''

echo '<div class="infoblock">'
echo '<h2>Last stderr</h2>'
echo '<div class="tbl"><div class="tr"><div class="type td">stderr</div><div class="time td">'
getfilemodified "$_arg_stats/TASK.ERR"
echo '</div></div></div>'
echo '<pre>'
if [ -f "$_arg_stats/TASK.ERR" ]; then
    cat "$_arg_stats/TASK.ERR"
else
    echo 'File not found'
fi
echo '</pre>'
echo '</div>'

echo ''


echo '</body>
</html>
'
