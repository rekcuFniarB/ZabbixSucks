#!/bin/sh

SELF="$(basename $0)"
USR="$(whoami)"

USAGE="Monitor sites. This script is supposed to run from cron.

USAGE
    -statsdir path
        Directory where to store stats. If ommited, will try to use '/run/user/ID/monitorsites' or '/dev/shm/monitorsites'.
    
    -tasks
        Directory where tasks are pladed. If ommited, will use /etc/monitorsites.
    
    -pagegen [page_file_path]
        Generate HTML page with stats. If no path specified, will store as 'index.html' in stats directory.
    
    -help
        Print this help.

EXAMPLE
    $SELF -statsdir /var/log/sitesmonitor -tasks /etc/monitorsites/tasks -pagegen /var/www/stats/index.html

Written by BrainFucker."

PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

## print messages to stderr
errlog () {
    echo "$@" 1>&2
}

## sendmail wrapper to add some headers
fn_sendmail() {
    local MAILNAME MESSAGE X_HEADERS HEADERS_DONE LINE
    if [ -f /etc/mailname ]; then
        MAILNAME="$(cat /etc/mailname | head -n 1)"
    fi
    if [ -z "$MAILNAME" ]; then
        MAILNAME='localhost'
    fi
    
    X_HEADERS="To: $USR@$MAILNAME
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-transfer-encoding: 8bit
"
    while read LINE; do
        if [ -z "$HEADERS_DONE" ]; then
            if [ -z "$LINE" ]; then
                MESSAGE="$MESSAGE$X_HEADERS"
                HEADERS_DONE=1
            fi
        fi
        MESSAGE="$MESSAGE$LINE
"
    done # while
    echo "$MESSAGE" | sendmail "$USR"
} # fn_sendmail()

## send email or just print
fn_notify () {
    if [ -n "$(which sendmail)" ]; then
        ## send email directly
        echo "Subject: $MAIL_SUBJ

$@" | fn_sendmail
    else
        ## Just print to stderr
        errlog "$@"
    fi
} ## fn_notify()

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

if [ -n "$_arg_help" ] || [ -n "$_arg_h" ]; then
    errlog "$USAGE"
    exit 0
fi

if [ -n "$_arg_tasks" ] && [ "$_arg_tasks" != 1 ]; then
    TASKS="$_arg_tasks"
else
    TASKS='/etc/monitorsites'
fi

if [ ! -d "$TASKS" ]; then
    errlog "No such directory $TASKS"
    exit 1
fi

if [ -n "$_arg_statsdir" ] && [ "$_arg_tasks" != 1 ]; then
    STATSDIR="$_arg_statsdir"
else
    ID=$(id -u)
    TMPDIR="/run/user/$ID"

    if [ ! -d "$TMPDIR" ]; then
        TMPDIR="/dev/shm"
    fi
    
    STATSDIR="$TMPDIR/monitorsites"
    
    if [ ! -d "$STATSDIR" ]; then
        mkdir "$STATSDIR"
    fi
    
    if [ ! -d "$STATSDIR" ]; then
        errlog "Could not create directory '$STATSDIR'"
        exit 1
    fi
fi

for TASK in "$TASKS/"*.task; do
    TIME="$(date)"
    TASKNAME="$(basename "$TASK" | sed 's/\.task$//' )"
    if [ _"$TASKNAME" = _'*' ]; then
        errlog "SITES MONITOR\n=============\n\nNo tasks."
        exit
    fi
    
    if [ ! -x "$TASK" ]; then
        # errlog "Monitor Sites: $TASK non executable. Skipping..."
        continue
    fi
    
    if [ ! -f "$STATSDIR/TASK__$TASKNAME.msg" ]; then
        touch "$STATSDIR/TASK__$TASKNAME.msg"
    fi
    
    if [ ! -f "$STATSDIR/TASK__$TASKNAME.err" ]; then
        touch "$STATSDIR/TASK__$TASKNAME.err"
    fi
    
    if [ ! -f "$STATSDIR/TASK__$TASKNAME.status" ]; then
        touch "$STATSDIR/TASK__$TASKNAME.status"
    fi
    
    START=$(date +%s%N)
    timeout 2m $TASK > "$STATSDIR/TASK.MSG" 2> "$STATSDIR/TASK.ERR"
    STATUS=$?
    END=$(date +%s%N)
    
    DIFF=$(( (END - START)/1000000 ))
    
    CHANGED=''
    
    ## timed out command returns exits code 124 if command not completed
    if [ $STATUS -eq 124 ]; then
        ERR='Task timed out.'
    fi
    
    _STATUS="$(cat "$STATSDIR/TASK__$TASKNAME.status")"
    if [ _"$STATUS" != _"$_STATUS" ]; then
        CHANGED="${CHANGED}STATUS "
        STATUS_CHANGED=1
    fi
    
    OUT="$(cat "$STATSDIR/TASK.MSG")"
    _OUT="$(cat "$STATSDIR/TASK__$TASKNAME.msg")"
    if [ _"$OUT" != _"$_OUT" ]; then
        CHANGED="${CHANGED}OUTPUT"
    fi
    
    if [ -n "$CHANGED" ]; then
        ERR="$ERR\n$(cat "$STATSDIR/TASK.ERR")"
        ## store status
        echo -n "$STATUS" > "$STATSDIR/TASK__$TASKNAME.status"
        mv "$STATSDIR/TASK.MSG" "$STATSDIR/TASK__$TASKNAME.msg"
        mv "$STATSDIR/TASK.ERR" "$STATSDIR/TASK__$TASKNAME.err"
        REPORT="$REPORT
        ## TASK $TASKNAME ##
        
        Date:         $TIME
        Time:         ${DIFF}ms
        
        Changed:      $CHANGED
        
        New status:   $STATUS
        Prev. status: $_STATUS
        
        ### Output:
        $OUT
        
        ### Prev. output:
        $_OUT
        
        ### StdErr:
        $ERR
        "
        MAIL_SUBJ="$MAIL_SUBJ$TASKNAME: $STATUS; "
    fi ## if $CHANGED
done ## for tasks

if [ -n "$REPORT" ]; then
    REPORT="
    SITES MONITOR REPORT
    ====================
    
    $REPORT
    "
    
    ## send notification if status changed
    if [ -n "$STATUS_CHANGED" ]; then
        fn_notify "$REPORT"
    fi
    
    echo -n "$REPORT" > "$STATSDIR/REPORT.txt"
fi

### Generate HTML page
if [ -n "$_arg_pagegen" ]; then
    if [ "$_arg_pagegen" = 1 ]; then
        PAGE="$STATSDIR/index.html"
    else
        PAGE="$_arg_pagegen"
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

<body>' > "$PAGE"

    for FILE in "$STATSDIR/TASK__"*
      do
        TASKNAME="$(basename "$FILE" | sed 's/TASK__//')"
        TIME="$(getfilemodified "$FILE")"
        echo '<div class="infoblock">' >> "$PAGE"
        echo "<h2>$TASKNAME" | sed 's#\.err#</h2>\n<div class="tbl"><div class="tr"><div class="type td">StdErr</div>%#' | \
            sed 's#\.msg#</h2>\n<div class="tbl"><div class="tr"><div class="type td">Message</div>%#' | \
            sed 's#\.status#</h2>\n<div class="tbl"><div class="tr"><div class="type td">Status</div>%#' | \
            sed "s#%#<div class=\"time td\">$TIME</div></div></div>#" >> "$PAGE"
        echo "<pre>" >> "$PAGE"
        cat "$FILE" >> "$PAGE"
        echo "</pre>" >> "$PAGE"
        echo '</div>' >> "$PAGE"
        echo '' >> "$PAGE"
      done
    
    if [ -f "$STATSDIR/REPORT.txt" ]; then
        echo '<div class="infoblock">' >> "$PAGE"
        echo '<h2>Last report</h2>' >> "$PAGE"
        echo '<div class="tbl"><div class="tr"><div class="type td">Summary</div><div class="time td">' >> "$PAGE"
        getfilemodified "$STATSDIR/REPORT.txt" >> "$PAGE"
        echo '</div></div></div>' >> "$PAGE"
        echo '<pre>' >> "$PAGE"
        cat "$STATSDIR/REPORT.txt" >> "$PAGE"
        echo '</pre>' >> "$PAGE"
        echo '</div>' >> "$PAGE"
        echo '' >> "$PAGE"
    fi
    
    if [ -f "$STATSDIR/TASK.MSG" ]; then
        echo '<div class="infoblock">' >> "$PAGE"
        echo '<h2>Last stdout</h2>' >> "$PAGE"
        echo '<div class="tbl"><div class="tr"><div class="type td">Message</div><div class="time td">' >> "$PAGE"
        getfilemodified "$STATSDIR/TASK.MSG" >> "$PAGE"
        echo '</div></div></div>' >> "$PAGE" 
        echo '<pre>' >> "$PAGE"
        cat "$STATSDIR/TASK.MSG" >> "$PAGE"
        echo '</pre>' >> "$PAGE"
        echo '</div>' >> "$PAGE"
        echo '' >> "$PAGE"
    fi
    
    if [ -f "$STATSDIR/TASK.ERR" ]; then
        echo '<div class="infoblock">' >> "$PAGE"
        echo '<h2>Last stderr</h2>' >> "$PAGE"
        echo '<div class="tbl"><div class="tr"><div class="type td">StdErr</div><div class="time td">' >> "$PAGE"
        getfilemodified "$STATSDIR/TASK.ERR" >> "$PAGE"
        echo '</div></div></div>' >> "$PAGE"
        echo '<pre>' >> "$PAGE"
        cat "$STATSDIR/TASK.ERR" >> "$PAGE"
        echo '</pre>' >> "$PAGE"
        echo '</div>' >> "$PAGE"
        echo '' >> "$PAGE"
    fi
    
    echo '</body>
</html>
' >> "$PAGE"
fi # if --pagegen