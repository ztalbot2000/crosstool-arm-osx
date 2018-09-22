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
#  the web, Most are filled with old disinformation and say that this is futile,
#  use a VM instead.  This is why there are tons of comments through out as
#  I try to navigate all the mindfields. The major ones are:
#
#     1) Old tools, missing tools and libraries like xz,objcopy,elf.h ...
#     2) No ext2,3,4 support.
#     3) HSFX is not case sensitive .
#     4) The number of packages and options are unfathonable.
#     5) Not enough M5 washers.
#
#  The process:
#
#  (1) Create a case sensitive volume using hdiutil and mount it to /Volumes/$Volume[Base]
#      where brew tools and crosstool-ng will be placed so as not to interfere
#      with any existing installations
#
#  (2) Create another case sensitive volume where the cross compilere created with
#      crosstool-ng will be built.
#
#  (3) Download, patch and build Raspbian.
#
#  (4) Blast an image to an SD card that includes Raspbian, LinuxCnC and other tools.
#
#     Start by executingi "bash .build.sh" and follow along.  This tool does
#     try to continue where it left off each time.
#
#
#  License:
#      Please feel free to use this in any way you see fit.
#

# Exit immediately if a command exits with a non-zero status
set -e

# Exit immediately for unbound variables.
set -u

# The process seems to open a lot of files at once. The default is 256. Bump it to 2048.
# Without this you will get an error: no rule to make IBM1388.so
ulimit -n 2048

# If latest is 'y', then git will be used to download crosstool-ng LATEST
# I believe there is a problem with 1.23.0 so for now, this is the default.
# Ticket #931 has been submitted to address this.
# It deals with CT_Mirror being undefined
DownloadCrosstoolLatestOpt='y'

#
# Config. Update below here to suite your specific needs, but all options can be
# specified from command line arguments. See ./build.sh -help.

#
# This is where your §{CrossToolNGConfigFile}.config file is if you have one.
# It would be copied to $CT_TOP_DIR/.config prior to ct-ng menuconfig
# It can be overriden with -f <ConfigFile>. Please do this instead of
# changing it here.
CrossToolNGConfigFile='armv8-rpi3-linux-gnueabihf.config'

# The starting directory where config files and sparse images will be created
ThisToolsStartingPath="${PWD}"

# This will be the name of the toolchain created by crosstools-ng
# It is placed in $CT_TOP_DIR
# The real name is based upon the options you have set in the CrossToolNG
# config file. You will probably need to change this.  You now can do so with
# the option -T <ToolchainName>. The default being armv8-rpi3-linux-gnueabihf
ToolchainName='armv8-rpi3-linux-gnueabihf'

# The version of Stretch to install
RaspbianStretchFile='2018-06-27-raspbian-stretch'

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
SavedSourcesPath="/Volumes/${VolumeBase}/sources"

# The compiler will be placed in /Volumes/<Volume>/x-tools
# It can be overriden with -O <OutputDir>.  Do this instead as 'x-tools' is
# a key word in the .config file with this tool that will automatically get
# changed with the -O <OutputDir> option
OutputDir='x-tools'

# Where the Raspbian kernel will be written to
TargetUSBDevice=''

# Where brew will be placed. An existing brew cannot be used because of
# interferences with macports or fink.
# I spent some time exploring the removal of brew. The thought being
# there was to much overhead.  This turned out to be false.  Brew has
# spent a lifetime determining the correct compile options for all
# of its casks.  The result was almost another brew written from scratch
# that did not behave as good as brew.
# 
BrewHome="/Volumes/${VolumeBase}/brew"
export HOMEBREW_CACHE="${SavedSourcesPath}"
# Never found anything there, but was recommnded when setting HOMEBREW_CACHE
export HOMEBREW_LOG_PATH="${BrewHome}/brew_logs"

# This is required so brew can be installed elsewhere
export BREW_PREFIX="${BrewHome}"
export PKG_CONFIG_PATH="${BREW_PREFIX}"

# This is the crosstools-ng version used by curl to fetch relased version
# of crosstools-ng. I don't know if it works with previous versions and
#  who knows about future ones.
CrossToolVersion='crosstool-ng-1.23.0'

# Changing this affects CT_TOP_DIR which also must be reflected in your
# crosstool-ng .config file
CrossToolSourceDir='crosstool-ng-src'

# Where CNC tools will be compiled
LinuxCNCSrcDir='LinuxCNC-src'
PyCNCSrcDir='PyCNC-src'

# Duplicated to allow altering included ct-ng config files
CT_TOP_DIR='/Volumes/CrossToolNG'
CT_TOP_DIR="/Volumes/${Volume}"

# The   resultant cross compiler goes in the Base
CT_TOP_DIR_BASE="/Volumes/${VolumeBase}"

# Where compiling various sources will be done from
COMPILING_LOCATION="${CT_TOP_DIR}/src"


# A string to hold options given, to be repeated
# This will save checking for them each time
CmdOptionString=''

# Adding to PATH can be exponentially explosive, so just keep three
OriginalPath="${PATH}"
PathWithBrewTools=''
PathWithCrossCompiler=''

# Options to be toggled from command line
# see -help
ToolchainNameOpt='n'
CleanRaspbianOpt='n'
VolumeOpt='n'
OutputDirOpt='n'
SavedSourcesPathOpt='n'
TestHostCompilerOpt='n'
TestCrossCompilerOpt='n'
TestCompilerOnlyOpt='y'
BuildRaspbianOpt='n'
RunCTNGOpt='n'
RunCTNGOptArg='build'
InstallRaspbianOpt='n'
InstallKernelOpt='n'
AddLinuxCNCOpt='n'
AddPyCNCOpt='n'

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
RaspbianSrcDir='Raspbian-src'

function showHelp()
{
cat <<'HELP_EOF'
   This shell script is a front end to crosstool-ng to help build a cross compiler on your Mac.  It downloads all the necessary files to build the cross compiler.  It only assumes you have Xcode command line tools installed.

   Options:
     -V <Volume>     - Instead of /Volumes/CrosstoolNG/ and
                                  /Volumes/CrosstoolNGBase/
                               use
                                  /Volumes/<Volume> and
                                  /Volumes/<Volume>Base
                           Note: To do this the .config file is changed automatically
                                 from CrosstoolNG to <Volume>

     -O <OutputDir>  - Instead of /Volumes/<Volume>Base/x-tools
                               use
                           /Volumes/<Volume>Base/<OutputDir>
                           Note: To do this the .config file is changed automatically
                                 from x-tools  to <OutputDir>
     -T <Toolchain>  - The ToolchainName created.
                       The default used is: armv8-rpi3-linux-gnueabihf
                       The actual result is based on what is in your
                       -f <configFile>
     -S <path>       - A path where sources can be retrieved from. It does not
                       get removed with any clean option. The  default is
                       <Volume>Base/sources
     -c Brew         - Remove all installed Brew tools.
     -c ct-ng        - Run make clean in crosstool-ng path
     -c realClean    - Unmounts the image and removes it. This destroys EVERYTHING!
     -c raspbian     - run make clean in the RaspbianSrcDir.
     -f <configFile> - The name and path of the ct-ng config file to use.
                       Default is armv8-rpi3-linux-gnueabihf.config
     -b              - Build the cross compiler AFTER building the necessary tools
                       and you have defined the crosstool-ng .config file.
     -b <last_step+>    * If last_step+ is specified ct-ng is executed with
                          LAST_SUCCESSFUL_STEP_NAME+ 
                        This is accomplished when CT_DEBUG=y and CT_SAVE_STEPS=y
     -b list-steps      * This could also be list-steps to show steps available. 
     -b raspbian>    - Download and build Raspbian.
     -i raspbian     - Install Raspbian Stretch and kernel on flash device.
     -i kernel       - Install Raspbian kernel on flash device.
     -t              - After the build, run a Hello World test on it.
     -t gcc          - test the gcc in this scripts path.
     
                       The product of which would be: armv8-rpi3-linux-gnueabihf-gcc ...
     -P              - Just Print the PATH variable
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
   local pid=$1
   local spindleCount=0
   local spindleArray=('|' '/' '-' '\')
   local STARTTIME=$(date +%s)

   while ps -p "${pid}" >/dev/null; do
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
      if [[ ${spindleCount} -eq ${#spindleArray[*]} ]]; then
         spindleCount=0
      fi
   done
   printf "\n${KNRM}"

   # Get the true return code of the process
   wait "${pid}"

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
   local ctDir="${CT_TOP_DIR_BASE}/${CrossToolSourceDir}"
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
function cleanRaspbian()
{
   printf "${KBLU}Cleaning raspbian (make mrproper) ${KNRM}\n"

   # Remove our elf.h
   cleanupElfHeaderForOSX

   printf "${KBLU}Checking for ${KNRM} ${CT_TOP_DIR}/${RaspbianSrcDir} ... "
   if [ -d "${CT_TOP_DIR}/${RaspbianSrcDir}" ]; then
      printf "${KGRN} found ${KNRM}\n"
   else
      printf "${KRED} not found ${KNRM}\n"
      exit -1
   fi
   printf "${KBLU}Checking for ${KNRM} ${CT_TOP_DIR}/${RaspbianSrcDir}/linux ... "
   if [ -d "${CT_TOP_DIR}/${RaspbianSrcDir}/linux" ]; then
      printf "${KGRN} found ${KNRM}\n"
   else
      printf "${KRED} not found ${KNRM}\n"
      exit -1
   fi
   cd "${CT_TOP_DIR}/${RaspbianSrcDir}/linux"
   make mrproper
}
function realClean()
{
   # Remove our elf.h
   cleanupElfHeaderForOSX

   # Eject the disk instead of unmounting it or you will have
   # a lot of disks hanging around.  I had 47, Doh!
   if [ -d  "${CT_TOP_DIR_BASE}" ]; then 
      printf "${KBLU}Ejecting ${CT_TOP_DIR_BASE} ${KNRM}\n"
      hdiutil eject "${CT_TOP_DIR_BASE}"
   fi

   # Eject the disk instead of unmounting it or you will have
   # a lot of disks hanging around.  I had 47, Doh!
   if [ -d  "${CT_TOP_DIR}" ]; then 
      printf "${KBLU}Ejecting  ${CT_TOP_DIR} ${KNRM}\n"
      hdiutil eject "${CT_TOP_DIR}"
   fi


   # Since everything is on the image, just remove it does it all
   printf "${KBLU}Removing ${Volume}.sparseimage ${KNRM}\n"
   removeFileWithCheck "${Volume}.sparseimage"
   printf "${KBLU}Removing ${VolumeBase}.sparseimage ${KNRM}\n"
   removeFileWithCheck "${VolumeBase}.sparseimage"
}

# For smaller more permanent stuff
function createCaseSensitiveVolumeBase()
{
   printf "${KBLU}Creating 4G volume for tools mounted as ${CT_TOP_DIR_BASE} ${KNRM} ...\n"
    if [  -d "${CT_TOP_DIR_BASE}" ]; then
       printf "${KYEL}WARNING${KNRM}: Volume already exists: ${CT_TOP_DIR_BASE} ${KNRM}\n"     
       return;
    fi

   if [ -f "${VolumeBase}.sparseimage" ]; then
      printf "${KRED}WARNING:${KNRM}\n"
      printf "         File already exists: ${VolumeBase}.sparseimage ${KNRM}\n"
      printf "         This file will be mounted as ${VolumeBase} ${KNRM}\n"
      
      # Give a couple of seconds for the user to react
      sleep 3

   else
      hdiutil create "${VolumeBase}"           \
                      -volname "${VolumeBase}" \
                      -type SPARSE             \
                      -size 4g                 \
                      -fs HFSX                 \
                      -quiet                   \
                      -puppetstrings
   fi

   hdiutil mount "${VolumeBase}.sparseimage"
}

function createTarBallSourcesDir()
{
    printf "${KBLU}Checking for saved tarballs directory ${KNRM} ${SavedSourcesPath} ..."
    if [ -d "${SavedSourcesPath}" ]; then
       printf "${KGRN} found ${KNRM}\n"
    else
       if [ "${SavedSourcesPathOpt}" = 'y' ]; then
          printf "${KRED} not found - ${KNRM} Cannot continue when saved sources path does not exist: ${SavedSourcesPathOpt}\n"
          exit -1
       fi
       printf "${KYEL} not found -OK ${KNRM}\n"
       printf "${KNRM}Creating ${KNRM} ${SavedSourcesPath} ... "
       mkdir "${SavedSourcesPath}"
       printf "${KGRN} done ${KNRM}\n"
    fi

}

# This is where the cross compiler and Raspbian will go
function createCaseSensitiveVolume()
{
    VolumeDir="${CT_TOP_DIR}"
    printf "${KBLU}Creating volume mounted as ${KNRM} ${VolumeDir} ...\n"
    if [ -d "${VolumeDir}" ]; then
       printf "${KYEL}WARNING${KNRM}: Volume already exists: ${VolumeDir} \n"      
       return;
    fi

   if [ -f "${Volume}.sparseimage" ]; then
      printf "${KRED}WARNING:${KNRM}\n"
      printf "         File already exists: ${Volume}.sparseimage ${KNRM}\n"
      printf "         This file will be mounted as ${Volume} ${KNRM}\n"
      
      # Give a couple of seconds for the user to react
      sleep 3

   else
      hdiutil create "${Volume}"              \
                      -volname "${Volume}"    \
                      -type SPARSE            \
                      -size 32                \
                      -fs HFSX                \
                      -quiet                  \
                      -puppetstrings
   fi

   hdiutil mount "${Volume}.sparseimage"
   
}

function createSrcDirForCompilation()
{
   # A place to compile from
   printf "${KBLU}Checking for:${KNRM} ${COMPILING_LOCATION} ... "
   if [ ! -d "${COMPILING_LOCATION}" ]; then
      mkdir "${COMPILING_LOCATION}"
      printf "${KGRN} created ${KNRM}\n"
   else
      printf "${KGRN} found ${KNRM}\n"
   fi
}

#
# If $BrewHome does not alread contain HomeBrew, download and install it. 
# Install the required HomeBrew packages.
#
# Binutils is for objcopy, objdump, ranlib, readelf
# sed, gawk libtool bash, grep are direct requirements
# pkg-config, pcre are dependancies of grep
# xz is reauired when configuring crosstool-ng
# help2man is reauired when configuring crosstool-ng
# wget  is reauired when configuring crosstool-ng
# wget  requires all kinds of stuff that is auto downloaded by brew. Sorry
# automake is required to fix a compile issue with gettext
# coreutils is for sha512sum
# sha2 is for sha512
# bison on osx was too old (2.3) and gcc compiler did not like it
# findutils is for xargs, needed by make modules in Raspbian
# gmp is for isl
# isl is for gcc
# mpc is for gcc
# gcc for Raspbian to solve error PIE disabled. Absolute addressing (perhaps -mdynamic-no-pic)
#
# for Raspbian tools - libelf ncurses gcc
# for xconfig - QT   (takes hours). That would be up to you.
BrewTools="coreutils findutils libtool pkg-config pcre grep ncurses gettext xz gnu-sed gawk binutils gmp isl mpc help2man autoconf automake bison bash wget sha2 libelf texinfo"

function buildBrewTools()
{
   printf "${KBLU}Checking for HomeBrew tools ${KNRM}\n"
   printf "${KBLU}Checking for our Brew completion flag ${KNRM}  ${BrewHome}.flagBrewComplete ... "
   if [ -f "${BrewHome}/.flagBrewComplete" ]; then
      printf "${KGRN} found ${KNRM}\n"
      printf "${KNRM} Brew will not be updated ${KNRM}\n"
      return
   fi
   printf "${KYEL} not found -OK ${KNRM}\n"
   
   if [ ! -d "${BrewHome}" ]; then
      printf "${KBLU}Installing HomeBrew tools ${KNRM} ...\n"
      mkdir "${BrewHome}"
      cd "${BrewHome}"
      curl -Lsf 'http://github.com/mxcl/homebrew/tarball/master' | tar xz --strip 1 -C "${BrewHome}"

   else
      printf "${KBLU}   - Using existing Brew installation ${KNRM} in ${BrewHome}\n"
   fi

   printf "${KBLU}Checking for Brew log path ${KNRM} ... "
   if [ ! -d "${HOMEBREW_LOG_PATH}" ]; then
      printf "${KYEL} not found -OK ${KNRM}\n"
      printf "${KBLU}Creating brew logs directory: ${KNRM} ${HOMEBREW_LOG_PATH} ... "
      mkdir "${HOMEBREW_LOG_PATH}"
      printf "${KGRN} done ${KNRM}\n"

   else
      printf "${KGRN} found ${KNRM}\n"
   fi

   export PATH="${PathWithBrewTools}"

   printf "${KBLU}Updating HomeBrew tools ${KNRM} ...\n"
   printf "${KRED}Ignore the ERROR: could not link ${KNRM}\n"
   printf "${KRED}Ignore the message "
   printf "Please delete these paths and run brew update ${KNRM}\n"
   printf "${KNRM}They are created by brew as it is not in /local or with sudo \n"
   printf "\n"

   # I dont know why this is true, but tar fails otherwise
   set +e

   printf "${KBLU}Running Brew update ${KNRM} ... Logging to /tmp/brew_update.log \n"
   brew update > '/tmp/brew_update.log' 2>&1 &
   pid="$!"
   waitForPid "${pid}"

   # Exit immediately if a command exits with a non-zero status
   set -e

   if [ "${rc}" != '0' ]; then
      printf "${KRED}Error : [${rc}] ${KNRM} brew update tools failed. Check the log for details\n"
      exit ${rc}
   fi
   printf "${KGRN} done ${KNRM}\n"
   

   # Do not Exit immediately if a command exits with a non-zero status.
   set +e

   
   printf "${KBLU}Installing brew tools. This may take a couple of hours ${KNRM} to ${BrewHome} ... \n"

   # --default-names was deprecated
   brew install ${BrewTools}  --build-from-source --with-real-names 
   printf "${KGRN} Install of Brew Tools done ${KNRM}\n"

   # Exit immediately if a command exits with a non-zero status
   set -e

   printf "${KBLU}Checking for ${KNRM} $BrewHome/bin/gsha512sum ${KNRM} ... "
   if [ ! -f "${BrewHome}/bin/gsha512sum" ]; then
      printf "${KRED} not found ${KNRM}\n"
      exit 1
   fi
   printf "${KGRN} found ${KNRM}\n"
   printf "${KBLU}Checking for ${KNRM} ${BrewHome}/bin/sha512sum ${KNRM} ... "
   if [ ! -f "${BrewHome}/bin/sha512sum" ]; then
      printf "${KYEL} not found -OK ${KNRM}\n"
      printf "${KNRM}Linking gsha512sum to sha512sum ${KNRM}\n"
      ln -s "${BrewHome}/bin/gsha512sum" "${BrewHome}/bin/sha512sum"
   else
      printf "${KGRN} found ${KNRM}\n"
   fi

   printf "${KBLU}Checking for ${KNRM} ${BrewHome}/bin/gsha256sum ${KNRM} ... "
   if [ ! -f "${BrewHome}/bin/gsha256sum" ]; then
      printf "${KRED} not found ${KNRM}\n"
      exit 1
   fi
   printf "${KGRN} found ${KNRM}\n"

   printf "${KBLU}Checking for ${KNRM} ${BrewHome}/bin/sha256sum ${KNRM} ... "
   if [ ! -f "${BrewHome}/bin/sha256sum" ]; then
      printf "${KYEL} not found -OK ${KNRM}\n"
      printf "${KNRM}Linking gsha256sum to sha256sum ${KNRM}\n"
      ln -s "${BrewHome}/bin/gsha256sum" "${BrewHome}/bin/sha256sum"
   else
      printf "${KGRN} found ${KNRM}\n"
   fi

   printf "${KBLU}Checking for ${KNRM} ${BrewHome}/bin/readlink ${KNRM} ... "
   if [ ! -f "${BrewHome}/bin/readlink" ]; then
      printf "${KYEL} not found -OK ${KNRM}\n"
      printf "${KNRM}Linking greadlink to readlink ${KNRM}\n"
      ln -s "${BrewHome}/bin/greadlink" "${BrewHome}/bin/readlink"
   else
      printf "${KGRN} found ${KNRM}\n"
   fi

   printf "${KBLU}Checking for ${KNRM} ${BrewHome}/bin/stat ${KNRM} ... "
   if [ ! -f "${BrewHome}/bin/stat" ]; then
      printf "${KYEL} not found -OK ${KNRM}\n"
      printf "${KNRM}Linking gstat to stat ${KNRM}\n"
      ln -s "${BrewHome}/bin/gstat" "${BrewHome}/bin/stat"
   else
      printf "${KGRN} found ${KNRM}\n"
   fi


   printf "${KBLU}Checking for ${KNRM} ${BrewHome}/bin/grep ${KNRM} ... "
   if [ ! -f "${BrewHome}/bin/grep" ]; then
      printf "${KYEL} not found -OK ${KNRM}\n"
      printf "${KNRM}Linking ggrep to grep ${KNRM}\n"
      ln -s "${BrewHome}/bin/ggrep" "${BrewHome}/bin/grep"
   else
      printf "${KGRN} found ${KNRM}\n"
   fi

   
   printf "${KBLU}Checking for ${KNRM} ${BrewHome}/opt/gcc/bin/gcc-8 ... "
   if [ -f "${BrewHome}/opt/gcc/bin/gcc-8" ]; then
      printf "${KGRN} found ${KNRM}\n"
      printf "${KBLU} Linking gcc-8 tools to gcc ${KNRM} ... "
      rc="n"
      cd "${BrewHome}/opt/gcc/bin"
      for fn in `ls *-8`; do
         local newFn=${fn/-8}
         if [ ! -L "${newFn}" ]; then
            if [ "${rc}" = 'n' ]; then
               printf "${KGRN} found ${KNRM}\n"
            fi
            rc='y'
            printf "${KNRM}linking ${fn} to ${newFn} ... "
            ln -sf "${fn}" "${newFn}"
            printf "${KGRN} done ${KNRM}\n"
         fi
      done
      if [ "${rc}" = 'n' ]; then
         printf "${KGRN}links already in place ${KNRM}\n"
      fi
   else
      printf "${KYEL}Not found -OK ${KNRM}\n"
   fi

   printf "${KGRN}Creating ${KNRM} ${BrewHome}.flagBrewComplete ... "
   touch "${BrewHome}/.flagBrewComplete"
   printf "${KGRN} done ${KNRM}\n"

}
# Brew binutils does not build ld, so rebuild them again
# Trying to build them first before gcc, causes ld not
# to be built.
function buildBinutilsForHost()
{
   local binutilsDir='binutils-2.30'
   local binutilsFile='binutils-2.30.tar.xz'
   local binutilsURL="https://mirror.sergal.org/gnu/binutils/${binutilsFile}"

   printf "${KBLU}Checking for a working ld ${KNRM} ... "
   if [ -x "${BrewHome}/bin/ld" ]; then
      printf "${KGRN} found ${KNRM}\n"
      return
   fi
   printf "${KYEL} not found -OK ${KNRM}\n"

   printf "${KBLU}Checking for a existing binutils source ${KNRM} ${COMPILING_LOCATION}/${binutilsDir} ... "
   if [ -d "${COMPILING_LOCATION}/${binutilsDir}" ]; then
      printf "${KGRN} found ${KNRM}\n"
   else
      printf "${KYEL} not found -OK ${KNRM}\n"

      printf "${KBLU}Checking for a saved ${binutilsFile} ${KNRM} ... "
      if [ -f "${SavedSourcesPath}/${binutilsFile}" ]; then
         printf "${KGRN} found ${KNRM}\n"
      else
         printf "${KYEL} not found -OK ${KNRM}\n"
         printf "${KBLU}Downloading ${binutilsFile} ${KNRM} ... "
         curl -Lsf "${binutilsURL}" -o "${SavedSourcesPath}/${binutilsFile}"
         printf "${KGRN} done ${KNRM}\n"
      fi
      printf "${KBLU}Extracting ${binutilsFile} ${KNRM} ... Logging to /tmp/binutils_extract.log\n"
      # I dont know why this is true, but configure fails otherwise
      set +e

      tar -xzf "${SavedSourcesPath}/${binutilsFile}" -C "${COMPILING_LOCATION}" > '/tmp/binutils_extract.log' 2>&1 &
      pid="$!"

      waitForPid "${pid}"

      # Exit immediately if a command exits with a non-zero status
      set -e

      if [ "${rc}" != '0' ]; then
         printf "${KRED}Error : [${rc}] ${KNRM} extract failed. Check the log for details\n"
         exit $rc
      fi
      printf "${KGRN} done ${KNRM}\n"
   fi
   
   printf "${KBLU}Configuring ${binutilsDir} ${KNRM} ... Logging to /tmp/binutils_configure.log\n"

   # I dont know why this is true, but configure fails otherwise
   set +e

   cd "${COMPILING_LOCATION}/${binutilsDir}"
   
   EPREFIX='' ./configure --prefix="${BrewHome}" --enable-ld=yes --target=x86_64-unknown-elf --disable-werror --enable-multilib --program-prefix='' > /tmp/binutils_configure.log 2>&1 &
   pid="$!"

   waitForPid "${pid}"

   # Exit immediately if a command exits with a non-zero status
   set -e

   if [ "${rc}" != '0' ]; then
      printf "${KRED}Error : [${rc}] ${KNRM} configure failed. Check the log for details\n"
      exit $rc
   fi
   printf "${KGRN} done ${KNRM}\n"

   printf "${KBLU}Compiling ${binutilsDir}  ${KNRM} ... Logging to /tmp/binutils_compile.log\n"

   # I dont know why this is true, but configure fails otherwise
   set +e

   make > '/tmp/binutils_compile.log' 2>&1 &
   pid="$!"
   waitForPid "${pid}"

   # Exit immediately if a command exits with a non-zero status
   set -e

   if [ "${rc}" != '0' ]; then
      printf "${KRED}Error : [${rc}] ${KNRM} build failed. Check the log for details\n"
      exit $rc
   fi
   printf "${KGRN} done ${KNRM}\n"

   printf "${KBLU}Installing ${binutilsDir} ${KNRM} ... Logging to /tmp/binutils_install.log\n"

   # I dont know why this is true, but make fails otherwise
   set +e

   make install > '/tmp/binutils_install.log' 2>&1 &
   pid="$!"
   waitForPid "${pid}"

   # Exit immediately if a command exits with a non-zero status
   set -e

   if [ "${rc}" != '0' ]; then
      printf "${KRED}Error : [${rc}] ${KNRM} configure failed. Check the log for details\n"
      exit $rc
   fi
   printf "${KGRN} done ${KNRM}\n"

}

function downloadCrossTool()
{
   printf "${KBLU}Downloading crosstool-ng ${KNRM} to ${COMPILING_LOCATION} \n"
   local CrossToolArchive="${CrossToolVersion}.tar.bz2"
   if [ -f "${SavedSourcesPath}/${CrossToolArchive}" ]; then
      printf "   -Using existing archive ${CrossToolArchive} ${KNRM}\n"
   else
      CrossToolUrl="http://crosstool-ng.org/download/crosstool-ng/${CrossToolArchive}"
      curl -L -o "${SavedSourcesPath}/${CrossToolArchive}" "${CrossToolUrl}"
   fi

   if [ -d "${COMPILING_LOCATION}/${CrossToolSourceDir}" ]; then
      printf "   ${KRED}WARNING${KNRM} - ${CrossToolSourceDir} exists and will be used.\n"
      printf "   ${KRED}WARNING${KNRM} - Remove it to start fresh\n"
   else
      tar -xf "${SavedSourcesPath}/${CrossToolArchive}" \
         -C "${COMPILING_LOCATION}/${CrossToolSourceDir}"
   fi
}
function downloadCrossTool_LATEST()
{  
   export PATH="${PathWithBrewTools}"
   
   cd "${COMPILING_LOCATION}"
   printf "${KBLU}Downloading crosstool-ng ${KNRM} to ${COMPILING_LOCATION} \n"

   if [ -d "${COMPILING_LOCATION}/${CrossToolSourceDir}" ]; then 
      printf "   ${KRED}WARNING${KNRM} - ${CrossToolSourceDir} exists and will be used.\n"
      printf "   ${KRED}WARNING${KNRM} - Remove it to start fresh\n"
      return
   fi

   local CrossToolUrl="https://github.com/crosstool-ng/crosstool-ng.git"
   CrossToolArchive=${CrossToolVersion}_latest.tar.xz
   
   if [ -f "${SavedSourcesPath}/${CrossToolArchive}" ]; then
      printf "   -Using existing archive ${CrossToolArchive} ${KNRM}\n"
      
      printf "${KBLU}Decompressing ${KNRM} ${CrossToolArchive} ... "
      
      tar -xf "${SavedSourcesPath}/${CrossToolArchive}" -C "${COMPILING_LOCATION}"
      
      printf "${KGRN} done ${KNRM}\n"    
      
   else
      git clone "${CrossToolUrl}"  "${COMPILING_LOCATION}/${CrossToolSourceDir}"
   fi
   
   if [ ! -f "${SavedSourcesPath}/${CrossToolArchive}" ]; then
      printf "${KBLU}saving ${KNRM} ${CrossToolArchive} ... "
      
      tar -cJf "${SavedSourcesPath}/${CrossToolArchive}" \
         "${COMPILING_LOCATION}/${CrossToolSourceDir}"
      
      printf "${KGRN} done ${KNRM}\n"
   fi    

   # We need to creat the configure tool
   printf "${KBLU}Running  crosstool bootstrap in ${KNRM} ${COMPILING_LOCATION} \n"
   cd "${COMPILING_LOCATION}/${CrossToolSourceDir}"

   # crosstool-ng-1.23.0 still has CT_Mirror
   # git checkout -b $CrossToolVersion

   ./bootstrap
}

function patchConfigFileForVolume()
{
    printf "${KBLU}Patching .config file for -V option ${KNRM} in ${COMPILING_LOCATION} ... "

    if [ "${VolumeOpt}" = 'y' ]; then
       printf "${KGRN} required ${KNRM}\n"
       printf "${KBLU}Changing /Volumes/CrossToolNG ${KNRM} to /Volumes/${Volume} ... "

       if [ -f "${COMPILING_LOCATION}/.config" ]; then
          sed -i.bak -e's/CrossToolNG/'${Volume}'/g' "${COMPILING_LOCATION}/.config"
          printf "${KGRN} done ${KNRM}\n"
       else
           printf "${KRED} not found ${KNRM}\n"
           printf "${KRED} aborting ${KNRM}\n"
           exit -1
       fi
    else 
       printf "${KYEL} not specified. not required ${KNRM}\n"
       printf "${KNRM}.config file not being patched as -V was not specified\n"
    fi
}

function patchConfigFileForOutputDir()
{
    printf "${KBLU}Patching .config file for -O option ${KNRM} in ${COMPILING_LOCATION} ... "
     
    if [ "${OutputDirOpt}" = 'y' ]; then
       printf "${KGRN} required ${KNRM}\n"
       printf "${KBLU}Changing x-tools ${KNRM} to ${OutputDir} ... "
       if [ -f "${COMPILING_LOCATION}/.config" ]; then
           sed -i.bak2 -e's/x-tools/'${OutputDir}'/g' "${COMPILING_LOCATION}/.config"
           printf "${KGRN} done ${KNRM}\n"
       else
           printf "${KRED} not found ${KNRM}\n"
           printf "${KRED} aborting ${KNRM}\n"
           exit -1
       fi
    else
       printf "${KGRN} not required ${KNRM}\n"
       printf "${KNRM}.config file not being patched as -O was not specified\n"
    fi

}

function patchConfigFileForSavedSourcesPath()
{
    printf "${KBLU}Patching .config file for -S ootion ${KNRM} in ${COMPILING_LOCATION} ... "
    if [ "${SavedSourcesPathOpt}" = 'y' ]; then
       printf "${KGRN} required ${KNRM}\n"
       printf "${KBLU}Changing ${CT_TOP_DIR}/sources ${KNRM} to ${SavedSourcesPath} ... "
       if [ -f "${COMPILING_LOCATION}/.config" ]; then
          # Since a path may have a slash, use a  pound sign as a delimeter
          sed -i.bak3 -e's#CT_LOCAL_TARBALLS_DIR="/Volumes/'${VolumeBase}'/sources"#CT_LOCAL_TARBALLS_DIR="'${SavedSourcesPath}'"#g' "${COMPILING_LOCATION}/.config" 
          
          printf "${KGRN} done ${KNRM}\n"
       else
          printf "${KRED} not found ${KNRM}\n"
          printf "${KRED} aborting ${KNRM}\n"
          exit -1
       fi
    else
       printf "${KYEL} not specified. not required ${KNRM}\n"
       printf "${KNRM}.config file not being patched as -S was not specified\n"
    fi
}

function patchCrosstool()
{
    printf "${KBLU}Patching crosstool-ng ${KNRM}\n"
    if [ -x "${CT_TOP_DIR_BASE}/ctng/bin/ct-ng" ]; then
      printf "${KYEL}    - found existing ct-ng. Using it instead ${KNRM}\n"
      return
    fi

    cd "${COMPILING_LOCATION}/${CrossToolSourceDir}"
    printf "${KBLU}Patching crosstool-ng ${KNRM} in ${PWD} \n"

    printf "${KNRM}   -No Patches required.\n"
    
# patch required with crosstool-ng-1.17
# left here as an example of how it was done.
#    sed -i .bak '6i\
##include <stddef.h>' kconfig/zconf.y
}

function compileCrosstool()
{
   printf "${KBLU}Configuring crosstool-ng ${KNRM} in ${PWD} \n"
   if [ -x "${CT_TOP_DIR_BASE}/ctng/bin/ct-ng" ]; then
      printf "${KGRN}    - found existing ct-ng. Using it instead ${KNRM}\n"
      return
   fi
   
   export PATH="${PathWithBrewTools}"
   
   cd "${COMPILING_LOCATION}/${CrossToolSourceDir}"


   # It is strange that gettext is put in opt
   gettextDir="${BrewHome}/opt/gettext"
   
   printf "${KBLU} Executing configure for crosstool-ng ${KNRM} --with-libintl-prefix ... \n"

   # export LDFLAGS
   # export CPPFLAGS

   # I dont know why this is true, but configure fails otherwise
   set +e

   # --with-libintl-prefix should have been enough, but it seems LDFLAGS and
   # CPPFLAGS is required too to fix libintl.h not found
   LDFLAGS="  -L${BrewHome}/opt/gettext/lib -lintl " \
   CPPFLAGS=" -I${BrewHome}/opt/gettext/include"     \
   ./configure --with-libintl-prefix=${gettextDir}   \
               --prefix="${CT_TOP_DIR_BASE}/ctng"    \
   > /tmp/ct-ng_config.log 2>&1 &
   pid="$!"
   waitForPid "${pid}"

   # Exit immediately if a command exits with a non-zero status
   set -e

   if [ "${rc}" != '0' ]; then
      printf "${KRED}Error : [${rc}] ${KNRM} configure failed. Check the log for details \n"
      exit $rc
   fi
   printf "${KGRN} Configure of crosstool-ng is done ${KNRM}\n"

   printf "${KBLU}Compiling crosstool-ng ${KNRM} in ${PWD} ... Logging to /tmp/ctng_build.log \n"

   # I dont know why this is true, but make fails otherwise
   set +e

   make > '/tmp/ctng_build.log' 2>&1 &
   pid="$!"
   waitForPid "${pid}"

   # Exit immediately if a command exits with a non-zero status
   set -e

   if [ "${rc}" != '0' ]; then
      printf "${KRED}Error : [${rc}] ${KNRM} build failed. Check the log for details \n"
      exit $rc
   fi
   printf "${KGRN} done ${KNRM}\n"

   printf "${KBLU}Installing  crosstool-ng ${KNRM}in ${CT_TOP_DIR_BASE}/ctng ... Logging to /tmp/ctng_install.log \n"

   # I dont know why this is true, but make fails otherwise
   set +e

   make install > '/tmp/ctng_install.log' 2>&1 &
   pid="$!"
   waitForPid "${pid}"

   # Exit immediately if a command exits with a non-zero status
   set -e

   if [ "${rc}" != '0' ]; then
      printf "${KRED}Error : [${rc}] ${KNRM} install failed. Check the log for details \n"
      exit $rc
   fi
   printf "${KGRN}Compilation of ct-ng is Complete ${KNRM}\n"
}

function createCrossCompilerConfigFile()
{

   cd "${COMPILING_LOCATION}"

   printf "${KBLU}Checking for ct-ng config file ${KNRM} ${COMPILING_LOCATION}/.config ... "
   if [ -f  "${COMPILING_LOCATION}/.config" ]; then
      printf "${KGRN} found ${KNRM}\n"
      printf "${KYEL}Using existing .config file. ${KNRM}\n"
      printf "${KNRM}Remove it if you wish to start over. \n"
      return
   else
      printf "${KYEL} not found -OK ${KNRM} \n"
   fi
   

   printf "${KBLU}Checking for an existing toolchain config file: ${KNRM} ${ThisToolsStartingPath}/${CrossToolNGConfigFile} ... \n"
   if [ -f "${ThisToolsStartingPath}/${CrossToolNGConfigFile}" ]; then
      printf "${KNRM}   - Using ${ThisToolsStartingPath}/${CrossToolNGConfigFile} \n"
      cp "${ThisToolsStartingPath}/${CrossToolNGConfigFile}"  "${COMPILING_LOCATION}/.config"

      cd "${COMPILING_LOCATION}"
      
      patchConfigFileForVolume
      
      patchConfigFileForOutputDir

      patchConfigFileForSavedSourcesPath

   else
      printf "${KNRM}   - None found ${KNRM}\n"
   fi

cat <<'CONFIG_EOF'

NOTES: on what to set in config file, taken from
https://gist.github.com/h0tw1r3/19e48ae3021122c2a2ebe691d920a9ca

- Paths and misc options
    - Set "Prefix directory" to the real values of:
        /Volumes/$VolumeBase/$OutputDir/${CT_TARGET}

- Target options
    By default this script builds the configuration for armv8-rpi3-linux-gnueabihf as this is my focus; However, crosstool-ng can build so many different types of cross compilers.  If you are interested in them, check out the samples with:

      ct-ng list-samples

    You could also just go to the crosstool-ng-src/samples directory and peruse them all.

   At least using this script will help you try configurations more easily.
   

CONFIG_EOF

   # Give the user a chance to digest this
   sleep 5

   # Use 'menuconfig' target for the fine tuning.

   # It seems ct-ng menuconfig dies without some kind of target
   export CT_TARGET='changeMe'
   ct-ng menuconfig

   printf "${KBLU}Once your finished tinkering with ct-ng menuconfig ${KNRM}\n"
   printf "${KBLU}to contineu the build ${KNRM}\n"
   printf "${KBLU}Execute: ${KNRM} ./build.sh ${CmdOptionString} -b \n"   

}

function buildCTNG()
{
   printf "${KBLU}Checking for an existing ct-ng ${KNRM} ${CT_TOP_DIR_BASE}/ctng/bin/ct-ng ... "
   if [ -x "${CT_TOP_DIR_BASE}/ctng/bin/ct-ng" ]; then
      printf "${KGRN} found ${KNRM}\n"
      printf "${KYEL}Remove it if you wish to have it rebuilt ${KNRM}\n"
      return
   else
      printf "${KYEL} not found -OK ${KNRM}\n"
      printf "${KNRM}Continuing with build \n"
   fi

   # The 1.23  archive is busted and does not contain CT_Mirror, until
   # it is fixed, use git Latest
   if [ "${DownloadCrosstoolLatestOpt}" = 'y' ];    then
      downloadCrossTool_LATEST
   else
      downloadCrossTool
   fi

   patchCrosstool
   compileCrosstool
}

function runCTNG()
{
   printf "${KBLU}Building Cross Compiler toolchain ${KNRM}\n"
   printf "${KBLU}Checking if ${ToolchainName}-gcc already exists ${KNRM} ... "
   testBuild
   if [ "${rc}" = '0' ]; then
      printf "${KGRN} found ${KNRM}"
      printf "${KNRM} To rebuild it, remove the old first \n"
      return
   else
      printf "${KYEL} not found -OK ${KNRM}"
      printf "${KNRM} Continuing with the build \n"
   fi

   createCrossCompilerConfigFile

   cd "${COMPILING_LOCATION}"
   
   printf "${KBLU}Checking for:${KNRM} ${COMPILING_LOCATION}/.config ... "
   if [ ! -f "${COMPILING_LOCATION}/.config" ]; then
      printf "${KRED}ERROR: You have still not created a: ${KNRM}"
      printf "${COMPILING_LOCATION}/.config file. ${KNRM}\n"
      printf "${KNRM}Change directory to ${COMPILING_LOCATION}\n"
      printf "${KNRM}And run: ./ct-ng menuconfig \n"
      printf "${KNRM}Before continuing with the build. \n"

      exit -1
   else
      printf "${KGRN} found ${KNRM}\n"
   fi
   export PATH="${PathWithBrewTools}"

   if [ "${RunCTNGOptArg}" = 'list-steps' ]; then
      ct-ng "${RunCTNGOptArg}"
      return
   fi
   if [ "${RunCTNGOptArg}" = 'build' ]; then
      printf "${KBLU} Executing ct-ng build to build the cross compiler ${KNRM}\n"
   else
      printf "${KBLU} Executing ct-ng ${RunCTNGOptArg} ${KNRM}\n"
   fi
      
   ct-ng "${RunCTNGOptArg}" 

   printf "${KNRM}And if all went well, you are done! Go forth and cross compile \n"
   printf "Raspbian if you so wish with: ./build.sh ${CmdOptionString} -b Raspbian \n"
}

function buildLibtool()
{   
    cd "${COMPILING_LOCATION}/libelf"
    # ./configure --prefix=${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}
    ./configure  -prefix="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}"  --host="${ToolchainName}"
    make
    make install
}

function downloadAndBuildzlibForTarget()
{
   local zlibFile='zlib-1.2.11.tar.gz'
   local zlibURL="https://zlib.net/${zlibFile}"

   printf "${KBLU}Checking for Cross Compiled ${KNRM} zlib.h and libz.a ... "
   if [ -f "${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/include/zlib.h" ] && 
      [ -f  "${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/lib/libz.a" ]; then
      printf "${KGRN} found ${KNRM}\n"
      return
   fi
   printf "${KYEL} not found -OK ${KNRM}\n"

   printf "${KBLU}Checking for ${KNRM} ${COMPILING_LOCATION}/zlib-1.2.11 ... "
   if [ -d "${COMPILING_LOCATION}/zlib-1.2.11" ]; then
      printf "${KGRN} found ${KNRM}\n"
      printf "${KNRM} Using existing zlib source ${KNRM}\n"
   else
      printf "${KYEL} not found -OK ${KNRM}\n"
      cd "${COMPILING_LOCATION}"
      printf "${KBLU}Checking for saved ${KNRM} ${zlibFile} ... "
      if [ -f "${SavedSourcesPath}/${zlibFile}" ]; then
         printf "${KGRN} found ${KNRM}\n"
      else
         printf "${KYEL} not found -OK ${KNRM}\n"
         printf "${KBLU}Downloading ${KNRM} ${zlibFile} ... "
         curl -Lsf "${zlibURL}" -o "${SavedSourcesPath}/${zlibFile}"
         printf "${KGRN} done ${KNRM}\n"
      fi
      printf "${KBLU}Decompressing ${KNRM} ${zlibFile} ... "
      tar -xzf "${SavedSourcesPath}/${zlibFile}" -C "${COMPILING_LOCATION}"
      printf "${KGRN} done ${KNRM}\n"
   fi

    printf "${KBLU} Configuring zlib ${KNRM} Logging to /tmp/zlib_config.log \n"
    cd "${COMPILING_LOCATION}/zlib-1.2.11"

    # I dont know why this is true, but configure fails otherwise
    set +e
    
    CHOST=${ToolchainName} ./configure \
          --prefix="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}" \
          --static \
          --libdir="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/lib" \
          --includedir="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/include" \
    > /tmp/zlib_config.log 2>&1 &

    pid="$!"
    waitForPid "${pid}"

    # Exit immediately if a command exits with a non-zero status
    set -e

    if [ "${rc}" != '0' ]; then
       printf "${KRED}Error : [${rc}] ${KNRM} configure failed. Check the log for details \n"
       exit $rc
    fi

    printf "${KBLU} Building zlib ${KNRM} Logging to /tmp/zlib_build.log \n"

    # I dont know why this is true, but build fails otherwise
    set +e
    make > '/tmp/zlib_build.log' 2>&1 &

    pid="$!"
    waitForPid "${pid}"

    # Exit immediately if a command exits with a non-zero status
    set -e

    if [ "${rc}" != '0' ]; then
       printf "${KRED}Error : [${rc}] ${KNRM} build failed. Check the log for details \n"
       exit $rc
    fi

    printf "${KBLU} Installing zlib ${KNRM} Logging to /tmp/zlib_install.log \n"

    # I dont know why this is true, but install fails otherwise
    set +e
    make install > '/tmp/zlib_install.log' 2>&1 &

    pid="$!"
    waitForPid "${pid}"
 
    # Exit immediately if a command exits with a non-zero status
    set -e

    if [ "${rc}" != '0' ]; then
       printf "${KRED}Error : [${rc}] ${KNRM} install failed. Check the log for details \n"
       exit $rc
    fi

}

function downloadElfLibrary()
{
   local elfLibURL='https://github.com/WolfgangSt/libelf.git'

   cd "${COMPILING_LOCATION}"
   printf "${KBLU}Downloading libelf latest ${KNRM} to ${PWD}\n"

   if [ -d 'libelf' ]; then
      printf "${KRED}WARNING ${KNRM}Path already exists libelf ${KNRM}\n"
      printf "        A fetch will be done instead to keep tree up to date\n"
      printf "\n"
      cd 'libelf'
      git fetch
    
   else
      git clone --depth=1 "${elfLibURL}"
   fi
}

function testBuild()
{
   export PATH="${PathWithCrossCompiler}"

   local gpp="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/bin/${ToolchainName}-g++"
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
  cout << "Hello ARM World!";
  return 0;
}
HELLO_WORLD_EOF


   ${ToolchainName}-g++ -fno-exceptions '/tmp/HelloWorld.cpp' -o '/tmp/HelloWorld'
   rc=$?

}

function testHostCompilerForpthreads()
{
cat <<'TEST_PTHREADS_EOF' > /tmp/pthreadsWorld.c

#include <unistd.h>     /* Symbolic Constants */
#include <sys/types.h>  /* Primitive System Data Types */ 
#include <errno.h>      /* Errors */
#include <stdio.h>      /* Input/Output */
#include <stdlib.h>     /* General Utilities */
#include <pthread.h>    /* POSIX Threads */
#include <string.h>     /* String handling */

/* prototype for thread routine */
void print_message_function ( void *ptr );

/* struct to hold data to be passed to a thread
   this shows how multiple data items can be passed to a thread */
typedef struct str_thdata
{
    int thread_no;
    char message[100];
} thdata;

int main()
{
    pthread_t thread1, thread2;  /* thread variables */
    thdata data1, data2;         /* structs to be passed to threads */
    
    /* initialize data to pass to thread 1 */
    data1.thread_no = 1;
    strcpy(data1.message, "Hello pthreads World!");
    
    /* initialize data to pass to thread 2 */
    data2.thread_no = 2;
    strcpy(data2.message, "Hi pthreads World!");
    
    /* create threads 1 and 2 */    
    pthread_create (&thread1, NULL, (void *) &print_message_function, (void *) &data1);
    pthread_create (&thread2, NULL, (void *) &print_message_function, (void *) &data2);

    /* Main block now waits for both threads to terminate, before it exits
       If main block exits, both threads exit, even if the threads have not
       finished their work */ 
    pthread_join(thread1, NULL);
    pthread_join(thread2, NULL);
              
    /* exit */  
    exit(0);
} /* main() */

/**
 * print_message_function is used as the start routine for the threads used
 * it accepts a void pointer 
**/
void print_message_function ( void *ptr )
{
    thdata *data;            
    data = (thdata *) ptr;  /* type cast to a pointer to thdata */
    
    /* do the work */
    printf("Thread %d says %s \n", data->thread_no, data->message);
    
    pthread_exit(0); /* exit */
} /* print_message_function ( void *ptr ) */



TEST_PTHREADS_EOF


   printf "${KBLU}Testing Compiler in PATH for pthreads ${KNRM} CMD = gcc /tmp/pthreadsWorld.c -o /tmp/pthreadsWorld ... "

   gcc /tmp/pthreadsWorld.c -o /tmp/pthreadsWorld
   rc=$?
   if [ "${rc}" != '0' ]; then
      printf "${KRED} failed ${KNRM}\n"
      return ${rc}
   fi
   printf "${KGRN} passed ${KNRM}\n"

   printf "${KBLU}Testing executable for pthreads ${KNRM} CMD = /tmp/pthreadsWorld \n"
   /tmp/pthreadsWorld
   rc=$?
}

function testHostCompilerForPIE()
{

cat <<'TEST_PIE_EOF' > /tmp/PIEWorld.cpp
#include <iostream>
using namespace std;

int local_global_var = 0x20;
 
int local_global_func(void) { return 0x30; }
 
int
main(void) {
    int x = local_global_func();
    local_global_var = 0x10;

    cout << "Hello PIE world!\n";
    return 0;
}

TEST_PIE_EOF


   printf "${KBLU}Testing Compiler in PATH for pie ${KNRM} CMD = g++ /tmp/PIEWorld.cpp -o /tmp/PIEWorld ... "

   g++ /tmp/PIEWorld.cpp -o /tmp/PIEWorld
   rc=$?
   if [ "${rc}" != '0' ]; then
      printf "${KRED} failed ${KNRM}\n"
      return ${rc}
   fi
   printf "${KGRN} passed ${KNRM}\n"

   printf "${KBLU}Testing executable for pie ${KNRM} CMD = /tmp/PIEWorld \n"
   /tmp/PIEWorld
   rc=$?
}

function testHostgcc()
{

   printf "${KBLU}Finding Compiler in PATH ${KNRM} CMD = which g++ ... "
   local whichgcc=$(which g++)
   if [ "${whichgcc}" = '' ]; then
      printf "${KRED} failed ${KNRM}\n"
      printf "${KRED} No executable compiler found. ${KNRM}\n"
      rc='-1'
      return
   fi
   printf "${KGRN} found: ${KNRM} ${whichgcc}\n"

cat <<'HELLO_WORLD_EOF' > /tmp/HelloWorld.cpp
#include <iostream>
using namespace std;

int main ()
{
  cout << "Hello World!\n";
  return 0;
} 
HELLO_WORLD_EOF

   printf "${KBLU}Testing Compiler in PATH ${KNRM} CMD = g++ /tmp/HelloWorld.cpp -o /tmp/HelloWorld ... "

   g++ /tmp/HelloWorld.cpp -o /tmp/HelloWorld
   rc=$?
   if [ ${rc} != '0' ]; then
      printf "${KRED} failed ${KNRM}\n"
      return ${rc}
   fi
   printf "${KGRN} passed ${KNRM}\n"

   printf "${KBLU}Testing executable ${KNRM} CMD = /tmp/HelloWorld \n"
   /tmp/HelloWorld
   rc=$?


}

function testHostCompiler()
{
   printf "${KBLU}Running Host Compiler tests ${KNRM}\n"
   export PATH="${PathWithBrewTools}"

   testHostgcc 
   if [ "${rc}" != '0' ]; then
      printf "${KRED} Boooo ! it failed :-( ${KNRM}\n"
      exit ${rc}
   fi

   testHostCompilerForPIE 
   if [ "${rc}" != '0' ]; then
      printf "${KRED} Boooo ! it failed :-( ${KNRM}\n"
      exit ${rc}
   fi

   testHostCompilerForpthreads
   if [ "${rc}" != '0' ]; then
      printf "${KRED} Boooo ! it failed :-( ${KNRM}\n"
      exit ${rc}
   fi

   printf "${KGRN} Wahoo ! it works!! ${KNRM}\n"

}
function testCrossCompiler()
{
   printf "${KBLU}Testing toolchain ${ToolchainName} ${KNRM}\n"

   testBuild   # testBuild sets rc
   if [ "${rc}" = '0' ]; then
      printf "${KGRN} Wahoo ! it works!! ${KNRM}\n"
      exit 0
   else
      printf "${KRED} Boooo ! it failed :-( ${KNRM}\n"
      exit -1
   fi
}

function buildCrossCompiler()
{
   createCrossCompilerConfigFile
   printf "${KBLU}Checking for working cross compiler first ${KNRM} ${ToolchainName}-g++ ... "
   testBuild   # testBuild sets rc
   if [ "${rc}" = '0' ]; then
      printf "${KGRN} found ${KNRM}\n"
      if [ "${BuildRaspbianOpt}" = 'y' ]; then
         return
      fi
      printf "${KNRM}To rebuild it again, remove the old one first ${KBLU}or ${KNRM}\n"
      printf "${KBLU}Execute:${KNRM} ./build.sh ${CmdOptionString} -b Raspbian ${KNRM}\n"
      printf "${KNRM}to start building Raspbian \n"

   else
      runCTNG
   fi
   
}

function downloadRaspbianKernel()
{
   local RaspbianURL='https://github.com/raspberrypi/linux.git'

   printf "${KMAG}*******************************************************************************${KNRM}\n"
   printf "${KMAG}* WHEN CONFIGURING THE RASPIAN KERNEL CHECK THAT THE \n"
   printf "${KMAG}*  COMPILER PREFIX IS: ${KRED} ${ToolchainName}-  ${KNRM}\n"
   printf "${KMAG}*******************************************************************************${KNRM}\n"

   # This is so very important that we must make sure you remember to set the compiler prefix
   # Maybe at a later date this will be automated
   # read -p 'Press any key to continue'
   sleep 5


   cd "${COMPILING_LOCATION}"
   printf "${KBLU}Downloading Raspbian Kernel latest ${KNRM} \n"

   
   printf "${KBLU}Checking for ${KNRM} ${RaspbianSrcDir} ... "
   if [ ! -d "${RaspbianSrcDir}" ]; then
      printf "${KYEL} not found -OK ${KNRM}\n"
      printf "${KBLU}Creating ${KNRM}${RaspbianSrcDir} ... "
      mkdir "${RaspbianSrcDir}"
      printf "${KGRN} done ${KNRM}\n"
   else
      printf "${KGRN} found ${KNRM}\n"
   fi

   cd "${COMPILING_LOCATION}/${RaspbianSrcDir}"

   printf "${KBLU}Checking for ${KNRM} ${RaspbianSrcDir}/linux ... "
   if [ -d "${COMPILING_LOCATION}/${RaspbianSrcDir}/linux" ]; then
      cd "${COMPILING_LOCATION}/${RaspbianSrcDir}/linux"
      printf "${KGRN} found ${KNRM}\n"
      printf "${KRED}WARNING ${KNRM}Path already exists ${RaspbianSrcDir} ${KNRM}\n"
      cd "${COMPILING_LOCATION}/${RaspbianSrcDir}/linux"
      
   else
      printf "${KYEL} not found -OK ${KNRM}\n"
      printf "${KBLU}Checking for saved ${KNRM} Raspbian.tar.xz ... "
      if [ -f "${SavedSourcesPath}/Raspbian.tar.xz" ]; then
         printf "${KGRN} found ${KNRM}\n"

         cd "${COMPILING_LOCATION}/${RaspbianSrcDir}"
         printf "${KBLU}Extracting saved ${KNRM} ${SavedSourcesPath}/Raspbian.tar.xz ... Logging to /tmp/Raspbian_extract.log \n"

         # I dont know why this is true, but tar fails otherwise
         set +e
         tar -xzf "${SavedSourcesPath}/Raspbian.tar.xz"  > '/tmp/Raspbian_extract.log' 2>&1 &

         pid="$!"
         waitForPid "${pid}"

         # Exit immediately if a command exits with a non-zero status
         set -e

         if [ "${rc}" != '0' ]; then
            printf "${KRED}Error : [${rc}] ${KNRM} extract failed. \n"
            exit $rc
         fi
 
         printf "${KGRN} done ${KNRM}\n"
         
      else
         printf "${KYEL} not found -OK${KNRM}\n"
         printf "${KBLU}Cloning Raspbian from git ${KNRM} \n"
         printf "${KBLU}This will take a while, but a copy will ${KNRM} \n"
         printf "${KBLU}be saved for the future. ${KNRM} \n"
         cd "${COMPILING_LOCATION}/${RaspbianSrcDir}"

         # results in git branch ->
         #            4.14.y
         #            and all remotes, No mptcp
         # git clone -recursive ${RaspbianURL}

         # results in git branch -> 
         #            rpi-4.14.y
         #            remotes/origin/HEAD -> origin/rpi-4.14.y
         #            remotes/origin/rpi-4.14.y
         # git clone --depth=1 ${RaspbianURL} 

         # So why no depth? There seems to be an issue with dtbs
         # not being compiled on OSX because of the option.
         # Thankfully we save a copy and as this script is
         # re-enterrit, you can always update the download
         # with a git fetch
         git clone "${RaspbianURL}" 

         printf "${KGRN} done ${KNRM}\n"

         printf "${KBLU}Checking out remotes/origin/rpi-4.18.y ${KNRM}\n"
         cd 'linux'
         git checkout -b 'remotes/origin/rpi-4.18.y'

         printf "${KGRN} checkout complete ${KNRM}\n"

         # Patch source for RT Linux
         # wget -O rt.patch.gz https://www.kernel.org/pub/linux/kernel/projects/rt/4.14/older/patch-4.14.18-rt15.patch.gz
         # zcat rt.patch.gz | patch -p1

         printf "${KBLU}Saving Raspbian source ${KNRM} to ${SavedSourcesPath}/Raspbian.tar.xz ...  Logging to raspbian_compress.log\n"

         # Change directory before tar
         cd "${COMPILING_LOCATION}/${RaspbianSrcDir}"
         # I dont know why this is true, but tar fails otherwise
         set +e
         tar -cJf "${SavedSourcesPath}/Raspbian.tar.xz" 'linux'  &
         pid="$!"
         waitForPid "${pid}"

         # Exit immediately if a command exits with a non-zero status
         set -e

         if [ "${rc}" != '0' ]; then
            printf "${KRED}Error : [${rc}] ${KNRM} save failed. Check the log for details \n"
            exit $rc
         fi
         printf "${KGRN} done ${KNRM}\n"
      fi
   fi

}

function downloadElfHeaderForOSX()
{
   local ElfHeaderFile='/usr/local/include/elf.h'
   printf "${KBLU}Checking for ${KNRM}${ElfHeaderFile}\n"
   if [ -f "${ElfHeaderFile}" ]; then
      printf "${KGRN} found ${KNRM}\n"
   else
      printf "${KRED}\n\n *** IMPORTANT*** ${KNRM}\n"
      printf "${KRED}The gcc with OSX does not have an elf.h \n"
      printf "${KRED}No CFLAGS will fix this as the compile strips them \n"
      printf "${KRED}A copy from GitHub will be placed in /usr/local/include \n"
      printf "${KRED}It will be removed after use.${KNRM}\n\n\n"
      sleep 6
      
      local ElfHeaderFileURL='https://gist.githubusercontent.com/mlafeldt/3885346/raw/2ee259afd8407d635a9149fcc371fccf08b0c05b/elf.h'
      curl -Lsf "${ElfHeaderFileURL}" >  "${ElfHeaderFile}"

      # Apples compiler complained about DECLS, so remove them
      sed -i, -e's/__BEGIN_DECLS//g' -e's/__END_DECLS//g' "${ElfHeaderFile}"
   fi
}

function cleanupElfHeaderForOSX()
{
   local ElfHeaderFile='/usr/local/include/elf.h'
   printf "${KBLU}Checking for ${KNRM} ${ElfHeaderFile} ... "
   if [ -f "${ElfHeaderFile}" ]; then
      printf "${KGRN} found ${KNRM}\n"
      if [[ $(grep 'Mathias Lafeldt <mathias.lafeldt@gmail.com>' "${ElfHeaderFile}") ]];then
         printf "${KGRN}Removing ${ElfHeaderFile} ${KNRM} ... "
         rm "${ElfHeaderFile}"
         printf "${KGRN} done ${KNRM}\n"
      else
         printf "${KRED} not done ${KNRM}\n"
         printf "${KRED}Warning. There is a ${KNRM} ${ElfHeaderFile}\n"
         printf "${KRED}But it was not put there by this tool, I believe ${KNRM}\n"
         sleep 4
      fi
   else
      printf "${KGRN} not found -OK ${KNRM}\n"

   fi
}

function configureRaspbianKernel()
{
   cd "${COMPILING_LOCATION}/${RaspbianSrcDir}/linux"
   printf "${KBLU}Configuring Raspbian Kernel ${KNRM} in ${PWD}\n"

   export PATH="${PathWithCrossCompiler}"


   # for bzImage
   export KERNEL=kernel7

   export CROSS_PREFIX="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/bin/${ToolchainName}-"

   printf "${KBLU}Checkingo for an existing linux/.config file ${KNRM} ... "
   if [ -f '.config' ]; then
      printf "${KYEL} found ${KNRM} \n"
      printf "${KNRM} make mproper & bcm2709_defconfig  ${KNRM} will not be done \n"
      printf "${KNRM} to protect previous changes ${KNRM} \n"
   else
      printf "${KYEL} not found -OK ${KNRM} \n"
      printf "${KBLU}Make bcm2709_defconfig ${KNRM} in ${PWD}\n"
      export CFLAGS='-Wl,-no_pie'
      export LDFLAGS='-Wl,-no_pie'
      make ARCH=arm O="${CT_TOP_DIR}/build/kernel" mrproper 


      make ARCH=arm \
         CONFIG_CROSS_COMPILE="${ToolchainName}-" \
         CROSS_COMPILE="${ToolchainName}-" \
         --include-dir="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/include" \
         bcm2709_defconfig

      # Since there is no config file then add the cross compiler
      echo "CONFIG_CROSS_COMPILE=\"${ToolchainName}-\"\n" >> '.config'

   fi

   # printf "${KBLU}Running make nconfig ${KNRM} \n"
   # This cannot include ARCH= ... as it runs on OSX
   # make nconfig


   printf "${KBLU}Make zImage ${KNRM} in ${PWD} \n"

   KBUILD_CFLAGS="-I${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/include" \
   KBUILD_LDLAGS="-L${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/lib" \
   ARCH=arm \
      make  -j4 CROSS_COMPILE="${ToolchainName}-" \
        CC="${ToolchainName}-gcc" \
        --include-dir="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/include" \
        zImage 

   printf "${KBLU}Make modules ${KNRM} in ${PWD}\n"
   KBUILD_CFLAGS="-I${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/include" \
   KBUILD_LDLAGS="-L${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/lib" \
   ARCH=arm \
      make  -j4 CROSS_COMPILE="${ToolchainName}-" \
      CC="${ToolchainName}-gcc" \
      --include-dir="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/include" \
      modules

   printf "${KBLU}Make dtbs ${KNRM} in ${PWD}\n"
   KBUILD_CFLAGS="-I${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/include" \
   KBUILD_LDLAGS="-L${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/lib" \
   ARCH=arm \
      make  -j4 CROSS_COMPILE="${ToolchainName}-" \
        CC=${ToolchainName}-gcc \
        --include-dir="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/include" \
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

function installRaspbianKernelToBootVolume()
{
   local BootPath='/Volumes/boot'  
   printf "${KBLU}Installing Cross Compiled Raspbian Kernel ${KNRM}\n"
   printf "${KBLU}Checking for Raspbian source ${KNRM} ..."
   if [ ! -d "${COMPILING_LOCATION}/${RaspbianSrcDir}/linux" ]; then
      printf "${KRED} not found ${KNRM}\n"
      printf "${KNRM} You must first successfully execute: ./biuld.sh ${CmdOptionString} -b Raspbian ${KNRM}\n"
      exit -1
   fi
   printf "${KGRN} found ${KNRM}\n"

   
   printf "${KBLU}Checking for ${BootPath}/overlays ${KNRM} ... "
   if [ ! -d "${BootPath}/overlays" ]; then
      printf "${KRED} not found ${KNRM}\n"
      printf "${KRED}The overlays dirctory should already exist. ${KNRM}\n"
      exit -1
   else
      printf "${KGRN} found ${KNRM}\n"
   fi

   printf "${KBLU}Checking for ${COMPILING_LOCATION}/${RaspbianSrcDir}/linux/arch/arm/boot/zImage ${KNRM} ... "
   if [ ! -f "${COMPILING_LOCATION}/${RaspbianSrcDir}/linux/arch/arm/boot/zImage" ]; then
      printf "${KRED} not found ${KNRM}\n"
      exit -1
   fi
   printf "${KGRN} found ${KNRM}\n"


   printf "${KBLU}Copying Raspbian file ${KNRM} *.dtb to ${BootPath} ... "
   cp ${COMPILING_LOCATION}/${RaspbianSrcDir}/linux/arch/arm/boot/dts/*.dtb "${BootPath}/"
   printf "${KGRN} done ${KNRM}\n"
   printf "${KBLU}Copying Raspbian file ${KNRM} overlays/*.dtb* to ${BootPath} ... "
   cp ${COMPILING_LOCATION}/${RaspbianSrcDir}/linux/arch/arm/boot/dts/overlays/*.dtb* "${BootPath}/overlays/"
   printf "${KGRN} done ${KNRM}\n"
   printf "${KBLU}Copying Raspbian file ${KNRM} overlays/README to ${BootPath} ... "
   cp "${COMPILING_LOCATION}/${RaspbianSrcDir}/linux/arch/arm/boot/dts/overlays/README" "${BootPath}/overlays/"
   printf "${KGRN} done ${KNRM}\n"
   printf "${KBLU}Copying Raspbian file ${KNRM} zImage to ${BootPath} ... "
   cp "${COMPILING_LOCATION}/${RaspbianSrcDir}/linux/arch/arm/boot/zImage" "${BootPath}/kernel7.img"
   printf "${KGRN} done ${KNRM}\n"
}
function compileFuseFromSource()
{
   # Version built was fuse-ext2 0.0.9 29
   # git command for fuse from source
   git clone --depth=1 https://github.com/alperakcan/fuse-ext2.git
   
   # keep this command
   CFLAGS="--std=gnu89 -D__FreeBSD__=10 -idirafter/usr/local/include -idirafter/usr/local/include/osxfuse/ -idirafter/Volumes/ctBase/brew/opt/e2fsprogs/include" LDFLAGS="-L/usr/local/opt/glib -L/usr/local/lib -L/Volumes/ctBase/brew/opt/e2fsprogs/lib" ./configure -prefix=/Volumes/ctBase/brew


}
function checkExt2InstallForOSX()
{
   # Interesting note.  I believe brew installed osxfuse in 
   # /usr/local/include/osxfuse and /usr/local/lib
   # anyway.  Must check this
   
   printf "${KBLU}Checking for Ext2 tools ${KNRM} ... "
   if [ ! -d "${BrewHome}/Caskroom/osxfuse" ] &&
      [ ! -d "${BrewHome}/Cellar/e2fsprogs/1.44.3/sbin/mke2fs" ]; then
      printf "${KRED} not found ${KNRM}\n"
      printf "${KNRM}You must first ${KNRM}\n"
      printf "${KBLU}Execute:${KNRM} ./build.sh ${CmdOptionString} -i ${KNRM}\n"
      printf "${KNRM}To install the brew Ext2 tools ... \n"
      exit -1
   fi
   printf "${KGRN} found ${KNRM}\n"

   printf "${KBLU}Checking that Ext2 tools are set up properly ${KNRM} ... "
   if [ ! -d '/Library/Filesystems/fuse-ext2.fs' ] &&
      [ ! -d '/Library/PreferencePanes/fuse-ext2.prefPane' ]; then
      printf "\n${KRED}As per the previous Fuse-Ext2 instructions ${KNRM}\n"

      printf "${KNRM}\n"
      printf "   For fuse-ext2 to be able to work properly, the filesystem extension and \n"
      printf "preference pane must be installed by the root user: \n"
      printf "\n" 
      printf "   sudo cp -pR ${BrewHome}/opt/fuse-ext2/System/Library/Filesystems/fuse-ext2.fs /Library/Filesystems/ \n"
      printf "   sudo chown -R root:wheel /Library/Filesystems/fuse-ext2.fs \n"
      printf "\n"
      printf "   sudo cp -pR ${BrewHome}/opt/fuse-ext2/System/Library/PreferencePanes/fuse-ext2.prefPane /Library/PreferencePanes/ \n"
      printf "   sudo chown -R root:wheel /Library/PreferencePanes/fuse-ext2.prefPane\n"
      printf "\n"
      printf "\n"


      exit -1
   fi

   printf "${KGRN} OK ${KNRM}\n"
   
}


function updateBrewForEXT2()
{
   export PATH="${PathWithBrewTools}"

   if [ ! -d "${BrewHome}/Caskroom/osxfuse" ] &&
      [ ! -d "${BrewHome}/Cellar/e2fsprogs/1.44.3/sbin/mke2fs" ]; then

      # Do not Exit immediately if a command exits with a non-zero status.
      set +e

      if [ ! -d "${BrewHome}/Caskroom/osxfuse" ]; then
         printf "${KBLU}Installing brew cask osxfuse ${KNRM}\n"
         printf "${KMAG}*** osxfuse will need sudo *** ${KNRM}\n"
         brew cask install osxfuse && true
      fi

      if [ ! -d "${BrewHome}/Cellar/e2fsprogs/1.44.3/sbin/mke2fs" ]; then
         printf "${KBLU}Installing brew ext4fuse ${KNRM}\n"
         #${BrewHome}/bin/brew install ext4fuse && true
         brew install --HEAD 'https://raw.githubusercontent.com/yalp/homebrew-core/fuse-ext2/Formula/fuse-ext2.rb' && true
      fi

      # Exit immediately if a command exits with a non-zero status
      set -e

      if [ -f  '/Library/Filesystems/fuse-ext2.fs/fuse-ext2.util' ] && 
         [ -f '/Library/PreferencePanes/fuse-ext2.prefPane/Contents/MacOS/fuse-ext2' ]
      then
         # They could be there from a previous installation
         # NOOP
         echo "${KNRM}"

      else

         printf "${KBLU}After the install and reboot ${KNRM}\n"
         printf "${KBLU}Execute again:${KNRM} ./build.sh ${CmdOptionString} -i \n"
         exit 0
      fi
   fi

   # Exit immediately if a command exits with a non-zero status
   set -e

   checkExt2InstallForOSX

}

function getUSBFlashDeviceForRoot()
{
   printf "\n\n"
   printf "${KBLU}Finding USB flash devices available to write kernel to ${KNRM} ...\n"
   
   # Create an array of lines of system USB devices
   local lines=()
   while IFS=$'\n' read -r line_data; do
      lines+=("${line_data}")
   done <  <( system_profiler  -detailLevel mini SPUSBDataType )
   
   # An array of found device and their corresponding device number
   local FoundDeviceNumbers=()
   local FoundDevices=()
   
   # Go over all the output stored in the array of lines
   for (( i=0; i<${#lines[@]}; i++ )); do
      line=${lines[$i]}
      
      # We are close to the device number when USB tags are found
      if [[ "${line}" = *"USB SD Reader:"* ]] ||
         [[ "${line}" = *"FLASH DRIVE:"* ]]
      then
         local device=''
         if [[ "${line}" = *"USB SD Reader:"* ]]; then
            device='USB SD Reader:'
         fi
         if [[ "${line}" = *"FLASH DRIVE:"* ]]; then
            device='FLASH DRIVE:'
         fi
         
         # Now continue searching for the device number
         for (( i++, j=$i; j<${#lines[@]}; j++, i++ )); do 
            line=${lines[$j]}
            
            # Blank lines means we are not close
            if [ "${line}" = '' ]; then
               break 1
            fi
            
            # Search for the disk number
            if [[ "${line}" = *"disk"* ]]; then
               local DeviceNumber=$(echo "${line}" | grep -o -E '[0-9]+$')
               if [[ ${DeviceNumber} -ge 2 ]]; then
                 
                  FoundDeviceNumbers+=("${DeviceNumber}")
                  FoundDevices+=("${device}")
               else
                  printf "${KYEL}Ignoring disk${DeviceNumber} ${KNRM}as it is less than 2 \n"
              fi
              
              # Continue searching for other devices
              break 1
           fi
         done
      fi
   done
   
   if [[ ! ${#FoundDeviceNumbers[@]} -gt 0 ]]; then
      printf "${KRED}No flash device found ${KNRM}\n"
      printf "${KRED}Insert a device and rerun ${KNRM}\n"
      exit -1
   fi
   
   
   if [[ ${#FoundDeviceNumbers[@]} -eq 1 ]]; then
      printf "${KNRM}Found /dev/disk${FoundDevices[0]} \n"
      read -p "Is this correct (Y/n) " -r
      if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
         rc="${FoundDevices[0]}"
         return
      fi
      if [[ "${REPLY}" =~ ^[Nn]$ ]]; then
         printf "${KRED}Insert a device and rerun. ${KNRM}\n"
         exit -1
      fi
      printf "${KRED}You haven't entered a correct response.${KNRM}\n"
      printf "${KRED}Aborted due user input.${KNRM}\n"
      exit -1
   fi
   
   printf "${KGRN}Found devices: ${KNRM}\n"
   for (( i=0; i<${#FoundDeviceNumbers[@]}; i++ )); do
        printf "${FoundDevices[$i]} /dev/disk${FoundDeviceNumbers[$i]} \n"
   done
   
   
   printf "${KNRM}To which device you would like to write Rasbian to? \n"
   read -p "(Please only enter the number like 2 for /dev/disk2) " -r
   if [[ ! "${REPLY}" =~ ^[0-9]$ ]]; then
      printf "${KRED}You haven't entered a number.${KNRM}\n"
      printf "${KRED}Aborted due user request.${KNRM}\n"
      exit -1
   fi
   
   if [[ ! "${REPLY}" -ge 2 ]]; then
      printf "${KRED}The number is lower than 2.${KNRM}\n"
      printf "${KRED}Since /dev/disk0 and /dev/disk1 are usually system drives,${KNRM}\n"
      printf "${KRED}We can't accept this device. We don't want to possibly destroy your ${KNRM}\n"
      printf "${KRED}system. ${KYEL};-) ${KNRM}\n"
      exit -1
   fi
   
   if [[ ! " ${FoundDeviceNumbers[@]} " =~ " ${REPLY} " ]]; then
      printf "${KRED}The number is not in the given list.${KNRM}\n"
      printf "${KRED}Insert a device and rerun or next time ${KNRM}\n"
      printf "${KRED}Enter a number from the given list.${KNRM}\n"
      exit -1
   fi

   rc="${REPLY}"
         
}

function mountRaspbianBootPartitiion()
{
   PATH="${PathWithBrewTools}"
   
   printf "${KBLU}Mounting /Volumes/boot ${KNRM} \n" 
   
   # Mounts boot without complaints about root
   # Mounts with nice message
   /usr/sbin/diskutil mount "/dev/disk${TargetUSBDevice}s1"
   
   # No done message required as diskutil provides its own
   
   printf "${KBLU}Checking for /Volumes/boot ${KNRM} ... "      
   if [ ! -d '/Volumes/boot' ]; then
      printf "${KRED} not found ${KNRM}\n"
      exit -1 
   fi
   printf "${KGRN} done ${KNRM}\n"
   
   
}


function mountRaspbianRootPartitiion()
{
   local RW='n'
   RW="$1"
   
   PATH="${PathWithBrewTools}"
   printf "${KBLU}Mounting Raspbian root Partitiions with fuse-ext ${KNRM} \n"  
   
   printf "${KBLU}Checking /Volumes/root already mounted${KNRM} ... " 
   if [ -d '/Volumes/root/bin' ]; then
      printf "${KGRN} already mounted ${KNRM}\n"
      return
   fi
   printf "${KGRN} not mounted ${KNRM}\n"
   
   getUSBFlashDeviceForRoot
   
   if [ "${RW}" = 'y' ]; then
      printf "${KBLU}Mounting /dev/disk${TargetUSBDevice}s2 (RW+) ${KNRM} as /Volumes/root ... " 
      sudo fuse-ext2 "/dev/disk${TargetUSBDevice}s2" '/Volumes/root' -o rw+
   else
      printf "${KBLU}Mounting /dev/disk${TargetUSBDevice}s2 (Read Only) ${KNRM} as /Volumes/root ... " 
      sudo fuse-ext2 "/dev/disk${TargetUSBDevice}s2" '/Volumes/root'
   fi
   printf "${KGRN} done ${KNRM}\n"
   
   printf "${KBLU}Checking for /Volumes/root/bin ${KNRM} ... "      
   if [ ! -d '/Volumes/root/bin' ]; then
      printf "${KRED} not found ${KNRM}\n"
      printf "${KRED} Raspbian not mounted ${KNRM}\n"
      exit -1 
   fi
   printf "${KGRN} done ${KNRM}\n"
}

function unMountRaspbianBootPartition()
{
   printf "${KBLU}Unmounting (Not ejecting) ${KNRM} /dev/disk${TargetUSBDevice}s1 ... "
       
   diskutil unmount  "/dev/disk${TargetUSBDevice}s1"
   
   # No done message required as diskutil provides its own
}

function unMountRaspbianRootPartition() 
{

   printf "${KBLU}Unmounting (Not ejecting) ${KNRM} /Volumes/root ... "
   printf "${KMAG} (sudo required) ${KNRM}"
   # UnMounted root if root was only mounted    
   sudo umount  "/Volumes/root"
   
   # No done message required as diskutil provides its own
}

function mountRaspbianVolume() 
{

   printf "${KBLU}Mounting  ${KNRM} /dev/disk${TargetUSBDevice} ... "
   # Only mounts boot
   # Gives error message mounting root
   diskutil mountDisk  "/dev/disk${TargetUSBDevice}"
   
   # No done message required as diskutil provides its own
}

function unMountRaspbianVolume() 
{

   printf "${KBLU}Unmounting (Not ejecting) ${KNRM} /dev/disk${TargetUSBDevice} ... "
   # Does not Unmounted root if only root mounted
   diskutil unmountDisk  "/dev/disk${TargetUSBDevice}"
   
   # No done message required as diskutil provides its own
}

function ejectRaspbianDisk()
{
   printf "${KBLU}Ejecting Raspbian Disk ${KNRM} ... "  
   
   hdiutil eject  "/dev/disk${TargetUSBDevice}"
   
   # No done message required as hdiutil provides its own
}

function downloadRaspbianStretch()
{
   local RaspbianStretchURL="http://director.downloads.raspberrypi.org/raspbian/images/raspbian-2018-06-29/${RaspbianStretchFile}.zip"
    
   
   printf "${KBLU}Downloading Raspbian Stretch latest ${KNRM} \n"   
   

   cd "${SavedSourcesPath}"

   printf "${KBLU}Checking for ${KNRM} ${RaspbianStretchFile}.img ... "
   if [ -f "${RaspbianStretchFile}.img" ]; then
      printf "${KGRN} found ${KNRM}\n"
      printf "${KNRM} It will be used instead of downloading another. \n"
      return
   fi
   
   printf "${KBLU}Checking for ${KNRM} ${RaspbianStretchFile}.zip ... "
   if [ -f "${RaspbianStretchFile}.zip" ]; then
      printf "${KGRN} found ${KNRM}\n"
    
   else
      printf "${KYEL} not found -OK ${KNRM}\n"
      
      printf "${KBLU}Fetching ${RaspbianStretchFile} ${KNRM}\n"
         
      wget -c "${RaspbianStretchURL}" 

      printf "${KGRN} done ${KNRM}\n"
   fi
   
   printf "${KBLU}Uncompressing ${RaspbianStretchFile}.zip ${KNRM} ... Logging to /tmp/stretch_unzip.log \n"
      
   # Do not Exit immediately if a command exits with a non-zero status.
   set +e
   
   unzip "${RaspbianStretchFile}.zip" > '/tmp/stretch_unzip.log' 2>&1 &
   pid="$!"
   waitForPid "${pid}"

   # Exit immediately if a command exits with a non-zero status
   set -e

   if [ "${rc}" != '0' ]; then
      printf "${KRED}Error : [${rc}] ${KNRM} unzip failed. Check the log for details\n"
      exit $rc
   fi
   
   printf "${KGRN} done ${KNRM}\n"     
      
}

function unPackDebFile()
{
   PATH="${PathWithBrewTools}"
   
   local checkFile="$1" 
   local pkguRL="$2"
   local pkg="$3"
   
   printf "${KBLU}Checking for file ${KNRM} ${checkFile} ... " 
   if [ -f "${checkFile}" ]; then
      printf "${KGRN} found ${KNRM}\n"
      printf "${KNRM}Package ${pkg} already installed\n"
      return
   fi
   printf "${KYEL} not found ${KNRM} - OK\n"
   
   cd ${SavedSourcesPath}
   
   printf "${KBLU}Checking for saved package ${pkg} ${KNRM} in ${PWD} ... " 
   if [ ! -f "${pkg}" ]; then
      printf "${KYEL} not found ${KGRN} -OK ${KNRM}\n"
      
      printf "${KBLU}Fetching  ${pkg} ${KNRM} from ${pkguRL} ... \n"
      wget -c "${pkguRL}/${pkg}"
      printf "${KGRN} done ${KNRM}\n"
     
   fi
   printf "${KGRN} found ${KNRM}\n"
   
   printf "${KBLU}Copying  ${pkg} ${KNRM} to /tmp ... " 
   cp "${pkg}" /tmp/
   printf "${KGRN} done ${KNRM}\n"
   
   cd /tmp
   printf "${KBLU}UnArchiving ${pkg} ${KNRM} in ${PWD} ... " 
   ar x "${pkg}" 'data.tar.xz'
   printf "${KGRN} done ${KNRM}\n"
   
   printf "${KBLU}Checking for ${KNRM} data.tar.xz ... " 
   if [ ! -f 'data.tar.xz' ]; then
      printf "${KRED} not found ${KNRM}\n"
      exit -1 
   fi
   printf "${KGRN} found ${KNRM}\n"
   
   printf "${KBLU}Extracting data.tar.xz ${KNRM} to /Volumes/boot/ ... "
  # tar -xf data.tar.xz -C/Volumes/boot/
   printf "${KGRN} done ${KNRM}\n"
   
   printf "${KBLU}removing /tmp/data.tar.xz and /tmp/${pkg} ${KNRM}  ... "
   rm '/tmp/data.tar.xz' "/tmp/${pkg}"
   printf "${KGRN} done ${KNRM}\n"
   
}

function addMissingRaspbianPackages()
{
   PATH="${PathWithBrewTools}"
   
   local pkguRL='http://ftp.us.debian.org/debian/pool/main/s/systemd'
   local pkg='libudev-dev_239-9_armhf.deb'
   local checkFile='/usr/include/udev.h'
   unPackDebFile  "${checkFile}" "${pkguRL}" "${pkg}"
}

function installRaspbianStretchOntoUSBDevice()
{
   printf "${KBLU}Installing ${RaspbianStretchFile}.img ${KNRM} \n"
   
   cd "${SavedSourcesPath}"

   printf "${KBLU}Checking for ${KNRM} ${RaspbianStretchFile}.img ... "
   if [ -f "${RaspbianStretchFile}.img" ]; then
      printf "${KGRN} found ${KNRM}\n"   
   else
      printf "${KRED} not found ${KNRM}\n"
      printf "${KRED} This should have already been downloaded and unzipped. ${KNRM}\n"
      exit -1
   fi
   
   unMountRaspbianVolume
    
   printf "${KBLU}Writing ${RaspbianStretchFile}.img ${KNRM} to /dev/disk${TargetUSBDevice} ... Logging to /tmp/dd.log\n"
   printf "\r${KNRM}Writing ... ${RaspbianStretchFile}.img using command: \n"  
   printf "\r${KNRM}sudo dd if=${RaspbianStretchFile}.img of=/dev/disk${TargetUSBDevice} bs=1m \n"    
   # Done this way to put dd in background as it takes a while
   # read -s -p "Password:" -r
    
   printf "\n${KYEL}Starting in ${KNRM} 5"; sleep 1
   printf "\r${KYEL}Starting in ${KNRM} 4"; sleep 1
   printf "\r${KYEL}Starting in ${KNRM} 3"; sleep 1
   printf "\r${KYEL}Starting in ${KNRM} 2"; sleep 1
   printf "\r${KYEL}Starting in ${KNRM} 1"; sleep 1
   printf "\r                   \n"
   
   # Do not Exit immediately if a command exits with a non-zero status.
   set +e
   
   # echo ${REPLY} | sudo -kS dd if="${RaspbianStretchFile}.img" of="/dev/disk${TargetUSBDevice}" bs=1m > /tmp/dd.og 2>&1 &
   sudo -sk dd if="${RaspbianStretchFile}.img" of="/dev/disk${TargetUSBDevice}" bs=1m > /tmp/dd.log  &
   sleep 20
   printf "\n\n"
   
   pid="$!"
   waitForPid "${pid}"

   # Exit immediately if a command exits with a non-zero status
   set -e

   if [ "${rc}" != '0' ]; then
      printf "${KRED}Error : [${rc}] ${KNRM} dd failed. Check the log for details \n"
      exit $rc
   fi   
   
   printf "${KGRN} done ${KNRM}\n"  
}

function downloadLinuxCNC()
{
   PATH="${PathWithCrossCompiler}"
   
   printf "${KBLU}Checking for existing LinuxCNC install ${KNRM} ... " 
   if [ -f "/Volumes/root/opt/local/linuxcnc" ]; then
      printf "${KGRN} found ${KNRM}\n"
      printf "${KNRM} Remove it to start over \n"
      return
   fi
   printf "${KGRN} not found -OK ${KNRM}\n"
     
   printf "${KBLU}Checking for existing LinuxCNC src ${KNRM} ${LinuxCNCSrcDir} ... " 
   if [ -d "${COMPILING_LOCATION}/${LinuxCNCSrcDir}" ]; then
      printf "${KGRN} found ${KNRM} Using it instead \n"      
   else
      printf "${KGRN} not found -OK ${KNRM}\n"
      
      printf "${KBLU}Checking for saved LinuxCNC src ${KNRM} ${LinuxCNCSrcDir}.tar.xz ... " 
      if [ -f "${SavedSourcesPath}/${LinuxCNCSrcDir}.tar.xz" ]; then
         printf "${KGRN} found -OK ${KNRM}\n"   
     
         printf "${KBLU}Extracting saved LinuxCNC src ${KNRM} to ${SavedSourcesPath}/${LinuxCNCSrcDir} ... "      
         tar -xf "${SavedSourcesPath}/${LinuxCNCSrcDir}.tar.xz" \
             -C "${COMPILING_LOCATION}"
             
         printf "${KGRN} done ${KNRM}\n" 
      else
         printf "${KGRN} not found -OK ${KNRM}\n" 
         
         printf "${KBLU}Creating ${LinuxCNCSrcDir} ${KNRM} in ${COMPILING_LOCATION} ... " 
         mkdir "${COMPILING_LOCATION}/${LinuxCNCSrcDir}"
         printf "${KGRN} done ${KNRM}\n" 
         
         printf "${KBLU}Retrieving LinuxCNC src ${KNRM} to ${LinuxCNCSrcDir} ... \n" 
         git clone --depth=1 'https://github.com/LinuxCNC/linuxcnc.git' \
             "${COMPILING_LOCATION}/${LinuxCNCSrcDir}"
           
         printf "${KBLU}Saving LinuxCNC src ${KNRM}to ${SavedSourcesPath}/${LinuxCNCSrcDir}.tar.xz ... "
         cd "${COMPILING_LOCATION}"
         tar -cJf "${SavedSourcesPath}/${LinuxCNCSrcDir}.tar.xz" "${LinuxCNCSrcDir}" 
         printf "${KGRN} done ${KNRM}\n" 
      fi
   fi  
   
}

function configureLinuxCNC()
{
   cd "${COMPILING_LOCATION}/${LinuxCNCSrcDir}"
   printf "${KBLU}Configuring LinuxCNC ${KNRM} in ${PWD}\n"

   export PATH="${PathWithCrossCompiler}"


   

   export CROSS_PREFIX="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/bin/${ToolchainName}-"

   printf "${KBLU}Checkingo for an existing linux/.config file ${KNRM} ... "
   if [ -f '.config' ]; then
      printf "${KYEL} found ${KNRM} \n"
      printf "${KNRM} make mproper & bcm2709_defconfig  ${KNRM} will not be done \n"
      printf "${KNRM} to protect previous changes ${KNRM} \n"
   else
      printf "${KYEL} not found -OK ${KNRM} \n"
      printf "${KBLU}Make bcm2709_defconfig ${KNRM} in ${PWD}\n"
      export CFLAGS='-Wl,-no_pie'
      export LDFLAGS='-Wl,-no_pie'
      

      # Since there is no config file then add the cross compiler
      echo "CONFIG_CROSS_COMPILE=\"${ToolchainName}-\"\n" >> '.config'

   fi

   

   # KBUILD_CFLAGS="-I${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/include" \
   # KBUILD_LDLAGS="-L${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/lib" \
   # ARCH=arm \
   #   make  -j4 CROSS_COMPILE="${ToolchainName}-" \
   #     CC="${ToolchainName}-gcc" \
   #     --include-dir="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/include" \
   #     zImage 
   
   exit -1

}

function downloadPyCNC()
{
   PATH="${PathWithCrossCompiler}"
   
   printf "${KBLU}Checking for existing PyCNC install ${KNRM} ... " 
   if [ -f "/Volumes/root/opt/local/PyCNC" ]; then
      printf "${KGRN} found ${KNRM}\n"
      printf "${KNRM} Remove it to start over \n"
      return
   fi
   printf "${KGRN} not found -OK ${KNRM}\n"
     
   printf "${KBLU}Checking for existing PyCNC src ${KNRM} ${PyCNCSrcDir} ... " 
   if [ -d "${COMPILING_LOCATION}/${PyCNCSrcDir}" ]; then
      printf "${KGRN} found ${KNRM} Using it instead \n"      
   else
      printf "${KGRN} not found -OK ${KNRM}\n"
      
      printf "${KBLU}Checking for saved PyCNC src ${KNRM} ${PyCNCSrcDir}.tar.xz ... " 
      if [ -f "${SavedSourcesPath}/${PyCNCSrcDir}.tar.xz" ]; then
         printf "${KGRN} found -OK ${KNRM}\n"   
     
         printf "${KBLU}Extracting saved PyCNC src ${KNRM} to ${SavedSourcesPath}/${PyCNCSrcDir} ... "      
         tar -xf "${SavedSourcesPath}/${PyCNCSrcDir}.tar.xz" \
             -C "${COMPILING_LOCATION}"
             
         printf "${KGRN} done ${KNRM}\n" 
      else
         printf "${KGRN} not found -OK ${KNRM}\n" 
         
         printf "${KBLU}Creating ${PyCNCSrcDir} ${KNRM} in ${COMPILING_LOCATION} ... " 
         mkdir "${COMPILING_LOCATION}/${PyCNCSrcDir}"
         printf "${KGRN} done ${KNRM}\n" 
         
         printf "${KBLU}Retrieving PyCNC src ${KNRM} to ${PyCNCSrcDir} ... \n" 
         git clone --depth=1 'https://github.com/Nikolay-Kha/PyCNC' \
             "${COMPILING_LOCATION}/${PyCNCSrcDir}"
           
         printf "${KBLU}Saving PyCNC src ${KNRM}to ${SavedSourcesPath}/${PyCNCSrcDir}.tar.xz ... "
         cd "${COMPILING_LOCATION}"
         tar -cJf "${SavedSourcesPath}/${PyCNCSrcDir}.tar.xz" "${PyCNCSrcDir}" 
         printf "${KGRN} done ${KNRM}\n" 
      fi
   fi
   cd "${COMPILING_LOCATION}/${PyCNCrcDir}"
   
   printf "${KGRN} Configuring PyCNC ${KNRM}\n"
   
   
}

function updateVariablesForChangedOptions()
{
   # Base gets changed based on Volume name given
   VolumeBase="${Volume}Base"

   CrossToolNGConfigFile="${ToolchainName}.config"

   # Do not change the name of VolumeBase. It would
   # defeat its purpose of being solid and separate


   # A specified saved sources path does not get updated
   if [ "${SavedSourcesPathOpt}" = 'n' ]; then
      SavedSourcesPath="/Volumes/${VolumeBase}/sources"
   fi
   BrewHome="/Volumes/${VolumeBase}/brew"
   CT_TOP_DIR="/Volumes/${Volume}"
   CT_TOP_DIR_BASE="/Volumes/${VolumeBase}"
   
   COMPILING_LOCATION="${CT_TOP_DIR}/src"   
   
   export BREW_PREFIX="${BrewHome}"
   export PKG_CONFIG_PATH="${BREW_PREFIX}"
   export HOMEBREW_CACHE="${SavedSourcesPath}"
   export HOMEBREW_LOG_PATH="${BrewHome}/brew_logs"
   
   PathWithBrewTools="${BrewHome}/bin:${BrewHome}/opt/gettext/bin:${BrewHome}/opt/bison/bin:${BrewHome}/opt/libtool/bin:/Volumes/${VolumeBase}/brew/opt/texinfo/bin:${BrewHome}/opt/gcc/bin:${BrewHome}/Cellar/e2fsprogs/1.44.3/sbin:/Volumes/${VolumeBase}/ctng/bin:${OriginalPath}" 
   
   PathWithCrossCompiler="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/bin:${PathWithBrewTools}" 
   
}
function explainExclusion()
{
   printf "${KRED} You cannot install Raspbian and then install the kernel \n"
   printf "${KRED} immediately afterwards.the raspbian image is squashfs and \n"
   printf "${KRED} to be bbted first to make it ext4 and do its own setup. \n"
   printf "${KRED} If you try to do it anyway afterwards, the extfs mount\n"
   printf "${KRED} will fail. ${KNRM}\n"
}


# Define this once and you save yourself some trouble
# Omit the : for the b as we will check for optional option
OPTSTRING='h?P?c:V:O:f:btT:i:S:a:'

# Getopt #1 - To enforce order
while getopts "${OPTSTRING}" opt; do
   case ${opt} in
      h)
          showHelp
          exit 0
          ;;
          #####################
      P)
          updateVariablesForChangedOptions
          
          PATH="${PathWithCrossCompiler}"
  
          printf "${KNRM}PATH=${PATH} \n"
          printf "${KNRM}KBUILD_CFLAGS=-I${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/include \n"
          printf "${KNRM}KBUILD_LDLAGS=-L${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/lib \n"
          printf "./configure  ARCH=arm  CROSS_COMPILE=${ToolchainName}- --prefix=${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName} \n"
          printf "make ARCH=arm --include-dir=${CT_TOP_DIR}Base/${OutputDir}/${ToolchainName}/${ToolchainName}/include CROSS_COMPILE=${ToolchainName}-\n"
          exit 0
          ;;
          #####################
      c)
          # Flag that something else was wanted to be done first
          TestCompilerOnlyOpt='n'

          if [[ "${OPTARG}" =~ ^[Bb]rew$ ]]; then 
             cleanBrew
             exit
          fi

          if  [ "${OPTARG}" = 'ctng' ] || 
              [ "${OPTARG}" = 'ct-ng' ]; then
             ct-ngMakeClean
             exit
          fi

          if [[ "${OPTARG}" =~ ^[Rr]aspbian$ ]]; then 
             cleanRaspbian
             exit
          fi

          if  [ "${OPTARG}" = 'realClean' ]; then
             realClean
             exit
          fi

          ;;
          #####################
      V)
          Volume="${OPTARG}"

          VolumeOpt='y'

          CmdOptionString="${CmdOptionString} -V ${Volume}"

          updateVariablesForChangedOptions

          ;;
          #####################
      O)
          OutputDir="${OPTARG}"

          OutputDirOpt='y'

          CmdOptionString="${CmdOptionString} -O ${OutputDir}"

          updateVariablesForChangedOptions

          ;;
          #####################
      f)
          CrossToolNGConfigFile="${OPTARG}"

          CmdOptionString="${CmdOptionString} -f ${CrossToolNGConfigFile}"

          # Do a quick check before we begin
          if [ -f "${ThisToolsStartingPath}/${CrossToolNGConfigFile}" ]; then
             printf "${KNRM}${ThisToolsStartingPath}/${CrossToolNGConfigFile} ... ${KGRN} found ${KNRM}\n"
          else
             printf "${KNRM}${ThisToolsStartingPath}/${CrossToolNGConfigFile} ... ${KRED} not found ${KNRM}\n"
             exit 1
          fi
          ;;
          #####################
      b)
          # Flag that something else was wanted to be done first
          TestCompilerOnlyOpt='n'

          # Check next positional parameter

          # Why would checking for an unbound variable cause an unbound variable?
          set +u

          nextOpt="${!OPTIND}"

          # Exit immediately for unbound variables.
          set -u

          # existing or starting with dash?
          if [[ -n "${nextOpt}" && "${nextOpt}" != -* ]]; then
             OPTIND=$((OPTIND + 1))

             if [[ "${nextOpt}" =~ ^[Rr]aspbian$ ]]; then 
                BuildRaspbianOpt='y'
             else
                # Run ct-ng with the option passed in 
                RunCTNGOptArg="${nextOpt}"
             fi
          else

             # Since -b  was specified alone, run ct-ng with default opt
             BuildCTNGOpt='y'
             RunCTNGOptArg='build'
          fi

          ;;
          #####################
       T)
          ToolchainNameOpt=y
          ToolchainName="${OPTARG}"

          CmdOptionString="${CmdOptionString} -T ${ToolchainName}"

          updateVariablesForChangedOptions

          ;;
          #####################
      t)

          # Check next positional parameter

          # Why would checking for an unbound variable cause an
          # unbound variable?

          set +u
          nextOpt=${!OPTIND}

          # Exit immediately for unbound variables.
          set -u

          # existing or starting with dash?
          if [[ -n "${nextOpt}" && "${nextOpt}" != -* ]]; then
             OPTIND=$((OPTIND + 1))
             if [ "${nextOpt}" = 'gcc' ]; then
                TestHostCompilerOpt='y';
             fi
          fi
          if [ "${TestHostCompilerOpt}" = 'n' ]; then
             TestCrossCompilerOpt='y'
          fi
          ;;
          #####################
       i)
          # Flag that something else was wanted to be done first
          TestCompilerOnlyOpt='n'

          # Check for valid install options
          if [[ "${OPTARG}" =~ ^[Rr]aspbian$ ]]; then 
              if [ "${InstallKernelOpt}" = 'y' ];then
                 explainExclusion
                 exit -1
              fi
             InstallRaspbianOpt='y'
          else
             if [[ "${OPTARG}" =~ ^[Kk]ernel$ ]]; then 
                if [ "${InstallRaspbianOpt}" = 'y' ]; then
                   explainExclusion
                   exit -1
                fi  
                InstallKernelOpt='y'
             else
                printf "${KRED}Unknown -i option (${OPTARG}) ${KNRM} ... \n"
                exit -1
             fi
          fi
          ;;
          #####################
      S)
          SavedSourcesPath="${OPTARG}"
          SavedSourcesPathOpt='y'

          ;;
          #####################
       a)
          # Flag that something else was wanted to be done first
          TestCompilerOnlyOpt='n'
          
          if [[ ! "${OPTARG}" =~ ^[Ll]inuxCNC$ ]] &&
             [[ ! "${OPTARG}" =~ ^[Pp]yCNC$ ]]
          then
             printf "${KRED}unknown option -a ${KNRM} ${OPTARG} \n"
             exit -1
          fi
           
          # Check for valid install options
          if [[ "${OPTARG}" =~ ^[Ll]inuxCNC$ ]]; then              
             AddLinuxCNCOpt='y'
          fi
          if [[ "${OPTARG}" =~ ^[Pp]yCNC$ ]]; then 
             AddPyCNCOpt='y'               
          fi
          ;;
          #####################
      \?)
          exit -1
          ;;
          #####################
      :)
          printf "${KRED}Option ${KNRM}-${OPTARG} requires an argument.\n" 
          exit -1
          ;;
          #####################
   esac
done



if [ "${TestHostCompilerOpt}" = 'y' ]; then
   testHostCompiler

   if [ "${TestCompilerOnlyOpt}" = 'y' ]; then
      exit 0
   fi
fi

if [ "${TestCrossCompilerOpt}" = 'y' ] && [ "${TestCompilerOnlyOpt}" = 'y' ]; then
   testCrossCompiler
   if [ "${TestCompilerOnlyOpt}" = 'y' ]; then
      exit 0
   fi
fi


# This all needs to be rechecked each time anyway so...
printf "${KBLU}Here we go ${KNRM} ... \n"

# We will put Brew and ct-ng here too so they dont need rebuilding
# all the time
createCaseSensitiveVolumeBase

# Create a directory to save/reuse tarballs
createTarBallSourcesDir

# Create the case sensitive volume first.
createCaseSensitiveVolume

# Create a place for compilations to occur
createSrcDirForCompilation

# OSX is either missing tools or they are too old.
# Solve this with putting brew tools in our own build.
buildBrewTools

# Brew tools does not contain ld and the OSX version results in the error
#  PIE disabled. Absolute addressing (perhaps -mdynamic-no-pic)
# Trying to build them first before gcc, causes ld not
# to be built.
#buildBinutilsForHost

buildCTNG

buildCrossCompiler

if [ "${BuildRaspbianOpt}" = 'y' ]; then
   
   downloadAndBuildzlibForTarget

   downloadRaspbianKernel
   downloadElfHeaderForOSX
   configureRaspbianKernel
   cleanupElfHeaderForOSX

fi

# Common tasks wheninstalling Raspbian or its kernel
if [ "${InstallRaspbianOpt}" = 'y' ] ||
   [ "${InstallKernelOpt}" = 'y' ]
then
   # updateBrewForEXT2
      
   getUSBFlashDeviceForInstallation
   TargetUSBDevice="${rc}"
         
   printf "${KGRN}Using flash device: ${KNRM} /dev/disk${TargetUSBDevice} \n"
   
   if [ "${InstallRaspbianOpt}" = 'y' ]; then
      downloadRaspbianStretch
      installRaspbianStretchOntoUSBDevice
   fi
   
   if [ "${InstallKernelOpt}" = 'y' ]; then
       mountRaspbianBootPartitiion
  
       installRaspbianKernelToBootVolume
       
       unMountRaspbianBootPartition
    fi
    
fi 
 
if [ "${AddLinuxCNCOpt}" = 'y' ]; then
   
   updateBrewForEXT2    
   
   mountRaspbianRootPartitiion  'n'
   
   addMissingRaspbianPackages
   
   downloadLinuxCNC
   
   configureLinuxCNC
fi
   
if [ "${AddPyCNCOpt}" = 'y' ]; then
   w=42
fi





exit 0
