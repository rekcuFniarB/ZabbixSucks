#!/bin/sh

SELF="$0"
BASENAME="$(basename $0)"
USR="$(whoami)"

USAGE="Monitor sites. This script is supposed to run from cron.

USAGE
    -statsdir path
        Directory where to store stats. If ommited, /tmp will be used.
    
    -tasks
        Directory where tasks are stored. If ommited, will use /etc/monitorsites.
    
    -pagegen [page_file_path]
        Generate HTML page with stats. If no path specified, will store as 'index.html' in stats directory.
    
    -onalert command
        Invoke specified command on alert. Alert message will be piped to command's stdin.
    
    -help
        Print this help.

EXAMPLE
    $BASENAME -statsdir /var/log/sitesmonitor -tasks /etc/monitorsites/tasks -pagegen /var/www/stats/index.html

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
## @param file
fn_notify () {
    if [ -n "$(which sendmail)" ]; then
        ## send email directly
        {
            echo "Subject: $MAIL_SUBJ\n\n"
            cat "$1"
        } | fn_sendmail
    else
        ## Just print to stderr
        cat "$1" 1>&2
    fi
    
    if [ -n "$_arg_onalert" -a -x "$_arg_onalert" ]; then
        cat "$1" | "$_arg_onalert"
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

## Standard site availability test
## Accepts no args. Invoked from tasks.
fn_test_site() {
    if [ -z "$URL" ]; then
        errlog "URL required."
        exit 1
    fi
    
    if [ -z "$USERAGENT" ]; then
        USERAGENT='Sites monitor'
    fi
    
    START=$(date '+%s%N')
    RESPONSE="$(wget -T 2 -t 3 -o /dev/null -U "$USERAGENT" -O - "$URL")"
    ST=$?
    END=$(date '+%s%N')
    
    DIFF=$(( (END - START)/1000000 ))
    
    errlog "Query time: ${DIFF}ms"
    
    if [ -z "$THRESHOLD" ]; then
        THRESHOLD=500
    fi
    
    if [ $DIFF -gt $THRESHOLD ]; then
        echo "Query time took more than ${THRESHOLD}ms (${DIFF}ms)"
        STATUS=$(( 200 + ST ))
    fi
    
    if [ -z "$RESPONSE" ]; then
        echo "Got empty response."
        STATUS=$(( 500 + ST ))
    fi
    
    if [ -z $STATUS ]; then
        STATUS=$ST
    fi
    
    ## If above request failed, test domain to print in logs
    if [ $STATUS -gt 0 ] && [ -n "$DOMAIN" ]; then
        timeout 10 ping -c 3 $DOMAIN 1>&2
        errlog
        timeout 10 traceroute $DOMAIN 1>&2
        errlog
        #traceroute6 $DOMAIN 1>&2
        #errlog
        timeout 10 dig @8.8.8.8 $DOMAIN 1>&2
        #errlog
        #dig AAAA $DOMAIN 1>&2
        #errlog
        #dig @8.8.8.8 AAAA $DOMAIN 1>&2
        #errlog
        #/sbin/ip -6 route show 1>&2
        #errlog
        #/sbin/route -A inet6 1>&2
    fi
    
    errlog
    #errlog "PATH: $PATH"
    
    exit $STATUS
}

if [ _"$BASENAME" = _'monitorsites' -o _"$BASENAME" = _'monitorsites.sh' ]; then
    for util in sed grep wget ping traceroute dig; do
        if [ -z "$(which "$util")" ]; then
            errlog "ERROR: required '$util' not found."
            exit 1
        fi
    done
    
    parse_args "$@"
    
    if [ -n "$_arg_help" ] || [ -n "$_arg_h" ]; then
        errlog "$USAGE"
        exit 0
    fi
    
    export SELF USR BASENAME
    
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
        #ID=$(id -u)
        #TMPDIR="/run/user/$ID"
        #
        #if [ ! -d "$TMPDIR" ]; then
        #    TMPDIR="/dev/shm"
        #fi
        TMPDIR='/tmp'
        
        STATSDIR="$TMPDIR/monitorsites"
        
        if [ ! -d "$STATSDIR" ]; then
            mkdir "$STATSDIR"
        fi
        
        if [ ! -d "$STATSDIR" ]; then
            errlog "Could not create directory '$STATSDIR'"
            exit 1
        fi
    fi
    
    ## Executing every task
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
        timeout 2m "$TASK" > "$STATSDIR/TASK.MSG" 2> "$STATSDIR/TASK.ERR"
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
        
        echo -n "$REPORT" > "$STATSDIR/REPORT.txt"
        
        ## send notification if status changed
        if [ -n "$STATUS_CHANGED" ]; then
            fn_notify "$STATSDIR/REPORT.txt"
        fi
        
        
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
fi ## if self
