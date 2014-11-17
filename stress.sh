#!/bin/sh

show_help() {
cat << EOF
Usage: ${0##*/} [-u BASE_URL] [-a ACCESS_LOG] [-s] [-t NUM_THREADS] [-n NUM_LINES] [-d DELAY_IN_SECS] [-p]  [-l CURL_LOG] [-r]

    -s  shuffle sample
    -p  show progress
    -r  print report at the end of the test

EOF
}

pv=cat
curllog=/dev/null
delay=0
num_lines=100000000
threads=50
accesslog="-"
shuffle=head

while getopts "ha:n:t:u:d:pl:rs" opt; do
    case "$opt" in
    h)
        show_help
        exit 0
        ;;
    a)  accesslog=$OPTARG
        ;;
    n)  num_lines=$OPTARG
        ;;
    t)  threads=$OPTARG
        ;;
    p)  pv="pv -l -s $num_lines"
        ;;
    l)  curllog=$OPTARG
        ;;
    r)  report="1"
        ;;
    u)  url=$OPTARG
        ;;
    d)  delay=$OPTARG
        ;;
    s)  shuffle=shuf
        ;;
    *)  show_help
        exit 1
        ;;
    esac
done

[ "$report" != "" ] && [ "$curllog" = "/dev/null" ] && curllog="/tmp/$(basename $0).$$.$RANDOM.tmp.log" deletecurllog="1"


if [ "$url" != "" ]; then
    >&2 echo "Preparing input..."
    tmpinput="/tmp/$(basename $0).$$.$RANDOM.tmp.log"
    if [ "$shuffle" = "shuf" ]; then
        $shuffle -n `expr $num_lines \* 2` $accesslog > $tmpinput || exit 1
    else
        tmpinput=$accesslog
    fi

    before=`date +%s`

    echo "Start testing..."
    cat $tmpinput | grep '" 200 ' | grep -v "'" | awk -F '"' '{print $2}' | grep GET | head -n $num_lines | awk -F ' ' '{print $2}' | xargs -n1 -P $threads sh -c "curl -sL -w '%{http_code} %{time_total} %{size_download} %{url_effective}\\n' -o /dev/null '$url'\$1; sleep $delay" _ | $pv > $curllog || exit 1

    rm -f $tmpinput

    after=`date +%s`

    elapsed=`expr $after - $before`
    reqseq=`expr $num_lines / $elapsed`

    >&2 echo "$reqseq req/seq"
fi

if [ "$report" != "" ]; then
    cat $curllog | awk ' {
        url = $4

        if (gsub(".*article-.*mobile=true.*", "mobile/articles", url) ||
            gsub(".*article-.*", "articles", url) ||
            gsub(".*video-.*mobile=true.*", "mobile/video", url) ||
            gsub(".*video-.*", "video", url) ||
            gsub(".*columnist-.*mobile=true.*", "mobile/columnist", url) ||
            gsub(".*columnist-.*", "columnist", url) ||
            gsub(".*/(home|homeus|homeau)/index.html.*mobile=true.*", "mobile/home", url) ||
            gsub(".*/(home|homeus|homeau)/index.html.*", "home", url) ||
            gsub(".*index.html.*mobile=true.*", "mobile/channels", url) ||
            gsub(".*index.html.*", "channels", url) ||
            gsub(".*rss.*", "rss", url) ||
            gsub(".*registration.*", "registration", url) ||
            gsub(".*meta.*", "meta", url) ||
            gsub(".*/geolocation/.*", "esi calls", url) ||
            gsub(".*/mobile/.*", "mobile feed", url) ||
            gsub(".*/api/.*", "api", url) ||
            gsub(".*/home/search.html.*", "search", url) ||
            gsub(".*/home/sitemap.*.html.*", "sitemap/html", url) ||
            gsub(".*sitemap.*.xml.*", "sitemap/xml", url) ||
            gsub(".*embed/video/.*", "embedded video", url) ||
            gsub(".*videoarchive.*", "video archive", url) ||
            gsub(".*c.*/item.cms.*", "cms items", url) ||
            gsub(".*/.*.html.*", "topic pages", url))
        {}

        count[url] += 1
        size[url] += $3
        times[url] += $2
        total_time += $2
    }
    END {
        for (i in times) {
            printf "%.1f%% %d %.2f %d %s\n", times[i]/total_time*100, count[i], (times[i]/count[i]), size[i], i
        }
    }' | sort -n
fi


[ "$deletecurllog" = "1" ] && rm -f $deletecurllog
