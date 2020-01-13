@echo off

rem -----------------------------------------------------------------------------
rem Start Script for the dotCMS Server
rem -----------------------------------------------------------------------------

@if not "%ECHO%" == ""  echo %ECHO%
@if "%OS%" == "Windows_NT" setlocal

if "%OS%" == "Windows_NT" (
  set "CURRENT_DIR=%~dp0%"
) else (
  set CURRENT_DIR=.\
)

rem Read an optional configuration file.
if "x%RUN_CONF%" == "x" (
   set "RUN_CONF=%CURRENT_DIR%build.conf.bat"
)
if exist "%RUN_CONF%" (
   echo Calling "%RUN_CONF%"
   call "%RUN_CONF%" %*
) else (
    echo Config file not found "%RUN_CONF%"
)

rem Guess DOTCMS_HOME if not defined
if not "%DOTCMS_HOME%" == "" goto gotDotcmsHome
set "DOTCMS_HOME=%CURRENT_DIR%..\%HOME_FOLDER%"
if exist "%DOTCMS_HOME%" goto okDotcmsHome
set "DOTCMS_HOME=%CURRENT_DIR%\%HOME_FOLDER%"
cd "%CURRENT_DIR%"
:gotDotcmsHome
if exist "%DOTCMS_HOME%" goto okDotcmsHome
echo The DOTCMS_HOME environment variable is not defined correctly: %DOTCMS_HOME%
echo This environment variable is needed to run this program
goto end
:okDotcmsHome

rem Guess CATALINA_HOME if not defined
if not "%CATALINA_HOME%" == "" goto gotHome
set "CATALINA_HOME=%CURRENT_DIR%.."
if exist "%CATALINA_HOME%\bin\catalina.bat" goto okHome
set "CATALINA_HOME=%CURRENT_DIR%"
cd "%CURRENT_DIR%"
:gotHome
if exist "%CATALINA_HOME%\bin\catalina.bat" goto okHome
echo The CATALINA_HOME environment variable is not defined correctly: %CATALINA_HOME%
echo This environment variable is needed to run this program
goto end
:okHome

rem Java VM configuration options

if not "%JAVA_OPTS%" == "" goto noDefaultJavaOpts
set JAVA_OPTS=-Djava.awt.headless=true -Xverify:none -Dfile.encoding=UTF8 -Dsun.jnu.encoding=UTF-8 -server -Xmx1G -Djava.endorsed.dirs=%DOTCMS_HOME%/WEB-INF/endorsed_libs  -XX:MaxPermSize=256m -XX:+DisableExplicitGC -XX:+UseConcMarkSweepGC -javaagent:%DOTCMS_HOME%/WEB-INF/lib/dot.jamm-0.2.5_2.jar
rem Uncomment the next line if you want to enable JMX
rem set JAVA_OPTS=%JAVA_OPTS% -Dcom.sun.management.jmxremote.port=7788 -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.authenticate=false -Djava.endorsed.dirs=$DOTCMS_HOME/WEB-INF/endorsed_libs
:noDefaultJavaOpts

if not ""%1"" == ""debug"" goto noDebug
set JAVA_OPTS=-Xdebug -Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=8000 %JAVA_OPTS%
:noDebug

set "EXECUTABLE=%CATALINA_HOME%\bin\catalina.bat"

rem Check that target executable exists

if exist "%EXECUTABLE%" goto okExec
echo Cannot find "%EXECUTABLE%"
echo This file is needed to run this program
goto end
:okExec


rem Get remaining unshifted command line arguments and save them in the
set CMD_LINE_ARGS=
:setArgs
if ""%1""=="""" goto doneSetArgs
set CMD_LINE_ARGS=%CMD_LINE_ARGS% %1
shift
goto setArgs
:doneSetArgs

setlocal enabledelayedexpansion
set SKIP_OPEN_DISTRO=false

rem check for open-distro arguments 
for %%x in (%*) do (
	echo %%~x
	if "%%x"=="--skipOpendistro" (
		echo skipping open distro
		set SKIP_OPEN_DISTRO=true
	)
)

rem Code for bringing Open Distro up if needed/specified
set ELASTICSEARCH_HOST=https://localhost
set ELASTICSEARCH_PORT=9200
set LAUNCH_OPEN_DISTRO=true
set OPEN_DISTRO_ALREADY_RUNNING=false
set OPEN_DISTRO_USER=admin
set OPEN_DISTRO_PASSWORD=admin
set OPEN_DISTRO_FAILED_DOCKER_MESSAGE=Unable to start the Elasticsearch docker container, please make sure you either start Elasticseach before you start dotCMS or have docker available so dotCMS can start the Elasticseach docker container
set health_check=stopped


if "!SKIP_OPEN_DISTRO!"=="false" (

	rem let's check if there's an Open Distro running
	for /f %%i in ('curl "%ELASTICSEARCH_HOST%:%ELASTICSEARCH_PORT%/_cat/health?h=status" -u %OPEN_DISTRO_USER%:%OPEN_DISTRO_PASSWORD% --insecure') do set health_check=%%i

	if "%health_check%"=="yellow" (
	  set OPEN_DISTRO_ALREADY_RUNNING=true
	)

	if "%health_check%"=="green" (
	  set OPEN_DISTRO_ALREADY_RUNNING=true
	)

	echo Is Open Distro already running? = %OPEN_DISTRO_ALREADY_RUNNING%

	if "%OPEN_DISTRO_ALREADY_RUNNING%"=="false" (
		
		echo Launching Open Distro...

		rem Launching Open Distro...
		docker run -d --name dot_opendistro -e PROVIDER_ELASTICSEARCH_HEAP_SIZE=1500m -e PROVIDER_ELASTICSEARCH_DNSNAMES=elasticsearch -e ES_ADMIN_PASSWORD=%OPEN_DISTRO_PASSWORD% -e discovery.type=single-node -p 9200:9200 gcr.io/cicd-246518/es-open-distro:1.2.0

		IF NOT "!ERRORLEVEL!"=="0" (
			echo.
			echo %OPEN_DISTRO_FAILED_DOCKER_MESSAGE%
			echo.
			GOTO OpenDistroEnd
		)

		rem let's get the health of Open Distro after starting it up
		:LoopStart
		for /f %%i in ('curl "%ELASTICSEARCH_HOST%:%ELASTICSEARCH_PORT%/_cat/health?h=status" -u %OPEN_DISTRO_USER%:%OPEN_DISTRO_PASSWORD% --insecure') do set health_check=%%i
		IF "!health_check!"=="yellow" GOTO LoopEnd
		IF "!health_check!"=="green" GOTO LoopEnd
		echo Elastic Search is unavailable - waiting
		TIMEOUT 15
		GOTO LoopStart
		:LoopEnd
		rem Open Distro ready! 	
	)

)
:OpenDistroEnd

rem Executing Tomcat
cd %CATALINA_HOME%\bin
call "%EXECUTABLE%" start %CMD_LINE_ARGS%
cd "%CURRENT_DIR%"

:end