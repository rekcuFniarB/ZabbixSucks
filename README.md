Simple sites availability monitoring util
=========================================

Usage
-----

In `tasks` directory create a `mydomain.com.task` file for each tested domain:

```bash
. "$SELF"

URL='https://mydomain.com/some/path/'
DOMAIN='mydomain.com' ## Optional. When test fails, will also test for ping and traceroute this hostname.
THRESHOLD=500 ## Optional, 500ms by default. Used to test response delay.
USERAGENT='Sites Monitor' ## Optional

fn_test_site
```

Create cron task:

    */5 * *   *   *     monitorsites.sh -tasks /etc/MonitorSites/tasks -pagegen /var/www/stats/index.html

where `-tasks` directory of `.task` files. `-pagegen` arg is optional, creates a html file with last reports.

When `sendmail` is available, alerts will be sent to local user under which this job was run.

### Command line options

`-statsdir path`

Directory where to store stats. If ommited, `/tmp` will be used.

`-tasks`

Directory where tasks are stored. If ommited, will use /etc/monitorsites.

`-pagegen [page_file_path]`

Generate HTML page with stats. If no path specified, will store as 'index.html' in stats directory.

`-onalert command`

Invoke specified command on alert. Alert message will be piped to command's stdin.

`-help`

Print this help.


### Special task example

```bash
### specialtest.task

/opt/scripts/do-some-test.sh
STATUS="$?"
if [ "$STATUS" -gt 0 ]; then
    ## If test failed, print it to stdout
    echo "WARNING: test failed"
    ## Exit with non zero status
    exit "$STATUS"
fi
```
