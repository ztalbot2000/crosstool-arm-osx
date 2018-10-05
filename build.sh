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
# ToolchainNameOpt='n'
# CleanRaspbianOpt='n'
VolumeOpt='n'
OutputDirOpt='n'
SavedSourcesPathOpt='n'
TestHostCompilerOpt='n'
TestCrossCompilerOpt='n'
TestCompilerOnlyOpt='y'
BuildRaspbianOpt='n'
# RunCTNGOpt='n'
RunCTNGOptArg='build'
InstallRaspbianOpt='n'
InstallKernelOpt='n'
AddLinuxCNCOpt='n'
AddPyCNCOpt='n'    
BuildGCCwithBrewOpt='n'

# Fun colour & cursor stuff

TCR=$(tput cr)
# TBLD=$(tput bold)
TNRM=$(tput sgr0)
# TBLK=$(tput setaf 0)
TRED=$(tput setaf 1)
TGRN=$(tput setaf 2)
TYEL=$(tput setaf 3)
TBLU=$(tput setaf 4)
TMAG=$(tput setaf 5)
TCYN=$(tput setaf 6)
# TWHT=$(tput setaf 7)


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
                       <Volume>Base/sources.
     -c Brew         - Remove all installed Brew tools.
     -c ct-ng        - Run make clean in crosstool-ng path.
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
     -a LinuxCNC     - Add LinuxCNC to Raspbian.
     -a PyCNC        - Add PyCNC to Raspbian.
     -t              - After the build, run a Hello World test on it.
     -t gcc          - test the gcc in this scripts path.
 
                       The product of which would be: armv8-rpi3-linux-gnueabihf-gcc ...
     -P              - Just Print the PATH variable.
     -h              - This menu.
     -help
     "none"          - Go for it all if no options given. it will always try to
                       continue where it left off.

HELP_EOF
}

function removeFileWithCheck()
{
   echo -n "Removing file $1 ${TNRM} ... "
   if [ -f "$1" ]; then
      rm "$1"
      echo "  ${TGRN} Done ${TNRM}"
   else
      echo "  ${TGRN} Not found ${TNRM}"
   fi
}
function removePathWithCheck()
{
   echo -n "Removing directory $1 ${TNRM} ... "
   if [ -d "$1" ]; then
      rm -rf "$1"
      echo "  ${TGRN} Done ${TNRM}"
   else
      echo "  ${TGRN} Not found ${TNRM}"
   fi
}

function waitForPid()
{
   local pid=$1
   local spindleCount=0
   local spindleArray=('|' '/' '-' "\\")
   local colorSpindleArray=("${TGRN}" "${TRED}" "${TBLU}" "${TCYN}")
   local STARTTIME SECONDS MM M H
   STARTTIME=$(date +%s)

   while ps -p "${pid}" >/dev/null; do
      sleep 1.0

      SECONDS=$(($(date +%s) - STARTTIME))
      ((S = SECONDS % 60))
      ((MM = SECONDS / 60)) # Total number of minutes
      ((M = MM % 60))
      ((H = MM / 60))
      echo -n "${TCR}${TNRM}[ "
      [ "$H" -gt "0" ] && printf "%02d:" $H
      printf "%02d:%02d ] ${TGRN}%s%s${TNRM}" $M $S "${colorSpindleArray[$spindleCount]}" "${spindleArray[$spindleCount]}"
      spindleCount=$((spindleCount + 1))
      if [[ ${spindleCount} -eq ${#spindleArray[*]} ]]; then
         spindleCount=0
      fi
   done
   # When done, overwite the spindle
   echo -n "${TCR}${TNRM}[ "
   printf "%02d:%02d ] " $M $S  

   # Get the true return code of the process
   wait "${pid}"

   # Set our global return code of the process
   rc=$?
}

function cleanBrew()
{
   if [ -f "${BrewHome}/.flagToDeleteBrewLater" ]; then
      echo "${TBLU}Cleaning our brew tools ${TNRM}"
      echo -n "Checking for ${TNRM} ${BrewHome} ... "
      if [ -d "${BrewHome}" ]; then
         echo "${TGRN} found ${TNRM}"
      else
         echo "${TRED} not found ${TNRM}"
         exit -1
      fi

      removePathWithCheck  "${BrewHome}"
   fi
}

function ct-ngMakeClean()
{
   echo "${TBLU}Cleaning ct-ng${TNRM} ..."
   local ctDir="${CT_TOP_DIR_BASE}/${CrossToolSourceDir}"
   echo -n "Checking for ${TNRM}${ctDir} ... "
   if [ -d "${ctDir}" ]; then
      echo "${TGRN} found ${TNRM}"
   else
      echo "${TRED} not found ${TNRM}"
      exit -1
   fi
   cd "${ctDir}"
   make clean
   echo "${TGRN} done ${TNRM}"
}
function cleanRaspbian()
{
   echo "${TBLU}Cleaning raspbian (make mrproper) ${TNRM}"

   # Remove our elf.h
   cleanupElfHeaderForOSX

   echo -n "${TBLU}Checking for ${TNRM} ${CT_TOP_DIR}/${RaspbianSrcDir} ... "
   if [ -d "${CT_TOP_DIR}/${RaspbianSrcDir}" ]; then
      echo "${TGRN} found ${TNRM}"
   else
      echo "${TRED} not found ${TNRM}"
      exit -1
   fi
   echo -n "${TBLU}Checking for ${TNRM} ${CT_TOP_DIR}/${RaspbianSrcDir}/linux ... "
   if [ -d "${CT_TOP_DIR}/${RaspbianSrcDir}/linux" ]; then
      echo "${TGRN} found ${TNRM}"
   else
      echo "${TRED} not found ${TNRM}"
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
      echo "${TBLU}Ejecting ${CT_TOP_DIR_BASE} ${TNRM}"
      hdiutil eject "${CT_TOP_DIR_BASE}"
   fi

   # Eject the disk instead of unmounting it or you will have
   # a lot of disks hanging around.  I had 47, Doh!
   if [ -d  "${CT_TOP_DIR}" ]; then
      echo "${TBLU}Ejecting  ${CT_TOP_DIR} ${TNRM}"
      hdiutil eject "${CT_TOP_DIR}"
   fi


   # Since everything is on the image, just remove it does it all
   echo "${TBLU}Removing ${Volume}.sparseimage ${TNRM}"
   removeFileWithCheck "${Volume}.sparseimage"
   echo "${TBLU}Removing ${VolumeBase}.sparseimage ${TNRM}"
   removeFileWithCheck "${VolumeBase}.sparseimage"
}

# For smaller more permanent stuff
function createCaseSensitiveVolumeBase()
{
   echo "${TBLU}Creating 4G volume for tools mounted as ${CT_TOP_DIR_BASE} ${TNRM} ..."
    if [  -d "${CT_TOP_DIR_BASE}" ]; then
       echo "${TYEL}WARNING${TNRM}: Volume already exists: ${CT_TOP_DIR_BASE} ${TNRM}"
       return
    fi

   if [ -f "${VolumeBase}.sparseimage" ]; then
      echo "${TRED}WARNING:${TNRM}"
      echo "         File already exists: ${VolumeBase}.sparseimage ${TNRM}"
      echo "         This file will be mounted as ${VolumeBase} ${TNRM}"
  
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
    echo -n "${TBLU}Checking for saved tarballs directory ${TNRM} ${SavedSourcesPath} ..."
    if [ -d "${SavedSourcesPath}" ]; then
       echo "${TGRN} found ${TNRM}"
    else
       if [ "${SavedSourcesPathOpt}" = 'y' ]; then
          echo "${TRED} not found - ${TNRM} Cannot continue when saved sources path does not exist: ${SavedSourcesPathOpt}"
          exit -1
       fi
       echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
       echo -n "${TNRM}Creating ${TNRM} ${SavedSourcesPath} ... "
       mkdir "${SavedSourcesPath}"
       echo "${TGRN} done ${TNRM}"
    fi

}

# This is where the cross compiler and Raspbian will go
function createCaseSensitiveVolume()
{
    VolumeDir="${CT_TOP_DIR}"
    echo "${TBLU}Creating volume mounted as ${TNRM} ${VolumeDir} ..."
    if [ -d "${VolumeDir}" ]; then
       echo "${TYEL}WARNING${TNRM}: Volume already exists: ${VolumeDir}"
       return
    fi

   if [ -f "${Volume}.sparseimage" ]; then
      echo "${TRED}WARNING:${TNRM}"
      echo "         File already exists: ${Volume}.sparseimage ${TNRM}"
      echo "         This file will be mounted as ${Volume} ${TNRM}"
  
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
   echo -n "${TBLU}Checking for:${TNRM} ${COMPILING_LOCATION} ... "
   if [ ! -d "${COMPILING_LOCATION}" ]; then
      mkdir "${COMPILING_LOCATION}"
      echo "${TGRN} created ${TNRM}"
   else
      echo "${TGRN} found ${TNRM}"
   fi
}

function softLinkBrewGTools
{                           

    local cwd
    cwd="${PWD}"
    cd "${BrewHome}/bin"
    for fn in g* ; do     
      if [ "${fn}" = 'grep' ]; then continue; fi   
      if [ "${fn}" = 'gar' ]; then continue; fi 
      if [ "${fn}" = 'groups' ]; then continue; fi  
      if [[ "${fn}" =~ ^gawk* ]]; then continue; fi
      if [ "${fn}" = 'gettext.sh' ]; then continue; fi
      if [ "${fn}" = 'gettextize' ]; then continue; fi
      	

      if [ "${fn}" = 'granlib' ]; then continue; fi  # Fails ncurses for build of gcc cross compiler
      if [ "${fn}" = 'gstrip' ]; then continue; fi  # Fails ncurses for host of gcc cross compiler
      	
      local fnWithoutG=${fn:1:999}
     	if [ ! -L "${fnWithoutG}" ]; then   
     	   echo   linking  "${fn}" "${fnWithoutG}"
    		 ln -s -f "${fn}" "${fnWithoutG}"
    	fi
    done
    
    cd "${cwd}"
}     

function installBrewTool()
{         
   local tool="$1"
   local toolOptions="$2" 
   local doSoftLink="$3" 
   local toolIsForGCCBrew="$4"  
   local pid   
   
   if [ "${toolIsForGCCBrew}"  = 'y' ] &&
   	  [ "${BuildGCCwithBrewOpt}" = 'n' ]
   then  
   	  echo "Skipping ${tool} as BuildGCCwithBrewOpt=n"
   	  return
   fi            
   echo "${TBLU}Installing brew tool ${tool} ${TNRM} .... Logging to /tmp/${tool}_install.log"   
   
   # Do not Exit immediately if a command exits with a non-zero status.    
   set +e                                                                 	
   
   if [ -z "${toolOptions}" ]; then                                                            	
   	 brew install "${tool}"  --build-from-source  > "/tmp/${tool}_install.log" 2>&1 & 
   	 pid="$!"	 
   else      
   	 brew install "${tool}"  --build-from-source  "${toolOptions}"  > "/tmp/${tool}_install.log" 2>&1 &
   	 pid="$!" 
   fi

   waitForPid "${pid}"                                                                              
                                                                                                  
   # Exit immediately if a command exits with a non-zero status                                     
   set -e                                                                                           
                                                                                                  
   if [ "${rc}" != '0' ]; then                                                                      
      echo "${TRED}Error : [${rc}] ${TNRM} brew update tools failed. Check the log for details"     
      exit "${rc}"                                                                                  
   fi                                                                                                   
   echo "${TGRN} done ${TNRM}"  
   
   if [ "${doSoftLink}" = 'y' ]; then
   	   softLinkBrewGTools "${BrewHome}/bin"
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
# gmp is for gawk and isl  
# readline is for gawk    
# makedepend is for openssl
# isl is for gcc  
# cmake is for doxygen    
# doxygen, meson-internal are for libmpclient   
# ninja, sphinx-doc, gdbm, makedepend, openssl, sqlite, python, meson, libmpdclient are for mpc
# mpc is for gcc
# gcc for Raspbian to solve error PIE disabled. Absolute addressing (perhaps -mdynamic-no-pic)  
# libunistring and libidn2   is required for wget
#  openssl is for wget
# for Raspbian tools - libelf ncurses gcc
# for xconfig - QT   (takes hours). That would be up to you.

function buildBrewTools()
{
   echo "${TBLU}Checking for HomeBrew tools ${TNRM}"
   echo -n "${TBLU}Checking for our Brew completion flag ${TNRM} ${BrewHome}.flagBrewComplete ... "
   if [ -f "${BrewHome}/.flagBrewComplete" ]; then
      echo "${TGRN} found ${TNRM}"
      echo "${TNRM} Brew will not be updated ${TNRM}"
      return
   fi
   echo "${TYEL} not found ${TGRN} -OK ${TNRM}"

   if [ ! -d "${BrewHome}" ]; then
      echo "${TBLU}Installing HomeBrew tool ${TNRM} ..."
      mkdir "${BrewHome}"
            
      git clone --depth=1 https://github.com/Homebrew/homebrew.git     "${BrewHome}"    

   else
      echo "${TBLU}   - Using existing Brew installation ${TNRM} in ${BrewHome}"
   fi      
   
   cd "${BrewHome}"

   echo -n "${TBLU}Checking for Brew logs directory ${TNRM} ... "
   if [ ! -d "${HOMEBREW_LOG_PATH}" ]; then
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
      echo -n "${TBLU}Creating brew logs directory: ${TNRM} ${HOMEBREW_LOG_PATH} ... "
      mkdir "${HOMEBREW_LOG_PATH}"
      echo "${TGRN} done ${TNRM}"

   else
      echo "${TGRN} found ${TNRM}"
   fi

   export PATH="${PathWithBrewTools}"

   echo "${TBLU}Updating HomeBrew tools ${TNRM}"
   echo "${TRED}Ignore the ERROR: could not link ${TNRM}"
   echo -n "${TRED}Ignore the message "
   echo "Please delete these paths and run brew update ${TNRM}"
   echo "${TNRM}They are created by brew as it is not in /local or with sudo"
   echo ""

   # I dont know why this is true, but tar fails otherwise
   set +e

   echo "${TBLU}Running Brew update ${TNRM} ... Logging to /tmp/brew_update.log"
   brew update > '/tmp/brew_update.log' 2>&1 &
   pid="$!"
   waitForPid "${pid}"

   # Exit immediately if a command exits with a non-zero status
   set -e

   if [ "${rc}" != '0' ]; then
      echo "${TRED}Error : [${rc}] ${TNRM} brew update tools failed. Check the log for details"
      exit "${rc}"
   fi
   echo "${TGRN} done ${TNRM}"
  
   installBrewTool 'm4'             ''                     'n' 'n'
   installBrewTool 'coreutils'      ''                     'y' 'n'
   installBrewTool 'findutils'      ''                     'y' 'n'
   installBrewTool 'libtool'        ''                     'y' 'n'
   installBrewTool 'pkg-config'     ''                     'n' 'n'
   installBrewTool 'pcre'           ''                     'n' 'n'
   installBrewTool 'grep'           '--with-default-names' 'y' 'n'
   installBrewTool 'ncurses'        ''                     'n' 'n'
   installBrewTool 'gettext'        ''                     'n' 'n'
   echo -n "${TBLU}Adding brew symbolic links for gettext ${TNRM} "
   brew link --force gettext                                       
   echo "${TGRN} done ${TNRM}"                                     
   installBrewTool 'xz'             ''                     'n' 'n'
   installBrewTool 'gnu-sed'        '--with-default-names' 'n' 'n' 
   installBrewTool 'gmp'            ''                     'n' 'n'  
   installBrewTool 'mpfr'           ''                     'n' 'n'      
   installBrewTool 'readline'       ''                     'n' 'n'
   installBrewTool 'gawk'           ''                     'y' 'n'
   installBrewTool 'binutils'       ''                     'y' 'n'  
   installBrewTool 'isl'            ''                     'n' 'n'  
   installBrewTool 'ninja'          ''                     'n' 'y'
   installBrewTool 'sphinx-doc'     ''                     'n' 'y'
   installBrewTool 'gdbm'           ''                     'n' 'n'
   installBrewTool 'makedepend'     ''                     'n' 'n'
   installBrewTool 'openssl'        ''                     'n' 'n'
   installBrewTool 'sqlite'         ''                     'n' 'y'
   installBrewTool 'python'         ''                     'n' 'y'
   installBrewTool 'meson'          ''                     'n' 'y' 
   installBrewTool 'cmake  '        ''                     'n' 'y'    
   installBrewTool 'doxygen'        ''                     'n' 'y' 
   installBrewTool 'meson-internal' ''                     'n' 'y'   
   installBrewTool 'libmpdclient'   ''                     'n' 'y'  
   installBrewTool 'mpc'            ''                     'n' 'y'
   installBrewTool 'help2man'       ''                     'n' 'n'
   installBrewTool 'autoconf'       ''                     'n' 'n'
   installBrewTool 'automake'       ''                     'n' 'n'
   installBrewTool 'bison'          ''                     'n' 'n'
   installBrewTool 'bash'           ''                     'n' 'n'  
   installBrewTool 'libunistring'   ''                     'n' 'n' 
   installBrewTool 'libidn2'        ''                     'n' 'n'
   installBrewTool 'wget'           ''                     'n' 'n'
   installBrewTool 'sha2'           ''                     'y' 'n'
   installBrewTool 'libelf'         ''                     'n' 'n'
   installBrewTool 'texinfo'        ''                     'n' 'n'
   installBrewTool 'gcc'            ''                     'n' 'y'                      
                  
   
   echo -n "${TBLU}Adding brew symbolic links for gettext ${TNRM} "
   brew link --force gettext
   echo "${TGRN} done ${TNRM}"

   echo -n "${TBLU}Checking for ${TNRM} ${BrewHome}/bin/gsha512sum ${TNRM} ... "
   if [ ! -f "${BrewHome}/bin/gsha512sum" ]; then
      echo "${TRED} not found ${TNRM}"
      exit 1
   fi
   echo "${TGRN} found ${TNRM}"
   echo -n "${TBLU}Checking for ${TNRM} ${BrewHome}/bin/sha512sum ${TNRM} ... "
   if [ ! -f "${BrewHome}/bin/sha512sum" ]; then
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
      echo "${TNRM}Linking gsha512sum to sha512sum ${TNRM}"
      ln -s "${BrewHome}/bin/gsha512sum" "${BrewHome}/bin/sha512sum"
   else
      echo "${TGRN} found ${TNRM}"
   fi

   echo -n "${TBLU}Checking for ${TNRM} ${BrewHome}/bin/gsha256sum ${TNRM} ... "
   if [ ! -f "${BrewHome}/bin/gsha256sum" ]; then
      echo "${TRED} not found ${TNRM}"
      exit 1
   fi
   echo "${TGRN} found ${TNRM}"

   echo -n "${TBLU}Checking for ${TNRM} ${BrewHome}/bin/sha256sum ${TNRM} ... "
   if [ ! -f "${BrewHome}/bin/sha256sum" ]; then
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
      echo "${TNRM}Linking gsha256sum to sha256sum ${TNRM}"
      ln -s "${BrewHome}/bin/gsha256sum" "${BrewHome}/bin/sha256sum"
   else
      echo "${TGRN} found ${TNRM}"
   fi

   echo -n "${TBLU}Checking for ${TNRM} ${BrewHome}/bin/readlink ${TNRM} ... "
   if [ ! -f "${BrewHome}/bin/readlink" ]; then
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
      echo "${TNRM}Linking greadlink to readlink ${TNRM}"
      ln -s "${BrewHome}/bin/greadlink" "${BrewHome}/bin/readlink"
   else
      echo "${TGRN} found ${TNRM}"
   fi

   echo -n "${TBLU}Checking for ${TNRM} ${BrewHome}/bin/stat ${TNRM} ... "
   if [ ! -f "${BrewHome}/bin/stat" ]; then
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
      echo "${TNRM}Linking gstat to stat ${TNRM}"
      ln -s "${BrewHome}/bin/gstat" "${BrewHome}/bin/stat"
   else
      echo "${TGRN} found ${TNRM}"
   fi


   echo -n "${TBLU}Checking for ${TNRM} ${BrewHome}/bin/grep ${TNRM} ... "
   if [ ! -f "${BrewHome}/bin/grep" ]; then
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
      echo "${TNRM}Linking ggrep to grep ${TNRM}"
      ln -s "${BrewHome}/bin/ggrep" "${BrewHome}/bin/grep"
   else
      echo "${TGRN} found ${TNRM}"
   fi

   echo -n "${TBLU}Checking for ${TNRM} ${BrewHome}/opt/gcc/bin/gcc-8 ... "
   if [ -f "${BrewHome}/opt/gcc/bin/gcc-8" ]; then
      echo "${TGRN} found ${TNRM}"
      echo -n "${TBLU} Linking gcc-8 tools to gcc ${TNRM} ... "
      rc="n"
      cd "${BrewHome}/opt/gcc/bin"
      for fn in *-8 ; do
         local newFn=${fn/-8}
         if [ ! -L "${newFn}" ]; then
            if [ "${rc}" = 'n' ]; then
               echo "${TGRN} found ${TNRM}"
            fi
            rc='y'
            echo -n "${TNRM}linking ${fn} to ${newFn} ... "
            ln -sf "${fn}" "${newFn}"
            echo "${TGRN} done ${TNRM}"
         fi
      done
      if [ "${rc}" = 'n' ]; then
         echo "${TGRN}links already in place ${TNRM}"
      fi
   else
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
   fi

   echo -n "${TGRN}Creating ${TNRM} ${BrewHome}.flagBrewComplete ... "
   touch "${BrewHome}/.flagBrewComplete"
   echo "${TGRN} done ${TNRM}"

}
# Brew binutils does not build ld, so rebuild them again
# Trying to build them first before gcc, causes ld not
# to be built.
function buildBinutilsForHost()
{
   local binutilsDir='binutils-2.30'
   local binutilsFile="${binutilsDir}.tar.xz"
   local binutilsURL="https://mirror.sergal.org/gnu/binutils/${binutilsFile}"

   echo -n "${TBLU}Checking for a working ld ${TNRM} ... "
   if [ -x "${BrewHome}/bin/ld" ]; then
      echo "${TGRN} found ${TNRM}"
      return
   fi
   echo "${TYEL}Not found ${TGRN} -OK ${TNRM}"

   echo -n "${TBLU}Checking for a existing binutils source ${TNRM} ${COMPILING_LOCATION}/${binutilsDir} ... "
   if [ -d "${COMPILING_LOCATION}/${binutilsDir}" ]; then
      echo "${TGRN} found ${TNRM}"
   else
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"

      echo -n "${TBLU}Checking for a saved ${binutilsFile} ${TNRM} ... "
      if [ -f "${SavedSourcesPath}/${binutilsFile}" ]; then
         echo "${TGRN} found ${TNRM}"
      else
         echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
         echo -n "${TBLU}Downloading ${binutilsFile} ${TNRM} ... "
         curl -Lsf "${binutilsURL}" -o "${SavedSourcesPath}/${binutilsFile}"
         echo "${TGRN} done ${TNRM}"
      fi
      echo "${TBLU}Extracting ${binutilsFile} ${TNRM} ... Logging to /tmp/binutils_extract.log"
      # I dont know why this is true, but configure fails otherwise
      set +e

      tar -xzf "${SavedSourcesPath}/${binutilsFile}" -C "${COMPILING_LOCATION}" > '/tmp/binutils_extract.log' 2>&1 &
      pid="$!"

      waitForPid "${pid}"

      # Exit immediately if a command exits with a non-zero status
      set -e

      if [ "${rc}" != '0' ]; then
         echo "${TRED}Error : [${rc}] ${TNRM} extract failed. Check the log for details"
         exit "${rc}"
      fi
      echo "${TGRN} done ${TNRM}"
   fi

   echo "${TBLU}Configuring ${binutilsDir} ${TNRM} ... Logging to /tmp/binutils_configure.log"

   # I dont know why this is true, but configure fails otherwise
   set +e

   cd "${COMPILING_LOCATION}/${binutilsDir}"

   EPREFIX='' ./configure --prefix="${BrewHome}" --enable-ld=yes --target=x86_64-unknown-elf --disable-werror --enable-multilib --program-prefix='' > /tmp/binutils_configure.log 2>&1 &
   pid="$!"

   waitForPid "${pid}"

   # Exit immediately if a command exits with a non-zero status
   set -e

   if [ "${rc}" != '0' ]; then
      echo "${TRED}Error : [${rc}] ${TNRM} configure failed. Check the log for details"
      exit "${rc}"
   fi
   echo "${TGRN} done ${TNRM}"

   echo "${TBLU}Compiling ${binutilsDir} ${TNRM} ... Logging to /tmp/binutils_compile.log"

   # I dont know why this is true, but configure fails otherwise
   set +e

   make > '/tmp/binutils_compile.log' 2>&1 &
   pid="$!"
   waitForPid "${pid}"

   # Exit immediately if a command exits with a non-zero status
   set -e

   if [ "${rc}" != '0' ]; then
      echo "${TRED}Error : [${rc}] ${TNRM} build failed. Check the log for details"
      exit "${rc}"
   fi
   echo "${TGRN} done ${TNRM}"

   echo "${TBLU}Installing ${binutilsDir} ${TNRM} ... Logging to /tmp/binutils_install.log"

   # I dont know why this is true, but make fails otherwise
   set +e

   make install > '/tmp/binutils_install.log' 2>&1 &
   pid="$!"
   waitForPid "${pid}"

   # Exit immediately if a command exits with a non-zero status
   set -e

   if [ "${rc}" != '0' ]; then
      echo "${TRED}Error : [${rc}] ${TNRM} configure failed. Check the log for details"
      exit "${rc}"
   fi
   echo "${TGRN} done ${TNRM}"

}

function downloadCrossTool()
{
   echo "${TBLU}Downloading crosstool-ng ${TNRM} to ${COMPILING_LOCATION}"
   local CrossToolArchive="${CrossToolVersion}.tar.bz2"
   if [ -f "${SavedSourcesPath}/${CrossToolArchive}" ]; then
      echo "   -Using existing archive ${CrossToolArchive} ${TNRM}"
   else
      CrossToolUrl="http://crosstool-ng.org/download/crosstool-ng/${CrossToolArchive}"
      curl -L -o "${SavedSourcesPath}/${CrossToolArchive}" "${CrossToolUrl}"
   fi

   if [ -d "${COMPILING_LOCATION}/${CrossToolSourceDir}" ]; then
      echo "   ${TRED}WARNING${TNRM} - ${CrossToolSourceDir} exists and will be used."
      echo "   ${TRED}WARNING${TNRM} - Remove it to start fresh"
   else
      tar -xf "${SavedSourcesPath}/${CrossToolArchive}" \
         -C "${COMPILING_LOCATION}/${CrossToolSourceDir}"
   fi
}
function downloadCrossTool_LATEST()
{
   export PATH="${PathWithBrewTools}"

   cd "${COMPILING_LOCATION}"
   echo "${TBLU}Downloading crosstool-ng ${TNRM} to ${COMPILING_LOCATION}"

   if [ -d "${COMPILING_LOCATION}/${CrossToolSourceDir}" ]; then
      echo "   ${TRED}WARNING${TNRM} - ${CrossToolSourceDir} exists and will be used."
      echo "   ${TRED}WARNING${TNRM} - Remove it to start fresh"
      return
   fi

   local CrossToolUrl="https://github.com/crosstool-ng/crosstool-ng.git"
   CrossToolArchive="${CrossToolVersion}_latest.tar.xz"

   if [ -f "${SavedSourcesPath}/${CrossToolArchive}" ]; then
      echo "   -Using existing archive ${CrossToolArchive} ${TNRM}"
  
      echo -n "${TBLU}Decompressing ${TNRM} ${CrossToolArchive} ... "
  
      tar -xf "${SavedSourcesPath}/${CrossToolArchive}" -C "${COMPILING_LOCATION}"
  
      echo "${TGRN} done ${TNRM}"
  
   else
      git clone "${CrossToolUrl}"  "${COMPILING_LOCATION}/${CrossToolSourceDir}"
   fi

   if [ ! -f "${SavedSourcesPath}/${CrossToolArchive}" ]; then
      echo -n "${TBLU}saving ${TNRM} ${CrossToolArchive} ... "
  
      tar -cJf "${SavedSourcesPath}/${CrossToolArchive}" \
         "${COMPILING_LOCATION}/${CrossToolSourceDir}"
  
      echo "${TGRN} done ${TNRM}"
   fi

   # We need to creat the configure tool
   echo "${TBLU}Running  crosstool bootstrap in ${TNRM} ${COMPILING_LOCATION}"
   cd "${COMPILING_LOCATION}/${CrossToolSourceDir}"

   # crosstool-ng-1.23.0 still has CT_Mirror
   # git checkout -b $CrossToolVersion

   ./bootstrap
}

function patchConfigFileForVolume()
{
    echo -n "${TBLU}Patching .config file for -V option ${TNRM} in ${COMPILING_LOCATION} ... "

    if [ "${VolumeOpt}" = 'y' ]; then
       echo "${TGRN} required ${TNRM}"
       echo -n "${TBLU}Changing /Volumes/CrossToolNG ${TNRM} to /Volumes/${Volume} ... "

       if [ -f "${COMPILING_LOCATION}/.config" ]; then
          sed -i.bak -e's/CrossToolNG/'${Volume}'/g' "${COMPILING_LOCATION}/.config"
          echo "${TGRN} done ${TNRM}"
       else
           echo "${TRED} not found ${TNRM}"
           echo "${TRED} aborting ${TNRM}"
           exit -1
       fi
    else
       echo "${TYEL} not specified. not required ${TNRM}"
       echo "${TNRM}.config file not being patched as -V was not specified"
    fi
}

function patchConfigFileForOutputDir()
{
    echo -n "${TBLU}Patching .config file for -O option ${TNRM} in ${COMPILING_LOCATION} ... "
 
    if [ "${OutputDirOpt}" = 'y' ]; then
       echo "${TGRN} required ${TNRM}"
       echo -n "${TBLU}Changing x-tools ${TNRM} to ${OutputDir} ... "
       if [ -f "${COMPILING_LOCATION}/.config" ]; then
           sed -i.bak2 -e's/x-tools/'${OutputDir}'/g' "${COMPILING_LOCATION}/.config"
           echo "${TGRN} done ${TNRM}"
       else
           echo "${TRED} not found ${TNRM}"
           echo "${TRED} aborting ${TNRM}"
           exit -1
       fi
    else
       echo "${TGRN} not required ${TNRM}"
       echo "${TNRM}.config file not being patched as -O was not specified"
    fi

}

function patchConfigFileForSavedSourcesPath()
{
    echo -n "${TBLU}Patching .config file for -S ootion ${TNRM} in ${COMPILING_LOCATION} ... "
    if [ "${SavedSourcesPathOpt}" = 'y' ]; then
       echo "${TGRN} required ${TNRM}"
       echo -n "${TBLU}Changing ${CT_TOP_DIR}/sources ${TNRM} to ${SavedSourcesPath} ... "
       if [ -f "${COMPILING_LOCATION}/.config" ]; then
          # Since a path may have a slash, use a  pound sign as a delimeter
          sed -i.bak3 -e's#CT_LOCAL_TARBALLS_DIR="/Volumes/'${VolumeBase}'/sources"#CT_LOCAL_TARBALLS_DIR="'${SavedSourcesPath}'"#g' "${COMPILING_LOCATION}/.config"
      
          echo "${TGRN} done ${TNRM}"
       else
          echo "${TRED} not found ${TNRM}"
          echo "${TRED} aborting ${TNRM}"
          exit -1
       fi
    else
       echo "${TYEL} not specified. not required ${TNRM}"
       echo "${TNRM}.config file not being patched as -S was not specified"
    fi
}

function patchCrosstool()
{
    echo "${TBLU}Patching crosstool-ng ${TNRM}"
    if [ -x "${CT_TOP_DIR_BASE}/ctng/bin/ct-ng" ]; then
      echo "${TYEL}    - found existing ct-ng. Using it instead ${TNRM}"
      return
    fi

    cd "${COMPILING_LOCATION}/${CrossToolSourceDir}"
    echo "${TBLU}Patching crosstool-ng ${TNRM} in ${PWD}"

    echo "${TNRM}   -No Patches required."

# patch required with crosstool-ng-1.17
# left here as an example of how it was done.
#    sed -i .bak '6i\
##include <stddef.h>' kconfig/zconf.y
}

function compileCrosstool()
{
   echo "${TBLU}Configuring crosstool-ng ${TNRM} in ${PWD}"
   if [ -x "${CT_TOP_DIR_BASE}/ctng/bin/ct-ng" ]; then
      echo "${TGRN}    - found existing ct-ng. Using it instead ${TNRM}"
      return
   fi

   export PATH="${PathWithBrewTools}"

   cd "${COMPILING_LOCATION}/${CrossToolSourceDir}"


   # It is strange that gettext is put in opt
   gettextDir="${BrewHome}/opt/gettext"

   echo "${TBLU} Executing configure for crosstool-ng ${TNRM} --with-libintl-prefix"

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
      echo "${TRED}Error : [${rc}] ${TNRM} configure failed. Check the log for details "
      exit "${rc}"
   fi
   echo "${TGRN} Configure of crosstool-ng is done ${TNRM}"

   echo "${TBLU}Compiling crosstool-ng ${TNRM} in ${PWD} ... Logging to /tmp/ctng_build.log"

   # I dont know why this is true, but make fails otherwise
   set +e

   make > '/tmp/ctng_build.log' 2>&1 &
   pid="$!"
   waitForPid "${pid}"

   # Exit immediately if a command exits with a non-zero status
   set -e

   if [ "${rc}" != '0' ]; then
      echo "${TRED}Error : [${rc}] ${TNRM} build failed. Check the log for details"
      exit "${rc}"
   fi
   echo "${TGRN} done ${TNRM}"

   echo "${TBLU}Installing crosstool-ng ${TNRM} in ${CT_TOP_DIR_BASE}/ctng ... Logging to /tmp/ctng_install.log"

   # I dont know why this is true, but make fails otherwise
   set +e

   make install > '/tmp/ctng_install.log' 2>&1 &
   pid="$!"
   waitForPid "${pid}"

   # Exit immediately if a command exits with a non-zero status
   set -e

   if [ "${rc}" != '0' ]; then
      echo "${TRED}Error : [${rc}] ${TNRM} install failed. Check the log for details"
      exit "${rc}"
   fi
   echo "${TGRN}Compilation of ct-ng is Complete ${TNRM}"
}

function createCrossCompilerConfigFile()
{

   cd "${COMPILING_LOCATION}"

   echo -n "${TBLU}Checking for target ct-ng config file ${TNRM} ${COMPILING_LOCATION}/.config ... "
   if [ -f  "${COMPILING_LOCATION}/.config" ]; then
      echo "${TGRN} found ${TNRM}"
      echo "${TYEL}Using existing .config file. ${TNRM}"
      echo "${TNRM}Remove it if you wish to start over."
      return
   else
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
   fi


   echo -n "${TBLU}Checking for an existing toolchain config file: ${TNRM} ${ThisToolsStartingPath}/${CrossToolNGConfigFile} ... "
   if [ -f "${ThisToolsStartingPath}/${CrossToolNGConfigFile}" ]; then
      echo "${TNRM}   - Using ${ThisToolsStartingPath}/${CrossToolNGConfigFile} "
      cp "${ThisToolsStartingPath}/${CrossToolNGConfigFile}"  "${COMPILING_LOCATION}/.config"

      cd "${COMPILING_LOCATION}"
  
      patchConfigFileForVolume
  
      patchConfigFileForOutputDir

      patchConfigFileForSavedSourcesPath

   else
      echo "${TNRM}   - None found ${TNRM}"
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

   echo "${TBLU}Once your finished tinkering with ct-ng menuconfig ${TNRM}"
   echo "${TBLU}to contineu the build ${TNRM}"
   echo "${TBLU}Execute: ${TNRM} ./build.sh ${CmdOptionString} -b"

}

function buildCTNG()
{
   echo -n "${TBLU}Checking for an existing ct-ng ${TNRM} ${CT_TOP_DIR_BASE}/ctng/bin/ct-ng ... "
   if [ -x "${CT_TOP_DIR_BASE}/ctng/bin/ct-ng" ]; then
      echo "${TGRN} found ${TNRM}"
      echo "${TYEL}Remove it if you wish to have it rebuilt ${TNRM}"
      return
   else
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
      echo "${TNRM}Continuing with build"
   fi

   # The 1.23  archive is busted and does not contain CT_Mirror, until
   # it is fixed, use git Latest
   if [ "${DownloadCrosstoolLatestOpt}" = 'y' ]; then
      downloadCrossTool_LATEST
   else
      downloadCrossTool
   fi

   patchCrosstool
   compileCrosstool
}

function runCTNG()
{
   echo "${TBLU}Building Cross Compiler toolchain ${TNRM}"
   echo -n "${TBLU}Checking if ${ToolchainName}-gcc already exists ${TNRM} ... "
   testBuild
   if [ "${rc}" = '0' ]; then
      echo -n "${TGRN} found ${TNRM}"
      echo "${TNRM} To rebuild it, remove the old first"
      return
   else
      echo -n "${TYEL} not found ${TGRN} -OK ${TNRM}"
      echo "${TNRM} Continuing with the build"
   fi

   createCrossCompilerConfigFile

   cd "${COMPILING_LOCATION}"

   echo -n "${TBLU}Checking for:${TNRM} ${COMPILING_LOCATION}/.config ... "
   if [ ! -f "${COMPILING_LOCATION}/.config" ]; then
      echo -n "${TRED}ERROR: You have still not created a: ${TNRM}"
      echo "${COMPILING_LOCATION}/.config file. ${TNRM}"
      echo "${TNRM}Change directory to ${COMPILING_LOCATION}"
      echo "${TNRM}And run: ./ct-ng menuconfig"
      echo "${TNRM}Before continuing with the build. "

      exit -1
   else
      echo "${TGRN} found ${TNRM}"
   fi
   export PATH="${PathWithBrewTools}"

   if [ "${RunCTNGOptArg}" = 'list-steps' ]; then
      ct-ng "${RunCTNGOptArg}"
      return
   fi
   if [ "${RunCTNGOptArg}" = 'build' ]; then
      echo "${TBLU} Executing ct-ng build to build the cross compiler ${TNRM}"
   else
      echo "${TBLU} Executing ct-ng ${RunCTNGOptArg} ${TNRM}"
   fi
  
   ct-ng "${RunCTNGOptArg}"

   echo "${TNRM}And if all went well, you are done! Go forth and cross compile"
   echo "Raspbian if you so wish with: ./build.sh ${CmdOptionString} -b Raspbian"
}

function buildLibtool()
{
    cd "${COMPILING_LOCATION}/libelf"
    # ./configure --prefix=${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}
    ./configure  -prefix="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}" --host="${ToolchainName}"
    make
    make install
}

function downloadAndBuildzlibForTarget()
{
   local zlibFile='zlib-1.2.11.tar.gz'
   local zlibURL="https://zlib.net/${zlibFile}"

   echo -n "${TBLU}Checking for Cross Compiled ${TNRM} zlib.h and libz.a ... "
   if [ -f "${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/include/zlib.h" ] &&
      [ -f  "${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/lib/libz.a" ]; then
      echo "${TGRN} found ${TNRM}"
      return
   fi
   echo "${TYEL} not found ${TGRN} -OK ${TNRM}"

   echo -n "${TBLU}Checking for ${TNRM} ${COMPILING_LOCATION}/zlib-1.2.11 ... "
   if [ -d "${COMPILING_LOCATION}/zlib-1.2.11" ]; then
      echo "${TGRN} found ${TNRM}"
      echo "${TNRM} Using existing zlib source ${TNRM}"
   else
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
      cd "${COMPILING_LOCATION}"
      echo -n "${TBLU}Checking for saved ${TNRM} ${zlibFile} ... "
      if [ -f "${SavedSourcesPath}/${zlibFile}" ]; then
         echo "${TGRN} found ${TNRM}"
      else
         echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
         echo -n "${TBLU}Downloading ${TNRM} ${zlibFile} ... "
         curl -Lsf "${zlibURL}" -o "${SavedSourcesPath}/${zlibFile}"
         echo "${TGRN} done ${TNRM}"
      fi
      echo -n "${TBLU}Decompressing ${TNRM} ${zlibFile} ... "
      tar -xzf "${SavedSourcesPath}/${zlibFile}" -C "${COMPILING_LOCATION}"
      echo "${TGRN} done ${TNRM}"
   fi

    echo "${TBLU} Configuring zlib ${TNRM} Logging to /tmp/zlib_config.log"
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
       echo "${TRED}Error : [${rc}] ${TNRM} configure failed. Check the log for details"
       exit "${rc}"
    fi

    echo "${TBLU} Building zlib ${TNRM} Logging to /tmp/zlib_build.log"

    # I dont know why this is true, but build fails otherwise
    set +e
    make > '/tmp/zlib_build.log' 2>&1 &

    pid="$!"
    waitForPid "${pid}"

    # Exit immediately if a command exits with a non-zero status
    set -e

    if [ "${rc}" != '0' ]; then
       echo "${TRED}Error : [${rc}] ${TNRM} build failed. Check the log for details"
       exit "${rc}"
    fi

    echo "${TBLU} Installing zlib ${TNRM} Logging to /tmp/zlib_install.log"

    # I dont know why this is true, but install fails otherwise
    set +e
    make install > '/tmp/zlib_install.log' 2>&1 &

    pid="$!"
    waitForPid "${pid}"

    # Exit immediately if a command exits with a non-zero status
    set -e

    if [ "${rc}" != '0' ]; then
       echo "${TRED}Error : [${rc}] ${TNRM} install failed. Check the log for details"
       exit "${rc}"
    fi

}

function downloadElfLibrary()
{
   local elfLibURL='https://github.com/WolfgangSt/libelf.git'

   cd "${COMPILING_LOCATION}"
   echo "${TBLU}Downloading libelf latest ${TNRM} to ${PWD}"

   if [ -d 'libelf' ]; then
      echo "${TRED}WARNING ${TNRM}Path already exists libelf ${TNRM}"
      echo "        A fetch will be done instead to keep tree up to date"
      echo ""
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
      echo "${TYEL}No executable compiler found. ${TNRM} ${gpp}"
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
    echo("Thread %d says %s \n", data->thread_no, data->message);

    pthread_exit(0); /* exit */
} /* print_message_function ( void *ptr ) */



TEST_PTHREADS_EOF


   echo -n "${TBLU}Testing Compiler in PATH for pthreads ${TNRM} CMD = gcc /tmp/pthreadsWorld.c -o /tmp/pthreadsWorld ... "

   gcc /tmp/pthreadsWorld.c -o /tmp/pthreadsWorld
   rc=$?
   if [ "${rc}" != '0' ]; then
      echo "${TRED} failed ${TNRM}"
      return ${rc}
   fi
   echo "${TGRN} passed ${TNRM}"

   echo "${TBLU}Testing executable for pthreads ${TNRM} CMD = /tmp/pthreadsWorld"
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


   echo -n "${TBLU}Testing Compiler in PATH for pie ${TNRM} CMD = g++ /tmp/PIEWorld.cpp -o /tmp/PIEWorld ... "

   g++ /tmp/PIEWorld.cpp -o /tmp/PIEWorld
   rc=$?
   if [ "${rc}" != '0' ]; then
      echo "${TRED} failed ${TNRM}"
      return ${rc}
   fi
   echo "${TGRN} passed ${TNRM}"

   echo "${TBLU}Testing executable for pie ${TNRM} CMD = /tmp/PIEWorld"
   /tmp/PIEWorld
   rc=$?
}

function testHostgcc()
{

   echo -n "${TBLU}Finding Compiler in PATH ${TNRM} CMD = which g++ ... "
   local whichgcc
   whichgcc=$(command -v g++)
   if [ "${whichgcc}" = '' ]; then
      echo "${TRED} failed ${TNRM}"
      echo "${TRED} No executable compiler found. ${TNRM}"
      rc='-1'
      return
   fi
   echo "${TGRN} found: ${TNRM} ${whichgcc}"

cat <<'HELLO_WORLD_EOF' > /tmp/HelloWorld.cpp
#include <iostream>
using namespace std;

int main ()
{
  cout << "Hello World!\n";
  return 0;
}
HELLO_WORLD_EOF

   echo -n "${TBLU}Testing Compiler in PATH ${TNRM} CMD = g++ /tmp/HelloWorld.cpp -o /tmp/HelloWorld ... "

   g++ /tmp/HelloWorld.cpp -o /tmp/HelloWorld
   rc=$?
   if [ "${rc}" != '0' ]; then
      echo "${TRED} failed ${TNRM}"
      return "${rc}"
   fi
   echo "${TGRN} passed ${TNRM}"

   echo "${TBLU}Testing executable ${TNRM} CMD = /tmp/HelloWorld"
   /tmp/HelloWorld
   rc=$?


}

function testHostCompiler()
{
   echo "${TBLU}Running Host Compiler tests ${TNRM}"
   export PATH="${PathWithBrewTools}"

   testHostgcc
   if [ "${rc}" != '0' ]; then
      echo "${TRED} Boooo ! it failed :-( ${TNRM}"
      exit "${rc}"
   fi

   testHostCompilerForPIE
   if [ "${rc}" != '0' ]; then
      echo "${TRED} Boooo ! it failed :-( ${TNRM}"
      exit "${rc}"
   fi

   testHostCompilerForpthreads
   if [ "${rc}" != '0' ]; then
      echo "${TRED} Boooo ! it failed :-( ${TNRM}"
      exit "${rc}"
   fi

   echo "${TGRN} Wahoo ! it works!! ${TNRM}"

}
function testCrossCompiler()
{
   echo "${TBLU}Testing toolchain ${ToolchainName} ${TNRM}"

   testBuild   # testBuild sets rc
   if [ "${rc}" = '0' ]; then
      echo "${TGRN} Wahoo ! it works!! ${TNRM}"
      exit 0
   else
      echo "${TRED} Boooo ! it failed :-( ${TNRM}"
      exit -1
   fi
}

function buildCrossCompiler()
{
   createCrossCompilerConfigFile
   echo -n "${TBLU}Checking for working cross compiler first ${TNRM} ${ToolchainName}-g++ ... "
   testBuild   # testBuild sets rc
   if [ "${rc}" = '0' ]; then
      echo "${TGRN} found ${TNRM}"
      if [ "${BuildRaspbianOpt}" = 'y' ]; then
         return
      fi
      echo "${TNRM}To rebuild it again, remove the old one first ${TBLU}or ${TNRM}"
      echo "${TBLU}Execute:${TNRM} ./build.sh ${CmdOptionString} -b Raspbian ${TNRM}"
      echo "${TNRM}to start building Raspbian"

   else
      runCTNG
   fi

}

function downloadRaspbianKernel()
{
   local RaspbianURL='https://github.com/raspberrypi/linux.git'

   echo "${TMAG}*******************************************************************************${TNRM}"
   echo "${TMAG}* WHEN CONFIGURING THE RASPIAN KERNEL CHECK THAT THE"
   echo "${TMAG}*  COMPILER PREFIX IS: ${TRED} ${ToolchainName}-  ${TNRM}"
   echo "${TMAG}*******************************************************************************${TNRM}"

   # This is so very important that we must make sure you remember to set the compiler prefix
   # Maybe at a later date this will be automated
   # read -p 'Press any key to continue'
   sleep 5


   cd "${COMPILING_LOCATION}"
   echo -n "${TBLU}Downloading Raspbian Kernel latest ${TNRM} "


   echo -n "${TBLU}Checking for ${TNRM} ${RaspbianSrcDir} ... "
   if [ ! -d "${RaspbianSrcDir}" ]; then
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
      echo -n "${TBLU}Creating ${TNRM}${RaspbianSrcDir} ... "
      mkdir "${RaspbianSrcDir}"
      echo "${TGRN} done ${TNRM}"
   else
      echo "${TGRN} found ${TNRM}"
   fi

   cd "${COMPILING_LOCATION}/${RaspbianSrcDir}"

   echo -n "${TBLU}Checking for ${TNRM} ${RaspbianSrcDir}/linux ... "
   if [ -d "${COMPILING_LOCATION}/${RaspbianSrcDir}/linux" ]; then
      cd "${COMPILING_LOCATION}/${RaspbianSrcDir}/linux"
      echo "${TGRN} found ${TNRM}"
      echo "${TRED}WARNING ${TNRM}Path already exists ${RaspbianSrcDir} ${TNRM}"
      cd "${COMPILING_LOCATION}/${RaspbianSrcDir}/linux"
  
   else
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
      echo -n "${TBLU}Checking for saved ${TNRM} Raspbian.tar.xz ... "
      if [ -f "${SavedSourcesPath}/Raspbian.tar.xz" ]; then
         echo "${TGRN} found ${TNRM}"

         cd "${COMPILING_LOCATION}/${RaspbianSrcDir}"
         echo "${TBLU}Extracting saved ${TNRM} ${SavedSourcesPath}/Raspbian.tar.xz ... Logging to /tmp/Raspbian_extract.log"

         # I dont know why this is true, but tar fails otherwise
         set +e
         tar -xzf "${SavedSourcesPath}/Raspbian.tar.xz"  > '/tmp/Raspbian_extract.log' 2>&1 &

         pid="$!"
         waitForPid "${pid}"

         # Exit immediately if a command exits with a non-zero status
         set -e

         if [ "${rc}" != '0' ]; then
            echo "${TRED}Error : [${rc}] ${TNRM} extract failed."
            exit "${rc}"
         fi

         echo "${TGRN} done ${TNRM}"
     
      else
         echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
         echo "${TBLU}Cloning Raspbian from git ${TNRM}"
         echo "${TBLU}This will take a while, but a copy will ${TNRM}"
         echo "${TBLU}be saved for the future. ${TNRM}"
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

         echo "${TGRN} done ${TNRM}"

         echo "${TBLU}Checking out remotes/origin/rpi-4.18.y ${TNRM}"
         cd 'linux'
         git checkout -b 'remotes/origin/rpi-4.18.y'

         echo "${TGRN} checkout complete ${TNRM}"

         # Patch source for RT Linux
         # wget -O rt.patch.gz https://www.kernel.org/pub/linux/kernel/projects/rt/4.14/older/patch-4.14.18-rt15.patch.gz
         # zcat rt.patch.gz | patch -p1

         echo "${TBLU}Saving Raspbian source ${TNRM} to ${SavedSourcesPath}/Raspbian.tar.xz ...  Logging to raspbian_compress.log"

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
            echo "${TRED}Error : [${rc}] ${TNRM} save failed. Check the log for details"
            exit "${rc}"
         fi
         echo "${TGRN} done ${TNRM}"
      fi
   fi

}

function downloadElfHeaderForOSX()
{
   local ElfHeaderFile='/usr/local/include/elf.h'
   echo -n "${TBLU}Checking for ${TNRM} ${ElfHeaderFile} ... "
   if [ -f "${ElfHeaderFile}" ]; then
      echo "${TGRN} found ${TNRM}"
   else
      echo ""
      echo ""
      echo "${TRED} *** IMPORTANT*** ${TNRM}"
      echo "${TRED}The gcc with OSX does not have an elf.h"
      echo "${TRED}No CFLAGS will fix this as the compile strips them"
      echo "${TRED}A copy from GitHub will be placed in /usr/local/include"
      echo "${TRED}It will be removed after use.${TNRM}"
      echo ""
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
   echo -n "${TBLU}Checking for ${TNRM} ${ElfHeaderFile} ... "
   if [ -f "${ElfHeaderFile}" ]; then
      echo "${TGRN} found ${TNRM}"
      # if [[ $(grep 'Mathias Lafeldt <mathias.lafeldt@gmail.com>' "${ElfHeaderFile}") ]];then
      if grep -q 'Mathias Lafeldt <mathias.lafeldt@gmail.com>' "${ElfHeaderFile}" ; then
         echo -n "${TGRN}Removing ${ElfHeaderFile} ${TNRM} ... "
         rm "${ElfHeaderFile}"
         echo "${TGRN} done ${TNRM}"
      else
         echo "${TRED} not done ${TNRM}"
         echo "${TRED}Warning. There is a ${TNRM} ${ElfHeaderFile}"
         echo "${TRED}But it was not put there by this tool, I believe ${TNRM}"
         sleep 4
      fi
   else
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"

   fi
}

function configureRaspbianKernel()
{
   cd "${COMPILING_LOCATION}/${RaspbianSrcDir}/linux"
   echo "${TBLU}Configuring Raspbian Kernel ${TNRM} in ${PWD}"

   export PATH="${PathWithCrossCompiler}"


   # for bzImage
   export KERNEL=kernel7

   export CROSS_PREFIX="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/bin/${ToolchainName}-"

   echo -n "${TBLU}Checkingo for an existing linux/.config file ${TNRM} ... "
   if [ -f '.config' ]; then
      echo "${TYEL} found ${TNRM}"
      echo "${TNRM} make mproper & bcm2709_defconfig  ${TNRM} will not be done"
      echo "${TNRM} to protect previous changes ${TNRM}"
   else
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
      echo "${TBLU}Make bcm2709_defconfig ${TNRM} in ${PWD}"
      export CFLAGS='-Wl,-no_pie'
      export LDFLAGS='-Wl,-no_pie'
      make ARCH=arm O="${CT_TOP_DIR}/build/kernel" mrproper


      make ARCH=arm \
         CONFIG_CROSS_COMPILE="${ToolchainName}-" \
         CROSS_COMPILE="${ToolchainName}-" \
         --include-dir="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/include" \
         bcm2709_defconfig

      # Since there is no config file then add the cross compiler
      # echo "CONFIG_CROSS_COMPILE=\"${ToolchainName}-\"\n" >> '.config'
      printf 'CONFIG_CROSS_COMPILE="%s-"\n' "${ToolchainName}" >> '.config'

   fi

   # echo "${TBLU}Running make nconfig ${TNRM}"
   # This cannot include ARCH= ... as it runs on OSX
   # make nconfig


   echo "${TBLU}Make zImage ${TNRM} in ${PWD}"

   KBUILD_CFLAGS="-I${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/include" \
   KBUILD_LDLAGS="-L${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/lib" \
   ARCH=arm \
      make  -j4 CROSS_COMPILE="${ToolchainName}-" \
        CC="${ToolchainName}-gcc" \
        --include-dir="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/include" \
        zImage

   echo "${TBLU}Make modules ${TNRM} in ${PWD}"
   KBUILD_CFLAGS="-I${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/include" \
   KBUILD_LDLAGS="-L${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/lib" \
   ARCH=arm \
      make  -j4 CROSS_COMPILE="${ToolchainName}-" \
      CC="${ToolchainName}-gcc" \
      --include-dir="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/include" \
      modules

   echo "${TBLU}Make dtbs ${TNRM} in ${PWD}"
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
   echo "${TBLU}Installing Cross Compiled Raspbian Kernel ${TNRM}"
   echo -n "${TBLU}Checking for Raspbian source ${TNRM} ..."
   if [ ! -d "${COMPILING_LOCATION}/${RaspbianSrcDir}/linux" ]; then
      echo "${TRED} not found ${TNRM}"
      echo "${TNRM} You must first successfully execute: ./biuld.sh ${CmdOptionString} -b Raspbian ${TNRM}"
      exit -1
   fi
   echo "${TGRN} found ${TNRM}"


   echo -n "${TBLU}Checking for ${BootPath}/overlays ${TNRM} ... "
   if [ ! -d "${BootPath}/overlays" ]; then
      echo "${TRED} not found ${TNRM}"
      echo "${TRED}The overlays dirctory should already exist. ${TNRM}"
      exit -1
   else
      echo "${TGRN} found ${TNRM}"
   fi

   echo -n "${TBLU}Checking for ${COMPILING_LOCATION}/${RaspbianSrcDir}/linux/arch/arm/boot/zImage ${TNRM} ... "
   if [ ! -f "${COMPILING_LOCATION}/${RaspbianSrcDir}/linux/arch/arm/boot/zImage" ]; then
      echo "${TRED} not found ${TNRM}"
      exit -1
   fi
   echo "${TGRN} found ${TNRM}"


   echo -n "${TBLU}Copying Raspbian file ${TNRM} *.dtb to ${BootPath} ... "
   cp ${COMPILING_LOCATION}/${RaspbianSrcDir}/linux/arch/arm/boot/dts/*.dtb "${BootPath}/"
   echo "${TGRN} done ${TNRM}"
   echo -n "${TBLU}Copying Raspbian file ${TNRM} overlays/*.dtb* to ${BootPath} ... "
   cp ${COMPILING_LOCATION}/${RaspbianSrcDir}/linux/arch/arm/boot/dts/overlays/*.dtb* "${BootPath}/overlays/"
   echo "${TGRN} done ${TNRM}"
   echo -n "${TBLU}Copying Raspbian file ${TNRM} overlays/README to ${BootPath} ... "
   cp "${COMPILING_LOCATION}/${RaspbianSrcDir}/linux/arch/arm/boot/dts/overlays/README" "${BootPath}/overlays/"
   echo "${TGRN} done ${TNRM}"
   echo -n "${TBLU}Copying Raspbian file ${TNRM} zImage to ${BootPath} ... "
   cp "${COMPILING_LOCATION}/${RaspbianSrcDir}/linux/arch/arm/boot/zImage" "${BootPath}/kernel7.img"
   echo "${TGRN} done ${TNRM}"
}
function compileFuseFromSource()
{
   # installing e2fsprogs says this may be needed for some programs
   #  export LDFLAGS="-L/Volumes/ctBase/brew/opt/e2fsprogs/lib"
   # export CPPFLAGS="-I/Volumes/ctBase/brew/opt/e2fsprogs/include"
   
   # osxfuse Readme says:
   #  git clone --recursive -b support/osxfuse-3 git://github.com/osxfuse/osxfuse.git osxfuse
   #  ./build.sh -t distribution
   # The resulting distribution package can be found in `/tmp/osxfuse/distribution`.


   
   # Version built was fuse-ext2 0.0.9 29
   # Version via brew was 0.0.9 29
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

   echo -n "${TBLU}Checking for Ext2 tools ${TNRM} ... "
   if [ ! -d "${BrewHome}/Caskroom/osxfuse" ] &&
      [ ! -d "${BrewHome}/Cellar/e2fsprogs/1.44.3/sbin/mke2fs" ]; then
      echo "${TRED} not found ${TNRM}"
      echo "${TNRM}You must first ${TNRM}"
      echo "${TBLU}Execute:${TNRM} ./build.sh ${CmdOptionString} -i ${TNRM}"
      echo "${TNRM}To install the brew Ext2 tools ..."
      exit -1
   fi
   echo "${TGRN} found ${TNRM}"

   echo -n "${TBLU}Checking that Ext2 tools are set up properly ${TNRM} ... "
   if [ ! -d '/Library/Filesystems/fuse-ext2.fs' ] &&
      [ ! -d '/Library/PreferencePanes/fuse-ext2.prefPane' ]; then
      echo ""
      echo "${TRED}As per the previous Fuse-Ext2 instructions ${TNRM}"

      echo "${TNRM}"
      echo "   For fuse-ext2 to be able to work properly, the filesystem extension and"
      echo "preference pane must be installed by the root user: "
      echo ""
      echo "   sudo cp -pR ${BrewHome}/opt/fuse-ext2/System/Library/Filesystems/fuse-ext2.fs /Library/Filesystems/"
      echo "   sudo chown -R root:wheel /Library/Filesystems/fuse-ext2.fs"
      echo ""
      echo "   sudo cp -pR ${BrewHome}/opt/fuse-ext2/System/Library/PreferencePanes/fuse-ext2.prefPane /Library/PreferencePanes/"
      echo "   sudo chown -R root:wheel /Library/PreferencePanes/fuse-ext2.prefPane"
      echo ""
      echo ""


      exit -1
   fi
   echo "${TGRN} OK ${TNRM}"

   echo -n "${TBLU}Checking that /Library/Filesystems/fuse-ext2.fs is the same ${TNRM} ... "
   diff -r '/Library/Filesystems/fuse-ext2.fs' "${BrewHome}/opt/fuse-ext2/System/Library/Filesystems/fuse-ext2.fs"
   rc=$?
   if [ "${rc}" != '0' ]; then
      echo "${TRED}Error : [${rc}] ${TNRM} Differs from ${BrewHome}/opt/fuse-ext2/System"
      exit "${rc}"
   fi
   echo "${TGRN} OK ${TNRM}"

   echo -n "${TBLU}Checking that /Library/PreferencePanes/fuse-ext2.prefPane is the same ${TNRM} ... "
   diff -r '/Library/PreferencePanes/fuse-ext2.prefPane' "${BrewHome}/opt/fuse-ext2/System/Library/PreferencePanes/fuse-ext2.prefPane"
   rc=$?
   if [ "${rc}" != '0' ]; then
      echo "${TRED}Error : [${rc}] ${TNRM} Differs from ${BrewHome}/opt/fuse-ext2/System"
      exit "${rc}"
   fi
   echo "${TGRN} OK ${TNRM}"

}


function updateBrewForEXT2()
{
   export PATH="${PathWithBrewTools}"

   if [ ! -d "${BrewHome}/Caskroom/osxfuse" ] &&
      [ ! -d "${BrewHome}/Cellar/e2fsprogs/1.44.3/sbin/mke2fs" ]; then

      # Do not Exit immediately if a command exits with a non-zero status.
      set +e

      if [ ! -d "${BrewHome}/Caskroom/osxfuse" ]; then
         echo "${TBLU}Installing brew cask osxfuse ${TNRM}"
         echo "${TMAG}*** osxfuse will need sudo *** ${TNRM}"
         brew cask install osxfuse && true
      fi

      if [ ! -d "${BrewHome}/Cellar/e2fsprogs/1.44.3/sbin/mke2fs" ]; then
         echo "${TBLU}Installing brew ext4fuse ${TNRM}"
         # ext2fuse version in brew is 0.8.1
         # this also downloads e2fsprogs 1.44.3
         # ${BrewHome}/bin/brew install ext4fuse && true
     
         # ext2fuse --head version is 0.0.9 29
         # this also downloads e2fsprogs 1.44.3
         brew install --HEAD 'https://raw.githubusercontent.com/yalp/homebrew-core/fuse-ext2/Formula/fuse-ext2.rb' && true
      fi

      # Exit immediately if a command exits with a non-zero status
      set -e

      if [ -f  '/Library/Filesystems/fuse-ext2.fs/fuse-ext2.util' ] &&
         [ -f '/Library/PreferencePanes/fuse-ext2.prefPane/Contents/MacOS/fuse-ext2' ]
      then
         # They could be there from a previous installation
         # NOOP
         echo -n "${TNRM}"

      else

         echo "${TBLU}After the install and reboot ${TNRM}"
         echo "${TBLU}Execute again:${TNRM} ./build.sh ${CmdOptionString} -i"
         exit 0
      fi
   fi

   # Exit immediately if a command exits with a non-zero status
   set -e

   checkExt2InstallForOSX

}

function getUSBFlashDeviceForRoot()
{
   echo ""
   echo "${TBLU}Finding USB flash devices available to write kernel to ${TNRM} ..."

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
         for (( i++, j=i; j<${#lines[@]}; j++, i++ )); do
            line=${lines[$j]}
        
            # Blank lines means we are not close
            if [ "${line}" = '' ]; then
               break 1
            fi
        
            # Search for the disk number
            if [[ "${line}" = *"disk"* ]]; then
               local DeviceNumber
               DeviceNumber=$(echo "${line}" | grep -o -E '[0-9]+$')
               if [[ ${DeviceNumber} -ge 2 ]]; then
             
                  FoundDeviceNumbers+=("${DeviceNumber}")
                  FoundDevices+=("${device}")
               else
                  echo "${TYEL}Ignoring disk${DeviceNumber} ${TNRM}as it is less than 2"
              fi
          
              # Continue searching for other devices
              break 1
           fi
         done
      fi
   done

   if [[ ! ${#FoundDeviceNumbers[@]} -gt 0 ]]; then
      echo "${TRED}No flash device found ${TNRM}"
      echo "${TRED}Insert a device and rerun ${TNRM}"
      exit -1
   fi


   if [[ ${#FoundDeviceNumbers[@]} -eq 1 ]]; then
      echo "${TNRM}Found /dev/disk${FoundDevices[0]}"
      read -p "Is this correct (Y/n) " -r
      if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
         rc="${FoundDevices[0]}"
         return
      fi
      if [[ "${REPLY}" =~ ^[Nn]$ ]]; then
         echo "${TRED}Insert a device and rerun. ${TNRM}"
         exit -1
      fi
      echo "${TRED}You haven't entered a correct response.${TNRM}"
      echo "${TRED}Aborted due user input.${TNRM}"
      exit -1
   fi

   echo "${TGRN}Found devices: ${TNRM}"
   for (( i=0; i<${#FoundDeviceNumbers[@]}; i++ )); do
        echo "${FoundDevices[$i]} /dev/disk${FoundDeviceNumbers[$i]}"
   done


   echo "${TNRM}To which device you would like to write Rasbian to?"
   read -p "(Please only enter the number like 2 for /dev/disk2) " -r
   re='^[0-9]+$'
   if [[ ! ${REPLY} =~ ${re} ]]; then
      echo "${TRED}You haven't entered a number.${TNRM}"
      echo "${TRED}Aborted due user request.${TNRM}"
      exit -1
   fi

   if [[ ! "${REPLY}" -ge 2 ]]; then
      echo "${TRED}The number is lower than 2.${TNRM}"
      echo "${TRED}Since /dev/disk0 and /dev/disk1 are usually system drives,${TNRM}"
      echo "${TRED}We can't accept this device. We don't want to possibly destroy your ${TNRM}"
      echo "${TRED}system. ${TYEL};-) ${TNRM}"
      exit -1
   fi

   # if [[ ! " ${FoundDeviceNumbers[@]} " =~ " ${REPLY} " ]]; then
   if ! printf '%s\n' "${FoundDeviceNumbers[@]}" | grep -x -q "${REPLY}"; then
      echo "${TRED}The number is not in the given list.${TNRM}"
      echo "${TRED}Insert a device and rerun or next time ${TNRM}"
      echo "${TRED}Enter a number from the given list.${TNRM}"
      exit -1
   fi

   rc="${REPLY}"
     
}

function mountRaspbianBootPartitiion()
{
   PATH="${PathWithBrewTools}"

   echo "${TBLU}Mounting /Volumes/boot ${TNRM}"

   # Mounts boot without complaints about root
   # Mounts with nice message
   /usr/sbin/diskutil mount "/dev/disk${TargetUSBDevice}s1"

   # No done message required as diskutil provides its own

   echo -n "${TBLU}Checking for /Volumes/boot ${TNRM} ... "  
   if [ ! -d '/Volumes/boot' ]; then
      echo "${TRED} not found ${TNRM}"
      exit -1
   fi
   echo "${TGRN} done ${TNRM}"


}


function mountRaspbianRootPartitiion()
{
   local RW='n'
   RW="$1"

   PATH="${PathWithBrewTools}"
   echo "${TBLU}Mounting Raspbian root Partitiions with fuse-ext ${TNRM}"

   echo -n "${TBLU}Checking /Volumes/root already mounted${TNRM} ... "
   if [ -d '/Volumes/root/bin' ]; then
      echo "${TGRN} already mounted ${TNRM}"
      return
   fi
   echo "${TGRN} not mounted ${TNRM}"

   getUSBFlashDeviceForRoot

   if [ "${RW}" = 'y' ]; then
      echo -n "${TBLU}Mounting /dev/disk${TargetUSBDevice}s2 (RW+) ${TNRM} as /Volumes/root ... "
      sudo fuse-ext2 "/dev/disk${TargetUSBDevice}s2" '/Volumes/root' -o rw+
   else
      echo -n "${TBLU}Mounting /dev/disk${TargetUSBDevice}s2 (Read Only) ${TNRM} as /Volumes/root ... "
      sudo fuse-ext2 "/dev/disk${TargetUSBDevice}s2" '/Volumes/root'
   fi
   echo "${TGRN} done ${TNRM}"

   echo -n "${TBLU}Checking for /Volumes/root/bin ${TNRM} ... "  
   if [ ! -d '/Volumes/root/bin' ]; then
      echo "${TRED} not found ${TNRM}"
      echo "${TRED} Raspbian not mounted ${TNRM}"
      exit -1
   fi
   echo "${TGRN} done ${TNRM}"
}

function unMountRaspbianBootPartition()
{
   echo -n "${TBLU}Unmounting (Not ejecting) ${TNRM} /dev/disk${TargetUSBDevice}s1 ... "
   
   diskutil unmount  "/dev/disk${TargetUSBDevice}s1"

   # No done message required as diskutil provides its own
}

function unMountRaspbianRootPartition()
{

   echo -n "${TBLU}Unmounting (Not ejecting) ${TNRM} /Volumes/root ... "
   echo -n "${TMAG} (sudo required) ${TNRM}"
   # UnMounted root if root was only mounted
   sudo umount  "/Volumes/root"

   # No done message required as diskutil provides its own
}

function mountRaspbianVolume()
{

   echo -n "${TBLU}Mounting  ${TNRM} /dev/disk${TargetUSBDevice} ... "
   # Only mounts boot
   # Gives error message mounting root
   diskutil mountDisk  "/dev/disk${TargetUSBDevice}"

   # No done message required as diskutil provides its own
}

function unMountRaspbianVolume()
{

   echo -n "${TBLU}Unmounting (Not ejecting) ${TNRM} /dev/disk${TargetUSBDevice} ... "
   # Does not Unmounted root if only root mounted
   diskutil unmountDisk  "/dev/disk${TargetUSBDevice}"

   # No done message required as diskutil provides its own
}

function ejectRaspbianDisk()
{
   echo -n "${TBLU}Ejecting Raspbian Disk ${TNRM} ... "

   hdiutil eject  "/dev/disk${TargetUSBDevice}"

   # No done message required as hdiutil provides its own
}

function downloadRaspbianStretch()
{
   local RaspbianStretchURL="http://director.downloads.raspberrypi.org/raspbian/images/raspbian-2018-06-29/${RaspbianStretchFile}.zip"


   echo "${TBLU}Downloading Raspbian Stretch latest ${TNRM}"


   cd "${SavedSourcesPath}"

   echo -n "${TBLU}Checking for ${TNRM} ${RaspbianStretchFile}.img ... "
   if [ -f "${RaspbianStretchFile}.img" ]; then
      echo "${TGRN} found ${TNRM}"
      echo "${TNRM} It will be used instead of downloading another."
      return
   fi

   echo -n "${TBLU}Checking for ${TNRM} ${RaspbianStretchFile}.zip ... "
   if [ -f "${RaspbianStretchFile}.zip" ]; then
      echo "${TGRN} found ${TNRM}"

   else
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
  
      echo "${TBLU}Fetching ${RaspbianStretchFile} ${TNRM}"
     
      wget -c "${RaspbianStretchURL}"

      echo "${TGRN} done ${TNRM}"
   fi

   echo "${TBLU}Uncompressing ${RaspbianStretchFile}.zip ${TNRM} ... Logging to /tmp/stretch_unzip.log "
  
   # Do not Exit immediately if a command exits with a non-zero status.
   set +e

   unzip "${RaspbianStretchFile}.zip" > '/tmp/stretch_unzip.log' 2>&1 &
   pid="$!"
   waitForPid "${pid}"

   # Exit immediately if a command exits with a non-zero status
   set -e

   if [ "${rc}" != '0' ]; then
      echo "${TRED}Error : [${rc}] ${TNRM} unzip failed. Check the log for details"
      exit "${rc}"
   fi

   echo "${TGRN} done ${TNRM}"
  
}

function unPackDebFile()
{
   PATH="${PathWithBrewTools}"

   local checkFile="$1"
   local pkguRL="$2"
   local pkg="$3"

   echo -n "${TBLU}Checking for file ${TNRM} ${checkFile} ... "
   if [ -f "${checkFile}" ]; then
      echo "${TGRN} found ${TNRM}"
      echo "${TNRM}Package ${pkg} already installed"
      return
   fi
   echo "${TYEL} not found ${TGRN} -OK ${TNRM}"

   cd "${SavedSourcesPath}"

   echo -n "${TBLU}Checking for saved package ${pkg} ${TNRM} in ${PWD} ... "
   if [ ! -f "${pkg}" ]; then
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
  
      echo "${TBLU}Fetching  ${pkg} ${TNRM} from ${pkguRL}"
      wget -c "${pkguRL}/${pkg}"
      echo "${TGRN} done ${TNRM}"
 
   fi
   echo "${TGRN} found ${TNRM}"

   echo -n "${TBLU}Copying  ${pkg} ${TNRM} to /tmp ... "
   cp "${pkg}" /tmp/
   echo "${TGRN} done ${TNRM}"

   cd /tmp
   echo -n "${TBLU}UnArchiving ${pkg} ${TNRM} in ${PWD} ... "
   ar x "${pkg}" 'data.tar.xz'
   echo "${TGRN} done ${TNRM}"

   echo -n "${TBLU}Checking for ${TNRM} data.tar.xz ... "
   if [ ! -f 'data.tar.xz' ]; then
      echo "${TRED} not found ${TNRM}"
      exit -1
   fi
   echo "${TGRN} found ${TNRM}"

   echo -n "${TBLU}Extracting data.tar.xz ${TNRM} to /Volumes/boot/ ... "
  # tar -xf data.tar.xz -C/Volumes/boot/
   echo "${TGRN} done ${TNRM}"

   echo -n "${TBLU}removing /tmp/data.tar.xz and /tmp/${pkg} ${TNRM}  ... "
   rm '/tmp/data.tar.xz' "/tmp/${pkg}"
   echo "${TGRN} done ${TNRM}"

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
   echo "${TBLU}Installing ${RaspbianStretchFile}.img ${TNRM}"

   cd "${SavedSourcesPath}"

   echo -n "${TBLU}Checking for ${TNRM} ${RaspbianStretchFile}.img ... "
   if [ -f "${RaspbianStretchFile}.img" ]; then
      echo "${TGRN} found ${TNRM}"
   else
      echo "${TRED} not found ${TNRM}"
      echo "${TRED} This should have already been downloaded and unzipped. ${TNRM}"
      exit -1
   fi

   unMountRaspbianVolume

   echo "${TBLU}Writing ${RaspbianStretchFile}.img ${TNRM} to /dev/disk${TargetUSBDevice} ... Logging to /tmp/dd.log"
   echo "${TCR}${TNRM}Writing ... ${RaspbianStretchFile}.img using command:"
   echo "${TCR}${TNRM}sudo dd if=${RaspbianStretchFile}.img of=/dev/disk${TargetUSBDevice} bs=1m"
   # Done this way to put dd in background as it takes a while
   # read -s -p "Password:" -r

   echo ""
   echo -n "${TCR}${TYEL}Starting in ${TNRM} 5"; sleep 1
   echo -n "${TCR}${TYEL}Starting in ${TNRM} 4"; sleep 1
   echo -n "${TCR}${TYEL}Starting in ${TNRM} 3"; sleep 1
   echo -n "${TCR}${TYEL}Starting in ${TNRM} 2"; sleep 1
   echo -n "${TCR}${TYEL}Starting in ${TNRM} 1"; sleep 1
   echo "${TCR}                   "

   # Do not Exit immediately if a command exits with a non-zero status.
   set +e

   sudo -sk dd if="${RaspbianStretchFile}.img" of="/dev/disk${TargetUSBDevice}" bs=1m  &
   sleep 20
   echo ""

   pid="$!"
   waitForPid "${pid}"

   # Exit immediately if a command exits with a non-zero status
   set -e

   if [ "${rc}" != '0' ]; then
      echo "${TRED}Error : [${rc}] ${TNRM} dd failed. Check the log for details"
      exit "${rc}"
   fi

   echo "${TGRN} done ${TNRM}"
}

function downloadLinuxCNC()
{
   PATH="${PathWithCrossCompiler}"

   echo -n "${TBLU}Checking for existing LinuxCNC install ${TNRM} ... "
   if [ -f "/Volumes/root/opt/local/linuxcnc" ]; then
      echo "${TGRN} found ${TNRM}"
      echo "${TNRM} Remove it to start over"
      return
   fi
   echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
 
   echo -n "${TBLU}Checking for existing LinuxCNC src ${TNRM} ${LinuxCNCSrcDir} ... "
   if [ -d "${COMPILING_LOCATION}/${LinuxCNCSrcDir}" ]; then
      echo "${TGRN} found ${TNRM} Using it instead"
   else
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
  
      echo -n "${TBLU}Checking for saved LinuxCNC src ${TNRM} ${LinuxCNCSrcDir}.tar.xz ... "
      if [ -f "${SavedSourcesPath}/${LinuxCNCSrcDir}.tar.xz" ]; then
         echo "${TGRN} found ${TNRM}"
 
         echo -n "${TBLU}Extracting saved LinuxCNC src ${TNRM} to ${SavedSourcesPath}/${LinuxCNCSrcDir} ... "  
         tar -xf "${SavedSourcesPath}/${LinuxCNCSrcDir}.tar.xz" \
             -C "${COMPILING_LOCATION}"
         
         echo "${TGRN} done ${TNRM}"
      else
         echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
     
         echo -n "${TBLU}Creating ${LinuxCNCSrcDir} ${TNRM} in ${COMPILING_LOCATION} ... "
         mkdir "${COMPILING_LOCATION}/${LinuxCNCSrcDir}"
         echo "${TGRN} done ${TNRM}"
     
         echo "${TBLU}Retrieving LinuxCNC src ${TNRM} to ${LinuxCNCSrcDir}"
         git clone --depth=1 'https://github.com/LinuxCNC/linuxcnc.git' \
             "${COMPILING_LOCATION}/${LinuxCNCSrcDir}"
       
         echo -n "${TBLU}Saving LinuxCNC src ${TNRM}to ${SavedSourcesPath}/${LinuxCNCSrcDir}.tar.xz ... "
         cd "${COMPILING_LOCATION}"
         tar -cJf "${SavedSourcesPath}/${LinuxCNCSrcDir}.tar.xz" "${LinuxCNCSrcDir}"
         echo "${TGRN} done ${TNRM}"
      fi
   fi

}

function configureLinuxCNC()
{
   cd "${COMPILING_LOCATION}/${LinuxCNCSrcDir}"
   echo "${TBLU}Configuring LinuxCNC ${TNRM} in ${PWD}"

   export PATH="${PathWithCrossCompiler}"




   export CROSS_PREFIX="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/bin/${ToolchainName}-"

   echo -n "${TBLU}Checkingo for an existing linux/.config file ${TNRM} ... "
   if [ -f '.config' ]; then
      echo "${TYEL} found ${TNRM}"
      echo "${TNRM} make mproper & bcm2709_defconfig  ${TNRM} will not be done"
      echo "${TNRM} to protect previous changes ${TNRM}"
   else
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
      echo "${TBLU}Make bcm2709_defconfig ${TNRM} in ${PWD}"
      export CFLAGS='-Wl,-no_pie'
      export LDFLAGS='-Wl,-no_pie'
  

      # Since there is no config file then add the cross compiler
      # echo "CONFIG_CROSS_COMPILE=\"${ToolchainName}-\"\n" >> '.config'
      printf 'CONFIG_CROSS_COMPILE="%s-"\n' "${ToolchainName}" >> '.config'

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

   echo -n "${TBLU}Checking for existing PyCNC install ${TNRM} ... "
   if [ -f "/Volumes/root/opt/local/PyCNC" ]; then
      echo "${TGRN} found ${TNRM}"
      echo "${TNRM} Remove it to start over"
      return
   fi
   echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
 
   echo -n "${TBLU}Checking for existing PyCNC src ${TNRM} ${PyCNCSrcDir} ... "
   if [ -d "${COMPILING_LOCATION}/${PyCNCSrcDir}" ]; then
      echo "${TGRN} found ${TNRM} Using it instead"
   else
      echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
  
      echo -n "${TBLU}Checking for saved PyCNC src ${TNRM} ${PyCNCSrcDir}.tar.xz ... "
      if [ -f "${SavedSourcesPath}/${PyCNCSrcDir}.tar.xz" ]; then
         echo "${TGRN} found ${TNRM}"
 
         echo -n "${TBLU}Extracting saved PyCNC src ${TNRM} to ${SavedSourcesPath}/${PyCNCSrcDir} ... "  
         tar -xf "${SavedSourcesPath}/${PyCNCSrcDir}.tar.xz" \
             -C "${COMPILING_LOCATION}"
         
         echo "${TGRN} done ${TNRM}"
      else
         echo "${TYEL} not found ${TGRN} -OK ${TNRM}"
     
         echo -n "${TBLU}Creating ${PyCNCSrcDir} ${TNRM} in ${COMPILING_LOCATION} ... "
         mkdir "${COMPILING_LOCATION}/${PyCNCSrcDir}"
         echo "${TGRN} done ${TNRM}"
     
         echo "${TBLU}Retrieving PyCNC src ${TNRM} to ${PyCNCSrcDir}"
         git clone --depth=1 'https://github.com/Nikolay-Kha/PyCNC' \
             "${COMPILING_LOCATION}/${PyCNCSrcDir}"
       
         echo -n "${TBLU}Saving PyCNC src ${TNRM}to ${SavedSourcesPath}/${PyCNCSrcDir}.tar.xz ... "
         cd "${COMPILING_LOCATION}"
         tar -cJf "${SavedSourcesPath}/${PyCNCSrcDir}.tar.xz" "${PyCNCSrcDir}"
         echo "${TGRN} done ${TNRM}"
      fi
   fi
   cd "${COMPILING_LOCATION}/${PyCNCSrcDir}"

   echo "${TGRN} Configuring PyCNC ${TNRM}"


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

 PathWithBrewTools="${BrewHome}/bin:${BrewHome}/opt/m4/bin:${BrewHome}/opt/ncurses/bin:${BrewHome}/opt/gettext/bin:${BrewHome}/opt/meson-internal/bin:${BrewHome}/opt/bison/bin:${BrewHome}/opt/libtool/bin:${BrewHome}/opt/sphinx-doc/bin:${BrewHome}/opt/sqlite/bin:${BrewHome}/opt/openssl/bin:${BrewHome}/opt/texinfo/bin:${BrewHome}/opt/gcc/bin:${BrewHome}/Cellar/e2fsprogs/1.44.3/sbin:/Volumes/${VolumeBase}/ctng/bin:${OriginalPath}"
   #PathWithBrewTools="${BrewHome}/bin:${BrewHome}/opt/m4/bin:${BrewHome}/opt/gettext/bin:${BrewHome}/opt/bison/bin:${BrewHome}/opt/libtool/bin:${BrewHome}/opt/texinfo/bin:${BrewHome}/opt/gcc/bin:${BrewHome}/Cellar/e2fsprogs/1.44.3/sbin:/Volumes/${VolumeBase}/ctng/bin:${OriginalPath}"

   PathWithCrossCompiler="${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/bin:${PathWithBrewTools}"

}
function explainExclusion()
{
   echo "${TRED} You cannot install Raspbian and then install the kernel"
   echo "${TRED} immediately afterwards.the raspbian image is squashfs and"
   echo "${TRED} to be bbted first to make it ext4 and do its own setup."
   echo "${TRED} If you try to do it anyway afterwards, the extfs mount"
   echo "${TRED} will fail. ${TNRM}"
}


# Define this once and you save yourself some trouble
# Omit the : for the b as we will check for optional option
OPTSTRING='h?P?c:V:O:f:btT:i:S:a:g'

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

          echo "${TNRM}PATH=${PATH}"
          echo "${TNRM}KBUILD_CFLAGS=-I${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/include"
          echo "${TNRM}KBUILD_LDLAGS=-L${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}/${ToolchainName}/sysroot/usr/lib"
          echo "./configure  ARCH=arm  CROSS_COMPILE=${ToolchainName}- --prefix=${CT_TOP_DIR_BASE}/${OutputDir}/${ToolchainName}"
          echo "make ARCH=arm --include-dir=${CT_TOP_DIR}Base/${OutputDir}/${ToolchainName}/${ToolchainName}/include CROSS_COMPILE=${ToolchainName}-"
          exit 0
          ;;
          #####################
      c)
          # Flag that something else was wanted to be done first
          TestCompilerOnlyOpt='n'

          if [[ "${OPTARG}" =~ ^[Bb]rew$ ]]; then
             cleanBrew
             exit 0
          fi

          if  [ "${OPTARG}" = 'ctng' ] ||
              [ "${OPTARG}" = 'ct-ng' ]; then
             ct-ngMakeClean
             exit 0
          fi

          if [[ "${OPTARG}" =~ ^[Rr]aspbian$ ]]; then
             # CleanRaspbianOpt='y'
             cleanRaspbian
             exit 0
          fi

          if  [ "${OPTARG}" = 'realClean' ]; then
             realClean
             exit 0
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
             echo "${TNRM}${ThisToolsStartingPath}/${CrossToolNGConfigFile} ... ${TGRN} found ${TNRM}"
          else
             echo "${TNRM}${ThisToolsStartingPath}/${CrossToolNGConfigFile} ... ${TRED} not found ${TNRM}"
             exit 1
          fi
          ;;
          #####################
      b)
          # Flag that something else was wanted to be done first
          TestCompilerOnlyOpt='n'


          # Why would checking for an unbound variable cause an unbound variable?
          set +u

          # Check next positional parameter
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
             # BuildCTNGOpt='y'
             # RunCTNGOpt='y'
             RunCTNGOptArg='build'
          fi

          ;;
          #####################
       T)
          # ToolchainNameOpt=y
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
              if [ "${InstallKernelOpt}" = 'y' ]; then
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
                echo "${TRED}Unknown -i option (${OPTARG}) ${TNRM}"
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
             echo "${TRED}unknown option -a ${TNRM} ${OPTARG}"
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
       g)                        
          BuildGCCwithBrewOpt='y'            
          ;;                     
          #####################  
          
          
      \?)
          exit -1
          ;;
          #####################
      :)
          echo "${TRED}Option ${TNRM}-${OPTARG} requires an argument."
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
echo "${TBLU}Here we go ${TNRM} ..."

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
# buildBinutilsForHost

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
     
   echo "${TGRN}Using flash device: ${TNRM} /dev/disk${TargetUSBDevice}"

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
   # noop at this time
   echo ""
fi





exit 0
