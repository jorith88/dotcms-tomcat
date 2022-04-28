#!/bin/sh

# -----------------------------------------------------------------------------
# Start Script for the dotCMS Server
# -----------------------------------------------------------------------------

# Better OS/400 detection
os400=false
case "`uname`" in
OS400*) os400=true;;
esac

# resolve links - $0 may be a softlink
PRG="$0"

while [ -h "$PRG" ] ; do
  ls=`ls -ld "$PRG"`
  link=`expr "$ls" : '.*-> \(.*\)$'`
  if expr "$link" : '/.*' > /dev/null; then
    PRG="$link"
  else
    PRG=`dirname "$PRG"`/"$link"
  fi
done

PRGDIR=`dirname "$PRG"`
EXECUTABLE=catalina.sh

# Read an optional running configuration file
if [ "x$RUN_CONF" = "x" ]; then
    RUN_CONF="$PRGDIR/build.conf"
fi
if [ -r "$RUN_CONF" ]; then
    . "$RUN_CONF" 2>/dev/null
fi

DISTRIBUTION_HOME=`cd "$PRGDIR/.." ; pwd`
TOMCAT_HOME=`cd "$PRGDIR/.." ; pwd`
DOTCMS_HOME=`cd "$PRGDIR/../$HOME_FOLDER" ; pwd`

## Script CONFIGURATION Options


# JAVA_OPTS: Below are the recommended minimum settings for the Java VM.
# These may (and should) be customized to suit your needs. Please check with 
# Sun Microsystems and the Apache Tomcat websites for the latest information 
# http://java.sun.com
# http://tomcat.apache.org

#Uncomment the following line to enable the JMX interface
#Please be aware that this configuration doesn't provide any authentication, so it could pose a security risk.
#More info at http://java.sun.com/j2se/1.5.0/docs/guide/management/agent.html

#JAVA_OPTS="$JAVA_OPTS -Dcom.sun.management.jmxremote.port=7788 -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.authenticate=false "

##add agentpath to be enable ability to profile application
#JAVA_OPTS="-agentpath:/Applications/YourKit_Java_Profiler_9.0.5.app/bin/mac/libyjpagent.jnilib $JAVA_OPTS -Djava.awt.headless=true -Xverify:none -Dfile.encoding=UTF8 -server -Xms1024M -Xmx1024M -XX:PermSize=128m "

#JAVA_OPTS="$JAVA_OPTS -Xdebug -Xrunjdwp:transport=dt_socket,address=8000,server=y,suspend=n"

JAVA_VERSION="$(java -version 2>&1 | grep -i version | cut -d'"' -f2 | cut -d'.' -f1-2)"

JAVA_OPTS="$JAVA_OPTS -Djava.awt.headless=true -Xverify:none -Dfile.encoding=UTF8 -server -Xmx1G -XX:MaxPermSize=256m -XX:+DisableExplicitGC -XX:+UseConcMarkSweepGC -Dsun.jnu.encoding=UTF-8"

if [ "$1" = "debug" ] ; then

    DEBUG_PORT="8000"
    if [ ! -x $2 ] ; then
        re='^[0-9]+$'
        if ! [[ $2 =~ $re ]] ; then
           echo "Using default debug port [$DEBUG_PORT]"
        else
            DEBUG_PORT="$2"
            echo "Using debug port [$DEBUG_PORT]"
        fi
    else
        echo "Using default debug port [$DEBUG_PORT]"
    fi

    #debug
    JAVA_OPTS="-Xdebug -Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=$DEBUG_PORT $JAVA_OPTS"
fi

if [ "$1" = "profile" ] || [ "$2" = "profile" ] || [ "$3" = "profile" ] ; then
    JAVA_OPTS="$JAVA_OPTS -javaagent:$DOTCMS_HOME/WEB-INF/profiler/profiler.jar"
fi

## END Script CONFIGURATION Options

# Check that target executable exists
if $os400; then
  # -x will Only work on the os400 if the files are: 
  # 1. owned by the user
  # 2. owned by the PRIMARY group of the user
  # this will not work if the user belongs in secondary groups
  eval
else
  if [ ! -x "$TOMCAT_HOME"/bin/"$EXECUTABLE" ]; then
    echo "Cannot find $TOMCAT_HOME/bin/$EXECUTABLE"
    echo "This file is needed to run this program"
    exit 1
  fi
fi 

# Sets DOTSERVER if not specified and changes existing JAVA_OPTS to use it 
if [ -z "$DOTSERVER" ]; then
        DOTSERVER=`echo "$DISTRIBUTION_HOME" | sed -e 's/\(.*\)\///'`
fi
export JAVA_OPTS="$JAVA_OPTS -Ddotserver=$DOTSERVER"

# Sets PID to DOTSERVER if not already specified
if [ -z "$CATALINA_PID" ]; then
        export CATALINA_PID="/tmp/$DOTSERVER.pid"
        if [ "$1" = "start" ] ; then
                if [ -e "$CATALINA_PID" ]; then
                        echo
                        echo "Pid file $CATALINA_PID exists! Are you 
sure dotCMS is not running?"
                        echo
                        echo "If dotCMS is not running, please remove 
the Pid file or change the"
                        echo "setting in bin/catalina.sh before starting 
your dotCMS application."
                        echo
                        exit 1
                fi
        fi
fi

## check for open-distro arguments 
SKIP_OPEN_DISTRO=false

for o in "$@"; do
  if [ $o = "--skipOpendistro" ]; then
    SKIP_OPEN_DISTRO=true
    echo "Not launching Open Distro"
    break
  fi
done

if [ "$SKIP_OPEN_DISTRO" = false ] ; then

    # Code for bringing Open Distro up if needed/specified
    OPEN_DISTRO_HOST=https://127.0.0.1
    OPEN_DISTRO_PORT=9200
    OPEN_DISTRO_ALREADY_RUNNING=false
    OPEN_DISTRO_USER=admin
    OPEN_DISTRO_PASSWORD=admin
    OPEN_DISTRO_FAILED_DOCKER_MESSAGE="Unable to start the Elasticsearch docker container, please make sure you either start Elasticseach before you start dotCMS or have docker available so dotCMS can start the Elasticseach docker container"

    echo "Launching Open Distro..."

    health_check="$(curl -s "$OPEN_DISTRO_HOST:$OPEN_DISTRO_PORT/_cat/health?h=status" -u $OPEN_DISTRO_USER:$OPEN_DISTRO_PASSWORD --insecure)"
    if [ "$health_check" = 'yellow' ] || [ "$health_check" = 'green' ]; then
      OPEN_DISTRO_ALREADY_RUNNING=true;
    fi

    echo "Is Open Distro already running? = $OPEN_DISTRO_ALREADY_RUNNING"

    if [ "$OPEN_DISTRO_ALREADY_RUNNING" = false ] ; then
        ## Bring up Open Distro
        docker start dot_opendistro || docker run -d --name dot_opendistro --mount source=esdata,target=/data -e PROVIDER_ELASTICSEARCH_HEAP_SIZE=1500m -e PROVIDER_ELASTICSEARCH_DNSNAMES=elasticsearch -e ES_ADMIN_PASSWORD=$OPEN_DISTRO_PASSWORD -e discovery.type=single-node -p $OPEN_DISTRO_PORT:9200 dotcms/es-open-distro:1.3.0
         ## Let's check the exit code of docker run
        docker_exit_code="$(echo $?)"
        echo "$docker_exit_code"
        if [ "$docker_exit_code" -gt 0 ] ; then 
            echo 
            echo "\033[1m$OPEN_DISTRO_FAILED_DOCKER_MESSAGE\033[0m"
            echo
        fi

        # Wait for heathy ElasticSearch
        # next wait for ES status to turn to Green or Yellow
        health_check="$(curl -s "$OPEN_DISTRO_HOST:$OPEN_DISTRO_PORT/_cat/health?h=status" -u $OPEN_DISTRO_USER:$OPEN_DISTRO_PASSWORD --insecure)"

        until ([ "$health_check" = 'yellow' ] || [ "$health_check" = 'green' ]); do
            health_check="$(curl -s "$OPEN_DISTRO_HOST:$OPEN_DISTRO_PORT/_cat/health?h=status" -u $OPEN_DISTRO_USER:$OPEN_DISTRO_PASSWORD --insecure)"
            >&2 echo "Open Distro is not yet ready. This is normal - Please wait"
            sleep 15
        done

        ## Open Distro ready
        echo "Open Distro ready!"
    fi

fi

echo "Using DOTCMS_HOME = $DOTCMS_HOME"
echo "Using DOTSERVER = $DOTSERVER"
echo "Using CATALINA_PID = $CATALINA_PID"
echo "Using JAVA_OPTS = $JAVA_OPTS"
cd $DOTCMS_HOME

if [ -z $1 ]; then
    cmd="start"
else
    cmd="$1"
    shift
fi

if [ $cmd = "-usage" -o $cmd = "usage" ]; then
  echo "Usage: startup.sh ( commands ... )"
  echo "commands:"
  echo "  usage        Prints out this info"
  echo "  No Arguments Start dotCMS"
  echo "  run          Start dotCMS redirecting the output to the console"
  exit 1;
elif [ $cmd = "run" ]; then
	exec "$TOMCAT_HOME"/bin/"$EXECUTABLE" run "$@"
else
    exec "$TOMCAT_HOME"/bin/"$EXECUTABLE" start "$@"
fi
