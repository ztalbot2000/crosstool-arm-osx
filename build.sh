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

#
# This is where your §{ToolchainName".config file is if you have one.
# It would be copied to $CT_TOP_DIR/.config prior to ct-ng menuconfig
# It can be overriden with -f <ConfigFile>. Please do this instead of
# changing it here.
CrossToolNGConfigFile="arm-rpi3-eabihf.config"
CrossToolNGConfigFilePath="${PWD}"

# This will be the name of the toolchain created by crosstools-ng
# It is placed in $CT_TOP_DIR
# The real name is based upon the options you have set in the CrossToolNG
# config file. You will probably need to change this.  I feel another option
# coming
ToolchainName='arm-rpi3-eabihf'

#
# Anything below here cannot be changed without bad effects
#

# This will be mounted as /Volumes/CrossToolNG
# It can be overriden with -V <Volume>.  Do this instead as 'CrossToolNG' is
# a key word in the .config file with this tool that will automatically get
# changed with the -V <Volume> option
Volume='CrossToolNG'

# The compiler will be placed in /Volumes/<Volume>/x-tools
# It can be overriden with -O <OutputPath>.  Do this instead as 'x-tools' is
# a key word in the .config file with this tool that will automatically get
# changed with the -O <OutputPath> option
OutputPath='x-tools'




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
# sha2 is for sha512
#
# for Raspbian tools - libelf gcc ncurses
# for xconfig - QT   (takes hours)
BrewTools="gnu-sed binutils gawk automake libtool bash grep wget xz help2man automake coreutils sha2 ncurses gettext"

# This is required so brew can be installed elsewhere
# Comments are for cut and paste during development
# export Volume=BLANK
# export BREW_PREFIX=/Volumes/${Volume}/brew
# export PKG_CONFIG_PATH=${BREW_PREFIX}
# export OutputPath='x-tools2'
# ToolchainName='arm-rpi3-eabihf'
# PATH=/Volumee/${Volume}/${OutputPath}${ToolchainName}/bin:${BREW_PREFIX}/bin:${PATH}
# EXTRA_CFLAGS=-I${PWD}/arch/arm/include/asm
# export CCPREFIX=/Volumes/BLANK/x-tools2/arm-rpi3-eabihf/bin/arm-rpi3-eabihf-
# ARCH=arm CROSS_COMPILE=${CCPREFIX} make O=/Volumes/${Volume}/build/kernel
# make ARCH=arm CROSS_COMPILE=${CCPREFIX} O=/Volumes/${Volume}/build/kernel HOSTCFLAGS="-I/Volumes/BLANK/Raspbian-src/linux/arch/arm/include/asm"
#  make ARCH=arm CROSS_COMPILE=${CCPREFIX} O=/Volumes/${Volume}/build/kernel HOSTCFLAGS="--sysroot=/Volumes/BLANK/Raspbian-src/linux -I/Volumes/BLANK/x-tools2/arm-rpi3-eabihf/arm-rpi3-eabihf/sys-include"
 


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
CT_TOP_DIR="/Volumes/CrossToolNG/crosstool-ng-src"
CT_TOP_DIR="/Volumes/${Volume}/${CrossToolSourceDir}" 

ImageNameExt=${ImageName}.sparseimage   # This cannot be changed



# Options for Rasbian below here
BuildRaspbian=n

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


function showHelp()
{
cat <<'HELP_EOF'
   This shell script is a front end to crosstool-ng to help build a cross compiler on your Mac.  It downloads all the necessary files to build the cross compiler.  It only assumes you have Xcode command line tools installed.

   Options:
      -I <ImageName>  - Instead of CrosstoolNG.sparseImage use <ImageName>.sparseImageI
      -V <Volume>     - Instead of /Volumes/CrosstoolNG/
                               use
                                   /Volumes/<Volume>
                           Note: To do this the .config file is changed automatically
                                 from CrosstoolNG  to <Volume>

      -O <OutputPath> - Instead of /Volumes/<Volume>/x-tools
                               use
                                   /Volumes/<Volume>/<OutputPath>
                           Note: To do this the .config file is changed automatically
                                 from x-tools  to <OutputPath>

      -c Brew         - Remove all installed Brew tools.
      -c ct-ng        - Run make clean in crosstool-ng path
      -c realClean    - Unmounts the image and removes it. This destroys EVERYTHING!
      -f <configFile> - The name and path of the config file to use.
                        Default is arm-rpi3-eabihf.config
      -b              - Build the cross compiler AFTER building the necessary tools
                        and you have defined the crosstool-ng .config file.
      -t              - After the build, run a Hello World test on it.
      -r              - Download and build Raspbian.
      help            - This menu.
      "none"          - Go for it all if no options given. it will always try to 
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
   $BrewHome/bin/brew install $BrewTools --with-real-names && true

   # change to Exit immediately if a command exits with a non-zero status.
   set -e

   printf "${KBLU}Checking for $BrewHome/bin/gsha512sum ...${KNRM}"
   if [ ! -f $BrewHome/bin/gsha512sum ]; then
      printf "${KRED}Not found${KNRM}\n"
      exit 1
   fi
   printf "${KGRN}found${KNRM}\n"
   printf "${KBLU}Checking for $BrewHome/bin/sha512sum ...${KNRM}"
   if [ ! -f $BrewHome/bin/gsha512sum ]; then
      printf "${KNRM}\nLinking gsha512sum to sha512sum${KNRM}\n"
      ln -s $BrewHome/bin/gsha512sum $BrewHome/bin/sha512sum
   else
      printf "${KGRN}found${KNRM}\n"
   fi

   printf "${KBLU}Checking for $BrewHome/bin/gsha256sum ...${KNRM}"
   if [ ! -f $BrewHome/bin/gsha256sum ]; then
      printf "${KRED}Not found${KNRM}\n"
      exit 1
   fi
   printf "${KGRN}found${KNRM}\n"
   printf "${KBLU}Checking for $BrewHome/bin/sha256sum ...${KNRM}"
   if [ ! -f $BrewHome/bin/gsha256sum ]; then
      printf "${KNRM}\nLinking gsha256sum to sha256sum${KNRM}\n"
      ln -s $BrewHome/bin/gsha256sum $BrewHome/bin/sha256sum
   else
      printf "${KGRN}found${KNRM}\n"
   fi

}

# This was one try. It does not work because --with-libintl-prefix does not
# I will leave this here because if you search for libintl problems,
# there are many
function fixLibIntlTry1()
{
   printf "${KBLU}Making gettext libintl available ${KNRM}\n"
   gettextVersion=$(brew list --versions gettext | awk '{print $2}')

   gettextInclude=${BrewHome}/Cellar/gettext/${gettextVersion}/include
   gettextLib=${BrewHome}/Cellar/gettext/${gettextVersion}/lib
   
   if [ ! -d "$gettextInclude" ]; then
      printf "${KEDU}Gettext include not found. ${gettextInclude}${KNRM}\n"
      exit 1
   fi
   if [ ! -d "$gettextLib" ]; then
      printf "${KEDU}Gettext lib not found. ${gettextLib}${KNRM}\n"
      exit 1
   fi

   if [ ! -d "$libintlCopyDir" ]; then
      mkdir "$libintlCopyDir"
      mkdir "$libintlCopyDir/include"
      mkdir "$libintlCopyDir/lib"

      printf "${KBLU}Copying gettext include to Brew${KNRM}\n"
      cd ${gettextInclude}
      cp libintl.h ${libintlCopyDir}/include/

      printf "${KBLU}Copying gettext lib to Brew${KNRM}\n"
      cd ${gettextLib}
      cp libintl.* ${libintlCopyDir}/lib/
    fi

    printf "${KGRN}Complete${KNRM}\n"
}

# This did not work either.  libintl.h was not picked up in brew/include
function fixLibIntlTry2()
{
   printf "${KBLU}Making gettext libintl available ${KNRM}\n"
   gettextVersion=$(brew list --versions gettext | awk '{print $2}')

   if [ ! -d "$gettextInclude" ]; then
      printf "${KEDU}Gettext include not found. ${gettextInclude}${KNRM}\n"
      exit 1
   fi
   if [ ! -d "$gettextLib" ]; then
      printf "${KEDU}Gettext lib not found. ${gettextLib}${KNRM}\n"
      exit 1
   fi

   if [ ! -f "$brew/include/libintl.h" ]; then

      printf "${KBLU}Copying gettext include to Brew${KNRM}\n"
      cd ${gettextInclude}
      cp libintl.h ${$BrewHome}/include/

      printf "${KBLU}Copying gettext lib to Brew${KNRM}\n"
      cd ${gettextLib}
      cp libintl.* ${$BrewHome}/lib/
    fi

    printf "${KGRN}Complete${KNRM}\n"
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
    printf "${KBLU}Patching .config file for 'CrossToolNG' in ${PWD}${KNRM}\n"
    if [ -f ".config" ]; then
       sed -i .bak -e's/CrossToolNG/'$Volume'/g' .config
    fi
}
function patchConfigFileForOutputPath()
{
    printf "${KBLU}Patching .config file for 'x-tools' in ${PWD}${KNRM}\n"
    if [ -f ".config" ]; then
       sed -i .bak2 -e's/x-tools/'$OutputPath'/g' .config
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
      printf "${KGRN}    - Found existing ct-ng. Using it instead${KNRM}\n"
      return
   fi

   # It is strange that gettext is put in opt
   gettextDir=${BrewHome}/opt/gettext
   
   PATH=$BrewHome/bin:$BrewHome/opt/gettext/bin:$PATH 
   export PATH
   printf "${KBLU} Executing configure --with-libintl-prefix=$gettextDir ${KNRM}\n"

   # export LDFLAGS
   # export CPPFLAGS

   # --with-libintl-prefix should have been enough, but it seems LDFLAGS and
   # CPPFLAGS is required too to fix libintl.h not found
   LDFLAGS="  -L/Volumes/CrossToolNG/brew/opt/gettext/lib -lintl " \
   CPPFLAGS=" -I/Volumes/CrossToolNG/brew/opt/gettext/include" \
   ./configure  --with-libintl-prefix=$gettextDir --enable-local

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
   printf "${KGRN}Compilation of ct-ng is Complete ${KNRM}\n"
}

function createToolchain()
{
   printf "${KBLU}Creating toolchain ${ToolchainName}...${KNRM}\n"


   cd ${CT_TOP_DIR}

   if [ ! -d "${ToolchainName}" ]; then
      mkdir $ToolchainName
   fi

   # the process seems to open a lot of files at once. The default is 256. Bump it to 1024.
   #ulimit -n 2048


   printf "${KBLU}Checking for an existing toolchain config file:${KNRM} ${CrossToolNGConfigFilePath}/${CrossToolNGConfigFile} ...${KNRM}\n"
   if [ -f "${CrossToolNGConfigFilePath}/${CrossToolNGConfigFile}" ]; then
      printf "   - Using ${CrossToolNGConfigFilePath}/${CrossToolNGConfigFile}${KNRM}\n"
      cp "${CrossToolNGConfigFilePath}/${CrossToolNGConfigFile}"  "${CT_TOP_DIR}/.config"

      cd "${CT_TOP_DIR}"
      if [ "$Volume" == 'CrossToolNG' ];then

         printf "${KBLU}.config file not being patched as -V was not specified${KNRM}\n"
      else
         patchConfigFileForVolume
      fi
      if [ "$OutputPath" == 'x-tools' ];then
         printf "${KBLU}.config file not being patched as -O was not specified${KNRM}\n"
      else
         patchConfigFileForOutputPath
      fi
   else
      printf "   - None found${KNRM}\n"
      if [ -f  "${CT_TOP_DIR}/.config" ]; then
         # We have some sort of config file to continue with
 
         # Stupid bash 
         printf "$KNRM"
      else
         printf "${KRED}There is no CrosstoolNG .config file to continue with${KNRM}\n"
         exit 1
      fi
   fi

cat <<'CONFIG_EOF'

NOTES: on what to set in config file, taken from
https://gist.github.com/h0tw1r3/19e48ae3021122c2a2ebe691d920a9ca

- Paths and misc options
    - Check "Try features marked as EXPERIMENTAL"
    - Set "Prefix directory" to the real values of:
        /Volumes/$Volume/$OutputPath/${CT_TARGET}

- Target options
    By default this script builds the configuration for arm-rpi3-eabihf as this is my focus; However, crosstool-ng can build so many different types of cross compilers.  If you are interested in them, check out the samples with:

      ct-ng list-samples

    You could also just go to the crosstool-ng-src/samples directory and peruse them all.

   At least using this script will help you try configurations more easily.
   

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
   printf "${KBLU}Execute:${KNRM}bash build.sh${KNRM}"
   if [ $Volume != 'CrossToolNG' ]; then
      printf "${KNRM} -V ${Volume}${KNRM}"
   fi
   if [ $OutputPath != 'x-tools' ]; then
      printf "${KNRM} -O ${OutputPath}${KNRM}"
   fi
   printf "${KNRM} -b${KNRM}\n"
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
   if [ ! -f "/Volumes/${Volume}/$OutputPath/${ToolchainName}/bin/arm-rpi3-eabihf-g++" ]; then
      printf "${KRED}No executable compiler found. ${KNRM}\n"
      rc='-1'
      return
   fi

   cat <<'   HELLO_WORLD_EOF' > /tmp/HelloWorld.cpp
      #include <iostream>
      using namespace std;

      int main ()
      {
        cout << "Hello World!";
        return 0;
      }
   HELLO_WORLD_EOF

   PATH=/Volumes/${Volume}/$OutputPath/${ToolchainName}/bin:$PATH

   arm-rpi3-eabihf-g++ -fno-exceptions /tmp/HelloWorld.cpp -o /tmp/HelloWorld
   rc=$?

}

RaspbianSrcDir="Raspbian-src"
function downloadRaspbianKernel
{
RaspbianURL="https://github.com/raspberrypi/linux.git"

   cd "/Volumes/${Volume}"
   printf "${KBLU}Downloading Raspbian Kernel latest... to ${PWD}${KNRM}\n"

   if [ -d "${RaspbianSrcDir}" ]; then
      printf "${KRED}WARNING ${KNRM}Path already exists ${RaspbianSrcDir}${KNRM}\n"
      printf "        A fetch will be done instead to keep tree up to date{KNRM}\n"
      printf "\n"
      cd "${RaspbianSrcDir}/linux"
      git fetch
    
   else
      printf "${KBLU}Creating ${RaspbianSrcDir} ... ${KNRM}"
      mkdir "${RaspbianSrcDir}"
      printf "${KGRN}done${KNRM}\n"

      cd "${RaspbianSrcDir}"
      git clone --depth=1 ${RaspbianURL}
   fi
}

function configureRaspbianKernel
{
   cd "/Volumes/${Volume}/${RaspbianSrcDir}/linux"
   printf "${KBLU}Configuring Raspbian Kernel in ${PWD}${KNRM}\n"
   PATH=$BrewHome/bin:$PATH 

   # Cleaning tree
   printf "${KBLU}Make mrproper in ${PWD}${KNRM}\n"
   make O=/Volumes/${Volume}/build/kernel mrproper

   # Only thing changed were

   # *
   # * General setup
   # *
   # Cross-compiler tool prefix (CROSS_COMPILE) [] (NEW) 
   # - Set to: arm-rpi3-eabihf-


   # Preemption Model  (Under Processor Types and features
   #   1. No Forced Preemption (Server) (PREEMPT_NONE) (NEW)
   #   2. Voluntary Kernel Preemption (Desktop) (PREEMPT_VOLUNTARY)
   # > 3. Preemptible Kernel (Low-Latency Desktop) (PREEMPT) (NEW)
   # choice[1-3]: 3

   make O=/Volumes/${Volume}/build/kernel nconfig
   make O=/Volumes/${Volume}/build/kernel


}

# Define this once and you save yourself some trouble
OPTSTRING='hc:I:V:O:f:btr'

# Getopt #1 - To enforce order
while getopts "$OPTSTRING" opt; do
   case $opt in
      I)
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
      O)
          OutputPath=$OPTARG
          ;;
      f)
          CrossToolNGConfigFile=$OPTARG

          # Do a quick check before we begin
          if [ -f "${CrossToolNGConfigFilePath}/${CrossToolNGConfigFile}" ]; then
             printf "${KNRM}${CrossToolNGConfigFilePath}/${CrossToolNGConfigFile} ...${KGRN}found${KNRM}\n"
          else
             printf "${KNRM}${CrossToolNGConfigFilePath}/${CrossToolNGConfigFile} ...${KRED}not found${KNRM}\n"
             exit 1
          fi
          ;;
   esac
done

# Reset the index for the next getopt optarg
OPTIND=1

while getopts "$OPTSTRING" opt; do
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
          if  [ $OPTARG == "realClean" ]; then
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
          printf "${KBLU}Testing toolchain ${ToolchainName}...${KNRM}\n"

          testBuild   # testBuild sets rc
          if [ ${rc} == '0' ]; then
             printf "${KGRN}Wahoo ! it works!! ${KNRM}\n"
             exit 0
          else
             printf "${KRED}Boooo ! it failed :-( ${KNRM}\n"
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
      r)
          # Done in first getopt for proper order

          printf "${KYEL}Checking for cross compiler first ... ${KNRM}"
          testBuild   # testBuild sets rc
          if [ ${rc} == '0' ]; then
             printf "${KGRN}  OK ${KNRM}\n"
          else
             printf "${KRED}  failed ${KNRM}\n"
             exit -1
          fi
          buildRaspbian=y
          downloadRaspbianKernel
          configureRaspbianKernel
          exit 0
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
# fixLibIntl

# The 1.23  archive is busted and does not contain CT_Mirror, until
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
