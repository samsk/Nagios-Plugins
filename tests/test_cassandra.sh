#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-05-25 01:38:24 +0100 (Mon, 25 May 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  http://www.linkedin.com/in/harisekhon
#

set -eu
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

echo "
# ============================================================================ #
#                               C a s s a n d r a
# ============================================================================ #
"

export DOCKER_IMAGE="harisekhon/cassandra-dev"

export CASSANDRA_TEST_VERSIONS="${CASSANDRA_TEST_VERSIONS:-22}"

export CASSANDRA_HOST="${CASSANDRA_HOST:-localhost}"

export DOCKER_CONTAINER="nagios-plugins-cassandra"
export MNTDIR="/nagios-plugins-tmp"

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Cassandra checks!!!'
    exit 0
fi

docker_run_test(){
    docker exec -ti "$DOCKER_CONTAINER" $MNTDIR/$@
}

test_cassandra(){
    local version="$1"
    echo "Setting up test Cassandra $version container"
    if ! docker ps | tee /dev/stderr | grep -q "[[:space:]]$DOCKER_CONTAINER$"; then
        docker rm -f "$DOCKER_CONTAINER" &>/dev/null || :
        echo "Starting Docker Cassandra test container"
        docker run -d --name "$DOCKER_CONTAINER" -v "$srcdir/..":"$MNTDIR" -p 7199:7199 -p 9042:9042 "$DOCKER_IMAGE":"$version"
        echo "sleeping for 10 secs to allow Cassandra time to start up and gossip protocol to settle"
        sleep 10
    else
        echo "Docker Cassandra test container already running"
    fi

    docker exec -ti "$DOCKER_CONTAINER" nodetool status
    hr
    # TODO: output parsing needs updating :-/
    #docker_run_test check_cassandra_balance.pl -v
    hr
    docker_run_test check_cassandra_heap.pl -w 70 -c 90 -v
    hr
    #docker_run_test check_cassandra_netstats.pl -v
    hr
    #docker_run_test check_cassandra_tpstats.pl -v
    hr

    echo
    echo -n "Deleting container "
    docker rm -f "$DOCKER_CONTAINER"
    sleep 1
    echo
    hr
    echo; echo
}

for version in $CASSANDRA_TEST_VERSIONS; do
    test_cassandra $version
done

# ============================================================================ #
#                                     E N D
# ============================================================================ #
exit 0
# ============================================================================ #
# Cassandra build in Travis is quite broken, appears due to an incorrect upgrade in the VM image

# workarounds for nodetool "You must set the CASSANDRA_CONF and CLASSPATH vars"
# even bare 'nodetool status' has broken environment in Travis, nothing to do with say Taint security
# Cassandra service on Travis is really broken, some hacks to make it work
if [ -n "${TRAVIS:-}" ]; then
#if false; then
    export CASSANDRA_HOME="${CASSANDRA_HOME:-/usr/local/cassandra}"
    # these were only necessary on the debug VM but not in the actual Travis env for some reason
    #sudo sed -ibak 's/jamm-0.2.5.jar/jamm-0.2.8.jar/' $CASSANDRA_HOME/bin/cassandra.in.sh $CASSANDRA_HOME/conf/cassandra-env.sh
    #sudo sed -ribak 's/^(multithreaded_compaction|memtable_flush_queue_size|preheat_kernel_page_cache|compaction_preheat_key_cache|in_memory_compaction_limit_in_mb):.*//' $CASSANDRA_HOME/conf/cassandra.yaml
    # stop printing xss = $JAVA_OPTS which will break nodetool parsing
    sudo sed -ibak2 's/^echo "xss = .*//' $CASSANDRA_HOME/conf/cassandra-env.sh
    sudo service cassandra status || sudo service cassandra start
    hr
fi

# /usr/local/bin/nodetool symlink doesn't source cassandra.in.sh properly
nodetool status || :
/usr/local/cassandra/bin/nodetool status || :
hr
# Cassandra checks are broken due to broken nodetool environment
# must set full path to /usr/local/cassandra/bin/nodetool to bypass /usr/local/bin/nodetool symlink which doesn't source cassandra.in.sh properly and breaks with "You must set the CASSANDRA_CONF and CLASSPATH vars@
$perl -T $I_lib ./check_cassandra_balance.pl  -n /usr/local/cassandra/bin/nodetool -v
hr
$perl -T $I_lib ./check_cassandra_heap.pl     -n /usr/local/cassandra/bin/nodetool -w 70 -c 90 -v
hr
$perl -T $I_lib ./check_cassandra_netstats.pl -n /usr/local/cassandra/bin/nodetool -v
hr
$perl -T $I_lib ./check_cassandra_tpstats.pl  -n /usr/local/cassandra/bin/nodetool -v

echo; echo
