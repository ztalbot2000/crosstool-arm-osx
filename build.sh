#!/bin/bash

#
#  Author: John Talbot
#
#  Installs a gcc cross compiler for compiling code for raspberry pi on OSX.
#  It also can build Raspbian as well.  The goal is to build a fully patched
#  Raspbian RT-Linux image with the LinuxCnC tools and bCnC too.
#
#  Check the README.md for the latest status of this goal.
#
#  This script is based on several scripts and forum posts I've found around
#  the web, the most significant being: 
#
#  http://okertanov.github.com/2012/12/24/osx-crosstool-ng/
#  http://crosstool-ng.org/hg/crosstool-ng/file/715b711da3ab/docs/MacOS-X.txt
#  http://gnuarmeclipse.livius.net/wiki/Toolchain_installation_on_OS_X
#  http://elinux.org/RPi_Kernel_Compilation
#
#
#  And serveral articles that mostly dealt with the MentorGraphics tool, which I
#  I abandoned in favor of crosstool-ng
#
#  The process:
#
#  (1) Create a case sensitive volume using hdiutil and mount it to /Volumes/$Volume[Base]
#      where brew and crosstool-ng will be placed so as not to interfere
#      with any existing installations
#
#  (2) Create another case sensitive volume where the cross compilere created with
#      crosstool-ng will be built.
#
#  (3) Download, patch and build Raspbian.
#
#  (4) Blast an image to an SD card that includes Raspbian, LinuxCnC and other tools.
#
#     Start by executing bash .build.sh and follow along.  This tool does
#     try to continue where it left off each time.
#
#
#  License:
#      Please feel free to use this in any way you see fit.
#
set -e

# Exit immediately for unbound variables.
set -u

# The process seems to open a lot of files at once. The default is 256. Bump it to 2048.
# Without this you will get an error: no rule to make IBM1388.so
ulimit -n 2048

# If latest is 'y', then git will be used to download crosstool-ng LATEST
# I believe there is a problem with 1.23.0 so for now, this is the default.
# Ticket #931 has been submitted to address this. It deals with CT_Mirror being undefined
downloadCrosstoolLatestOpt=y

#
# Config. Update below here to suite your specific needs, but all options can be
# specified from command line arguments. See ./build.sh -help.

# The crosstool image will be $ImageName.sparseimage
# The volume will grow as required because of the SPARSE type
# You can change this with -i <ImageName> but it will always
# be <ImageName>.sparseimage
ImageName="CrossToolNG"

# I got tired of rebuilding brew and ct-ng. They now go here
ImageNameBase="${ImageName}Base"

#
# This is where your §{CrossToolNGConfigFile}.config file is if you have one.
# It would be copied to $CT_TOP_DIR/.config prior to ct-ng menuconfig
# It can be overriden with -f <ConfigFile>. Please do this instead of
# changing it here.
CrossToolNGConfigFile="armv8-rpi3-linux-gnueabihf.config"
CrossToolNGConfigFilePath="${PWD}"

# This will be the name of the toolchain created by crosstools-ng
# It is placed in $CT_TOP_DIR
# The real name is based upon the options you have set in the CrossToolNG
# config file. You will probably need to change this.  You now can do so with
# the option -T <ToolchainName>. The default being armv8-rpi3-linux-gnueabihf
ToolchainNameOpt='n'
ToolchainName='armv8-rpi3-linux-gnueabihf'

#
# Anything below here cannot be changed without bad effects
#

# This will be mounted as /Volumes/CrossToolNG
# It can be overriden with -V <Volume>.  Do this instead as 'CrossToolNG' is
# a key word in the .config file with this tool that will automatically get
# changed with the -V <Volume> option
Volume='CrossToolNG'
VolumeBase="${Volume}Base"

# Downloading the sources all the time is painful, especially when one site is down
# There is no option for this because the ct-ng config file must also be
# changed
TarBallSourcesPath="/Volumes/${VolumeBase}/sources"

# The compiler will be placed in /Volumes/<Volume>/x-tools
# It can be overriden with -O <OutputDir>.  Do this instead as 'x-tools' is
# a key word in the .config file with this tool that will automatically get
# changed with the -O <OutputDir> option
OutputDir='x-tools'




# Where brew will be placed. An existing brew cannot be used because of
# interferences with macports or fink.
# I spent some time exploring the removal of brew. The thought being
# there was to much overhead.  This turned out to be false.  Brew has
# spent a lifetime determining the correct compile options for all
# of its casks.  The result was almost another brew written from scratch
# that did not behave as good as brew.
# 
BrewHome="/Volumes/${VolumeBase}/brew"
export HOMEBREW_CACHE=${TarBallSourcesPath}
export HOMEBREW_LOG_PATH=${BrewHome}/brew_logs 

# This is required so brew can be installed elsewhere
export BREW_PREFIX=$BrewHome
export PKG_CONFIG_PATH=$BREW_PREFIX

# This is the crosstools-ng version used by curl to fetch relased version
# of crosstools-ng. I don't know if it works with previous versions and
#  who knows about future ones.
CrossToolVersion="crosstool-ng-1.23.0"

# Changing this affects CT_TOP_DIR which also must be reflected in your
# crosstool-ng .config file
CrossToolSourceDir="crosstool-ng-src"

# See note just above why this is duplicated
CT_TOP_DIR="/Volumes/CrossToolNG"
CT_TOP_DIR="/Volumes/${Volume}"



# Where Raspbian boot files will be placed
# MSDOS FAT16 volume names are limited to 8 characters
BootDir="RBoot"
BootFS="/Volumes/${BootDir}"

# Where Raspbian root files will be placed
RootDir="RRoot"
RootFS="/Volumes/${RootDir}"


# Options to be toggled from command line
# see -help
BuildRaspbianOpt='n'
CleanRaspbianOpt='n'
BuildToolchainOpt='n'
InstallKernelOpt='n'

# Fun colour stuff
KNRM="\x1B[0m"
KRED="\x1B[31m"
KGRN="\x1B[32m"
KYEL="\x1B[33m"
KBLU="\x1B[34m"
KMAG="\x1B[35m"
KCYN="\x1B[36m"
KWHT="\x1B[37m"


# a global return code value for those who return one
rc='0'


# Where to put Raspbian Sourcefrom /Volumes/<Volume>
RaspbianSrcDir="Raspbian-src"

function showHelp()
{
cat <<'HELP_EOF'
   This shell script is a front end to crosstool-ng to help build a cross compiler on your Mac.  It downloads all the necessary files to build the cross compiler.  It only assumes you have Xcode command line tools installed.

   Options:
     -I <ImageName>  - Instead of CrosstoolNG.sparseImage use <ImageName>.sparseImageI
     -V <Volume>     - Instead of /Volumes/CrosstoolNG/ and
                                  /Volumes/CrosstoolNGBase/
                               use
                                  /Volumes/<Volume> and
                                  /Volumes/<Volume>Base
                           Note: To do this the .config file is changed automatically
                                 from CrosstoolNG to <Volume>

     -O <OutputDir>  - Instead of /Volumes/<Volume>/x-tools
                               use
                           /Volumes/<Volume>/<OutputDir>
                           Note: To do this the .config file is changed automatically
                                 from x-tools  to <OutputDir>

     -c Brew         - Remove all installed Brew tools.
     -c ct-ng        - Run make clean in crosstool-ng path
     -c realClean    - Unmounts the image and removes it. This destroys EVERYTHING!
     -c raspbian     - run make clean in the RaspbianSrcDir.
     -f <configFile> - The name and path of the config file to use.
                       Default is armv8-rpi3-linux-gnueabihf.config
     -b              - Build the cross compiler AFTER building the necessary tools
                       and you have defined the crosstool-ng .config file.
     -b <last_step+>    * If last_step+ is specified ct-ng is executed with LAST_SUCCESSFUL_STETP_NAME+ 
                        This is accomplished when CT_DEBUG=y and CT_SAVE_STEPS=y
     -b list-steps      * This could also be list-steps to show steps available. 
     -b raspbian>    - Download and build Raspbian.
     -t              - After the build, run a Hello World test on it.
     -T <Toolchain>  - The ToolchainName created.
                       The default used is: armv8-rpi3-linux-gnueabihf
                       The actual result is based on what is in your
                           -f <configFile>
                       The product of which would be: armv8-rpi3-linux-gnueabihf-gcc ...
     -P              - Just Print the PATH variableH
     -h              - This menu.
     -help
     "none"          - Go for it all if no options given. it will always try to 
                       continue where it left off

HELP_EOF
}

function removeFileWithCheck()
{
   printf "Removing file $1 ${KNRM} ... "
   if [ -f "$1" ]; then
      rm "$1"
      printf "  ${KGRN} Done ${KNRM}\n"
   else
      printf "  ${KGRN} Not found ${KNRM}\n"
   fi
}
function removePathWithCheck()
{
   printf "Removing directory $1 ${KNRM} ... "
   if [ -d "$1" ]; then
      rm -rf "$1"
      printf "  ${KGRN} Done ${KNRM}\n"
   else
      printf "  ${KGRN} Not found ${KNRM}\n"
   fi
}

function waitForPid()
{
   pid=$1
   spindleCount=0
   spindleArray=("|" "/" "-" "\\")
   STARTTIME=$(date +%s)

   while ps -p $pid >/dev/null; do
      sleep 1.0

      SECONDS=$(($(date +%s) - $STARTTIME))
      let S=${SECONDS}%60
      let MM=${SECONDS}/60 # Total number of minutes
      let M=${MM}%60
      let H=${MM}/60
      printf "\r${KNRM}[ "
      [ "$H" -gt "0" ] && printf "%02d:" $H
      printf "%02d:%02d ] ${KGRN}%s${KNRM}" $M $S ${spindleArray[$spindleCount]}
      spindleCount=$((spindleCount + 1))
      if [[ $spindleCount -eq ${#spindleArray[*]} ]]; then
         spindleCount=0
      fi
   done
   printf "\n${KNRM}"

   # Get the true return code of the process
   wait $pid

   # Set our global return code of the process
   rc=$?
}


function cleanBrew()
{
   if [ -f "${BrewHome}/.flagToDeleteBrewLater" ]; then
   printf "${KBLU}Cleaning our brew tools ${KNRM}\n"
      printf "Checking for ${KNRM} ${BrewHome} ... "
      if [ -d "${BrewHome}" ]; then
         printf "${KGRN} found ${KNRM}\n"
      else
         printf "${KRED} not found ${KNRM}\n"
         exit -1
      fi

      removePathWithCheck  "${BrewHome}"
   fi
}

function ct-ngMakeClean()
{
   printf "${KBLU}Cleaning ct-ng${KNRM} ...\n"
   ctDir="/Volumes/${VolumeBase}/${CrossToolSourceDir}"
   printf "Checking for ${KNRM}${ctDir} ... "
   if [ -d "${ctDir}" ]; then
      printf "${KGRN} found ${KNRM}\n"
   else
      printf "${KRED} not found ${KNRM}\n"
      exit -1
   fi
   cd "${ctDir}"
   make clean 
   printf "${KGRN} done ${KNRM}\n"
}
function raspbianClean()
{
   printf "${KBLU}Cleaning raspbian (make mrproper) ${KNRM}\n"

   # Remove our elf.h
   cleanupElfHeaderForOSX

   printf "${KBLU}Checking for ${KNRM}${CT_TOP_DIR}/${RaspbianSrcDir} ... "
   if [ -d "${CT_TOP_DIR}/${RaspbianSrcDir}" ]; then
      printf "${KGRN} found ${KNRM}\n"
   else
      printf "${KRED} not found ${KNRM}\n"
      exit -1
   fi
   printf "${KBLU}Checking for ${KNRM}${CT_TOP_DIR}/${RaspbianSrcDir}/linux ... "
   if [ -d "${CT_TOP_DIR}/${RaspbianSrcDir}/linux" ]; then
      printf "${KGRN} found ${KNRM}\n"
   else
      printf "${KRED} not found ${KNRM}\n"
      exit -1
   fi
   cd ${CT_TOP_DIR}/$RaspbianSrcDir/linux
   make mrproper
}
function realClean()
{
   # We need to clean brew as it purges brew's cache
   cleanBrew

   # Remove our elf.h
   cleanupElfHeaderForOSX

   # Eject the disk instead of unmounting it or you will have
   # a lot of disks hanging around.  I had 47, Doh!
   if [ -d  "/Volumes/${VolumeBase}" ]; then 
      printf "${KBLU}Ejecting  /Volumes/${VolumeBase}${KNRM}\n"
      hdiutil eject /Volumes/${VolumeBase}
   fi

   # Since everything is on the image, just remove it does it all
   printf "${KBLU}Removing ${ImageName}.sparseimage${KNRM}\n"
   removeFileWithCheck "${ImageName}.sparseimage"
   printf "${KBLU}Removing ${ImageNameBase}.sparseimage${KNRM}\n"
   removeFileWithCheck "${ImageNameBase}.sparseimage"
}

# For smaller more permanent stuff
function createCaseSensitiveVolumeBase()
{
    VolumeDir="/Volumes/${VolumeBase}"
    printf "${KBLU}Creating 4G volume for tools mounted as ${VolumeDir}${KNRM} ...\n"
    if [  -d "${VolumeDir}" ]; then
       printf "${KYEL}WARNING${KNRM}: Volume already exists: ${VolumeDir}${KNRM}\n"
      
       # Give a couple of seconds for the user to react
       sleep 3

       return;
    fi

   if [ -f "${ImageNameBase}.sparseimage" ]; then
      printf "${KRED}WARNING:${KNRM}\n"
      printf "         File already exists: ${ImageNameBase}.sparseimage ${KNRM}\n"
      printf "         This file will be mounted as ${VolumeBase} ${KNRM}\n"
      
      # Give a couple of seconds for the user to react
      sleep 3

   else
      hdiutil create ${ImageNameBase}        \
                      -volname ${VolumeBase} \
                      -type SPARSE           \
                      -size 4g               \
                      -fs HFSX               \
                      -quiet                 \
                      -puppetstrings
   fi

   hdiutil mount "${ImageNameBase}.sparseimage"
}

function createTarBallSourcesDir()
{
    printf "${KBLU}Checking for saved tarballs directory ${KNRM}${TarBallSourcesPath} ${KNRM} ..."
    if [ -d "${TarBallSourcesPath}" ]; then
       printf "${KGRN} found ${KNRM}\n"
    else
       printf "${KYEL} not found ${KNRM}\n"
       printf "${KNRM}Creating ${KNRM}${TarBallSourcesPath}${KNRM} ... "
       mkdir "${TarBallSourcesPath}"
       printf "${KGRN} done ${KNRM}\n"
    fi

   # Not used ???
   # printf "${KBLU}Checking for ${KNRM}${CT_TOP_DIR}/${ToolchainName} ${KNRM} ..."
   # if [ ! -d "${CT_TOP_DIR}/${ToolchainName}" ]; then
   #   printf "${KGRN} found ${KNRM}\n"
   # else
   #   printf "${KYEL} not found ${KNRM}\n"
   #   printf "${KNRM}Creating ${KNRM}${TarBallSourcesPath}${KNRM} ... "
   #   mkdir ${CT_TOP_DIR}/$ToolchainName
   #   printf "${KGRN} done ${KNRM}\n"
   # fi
}

# This is where the cross compiler and Raspbian will go
function createCaseSensitiveVolume()
{
    VolumeDir="${CT_TOP_DIR}"
    printf "${KBLU}Creating volume mounted as ${KNRM}${VolumeDir} ...\n"
    if [  -d "${VolumeDir}" ]; then
       printf "${KYEL}WARNING${KNRM}: Volume already exists: ${VolumeDir}${KNRM}\n"
      
       # Give a couple of seconds for the user to react
       sleep 3

       return;
    fi

   if [ -f "${ImageName}.sparseimage" ]; then
      printf "${KRED}WARNING:${KNRM}\n"
      printf "         File already exists: ${ImageName}.sparseimage ${KNRM}\n"
      printf "         This file will be mounted as ${Volume} ${KNRM}\n"
      
      # Give a couple of seconds for the user to react
      sleep 3

   else
      hdiutil create ${ImageName}           \
                      -volname ${Volume}    \
                      -type SPARSE          \
                      -size 32              \
                      -fs HFSX              \
                      -quiet                \
                      -puppetstrings
   fi

   hdiutil mount "${ImageName}.sparseimage"
}

#
# If $BrewHome does not alread contain HomeBrew, download and install it. 
# Install the required HomeBrew packages.
#
# Binutils is for objcopy, objdump, ranlib, readelf
# sed, gawk libtool bash, grep are direct requirements
# xz is reauired when configuring crosstool-ng
# help2man is reauired when configuring crosstool-ng
# wget  is reauired when configuring crosstool-ng
# wget  requires all kinds of stuff that is auto downloaded by brew. Sorry
# automake is required to fix a compile issue with gettext
# coreutils is for sha512sum
# sha2 is for sha512
# bison on osx was too old (2.3) and gcc compiler did not like it
# findutils is for xargs, needed by make modules in Raspbian
#
# for Raspbian tools - libelf ncurses
# for xconfig - QT   (takes hours). That would be up to you.
BrewTools="coreutils findutils libtool grep ncurses gettext xz gnu-sed gawk binutils help2man autoconf automake bison bash wget sha2"

function buildBrewTools()
{
   printf "${KBLU}Checking for HomeBrew tools ${KNRM} ...\n"
   if [ ! -d "$BrewHome" ]; then
      printf "Installing HomeBrew tools ${KNRM} ...\n"
      mkdir "$BrewHome"
      cd "$BrewHome"
      curl -Lsf http://github.com/mxcl/homebrew/tarball/master | tar xz --strip 1 -C${BrewHome}

      touch "${BrewHome}/.flagToDeleteBrewLater"
   else
      printf "   - Using existing Brew installation in ${BrewHome}${KNRM}\n"
   fi

   printf "${KBLU}Checking for Brew log path  ${KNRM} ..."
   if [ ! -d "$HOMEBREW_LOG_PATH" ]; then
      printf "${KYEL} not found ${KNRM}\n"
      printf "${KNRM}Creating brew logs directory: ${HOMEBREW_LOG_PATH} ... "
      mkdir "$HOMEBREW_LOG_PATH"
      printf "${KGRN} done ${KNRM}\n"

   else
      printf "${KGRN} found ${KNRM}\n"
   fi

   export PATH=$BrewHome/bin:$BrewHome/opt/gettext/bin:$BrewHome/opt/bison/bin:$BrewHome/opt/libtool/bin:$BrewHome/opt/gcc/bin:/Volumes/${VolumeBase}/ctng/bin:$PATH 

   printf "${KBLU}Updating HomeBrew tools${KNRM} ...\n"
   printf "${KRED}Ignore the ERROR: could not link ${KNRM}\n"
   printf "${KRED}Ignore the message "
   printf "Please delete these paths and run brew update ${KNRM}\n"
   printf "They are created by brew as it is not in /local or with sudo ${KNRM}\n"
   printf "\n"

   # I dont know why this is true, but tar fails otherwise
   set +e

   printf "${KBLU}Running Brew update${KNRM} ... Logging to /tmp/brew_update.log \n"
   $BrewHome/bin/brew update > /tmp/brew_update.log 2>&1 &
   pid="$!"
   waitForPid "$pid"
   set -e
   if [ $rc != 0 ]; then
      printf "${KRED}Error : [${rc}] ${KNRM} brew update tools failed. Check the log for details\n"
      exit $rc
   fi
   printf "${KGRN} done ${KNRM}\n"


   # Do not Exit immediately if a command exits with a non-zero status.
   set +e

#  $BrewHome/bin/brew install findutils --with-default-names --build-from-source 
#  $BrewHome/bin/brew install libtool --with-default-names --build-from-source 
#  $BrewHome/bin/brew install gnu-indent --with-default-names --build-from-source 
#  $BrewHome/bin/brew install gnu-sed --with-default-names --build-from-source 
#  $BrewHome/bin/brew install gnutls --build-from-source 
#  $BrewHome/bin/brew install grep --with-default-names --build-from-source 
#  $BrewHome/bin/brew install gnu-tar --with-default-names --build-from-source 
#  $BrewHome/bin/brew install gawk --build-from-source 
#  $BrewHome/bin/brew install ncurses  --build-from-source 
#  $BrewHome/bin/brew install gettext  --build-from-source 
#  $BrewHome/bin/brew install binutils  --build-from-source 
#  $BrewHome/bin/brew install help2man  --build-from-source 
#  $BrewHome/bin/brew install autoconf  --build-from-source 
#  $BrewHome/bin/brew install automake  --build-from-source 
#  $BrewHome/bin/brew install bison  --build-from-source 
#  $BrewHome/bin/brew install bash  --build-from-source 
#  $BrewHome/bin/brew install wget  --build-from-source 
#  $BrewHome/bin/brew install sha2" --build-from-source 

   # $BrewHome/bin/brew install --with-default-names $BrewTools && true
   # $BrewHome/bin/brew install $BrewTools --build-from-source --with-real-names && true
   # --default-names was deprecated
   printf "${KBLU}Installing brew tools. This may take quite a while ${KNRM} to ${BrewHome} ... Logging to /tmp/brewToolsInstall.log\n"
   $BrewHome/bin/brew install $BrewTools  --build-from-source --with-default-names > /tmp/brewToolsInsrall.log 2>&1 &
   pid="$!"
   waitForPid "$pid"
   if [ $rc != 0 ]; then
      printf "${KRED}Error : [${rc}] ${KNRM} brew tools failed. Check the log for details\n"
      exit $rc
   fi
   printf "${KGRN} done ${KNRM}\n"

   # change to Exit immediately if a command exits with a non-zero status.
   set -e

   printf "${KBLU}Checking for ${KNRM}$BrewHome/bin/gsha512sum ${KNRM} ..."
   if [ ! -f $BrewHome/bin/gsha512sum ]; then
      printf "${KRED} not found ${KNRM}\n"
      exit 1
   fi
   printf "${KGRN} found ${KNRM}\n"
   printf "${KBLU}Checking for ${KNRM}$BrewHome/bin/sha512sum ${KNRM} ..."
   if [ ! -f $BrewHome/bin/sha512sum ]; then
      printf "${KYEL} not found ${KNRM}\n"
      printf "${KNRM}Linking gsha512sum to sha512sum ${KNRM}\n"
      ln -s $BrewHome/bin/gsha512sum $BrewHome/bin/sha512sum
   else
      printf "${KGRN} found ${KNRM}\n"
   fi

   printf "${KBLU}Checking for ${KNRM}$BrewHome/bin/gsha256sum ${KNRM} ... "
   if [ ! -f $BrewHome/bin/gsha256sum ]; then
      printf "${KRED} not found ${KNRM}\n"
      exit 1
   fi
   printf "${KGRN} found ${KNRM}\n"

   printf "${KBLU}Checking for ${KNRM}$BrewHome/bin/sha256sum ${KNRM} ... "
   if [ ! -f $BrewHome/bin/sha256sum ]; then
      printf "${KYEL} not found ${KNRM}\n"
      printf "${KNRM}Linking gsha256sum to sha256sum ${KNRM}\n"
      ln -s $BrewHome/bin/gsha256sum $BrewHome/bin/sha256sum
   else
      printf "${KGRN} found ${KNRM}\n"
   fi

   printf "${KBLU}Checking for ${KNRM}$BrewHome/bin/readlink ${KNRM} ... "
   if [ ! -f $BrewHome/bin/readlink ]; then
      printf "${KYEL} not found ${KNRM}\n"
      printf "${KNRM}Linking greadlink to readlink ${KNRM}\n"
      ln -s $BrewHome/bin/greadlink $BrewHome/bin/readlink
   else
      printf "${KGRN} found ${KNRM}\n"
   fi

   printf "${KBLU}Checking for ${KNRM}$BrewHome/bin/stat ${KNRM} ... "
   if [ ! -f $BrewHome/bin/stat ]; then
      printf "${KYEL} not found ${KNRM}\n"
      printf "${KNRM}Linking gstat to stat ${KNRM}\n"
      ln -s $BrewHome/bin/gstat $BrewHome/bin/stat
   else
      printf "${KGRN} found ${KNRM}\n"
   fi

#  printf "${KBLU}Checking for ${KNRM}$BrewHome/bin/readelf ${KNRM} ... "
#  if [ ! -f $BrewHome/bin/readelf ]; then
#     printf "${KYEL} not found ${KNRM}\n"
#     printf "${KNRM}Linking greadelf to readelf ${KNRM}\n"
#     ln -s $BrewHome/bin/greadelf $BrewHome/bin/readelf
#  else
#     printf "${KGRN} found ${KNRM}\n"
#  fi

#  printf "${KBLU}Checking for ${KNRM}$BrewHome/bin/ranlib ${KNRM} ... "
#  if [ ! -f $BrewHome/bin/ranlib ]; then
#     printf "${KYEL} not found ${KNRM}\n"
#     printf "${KNRM}Linking granlib to ranlib ${KNRM}\n"
#     ln -s $BrewHome/bin/granlib $BrewHome/bin/ranlib
#  else
#     printf "${KGRN} found ${KNRM}\n"
#  fi
#
#  printf "${KBLU}Checking for ${KNRM}$BrewHome/bin/objcopy ${KNRM} ... "
#  if [ ! -f $BrewHome/bin/objcopy ]; then
#     printf "${KYEL} not found ${KNRM}\n"
#     printf "${KNRM}Linking gobjcopy to objcopy ${KNRM}\n"
#     ln -s $BrewHome/bin/gobjcopy $BrewHome/bin/objcopy
#  else
#     printf "${KGRN} found ${KNRM}\n"
#  fi
#
#  printf "${KBLU}Checking for ${KNRM}$BrewHome/bin/objdump ${KNRM} ... "
#  if [ ! -f $BrewHome/bin/objdump ]; then
#     printf "${KYEL} not found ${KNRM}\n"
#     printf "${KNRM}Linking gobjdump to objdump ${KNRM}\n"
#     ln -s $BrewHome/bin/gobjdump $BrewHome/bin/objdump
#  else
#     printf "${KGRN} found ${KNRM}\n"
#  fi
#
#  printf "${KBLU}Checking for ${KNRM}$BrewHome/bin/sed ${KNRM} ... "
#  if [ ! -f $BrewHome/bin/sed ]; then
#     printf "${KYEL} not found ${KNRM}\n"
#     printf "${KNRM}Linking gsed to sed ${KNRM}\n"
#     ln -s $BrewHome/bin/gsed $BrewHome/bin/sed
#  else
#     printf "${KGRN} found ${KNRM}\n"
#  fi

   printf "${KBLU}Checking for ${KNRM}$BrewHome/bin/grep ${KNRM} ... "
   if [ ! -f $BrewHome/bin/grep ]; then
      printf "${KYEL} not found ${KNRM}\n"
      printf "${KNRM}Linking ggrep to grep ${KNRM}\n"
      ln -s $BrewHome/bin/ggrep $BrewHome/bin/grep
   else
      printf "${KGRN} found ${KNRM}\n"
   fi

}
function downloadCrossTool_LATEST()
{  
   cd /Volumes/${VolumeBase}
   printf "${KBLU}Downloading crosstool-ng ${KNRM} to ${PWD} \n"

   if [ -d "${CrossToolSourceDir}" ]; then 
      printf "   ${KRED}WARNING${KNRM} - ${CrossToolSourceDir} exists and will be used.\n"
      printf "   ${KRED}WARNING${KNRM} - Remove it to start fresh\n"
      return
   fi

   CrossToolUrl="https://github.com/crosstool-ng/crosstool-ng.git"
   git clone ${CrossToolUrl}  ${CrossToolSourceDir}

   # We need to creat the configure tool
   printf "${KBLU}Running  crosstool bootstrap to ${PWD} ${KNRM}\n"
   cd "${CrossToolSourceDir}"

   # crosstool-ng-1.23.0 still has CT_Mirror
   # git checkout -b $CrossToolVersion

   ./bootstrap
}

function patchConfigFileForVolume()
{
    printf "${KBLU}Patching .config file for 'CrossToolNG' in ${PWD}${KNRM}\n"
    if [ -f ".config" ]; then
       sed -i .bak -e's/CrossToolNG/'$Volume'/g' .config
    fi
}

function patchConfigFileForOutputDir()
{
    printf "${KBLU}Patching .config file for 'x-tools' in ${PWD}${KNRM}\n"
    if [ -f ".config" ]; then
       sed -i .bak2 -e's/x-tools/'$OutputDir'/g' .config
    fi
}

function patchCrosstool()
{
    printf "${KBLU}Patching crosstool-ng ${KNRM}\n"
    if [ -x "/Volumes/${VolumeBase}/ctng/bin/ct-ng" ]; then
      printf "${KGRN}    - found existing ct-ng. Using it instead ${KNRM}\n"
      return
    fi

    cd "/Volumes/${VolumeBase}/${CrossToolSourceDir}"
    printf "${KBLU}Patching crosstool-ng in ${PWD} ${KNRM}\n"

    printf "Patching crosstool-ng ${KNRM}\n"
    printf "   -No Patches requires.\n"
    
# patch required with crosstool-ng-1.17
# left here as an example of how it was done.
#    sed -i .bak '6i\
##include <stddef.h>' kconfig/zconf.y
}

function buildCrosstool()
{
   printf "${KBLU}Configuring crosstool-ng ${KNRM} in ${PWD} \n"
   if [ -x "/Volumes/${VolumeBase}/ctng/bin/ct-ng" ]; then
      printf "${KGRN}    - found existing ct-ng. Using it instead ${KNRM}\n"
      return
   fi
   cd "/Volumes/${VolumeBase}/${CrossToolSourceDir}"


   # It is strange that gettext is put in opt
   gettextDir=${BrewHome}/opt/gettext
   
   printf "${KBLU} Executing configure --with-libintl-prefix=$gettextDir ${KNRM}\n"

   # export LDFLAGS
   # export CPPFLAGS

   # --with-libintl-prefix should have been enough, but it seems LDFLAGS and
   # CPPFLAGS is required too to fix libintl.h not found
   LDFLAGS="  -L${BrewHome}/opt/gettext/lib -lintl " \
   CPPFLAGS=" -I${BrewHome}/opt/gettext/include" \
   ./configure  --with-libintl-prefix=$gettextDir --prefix="/Volumes/${VolumeBase}/ctng" \
   > /tmp/ct-ng_config.log 2>&1 &
   pid="$!"
   waitForPid "$pid"
   if [ $rc != 0 ]; then
      printf "${KRED}Error : [${rc}] ${KNRM} configure failed. Check the log for details\n"
      exit $rc
   fi
   printf "${KGRN} done ${KNRM}\n"


   # These are not needed by crosstool-ng version 1.23.0
   # 
   #        OBJCOPY=$BrewHome/bin/objcopy         \
   #        OBJDUMP=$BrewHome/bin/objdump         \
   #        RANLIB=$BrewHome/bin/ranlib           \
   #        READELF=$BrewHome/bin/readelf         \
   #        LIBTOOL=$BrewHome/obj/libtool         \
   #        LIBTOOLIZE=$BrewHome/bin/libtoolize   \
   #        SED=$BrewHome/bin/sed                 \
   #        AWK=$BrewHome/bin/gawk                \
   #        AUTOMAKE=$BrewHome/bin/automake       \
   #        BASH=$BrewHome/bin/bash               \
   #        CFLAGS="-std=c99 -Doffsetof=__builtin_offsetof"

   printf "${KBLU}Compiling crosstool-ng ${KNRM}in ${PWD} ... Logging to /tmp/ctng_build.log\n"
   make > /tmp/ctng_build.log 2>&1 &
   pid="$!"
   waitForPid "$pid"
   if [ $rc != 0 ]; then
      printf "${KRED}Error : [${rc}] ${KNRM} build failed. Check the log for details\n"
      exit $rc
   fi
   printf "${KGRN} done ${KNRM}\n"

   printf "${KBLU}Installing  crosstool-ng ${KNRM}in /Volumes/${VolumeBase}/ctng ... Logging to /tmp/ctng_install.log\n"
   make install > /tmp/ctng_install.log 2>&1 &
   pid="$!"
   waitForPid "$pid"
   if [ $rc != 0 ]; then
      printf "${KRED}Error : [${rc}] ${KNRM} install failed. Check the log for details\n"
      exit $rc
   fi
   printf "${KGRN}Compilation of ct-ng is Complete ${KNRM}\n"
}

function createCrossCompilerConfigFile()
{


   cd ${CT_TOP_DIR}


   printf "${KBLU}Checking for ct-ng config file ${KNRM}${CT_TOP_DIR}/.config ... "
   if [ -f  "${CT_TOP_DIR}/.config" ]; then
      printf "${KGRN} found ${KNRM}\n"
      printf "${KYEL}Using existing .config file ${KNRM}\n"
      printf "${KNRM}Remove it if you wish to start over ${KNRM}\n"
      return
   else
      printf "${KRED} not found ${KNRM}\n"
   fi
   

   printf "${KBLU}Checking for an existing toolchain config file: ${KNRM} ${CrossToolNGConfigFilePath}/${CrossToolNGConfigFile} ...\n"
   if [ -f "${CrossToolNGConfigFilePath}/${CrossToolNGConfigFile}" ]; then
      printf "   - Using ${CrossToolNGConfigFilePath}/${CrossToolNGConfigFile} ${KNRM}\n"
      cp "${CrossToolNGConfigFilePath}/${CrossToolNGConfigFile}"  "${CT_TOP_DIR}/.config"

      cd "${CT_TOP_DIR}"
      if [ "$Volume" == 'CrossToolNG' ];then

         printf "${KBLU}.config file not being patched as -V was not specified ${KNRM}\n"
      else
         patchConfigFileForVolume
      fi
      if [ "$OutputDir" == 'x-tools' ];then
         printf "${KBLU}.config file not being patched as -O was not specified ${KNRM}\n"
      else
         patchConfigFileForOutputDir
      fi
   else
      printf "   - None found${KNRM}\n"
   fi

cat <<'CONFIG_EOF'

NOTES: on what to set in config file, taken from
https://gist.github.com/h0tw1r3/19e48ae3021122c2a2ebe691d920a9ca

- Paths and misc options
    - Set "Prefix directory" to the real values of:
        /Volumes/$Volume/$OutputDir/${CT_TARGET}

- Target options
    By default this script builds the configuration for armv8-rpi3-linux-gnueabihf as this is my focus; However, crosstool-ng can build so many different types of cross compilers.  If you are interested in them, check out the samples with:

      ct-ng list-samples

    You could also just go to the crosstool-ng-src/samples directory and peruse them all.

   At least using this script will help you try configurations more easily.
   

CONFIG_EOF

   # Give the user a chance to digest this
   sleep 5

   export PATH=${CT_TOP_DIR}/$OutputDir/$ToolchainName/bin:$BrewHome/bin:$BrewHome/opt/gettext/bin:$BrewHome/opt/bison/bin:$BrewHome/opt/libtool/bin:$BrewHome/opt/gcc/bin:/Volumes/${VolumeBase}/ctng/bin:$PATH 

   # Use 'menuconfig' target for the fine tuning.

   # It seems ct-ng menuconfig dies without some kind of target
   export CT_TARGET="changeMe"
   ct-ng menuconfig

   printf "${KBLU}Once your finished tinkering with ct-ng menuconfig${KNRM}\n"
   printf "${KBLU}to contineu the build${KNRM}\n"
   printf "${KBLU}Execute:${KNRM} ./build.sh -b ${KNRM}"
   if [ $Volume != 'CrossToolNG' ]; then
      printf "${KNRM} -V ${Volume}${KNRM}"
   fi
   if [ $OutputDir != 'x-tools' ]; then
      printf "${KNRM} -O ${OutputDir}${KNRM}"
   fi
   printf "\n"
   

}

function buildToolchain()
{
   printf "${KBLU}Building toolchain ${KNRM}\n"

   cd ${CT_TOP_DIR}

   # Allow the source that crosstools-ng downloads to be saved
   printf "${KBLU}Checking for:${KNRM} ${PWD}/src ... "
   if [ ! -d "src" ]; then
      mkdir "src"
      printf "${KGRN} created ${KNRM}\n"
   else
      printf "${KGRN} found ${KNRM}\n"
   fi

   printf "${KBLU}Checking for:${KNRM} ${PWD}/.config ... "
   if [ ! -f '.config' ]; then
      printf "${KRED}ERROR: You have still not created a: ${KNRM}"
      printf "${PWD}/.config file. ${KNRM}\n"
      printf "Change directory to ${CT_TOP_DIR}${KNRM}\n"
      printf "And run: ./ct-ng menuconfig ${KNRM}\n"
      printf "Before continuing with the build ${KNRM}\n"

      exit -1
   else
      printf "${KGRN} found ${KNRM}\n"
   fi
   export PATH=${CT_TOP_DIR}/$OutputDir/$ToolchainName/bin:$BrewHome/bin:$BrewHome/opt/gettext/bin:$BrewHome/opt/bison/bin:$BrewHome/opt/libtool/bin:$BrewHome/opt/gcc/bin:/Volumes/${VolumeBase}/ctng/bin:$PATH 

   if [ "$1" == "list-steps" ]; then
      ct-ng "$1"
      return
   fi
   if [ "$1" == "build" ]; then
      printf "${KBLU} Executing ct-ng build to build the cross compiler ${KNRM}\n"
   else
      printf "${KBLU} Executing ct-ng $1 ${KNRM}\n"
   fi
      
   ct-ng "$1" 

   printf "And if all went well, you are done! Go forth and cross compile ${KNRM}\n"
   printf "Raspbian if you so wish with: ./build.sh -b Raspbian ${KNRM}\n"
}

function buildLibtool
{   
    cd "${CT_TOP_DIR}/src/libelf"
    # ./configure --prefix=${CT_TOP_DIR}/${OutputDir}/${ToolchainName}
    ./configure  -prefix=${CT_TOP_DIR}/${OutputDir}/${ToolchainName}  --host=${ToolchainName}
    make
    make install
}

function downloadAndBuildzlib
{
   zlibFile="zlib-1.2.11.tar.gz"
   zlibURL="https://zlib.net/zlib-1.2.11.tar.gz"

   printf "${KBLU}Checking for ${KNRM}zlib.h and libz.a ... "
   if [ -f "${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/${ToolchainName}/include/zlib.h" ] && [ -f  "${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/${ToolchainName}/lib/libz.a" ]; then
      printf "${KGRN} found ${KNRM}\n"
      return
   fi
   printf "${KYEL} not found ${KNRM}\n"

   printf "${KBLU}Checking for ${KNRM}${CT_TOP_DIR}/src/zlib-1.2.11 ... "
   if [ -d "${CT_TOP_DIR}/src/zlib-1.2.11" ]; then
      printf "${KGRN} found ${KNRM}\n"
      printf "${KNRM} Using existing zlib source ${KNRM}\n"
   else
      printf "${KYEL} not found ${KNRM}\n"
      cd "${CT_TOP_DIR}/src/"
      printf "${KBLU}Checking for saved ${KNRM}${zlibFile} ... "
      if [ -f "${TarBallSourcesPath}/${zlibFile}" ]; then
         printf "${KGRN} found ${KNRM}\n"
      else
         printf "${KYEL} not found ${KNRM}\n"
         printf "${KBLU}Downloading ${KNRM}${zlibFile} ... "
         curl -Lsf "${zlibURL}" -o "${TarBallSourcesPath}/${zlibFile}"
         printf "${KGRN} done ${KNRM}\n"
      fi
      printf "${KBLU}Decompressing ${KNRM}${zlibFile} ... "
      tar -xzf ${TarBallSourcesPath}/${zlibFile} -C${CT_TOP_DIR}/src
      printf "${KGRN} done ${KNRM}\n"
   fi

     printf "${KBLU} Configuring zlib ${KNRM} Logging to /tmp/zlib_config.log \n"
    cd "${CT_TOP_DIR}/src/zlib-1.2.11"
    CHOST=${ToolchainName} ./configure \
          --prefix=${CT_TOP_DIR}/${OutputDir}/${ToolchainName} \
          --static \
          --libdir=${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/${ToolchainName}/lib \
          --includedir=${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/${ToolchainName}/include \
    > /tmp/zlib_config.log 2>&1 &

    pid="$!"
    waitForPid "$pid"
    if [ $rc != 0 ]; then
       printf "${KRED}Error : [${rc}] ${KNRM} configure failed. Check the log for details\n"
       exit $rc
    fi

    printf "${KBLU} Building zlib ${KNRM} Logging to /tmp/zlib_build.log \n"
    make > /tmp/zlib_build.log 2>&1 &

    pid="$!"
    waitForPid "$pid"
    if [ $rc != 0 ]; then
       printf "${KRED}Error : [${rc}] ${KNRM} build failed. Check the log for details\n"
       exit $rc
    fi

    


    printf "${KBLU} Installing zlib ${KNRM} Logging to /tmp/zlib_install.log \n"
    make install > /tmp/zlib_install.log 2>&1 &

    pid="$!"
    waitForPid "$pid"
    if [ $rc != 0 ]; then
       printf "${KRED}Error : [${rc}] ${KNRM} install failed. Check the log for details\n"
       exit $rc
    fi

}


function downloadElfLibrary
{
elfLibURL="https://github.com/WolfgangSt/libelf.git"

   cd "${CT_TOP_DIR}/src"
   printf "${KBLU}Downloading libelf latest ${KNRM} to ${PWD}\n"

   if [ -d "libelf" ]; then
      printf "${KRED}WARNING ${KNRM}Path already exists libelf ${KNRM}\n"
      printf "        A fetch will be done instead to keep tree up to date\n"
      printf "\n"
      cd "libelf"
      git fetch
    
   else
      git clone --depth=1 ${elfLibURL}
   fi
}

function testBuild
{
   gpp="${CT_TOP_DIR}/$OutputDir/$ToolchainName/bin/${ToolchainName}-g++"
   if [ ! -f "${gpp}" ]; then
      printf "${KYEL}No executable compiler found. ${KNRM} ${gpp} \n"
      rc='-1'
      return
   fi

cat <<'HELLO_WORLD_EOF' > /tmp/HelloWorld.cpp
#include <iostream>
using namespace std;

int main ()
{
  cout << "Hello World!";
  return 0;
}
HELLO_WORLD_EOF

   PATH=${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/bin:$PATH

   ${ToolchainName}-g++ -fno-exceptions /tmp/HelloWorld.cpp -o /tmp/HelloWorld
   rc=$?

}

function downloadRaspbianKernel
{
RaspbianURL="https://github.com/raspberrypi/linux.git"

   printf "${KMAG}*******************************************************************************${KNRM}\n"
   printf "${KMAG}* WHEN CONFIGURING THE RASPIAN KERNEL YOU MUST SET THE \n"
   printf "${KMAG}*  COMPILER PREFIX TO: ${KRED} ${ToolchainName}-  ${KNRM}\n"
   printf "${KMAG}*******************************************************************************${KNRM}\n"

   # This is so very important that we must make sure you remember to set the compiler prefix
   # Maybe at a later date this will be automated
   read -p "Press any key to continue"


   cd "${CT_TOP_DIR}"
   printf "${KBLU}Downloading Raspbian Kernel latest ${KNRM} \n"

   
   printf "${KBLU}Checking for ${KNRM} ${RaspbianSrcDir} ... "
   if [ ! -d "${RaspbianSrcDir}" ]; then
      printf "${KYEL} not found ${KNRM}\n"
      printf "${KBLU}Creating ${KNRM}${RaspbianSrcDir} ... "
      mkdir "${RaspbianSrcDir}"
      printf "${KGRN} done ${KNRM}\n"
   else
      printf "${KGRN} found ${KNRM}\n"
   fi

   cd "${CT_TOP_DIR}/${RaspbianSrcDir}"

   printf "${KBLU}Checking for ${KNRM} ${RaspbianSrcDir}/linux ... "
   if [ -d "${CT_TOP_DIR}/${RaspbianSrcDir}/linux" ]; then
      cd "${CT_TOP_DIR}/${RaspbianSrcDir}/linux"
      printf "${KGRN} found ${KNRM}\n"
      printf "${KRED}WARNING ${KNRM}Path already exists ${RaspbianSrcDir} ${KNRM}\n"
      printf "        A fetch will be done instead to keep tree up to date\n"
      printf "\n"
      cd "${CT_TOP_DIR}/${RaspbianSrcDir}/linux"
      git fetch
    
   else
      printf "${KGRN} not found -OK  ${KNRM}\n"
      printf "${KBLU}Checking for saved ${KNRM} linux.tar.xz ... "
      if [ -f "${TarBallSourcesPath}/linux.tar.xz" ]; then
         printf "${KGRN} found ${KNRM}\n"

         cd "${CT_TOP_DIR}/${RaspbianSrcDir}"
         printf "${KBLU}Extracting saved ${KNRM} ${TarBallSourcesPath}/linux.tar.xz ... Logging to /tmp/linux_extract.log\n"
         # I dont know why this is true, but tar fails otherwise
         set +e
         tar -xzf ${TarBallSourcesPath}/linux.tar.xz  > /tmp/linux_extract.log 2>&1 &

         pid="$!"
         waitForPid ${pid}
         set -e

         if [ $rc != 0 ]; then
            printf "${KRED}Error : [${rc}] ${KNRM} extract failed. \n"
            exit $rc
         fi
 
         printf "${KGRN} done ${KNRM}\n"
         
      else
         printf "${KYEL} not found ${KNRM}\n"
         printf "${KBLU}Cloning Raspbian from git ${KNRM} ... \n"
         cd "${CT_TOP_DIR}/${RaspbianSrcDir}"

         git clone --depth=1 ${RaspbianURL} 

         printf "${KGRN} done ${KNRM}\n"

         # Fix missing dtb's 
         # cd linux
         # git remote add mptcp https://github.com/multipath-tcp/mptcp.git
         # git fetch mptcp
         # git checkout -b rpi_mptcp origin/rpi-4.14.y
         # # SETTING UP GIT EMAIL (CAN BE A TRASH MAIL OR JUST EXAMPLE@MAIL.COM)
         # git config --global user.email "example@mail.com"
         # git merge mptcp/mptcp_v0.94
         # cd ..

         # Patch source for RT Linux
         # wget -O rt.patch.gz https://www.kernel.org/pub/linux/kernel/projects/rt/4.14/older/patch-4.14.18-rt15.patch.gz
         # zcat rt.patch.gz | patch -p1

         printf "${KBLU}Saving Raspbian source ${KNRM} to ${TarBallSourcesPath}/linux.tar.xz ...  Logging to raspbian_compress.log\n"
         # I dont know why this is true, but tar fails otherwise
         set +e
         tar -cJf "${TarBallSourcesPath}/linux.tar.xz" linux  &
         pid="$!"
         waitForPid "$pid"
         set -e
         if [ $rc != 0 ]; then
            printf "${KRED}Error : [${rc}] ${KNRM} save failed. Check the log for details\n"
            exit $rc
         fi
         printf "${KGRN} done ${KNRM}\n"
      fi
   fi

}
function downloadElfHeaderForOSX
{
   ElfHeaderFile="/usr/local/include/elf.h"
   printf "${KBLU}Checking for ${KNRM}${ElfHeaderFile}\n"
   if [ -f "${ElfHeaderFile}" ]; then
      printf "${KGRN} found ${KNRM}\n"
   else
      printf "${KRED}\n\n *** IMPORTANT*** ${KNRM}\n"
      printf "${KRED}The gcc with OSX does not have an elf.h \n"
      printf "${KRED}No CFLAGS will fix this as the compile strips them\n"
      printf "${KRED}A copy from GitHub will be placed in /usr/local/include\n"
      printf "${KRED}Another copy will be put in The Raspbian source linux subdirectory,\n"
      printf "${KRED}as a reminder for this tool to remove it later.${KNRM}\n\n\n"
      sleep 6
      
      ElfHeaderFileURL="https://gist.githubusercontent.com/mlafeldt/3885346/raw/2ee259afd8407d635a9149fcc371fccf08b0c05b/elf.h"
      curl -Lsf ${ElfHeaderFileURL} >  ${ElfHeaderFile}
   fi
}

function cleanupElfHeaderForOSX
{
   ElfHeaderFile="/usr/local/include/elf.h"
   printf "${KBLU}Checking for ${KNRM} ${ElfHeaderFile} ... "
   if [ -f "${ElfHeaderFile}" ]; then
      printf "${KGRN} found ${KNRM}\n"
      if [[ $(grep 'Mathias Lafeldt <mathias.lafeldt@gmail.com>' ${ElfHeaderFile}) ]];then
         printf "${KGRN}Removing ${ElfHeaderFile} ${KNRM} ... "
         rm "${ElfHeaderFile}"
         printf "${KGRN} done ${KNRM}\n"
      else
         printf "${KRED} not done ${KNRM}\n"
         printf "${KRED}Warning. There is a ${KNRM}${ElfHeaderFile}\n"
         printf "${KRED}But it was not put there by this tool, I believe ${KNRM}\n"
         sleep 4
      fi
   else
      printf "${KGRN} not found - OK ${KNRM}\n"

   fi
}

function configureRaspbianKernel
{
   cd "${CT_TOP_DIR}/${RaspbianSrcDir}/linux"
   printf "${KBLU}Configuring Raspbian Kernel in ${PWD}${KNRM}\n"

   export PATH=${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/bin:$BrewHome/bin:$BrewHome/opt/gettext/bin:$BrewHome/opt/bison/bin:$BrewHome/opt/libtool/bin:$BrewHome/opt/gcc/bin:/Volumes/${VolumeBase}/ctng/bin:$PATH 
   echo $PATH


   # for bzImage
   export KERNEL=kernel7

   export CROSS_PREFIX=${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/bin/${ToolchainName}-

   printf "${KBLU}Checkingo for an existing .config file ${KNRM} ... "
   if [ -f .config ]; then
      printf "${KYEL} found ${KNRM} \n""
      printf "${KNRM} make mproper & bcm2709_defconfig  ${KNRM} will not be done \n""
      printf "${KNRM} to protect previous changes  ${KNRM} \n""
   else
      printf "${KGRN} not found ${KNRM} \n""
      printf "${KBLU}Make bcm2709_defconfig in ${PWD}${KNRM}\n"
      export LFS_CFLAGS=-I${CT_TOP_DIR}/$OutputDir/$ToolchainName/$ToolchainName/include
      export LFS_LDFLAGS=-I${CT_TOP_DIR}/$OutputDir/$ToolchainName/$ToolchainName/lib
      make ARCH=arm O=${CT_TOP_DIR}/build/kernel mrproper 
      make ARCH=arm CONFIG_CROSS_COMPILE=${ToolchainName}- CROSS_COMPILE=${ToolchainName}- --include-dir=${CT_TOP_DIR}/$OutputDir/$ToolchainName/$ToolchainName/include  bcm2709_defconfig
   fi

   printf "${KBLU}Running make nconfig ${KNRM} \n"
   # This cannot include ARCH= ... as it runs on OSX
   make nconfig


   printf "${KBLU}Make zImage in ${PWD}${KNRM}\n"

   KBUILD_CFLAGS=-I${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/include \
   KBUILD_LDLAGS=-L${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/lib \
   HOSTCC=${ToolchainName}-gcc \
   ARCH=arm \
      make  -j4 CROSS_COMPILE=${ToolchainName}- \
        CC=${ToolchainName}-gcc \
        --include-dir=${CT_TOP_DIR}/$OutputDir/$ToolchainName/$ToolchainName/include \
        zImage 

   printf "${KBLU}Make modules in ${PWD}${KNRM}\n"
   KBUILD_CFLAGS=-I${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/include \
   KBUILD_LDLAGS=-L${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/lib \
   HOSTCC=${ToolchainName}-gcc \
   ARCH=arm \
      make  -j4 CROSS_COMPILE=${ToolchainName}- \
        CC=${ToolchainName}-gcc \
        --include-dir=${CT_TOP_DIR}/$OutputDir/$ToolchainName/$ToolchainName/include \
        modules

   printf "${KBLU}Make dtbs in ${PWD}${KNRM}\n"
   KBUILD_CFLAGS=-I${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/include \
   KBUILD_LDLAGS=-L${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/lib \
   HOSTCC=${ToolchainName}-gcc \
   ARCH=arm \
      make  -j4 CROSS_COMPILE=${ToolchainName}- \
        CC=${ToolchainName}-gcc \
        --include-dir=${CT_TOP_DIR}/$OutputDir/$ToolchainName/$ToolchainName/include \
        dtbs

   # Only thing changed were

   # *
   # * General setup
   # *
   # Cross-compiler tool prefix (CROSS_COMPILE) [] (NEW) 
   # - Set to: armv8-rpi3-linux-gnueabihf-


   # Preemption Model  (Under Processor Types and features
   #   1. No Forced Preemption (Server) (PREEMPT_NONE) (NEW)
   #   2. Voluntary Kernel Preemption (Desktop) (PREEMPT_VOLUNTARY)
   # > 3. Preemptible Kernel (Low-Latency Desktop) (PREEMPT) (NEW)
   # choice[1-3]: 3

   # make O=${CT_TOP_DIR}/build/kernel nconfig
   # make O=${CT_TOP_DIR}/build/kernel


}
function installRaspbianKernel()
{
   printf "${KBLU}Installing Raspbian Kernel ${KNRM}\n"
   printf "${KBLU}Checking for Raspbian source ${KNRM} ..."
   if [ ! -d "${CT_TOP_DIR}/${RaspbianSrcDir}/linux" ]; then
      printf "${KRED} not found ${KNRM}\n"
      printf "${KNRM} You must first successfully execute: ./biuld.sh -b Raspbian ${KNRM}\n"
      exit -1
   fi
   printf "${KGRN} found ${KNRM}\n"

   printf "${KBLU}Checking for ${BootFS} ${KNRM} ..."
   if [ ! -d "${BootFS}" ]; then
      printf "${KRED} not found ${KNRM}\n"
      exit -1
   fi
   printf "${KGRN} found ${KNRM}\n"

   printf "${KBLU}Checking for ${CT_TOP_DIR}/${RaspbianSrcDir}/linux/arch/arm/boot/zImage ${KNRM} ..."
   if [ ! -f "${CT_TOP_DIR}/${RaspbianSrcDir}/linux/arch/arm/boot/zImage" ]; then
      printf "${KRED} not found ${KNRM}\n"
      exit -1
   fi
   printf "${KGRN} found ${KNRM}\n"


   printf "${KBLU}Copying Raspbian file ${KNRM}\n"
   

   # FIXME add sudo later
   cp ${CT_TOP_DIR}/${RaspbianSrcDir}/linux/arch/arm/boot/dts/*.dtb ${BootFS}/
   cp ${CT_TOP_DIR}/${RaspbianSrcDir}/linux/arch/arm/boot/dts/overlays/*.dtb* ${BootFS}/overlays/
   cp ${CT_TOP_DIR}/${RaspbianSrcDir}/linux/arch/arm/boot/dts/overlays/README ${BootFS}/overlays/
   cp ${CT_TOP_DIR}/${RaspbianSrcDir}/linux/arch/arm/boot/zImage ${BootFS}/kernel7.img
}
function checkExt2InstallForOSX()
{

   printf "${KBLU}Checking for Ext2 tools ${KNRM} ..."
   if [ ! -d $BrewHome/Caskroom/osxfuse ] &&
      [ ! -d $BrewHome/Cellar/e2fsprogs/1.44.3/sbin/mke2fs ]; then
      printf "${KRED} not found ${KNRM}\n"
      printf "${KNRM}You must first execute: ./build.sh -i ${KNRM}\n"
      printf "${KNRM}To install the brew Ext2 tools ... ${KNRM}\n"
      exit -1
   fi
   printf "${KGRN} found ${KNRM}\n"

   printf "${KBLU}Checking that Ext2 tools are set up properly ${KNRM} ... "
   if [ ! -d /Library/Filesystems/fuse-ext2.fs ] &&
      [ ! -d /Library/PreferencePanes/fuse-ext2.prefPane ]; then
      printf "\n${KRED}As per the previous Fuse-Ext2 instructions ${KNRM}\n"

      cat <<'      EXT2_EOF'

          For fuse-ext2 to be able to work properly, the filesystem extension and
          preference pane must be installed by the root user:
 
          sudo cp -pR /Volumes/CrossToolNGBase/brew/opt/fuse-ext2/System/Library/Filesystems/fuse-ext2.fs /Library/Filesystems/
          sudo chown -R root:wheel /Library/Filesystems/fuse-ext2.fs

          sudo cp -pR /Volumes/CrossToolNGBase/brew/opt/fuse-ext2/System/Library/PreferencePanes/fuse-ext2.prefPane /Library/PreferencePanes/
          sudo chown -R root:wheel /Library/PreferencePanes/fuse-ext2.prefPane

      EXT2_EOF

      exit -1
   fi

   printf "${KGRN} OK ${KNRM}\n"
   
}

function updateBrewForEXT2()
{
   export PATH=$BrewHome/bin:$BrewHome/opt/gettext/bin:$BrewHome/opt/bison/bin:$BrewHome/opt/libtool/bin:$BrewHome/opt/gcc/bin:$BrewHome/Cellar/e2fsprogs/1.44.3/sbin:$PATH 

   printf "${KBLU}Checking for HomeBrew tools ${KNRM} ..."
   if [ ! -f "${BrewHome}/bin/brew" ]; then
      printf "${KRED} not found ${KNRM}\n"
      printf "${KNRM}You must first execute: ./build.sh  ${KNRM}\n"
      printf "${KNRM}To install the brew tools etc ... ${KNRM}\n"
      exit -1
   fi
   printf "${KGRN} found ${KNRM}\n"

   if [ ! -d $BrewHome/Caskroom/osxfuse ] &&
      [ ! -d $BrewHome/Cellar/e2fsprogs/1.44.3/sbin/mke2fs ]; then
      printf "${KBLU}Updating HomeBrew tools${KNRM} ...\n"
      printf "${KRED}Ignore the ERROR: could not link ${KNRM}\n"
      printf "${KRED}Ignore the message "
      printf "Please delete these paths and run brew update ${KNRM}\n"
      printf "They are created by brew as it is not in /local or with sudo ${KNRM}\n"
      printf "\n"

      $BrewHome/bin/brew update

      # Do not Exit immediately if a command exits with a non-zero status.
      set +e

      if [ ! -d $BrewHome/Caskroom/osxfuse ]; then
         printf "${KBLU}Installing brew cask osxfuse ${KNRM}\n"
         $BrewHome/bin/brew cask install osxfuse && true
      fi

      if [ ! -d $BrewHome/Cellar/e2fsprogs/1.44.3/sbin/mke2fs ]; then
         printf "${KBLU}Installing brew ext4fuse ${KNRM}\n"
         #$BrewHome/bin/brew install ext4fuse && true
         $BrewHome/bin/brew install --HEAD https://raw.githubusercontent.com/yalp/homebrew-core/fuse-ext2/Formula/fuse-ext2.rb && true
      fi

      printf "${KBLU}After the install and reboot ${KNRM} \n"
      printf "${KBLU}Execute again: ${KNRM} ./build.sh -1 \n"

      exit 0
   fi

   # change to Exit immediately if a command exits with a non-zero status.
   set -e

   checkExt2InstallForOSX

}

function createDosBootPVolume()
{
    printf "${KBLU}Creating 1G volume for Raspbian boot mounted as ${BootFS}${KNRM} ...\n"
    if [  -d "${BootFS}" ]; then
       printf "${KYEL}WARNING${KNRM}: Volume already exists: ${BootFS}${KNRM}\n"
      
       # Give a couple of seconds for the user to react
       sleep 3

       return;
    fi

   if [ -f "${BootDir}.sparseimage" ]; then
      printf "${KRED}WARNING:${KNRM}\n"
      printf "         File already exists: ${BootDir}.sparseimage ${KNRM}\n"
      printf "         This file will be mounted as ${BootDir}${KNRM}\n"
      
      # Give a couple of seconds for the user to react
      sleep 3

   else
      hdiutil create ${BootDir}                  \
                      -volname ${BootDir}        \
                      -type SPARSE               \
                      -size 1g                   \
                      -fs "MS-DOS FAT16"         \
                      -quiet                     \
                      -puppetstrings
   fi

   hdiutil mount ${BootDir}.sparseimage
}

# At this time I do not care that this is not an ext4 partition.
# I'll see about fixing this properly later.  There are bigger fish to fry.
function createRootPVolume()
{
    printf "${KBLU}Creating 7g volume for Raspbian root mounted as ${RootFS}${KNRM} ...\n"
    if [  -d "${RootFS}" ]; then
       printf "${KYEL}WARNING${KNRM}: Volume already exists: ${RootFS}${KNRM}\n"
      
       # Give a couple of seconds for the user to react
       sleep 3

       return;
    fi

   if [ -f "${RootDir}.sparseimage" ]; then
      printf "${KRED}WARNING:${KNRM}\n"
      printf "         File already exists: ${RootDir}.sparseimage ${KNRM}\n"
      printf "         This file will be mounted as ${RootDir}${KNRM}\n"
      
      # Give a couple of seconds for the user to react
      sleep 3

   else
      hdiutil create ${RootDir}                  \
                      -volname ${RootDir}        \
                      -type SPARSE               \
                      -size 7g                   \
                      -fs HFSX                   \
                      -quiet                     \
                      -puppetstrings
   fi

   hdiutil mount ${RootDir}.sparseimage
}

function createPartitions
{
  # bootp=${device}p1
  # rootp=${device}p2

  # mkfs.vfat ${bootp}
  # mkfs.ext4 ${rootp}



  mkdir -p ${RootFS}/proc
  mkdir -p ${RootFS}/sys
  mkdir -p ${RootFS}/dev
  mkdir -p ${RootFS}/dev/pts
  mkdir -p ${RootFS}/usr/src/delivery

}


function downloadCrossTool()
{
   cd /Volumes/${VolumeBase}
   printf "${KBLU}Downloading crosstool-ng ${KNRM} to ${PWD} \n"
   CrossToolArchive=${CrossToolVersion}.tar.bz2
   if [ -f "$CrossToolArchive" ]; then
      printf "   -Using existing archive $CrossToolArchive ${KNRM}\n"
   else
      CrossToolUrl="http://crosstool-ng.org/download/crosstool-ng/${CrossToolArchive}"
      curl -L -o ${CrossToolArchive} $CrossToolUrl
   fi

   if [ -d "${CrossToolSourceDir}" ]; then
      printf "   ${KRED}WARNING${KNRM} - ${CT_TOP_DIR} exists and will be used.\n"
      printf "   ${KRED}WARNING${KNRM} - Remove it to start fresh\n"
   else
      tar -xf $CrossToolArchive -C $CrossToolSourceDir
   fi
}

function updateVariables()
{
   # MSDOS FAT16 volume names are limited to 8 characters
   BootDir="RBoot"
   BootFS="/Volumes/${BootDir}"

   RootDir="RRoot"
   RootFS="/Volumes/${RootDir}"

   CrossToolNGConfigFile="${ToolchainName}.config"

   # Do not change the name of VolumeBase. It would
   # defeat its purpose of being solid and separate

   # Change all variables that require this
   TarBallSourcesPath="/Volumes/${VolumeBase}/sources"
   BrewHome="/Volumes/${VolumeBase}/brew"
   CT_TOP_DIR="/Volumes/${Volume}"

   export BREW_PREFIX=$BrewHome
   export PKG_CONFIG_PATH=$BREW_PREFIX
   export HOMEBREW_CACHE=${TarBallSourcesPath}
   export HOMEBREW_LOG_PATH=${BrewHome}/brew_logs
}



# Define this once and you save yourself some trouble
# Omit the : for the b as we will check for optional option
OPTSTRING='h?P?c:I:V:O:f:btT:i'

# Getopt #1 - To enforce order
while getopts "$OPTSTRING" opt; do
   case $opt in
      c)
          if  [ $OPTARG == "raspbian" ] || [ $OPTARG == "Raspbian" ]; then
             CleanRaspbianOpt='y';
          fi

          ;;
          #####################
      I)
          ImageName=$OPTARG

          updateVariables

          ;;
          #####################
      V)
          Volume=$OPTARG

          updateVariables

          ;;
      O)
          OutputDir=$OPTARG

          updateVariables

          ;;
          #####################
      f)
          CrossToolNGConfigFile=$OPTARG

          # Do a quick check before we begin
          if [ -f "${CrossToolNGConfigFilePath}/${CrossToolNGConfigFile}" ]; then
             printf "${KNRM}${CrossToolNGConfigFilePath}/${CrossToolNGConfigFile} ... ${KGRN} found ${KNRM}\n"
          else
             printf "${KNRM}${CrossToolNGConfigFilePath}/${CrossToolNGConfigFile} ... ${KRED} not found ${KNRM}\n"
             exit 1
          fi
          ;;
          #####################
      b)
          # Check next positional parameter
          # Why would checking for an unbound variable cause an unbound variable?
          set +u
          nextOpt=${!OPTIND}
          set -u
          # existing or starting with dash?
          if [[ -n $nextOpt && $nextOpt != -* ]]; then
             OPTIND=$((OPTIND + 1))

             if [ ${nextOpt} == "raspbian" ] || [ ${nextOpt} == "Raspbian" ]; then
                BuildRaspbianOpt=y
             fi
          else
             BuildToolchainOpt='y'
          fi

          ;;
          #####################
       T)
          ToolchainNameOpt=y
          ToolchainName=$OPTARG

          updateVariables

          ;;
          #####################
       i)
          InstallKernelOpt=y
          ;;
          #####################
   esac
done

# Reset the index for the next getopt optarg
OPTIND=1

while getopts "$OPTSTRING" opt; do
   case $opt in
      h)
          showHelp
          exit 0
          ;;
          #####################
      c)
          if  [ $OPTARG == "Brew" ]; then
             cleanBrew
             exit 0
          fi
          if  [ $OPTARG == "ct-ng" ]; then
             ct-ngMakeClean
             exit 0
          fi
          if  [ $OPTARG == "raspbian" ] || [ $OPTARG == "Raspbian" ]; then
             raspbianClean
             if  [ $BuildRaspbianOpt == 'n' ]; then
                exit 0
             fi
             # so not to do it twicw
             CleanRaspbianOpt='n'
          fi
          if  [ $OPTARG == "realClean" ]; then
             realClean
             exit 0
          fi

          printf "${KRED}Invalid option: -c ${KNRM}$OPTARG${KNRM}\n"
          exit 1
          ;;
          #####################
      b)
          # Check next positional parameter
          # Why would checking for an unbound variable cause an unbound variable?
          set +u
          nextOpt=${!OPTIND}
          set -u
          # existing or starting with dash? 
          if [[ -n $nextOpt && $nextOpt != -* ]]; then
             OPTIND=$((OPTIND + 1))
             # Any other options than raspbian, just pass
             # to ct-ng
             if [ $nextOpt != "raspbian" ] && [ $nextOpt != "Raspbian" ]; then
                # This would be for like 'list'
                buildToolchain $nextOpt
             fi
          else
             createCrossCompilerConfigFile

             # -b alone is build the cross compiler
             
             printf "${KBLU}Checking for working cross compiler first ${KNRM} ... "
             testBuild   # testBuild sets rc
             if [ ${rc} == '0' ]; then
                printf "${KGRN} found ${KNRM}\n"
                printf "To rebuild it again, remove the old one first or ${KNRM}\n"
                if [ $ToolchainNameOpt == 'y' ]; then
                   printf "${KBLU}Execute:${KNRM} ./build.sh -T ${ToolchainName} -b build ${KNRM}\n"
                else
                   printf "${KBLU}Execute:${KNRM} ./build.sh -b build ${KNRM}\n"
                fi
             else
                buildToolchain "build"
             fi
          fi

          # Check to continue and build Raspbian
          if [ $BuildRaspbianOpt == 'n' ]; then
             exit 0
          fi

          if  [ $CleanRaspbianOpt == 'y' ]; then
             raspbianClean
          fi

          printf "${KYEL}Checking for cross compiler again ${KNRM} ... "
          testBuild   # testBuild sets rc
          if [ ${rc} == '0' ]; then
             printf "${KGRN}  found ${KNRM}\n"
          else
             printf "${KRED}  failed ${KNRM}\n"
             exit -1
          fi

          downloadAndBuildzlib

          downloadRaspbianKernel
          downloadElfHeaderForOSX
          configureRaspbianKernel
          cleanupElfHeaderForOSX

          exit 0
          ;;
          #####################
      t)
          printf "${KBLU}Testing toolchain ${ToolchainName} ${KNRM}\n"

          testBuild   # testBuild sets rc
          if [ ${rc} == '0' ]; then
             printf "${KGRN} Wahoo ! it works!! ${KNRM}\n"
          exit 0
          else
             printf "${KRED} Boooo ! it failed :-( ${KNRM}\n"
             exit -1
          fi
          ;;
          #####################
      I)
          # Done in first getopt for proper order
          ;;
          #####################
      V)
          # Done in first getopt for proper order
          ;;
          #####################
      T)
          # Done in first getopt for proper order
          ;;
          #####################
      P)
          export PATH=${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/bin:$BrewHome/bin:$BrewHome/opt/gettext/bin:$BrewHome/opt/bison/bin:$BrewHome/opt/libtool/bin:$BrewHome/opt/gcc/bin:/Volumes/${VolumeBase}/ctng/bin:$PATH
  
          printf "${KNRM}PATH=${PATH}${KNRM}\n"
          printf "./configure  ARCH=arm  CROSS_COMPILE=${CT_TOP_DIR}/$OutputDir/${ToolchainName}/bin/${ToolchainName}- --prefix=${CT_TOP_DIR}/${OutputDir}/${ToolchainName}\n"
    printf "make ARCH=arm --include-dir=${CT_TOP_DIR}/$OutputDir/${ToolchainName}/${ToolchainName}/include CROSS_COMPILE=${CT_TOP_DIR}/$OutputDir/${ToolchainName}/bin/${ToolchainName}-\n"
          exit 0
          ;;
          #####################
       i)
          InstallKernelOpt=y

          updateBrewForEXT2

          createDosBootPVolume
          createRootPVolume

          installRaspbianKernel

          exit 0
          ;;
          #####################
      \?)
          printf "${KRED}Invalid option: ${KNRM}-${OPTARG}\n"
          exit 1
          ;;
          #####################
      :)
          printf "${KRED}Option ${KNRM}-${OPTARG} requires an argument.\n" 
          exit 1
          ;;
          #####################
   esac
done

printf "${KBLU}Here we go ${KNRM} ... \n"

# We will put Brew and ct-ng here too so they dont need rebuilding
# all the time
createCaseSensitiveVolumeBase

# Create a directory to save/reuse tarballs
createTarBallSourcesDir

# Create the case sensitive volume first.
createCaseSensitiveVolume

# OSX is either missing tools or they are too old.
# Solve this with putting brew tools in our own build.
buildBrewTools

printf "${KBLU}Checking for an existing ct-ng ${KNRM} /Volumes/${VolumeBase}/ctng/bin/ct-ng ... "
if [ -x "/Volumes/${VolumeBase}/ctng/bin/ct-ng" ]; then
   printf "${KGRN} found ${KNRM}\n"
   printf "${KYEL}Remove it if you wish to have it rebuilt ${KNRM} or \n"
   if [ $ToolchainNameOpt == 'y' ]; then
      printf "${KBLU}Execute:${KNRM} ./build.sh -T ${ToolchainName} -b ${KNRM}\n"
   else
      printf "${KBLU}Execute:${KNRM} ./build.sh -b ${KNRM}\n"
   fi
   printf "to build the cross compiler\n"

   exit 0
else
   printf "${KGRN} not found ${KNRM}\n"
   printf "${KNRM}Continuing with build\n";
fi

# The 1.23  archive is busted and does not contain CT_Mirror, until
# it is fixed, use git Latest
if [ ${downloadCrosstoolLatestOpt} == 'y' ]; then
   downloadCrossTool_LATEST
else
   downloadCrossTool
fi

patchCrosstool
buildCrosstool
createCrossCompilerConfigFile


exit 0
