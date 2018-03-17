#!/bin/bash
#
#  Author: John Talbot
#
#  Changes
#    3/11/18 - Updated to use crosstool-ng v1.23
#    3/12/18 - You can now choose crosstool-ng (Latest) from git 
#
#  Installs a gcc cross compiler for compiling code for raspberry pi on OSX.
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
#  (1) Install HomeBrew and packages: gnu-sed binutils gawk automake libtool
#                                     bash grep wget xz help2man
#
#  (2) Download Homebrew to $BrewHome so as not to interfere with macports or fink
#
#  (3) Create a case sensitive volume using hdiutil and mount it to /Volumes/$Volume
#      The size of the volume grows as needed since it is of type SPARSE.
#      This also means that the filee of the mounted volume is $ImageName.sparseimage
#
#  (4) Download, patch and build crosstool-ng
#
#  (5) Configure and build the toolchain.
#
#  License:
#      Please feel free to use this in any way you see fit.
#
set -e

# Exit immediately for unbound variables.
set -u

# If latest is 'y', then git will be used to download crosstool-ng LATEST
# I believe there is a problem with 1.23.0 so for now, this is the default.
# Ticket #931 has been submitted to address this. It deals with CT_Mirror being undefined
downloadCrosstoolLatest=y

#
# Config. Update below here to suite your specific needs.
#

# The crosstool image will be $ImageName.sparseimage
# The volume will grow as required because of the SPARSE type
# You can change this with -i <ImageName> but it will always
# be <ImageName>.sparseimage
ImageName="CrossToolNG"

# This will be mounted as /Volumes/CrossToolNG
# It can be overriden with -V <volume>
Volume="CrossToolNG"

# This will be the name of the toolchain created by crosstools-ng
# It is placed in $CT_TOP_DIR
ToolChainName="arm-unknown-linux-gnueabihf"

#
# This is where your §{ToolchainName".config file is if you have one.
# It would be copied to $CT_TOP_DIR/.config prior to ct-ng menuconfig
#
CrossToolNGConfigFilePath=`pwd`

#
# Anything below here cannot be changed without bad effects
#

# Where brew will be placed. An existing brew cannot be used because of
# interferences with macports or fink.
BrewHome="/Volumes/${Volume}/brew"

# Binutils is for objcopy, objdump, ranlib, readelf
# sed, gawk libtool bash, grep are direct requirements
# xz is reauired when configuring crosstool-ng
# help2man is reauired when configuring crosstool-ng
# wget  is reauired when configuring crosstool-ng
# wget  requires all kinds of stuff that is auto downloaded by brew. Sorry
# automake is required to fix a compile issue with gettect
# coreutils is for sha512sum
#
BrewTools="gnu-sed binutils gawk automake libtool bash grep wget xz help2man automake coreutils"

# This is required so brew can be installed elsewhere
export BREW_PREFIX=$BrewHome

# This is the crosstools-ng version used by curl to fetch relased version
# of crosstools-ng. I don't know if it works with previous versions and
#  who knows about future ones.
CrossToolVersion="crosstool-ng-1.23.0"

# Changing this affects CT_TOP_DIR which also must be reflected in your
# crosstool-ng .config file
CrossToolSourceDir="crosstool-ng-src"

# See note just above why this is duplicated
CT_TOP_DIR="/Volumes/CrossToolNG/crosstool-ng-src"
CT_TOP_DIR="/Volumes/${Volume}/${CrossToolSourceDir}" 

ImageNameExt=${ImageName}.sparseimage   # This cannot be changed

# Fun colour stuff
KNRM="\x1B[0m"
KRED="\x1B[31m"
KGRN="\x1B[32m"
KYEL="\x1B[33m"
KBLU="\x1B[34m"
KMAG="\x1B[35m"
KCYN="\x1B[36m"
KWHT="\x1B[37m"




function showHelp()
{
cat <<'HELP_EOF'
   This shell script is a front end to crosstool-ng to help build a cross compiler on your Mac.  It downloads all the necessary files to build the cross compiler.  It only assumes you have Xcode command line tools installed.

   Options:
      -i <ImageName> - Instead of CrosstoolNG.sparseImage use <ImageName>.sparseImageI
      -V <Volume>    - Instead of /Volumes/CrosstoolNG/ use /Volumes/<Volume>
      -c Brew        - Remove all installed Brew tools.
      -c ct-ng       - Run make clean in crosstool-ng path
      -c realClean   - Unmounts the image and removes it. This destroys EVERYTHING!
      -b             - Build the cross compiler AFTER building the necessary tools
                       and you have defined the crosstool-ng .config file.
      -t             - After the build, run a Hello World test on it.
      help           - This menu.
      "none"         - Go for it all if no options given. it will always try to 
                       continue where it left off

HELP_EOF
}

function removeFileWithCheck()
{
   printf "Removing file $1 ...${KNRM}"
   if [ -f "$1" ]; then
      rm "$1"
      printf "  ${KGRN}-Done${KNRM}\n"
   else
      printf "  ${KGRN}-Not found${KNRM}\n"
   fi
}
function removePathWithCheck()
{
   printf "Removing directory $1 ...${KNRM}"
   if [ -d "$1" ]; then
      rm -rf "$1"
      printf "  ${KGRN}-Done${KNRM}\n"
   else
      printf "  ${KGRN}-Not found${KNRM}\n"
   fi
}

function cleanBrew()
{
   printf "${KBLU}Cleaning our brew tools...${KNRM}\n"

   if [ -f "${BrewHome}/.flagToDeleteBrewLater" ]; then
      printf "${KBLU}Cleaning brew cache ... ${KNRM}"
      ${BrewHome}/bin/brew cleanup --cache
      printf "${KGRN}  -done${KNRM}\n"
      removePathWithCheck  "${BrewHome}"
   fi
}

function ct-ngMakeClean()
{
   printf "${KBLU}Cleaning ct-ng...${KNRM}\n"
   cd $CT_TOP_DIR
   make clean
}
function realClean()
{
   # We need to clean brew as it purges brew's cache
   cleanBrew

   if [ -d  "/Volumes/${Volume}" ]; then 
      printf "${KBLU}Unmounting  /Volumes/${Volume}${KNRM}\n"
      hdiutil unmount /Volumes/${Volume}
   fi

   # Since everything is on the image, just remove it does it all
   printf "${KBLU}Removing ${ImageNameExt}${KNRM}\n"
   removeFileWithCheck ${ImageNameExt}
}

function createCaseSensitiveVolume()
{
    printf "${KBLU}Creating volume mounted on /Volumes/${Volume}...${KNRM}\n"
    if [  -d "/Volumes/${Volume}" ]; then
       printf "WARNING: Volume already exists: /Volumes/${Volume}${KNRM}\n"
      
       # Give a couple of seconds for the user to react
       sleep 3

       return;
    fi

   if [ -f "${ImageNameExt}" ]; then
      printf "${KRED}WARNING:${KNRM}\n"
      printf "         File already exists: ${ImageNameExt}${KNRM}\n"
      printf "         This file will be mounted as /Volumes/${Volume}${KNRM}\n"
      
      # Give a couple of seconds for the user to react
      sleep 3

   else
      hdiutil create ${ImageName}           \
                      -volname ${Volume}    \
                      -type SPARSE          \
                      -size 8g              \
                      -fs HFSX              \
                      -puppetstrings
   fi

   hdiutil mount ${ImageNameExt}
}

#
# If $BrewHome does not alread contain HomeBrew, download and install it. 
# Install the required HomeBrew packages.
#
function buildBrewDepends()
{
   printf "${KBLU}Checking for HomeBrew tools...${KNRM}\n"
   if [ ! -d "$BrewHome" ]; then
      printf "Installing HomeBrew tools...${KNRM}\n"
      mkdir "$BrewHome"
      cd "$BrewHome"
      curl -Lsf http://github.com/mxcl/homebrew/tarball/master | tar xz --strip 1 -C${BrewHome}

      touch "${BrewHome}/.flagToDeleteBrewLater"
   else
      printf "   - Using existing Brew installation in ${BrewHome}${KNRM}\n"
   fi
   PATH=$BrewHome/bin:$PATH 

   printf "${KBLU}Updating HomeBrew tools...${KNRM}\n"
   printf "${KRED}Ignore the ERROR: could not link${KNRM}\n"
   printf "${KRED}Ignore the message "
   printf "Please delete these paths and run brew update${KNRM}\n"
   printf "They are created by brew as it is not in /local or with sudo${KNRM}\n"
   printf "\n"


   $BrewHome/bin/brew update

   # Do not Exit immediately if a command exits with a non-zero status.
   set +e

   # $BrewHome/bin/brew install --with-default-names $BrewTools && true
   $BrewHome/bin/brew install $BrewTools && true

   # change to Exit immediately if a command exits with a non-zero status.
   set -e
}



function downloadCrossTool()
{
   cd /Volumes/${Volume}
   printf "${KBLU}Downloading crosstool-ng... to ${PWD}${KNRM}\n"
   CrossToolArchive=${CrossToolVersion}.tar.bz2
   if [ -f "$CrossToolArchive" ]; then
      printf "   -Using existing archive $CrossToolArchive${KNRM}\n"
   else
      CrossToolUrl="http://crosstool-ng.org/download/crosstool-ng/${CrossToolArchive}"
      curl -L -o ${CrossToolArchive} $CrossToolUrl
   fi

   if [ -d $CT_TOP_DIR ]; then
      printf "   ${KRED}WARNING${KNRM} - ${CT_TOP_DIR} exists and will be used.\n"
      printf "   ${KRED}WARNING${KNRM} - Remove it to start fresh\n"
   else
      tar -xvf $CrossToolArchive

      # Sadly we move the real archive name to CT_TOP_DIR
      # so that if you use latest or a common crosstool-ng .config file
      # CT_TOP_DIR matches here and there.
      mv $CrossToolVersion $CrossToolSourceDir
   fi
}


function downloadCrossTool_LATEST()
{  
   cd /Volumes/${Volume}
   printf "${KBLU}Downloading crosstool-ng... to ${PWD}${KNRM}\n"

   if [ -d $CT_TOP_DIR ]; then 
      printf "   ${KRED}WARNING${KNRM} - ${CT_TOP_DIR} exists and will be used.\n"
      printf "   ${KRED}WARNING${KNRM} - Remove it to start fresh\n"
      return
   fi

   CrossToolUrl="https://github.com/crosstool-ng/crosstool-ng.git"
   git clone ${CrossToolUrl}  ${CT_TOP_DIR}

   # We need to creat the configure tool
   printf "${KBLU}Running  crosstool bootstrap... to ${PWD}${KNRM}\n"
   cd ${CT_TOP_DIR}

   # crosstool-ng-1.23.0 still has CT_Mirror
   # git checkout -b $CrossToolVersion

   ./bootstrap
}

function patchConfigFileForVolume()
{
    printf "${KBLU}Patching .config file for 'CrossToolNG' in${PWD}${KNRM}\n"
    if [ -f ".config" ]; then
       sed -i .bak -e's/CrossToolNG/'$Volume'/g' .config
    fi
}


function patchCrosstool()
{
    cd ${CT_TOP_DIR}
    printf "${KBLU}Patching crosstool-ng... in ${PWD}${KNRM}\n"

    printf "Patching crosstool-ng...${KNRM}\n"
    printf "   -No Patches requires.\n"
    
# patch required with crosstool-ng-1.17
# left here as an example of how it was done.
#    sed -i .bak '6i\
##include <stddef.h>' kconfig/zconf.y
}

function buildCrosstool()
{
   cd ${CT_TOP_DIR}
   printf "${KBLU}Configuring crosstool-ng... in ${PWD}${KNRM}\n"

   if [ -x ct-ng ]; then
      printf "    - Found existing ct-ng. Using it instead${KNRM}\n"
      return
   fi
  
   PATH=$BrewHome/bin:$PATH 
   ./configure        \
          --enable-local                       

   # These are not needed by crosstool-ng version 1.23.0
   # 
   #        OBJCOPY=$BrewHome/bin/objcopy         \
   #        OBJDUMP=$BrewHome/bin/objdump         \
   #        RANLIB=$BrewHome/bin/ranlib           \
   #        READELF=$BrewHome/bin/readelf         \
   #        LIBTOOL=$BrewHome/bin/libtool         \
   #        LIBTOOLIZE=$BrewHome/bin/libtoolize   \
   #        SED=$BrewHome/bin/sed                 \
   #        AWK=$BrewHome/bin/gawk                \
   #        AUTOMAKE=$BrewHome/bin/automake       \
   #        BASH=$BrewHome/bin/bash               \
   #        CFLAGS="-std=c99 -Doffsetof=__builtin_offsetof"

   printf "${KBLU}Compiling crosstool-ng... in ${PWD}${KNRM}\n"
   export PATH=$BrewHome/bin:$PATH

   make
}

function createToolchain()
{
   printf "${KBLU}Creating toolchain ${ToolChainName}...${KNRM}\n"


   cd ${CT_TOP_DIR}

   if [ ! -d "${ToolChainName}" ]; then
      mkdir $ToolChainName
   fi

   # the process seems to open a lot of files at once. The default is 256. Bump it to 1024.
   #ulimit -n 2048


   printf "${KBLU}Checking for an existing toolchain config file:${KNRM} ${ToolChainName}.config ...${KNRM}\n"
   if [ -f ${CrossToolNGConfigFilePath}/${ToolChainName}.config ]; then
      printf "   - Using $CrossToolNGConfigFilePath/${ToolChainName}.config${KNRM}\n"
      cp ${CrossToolNGConfigFilePath}/${ToolChainName}.config  \
           ${CT_TOP_DIR}/.config

      cd ${CT_TOP_DIR}
      if [$Volume == 'CrossToolNG'];then
         printf "${KNBLU}.config file not being patched as -V was not specified${KNRM}"
      else
         patchConfigFileForVolume
      fi
   else
      printf "   - None found${KNRM}\n"
   fi

cat <<'CONFIG_EOF'

NOTES: on what to set in config file, taken from
https://gist.github.com/h0tw1r3/19e48ae3021122c2a2ebe691d920a9ca

- Paths and misc options
    - Check "Try features marked as EXPERIMENTAL"
    - Set "Prefix directory" to the real values of:
        /Volumes/$Volume/x-tools/${CT_TARGET}

- Target options
    - Set "Target Architecture" to "arm"
    - Set "Endianness" to "Little endian"
    - Set "Bitness" to "32-bit"
    - Set "Architecture level" to "armv6zk"
    - Set "Emit assembly for CPU" to "arm1176jzf-s"
    - Set "Use specific FPU" to "vfp"
    - Set "Floating point" to "hardware (FPU)"
    - Set "Default instruction set mode" to "arm"
    - Check "Use EABI"
- Toolchain options
    - Set "Tuple's vendor string" to "rpi"
- Operating System
    - Set "Target OS" to "linux"
- Binary utilities
    - Set "Binary format" to "ELF"
    - Set "binutils version" to "2.25.1"
- C-library
    - Set "C library" to "glibc"
    - Set "glibc version" to "2.19"
- C compiler
    - Check "Show Linaro versions"
    - Set "gcc version" to "linaro-4.9-2015.06"
    - Check "C++" under "Additional supported languages"
    - Set "gcc extra config" to "--with-float=hard"
    - Check "Link libstdc++ statically into the gcc binary"
- Companion libraries
    - Set "ISL version" to "0.14

CONFIG_EOF

   # Give the user a chance to digest this
   sleep 5

   # Use 'menuconfig' target for the fine tuning.
   PATH=${BrewHome}/bin:$PATH

   # It seems ct-ng menuconfig dies without some kind of target
   export CT_TARGET="changeMe"
   ./ct-ng menuconfig

   printf "${KBLU}Once your finished tinkering with ct-ng menuconfig${KNRM}\n"
   printf "${KBLU}to contineu the build${KNRM}\n"
   if [ $Volume == 'CrossToolNG' ]; then
      printf "${KBLU}Execute:${KNRM}bash build.sh -b       (To continue build)${KNRM}\n"
   else
      printf "${KBLU}Execute:${KNRM}bash build.sh -V ${Volume} -b       (To continue build)${KNRM}\n"
   fi
   printf "${KBLU}or${KNRM}\n"
   printf "PATH=${BrewHome}/bin:\$PATH${KNRM}\n"
   printf "cd ${CT_TOP_DIR}${KNRM}\n"
   printf "./ct-ng build${KNRM}\n"
   

}

function buildToolchain()
{
   printf "${KBLU}Building toolchain...${KNRM}\n"

   cd /Volumes/${Volume}

   # Allow the source that crosstools-ng downloads to be saved
   printf "${KBLU}Checking for:${KNRM} ${PWD}/src ...${KNRM}"
   if [ ! -d "src" ]; then
      mkdir "src"
      printf "${KGRN}   -created${KNRM}\n"
   else
      printf "${KGRN}   -Done${KNRM}\n"
   fi

   cd ${CT_TOP_DIR}

   printf "${KBLU}Checking for:${KNRM} ${PWD}/.config ...${KNRM}"
   if [ ! -f '.config' ]; then
      printf "${KRED}ERROR: You have still not created a: ${KNRM}"
      printf "${PWD}/.config file.${KNRM}\n"
      printf "Change directory to ${CT_TOP_DIR}${KNRM}\n"
      printf "And run: ./ct-ng menuconfig${KNRM}\n"
      printf "Before continuing with the build${KNRM}\n"

      exit -1
   else
      printf "${KGRN}   -Done${KNRM}\n"
   fi


   PATH=${BrewHome}/bin:$PATH
   ./ct-ng build

   printf "And if all went well, you are done! Go forth and compile.${KNRM}\n"
}

function testBuild
{
   printf "${KBLU}Testing toolchain ${ToolChainName}...${KNRM}\n"

cat <<'HELLO_WORLD_EOF' > /tmp/HelloWorld.cpp
#include <iostream>
using namespace std;

int main ()
{
  cout << "Hello World!";
  return 0;
}
HELLO_WORLD_EOF

# PATH=/Volumes/CrossToolNG/x-tools/arm-rpi-eabihf/bin:$PATH arm-rpi-eabihf-g++ -specs=nosys.specs -mthumb -mcpu=cortex-m3 /tmp/HelloWorld.cpp -fno-exceptions -o /tmp/HelloWorld
#PATH=/Volumes/CrossToolNG/x-tools/arm-rpi-eabihf/bin:$PATH arm-rpi-eabihf-g++ -fno-exceptions /tmp/HelloWorld.cpp -o /tmp/HelloWorld
PATH=/Volumes/CrossToolNG/x-tools/arm-rpi-eabihf/bin:$PATH arm-rpi-eabihf-g++ -fno-exceptions /tmp/HelloWorld.cpp -o /tmp/HelloWorld
}


while getopts "hc:I:V:bt" opt; do
   case $opt in
      h)
          showHelp
          exit 0;
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
          if  [ $OPTARG == "real" ]; then
             realClean
             exit 0
          fi

          printf "${KRED}Invalid option: -c ${KNRM}$OPTARG${KNRM}\n"
          exit 1
          ;;
          #####################
      b)
          buildToolchain
          exit 0
          ;;
          #####################
      t)
          testBuild
          exit 0
          ;;
          #####################
      i)
          ImageName=$OPTARG
          ImageNameExt=${ImageName}.sparseimage   # This cannot be changed
          ;;
          #####################
      V)
          Volume=$OPTARG

          # Change all variables that require this
          BrewHome="/Volumes/${Volume}/brew"
          export BREW_PREFIX=$BrewHome
          CT_TOP_DIR="/Volumes/${Volume}/${CrossToolSourceDir}" 
          ;;
          #####################
      \?)
          printf "${KRED}Invalid option: ${KNRM}-$OPTARG${KNRM}\n"
          exit 1
          ;;
          #####################
      :)
          printf "${KRED}Option ${KNRM}-$OPTARG {$KRED} requires an argument.\n" 
          exit 1
          ;;
          #####################
   esac
done

printf "${KBLU}Here we go ....${KNRM}\n"

# Create the case sensitive volume first.  This is where we will
# put Brew too.
createCaseSensitiveVolume
buildBrewDepends

# The 1.23  archive is busted and does nnot contain CT_Mirror, until
# it is fixed, use git Latest
if [ ${downloadCrosstoolLatest} == 'y' ]; then
   downloadCrossTool_LATEST
else
   downloadCrossTool
fi

patchCrosstool
buildCrosstool
createToolchain

exit 0
