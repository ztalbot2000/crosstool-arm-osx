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
#      where missing gnu tools  and crosstool-ng will be placed so as not to interfere
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

# During compile of OSX tools, log output to console
# Either "none" or "full"
LoggingOpt="none"

# The process seems to open a lot of files at once. The default is 256. Bump it to 2048.
# Without this you will get an error: no rule to make IBM1388.so
ulimit -n 2048

# If latest is 'y', then git will be used to download crosstool-ng LATEST
# I believe there is a problem with 1.23.0 so for now, this is the default.
# Ticket #931 has been submitted to address this. It deals with CT_Mirror being undefined
downloadCrosstoolLatestOpt=y

#
# Config. Update below here to suite your specific needs, but all options can be
# specified from command line arguments. See build.sh -help.

# The crosstool image will be $ImageName.sparseimage
# The volume will grow as required because of the SPARSE type
# You can change this with -i <ImageName> but it will always
# be <ImageName>.sparseimage
ImageName="CrossToolNG"

# I got tired of rebuilding missing OSX tools  and ct-ng. They now go here
ImageNameBase="${ImageName}Base"

#
# This is where your §{CrossToolNGConfigFile}.config file is if you have one.
# It would be copied to $CT_TOP_DIR/.config prior to ct-ng menuconfig
# It can be overriden with -f <ConfigFile>. Please do this instead of
# changing it here.
CrossToolNGConfigFile="arm-rpi3-eabihf.config"
CrossToolNGConfigFilePath="${PWD}"

# This will be the name of the toolchain created by crosstools-ng
# It is placed in $CT_TOP_DIR
# The real name is based upon the options you have set in the CrossToolNG
# config file. You will probably need to change this.  You now can do so with
# the option -T <ToolchainName>. The default being arm-rpi3-eabihf
ToolchainName='arm-rpi3-eabihf'

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

# These are tools missing from OSX and/or do not have the needed functionality
# We will also install ct-ng here.
ToolsPath="/Volumes/${VolumeBase}/tools"
ToolsLibPath="${ToolsPath}/lib"
ToolsIncludePath="${ToolsPath}/include"
ToolsBinPath="${ToolsPath}/bin"


# Binutils is for objcopy, objdump, ranlib, readelf
# sed, gawk libtool bash, grep are direct requirements
# xz is reauired when configuring crosstool-ng
# help2man is reauired when configuring crosstool-ng
# wget  is reauired when configuring crosstool-ng
# automake is required to fix a compile issue with gettext
# coreutils is for sha512sum
# sha2 is for sha512
# bison on osx was too old (2.3) and gcc compiler did not like it
# findutils is for xargs, needed by make modules in Raspbian
#
# for Raspbian tools - libelf ncurses
# for xconfig - QT   (takes hours). That would be up to you.

# This is required so brew can be installed elsewhere
# Comments are for cut and paste during development
# export Volume=BLANK
# export OutputDir='x-tools'
# ToolchainName='arm-rpi3-eabihf'
#  export PATH=${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/bin:$ToolsBinPath:/Volumes/${VolumeBase}/ctng/bin:$PATH 
# export CCPREFIX=/Volumes/BLANK/x-tools2/arm-rpi3-eabihf/bin/arm-rpi3-eabihf-
# ARCH=arm CROSS_COMPILE=${CCPREFIX} make O=/Volumes/${Volume}/build/kernel
# make ARCH=arm CROSS_COMPILE=${CCPREFIX} O=/Volumes/${Volume}/build/kernel HOSTCFLAGS="-I/Volumes/BLANK/Raspbian-src/linux/arch/arm/include/asm"
#  make ARCH=arm CROSS_COMPILE=${CCPREFIX} O=/Volumes/${Volume}/build/kernel HOSTCFLAGS="--sysroot=/Volumes/BLANK/Raspbian-src/linux -I/Volumes/BLANK/x-tools2/arm-rpi3-eabihf/arm-rpi3-eabihf/sys-include"
 


# This is the crosstools-ng version used by curl to fetch relased version
# of crosstools-ng. I don't know if it works with previous versions and
#  who knows about future ones.
CrossToolVersion="crosstool-ng-1.23.0"

# Changing this affects CT_TOP_DIR which also must be reflected in your
# crosstool-ng .config file
CrossToolSourceDir="crosstool-ng-src"

CT_TOP_DIR="/Volumes/${Volume}"

ImageNameExt=${ImageName}.sparseimage   # This cannot be changed
ImageNameExtBase=${ImageNameBase}.sparseimage   # This cannot be changed



# Options to be toggled from command line
# see -help
BuildRaspbianOpt="n"
CleanRaspbianOpt="n"
BuildToolchainOpt="n"

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

function waitForPid()
{
   pid=$1 
   spindleCount=0
   spindleArray=("|" "/" "-" "\\")

   while ps -p $pid >/dev/null; do
      sleep 0.5
      printf  "\r${KGRN}" 
      printf ${spindleArray[$spindleCount]}
      printf  " ${KNRM}"
      spindleCount=$((spindleCount + 1))
      if [[ $spindleCount -eq ${#spindleArray[*]} ]]; then
         spindleCount=0
      fi
   done
   printf "\r${KNRM}Done\n"

   # Get the true return code of the process
   wait $pid

   # Set our global return code of the process
   rc=$?
}

function buildAndInstallOSXTool()
{
   pkgURL=$1
   pkg=$2
   checkFile=$3
   srcDir=$4
   name=$5
   configCmdOptions=$6

   printf "${KBLU}Checking for ${KNRM}${name}... "
   if [ -f "${ToolsPath}/${checkFile}" ]; then
      printf "${KGRN}found${KNRM}\n"
      return
   fi
   printf "${KYEL}not found${KNRM}\n"

   printf "${KBLU}Checking for ${KNRM}${CT_TOP_DIR}/src/${srcDir} ... "
   if [ -d "${CT_TOP_DIR}/src/${srcDir}" ]; then
      printf "${KGRN}found${KNRM}\n"
      printf "${KNRM}Using existing ${name} source${KNRM}\n"
   else
      printf "${KYEL}not found${KNRM}\n"
      cd "${CT_TOP_DIR}/src/"
      printf "${KBLU}Checking for saved ${KNRM}${pkg} ... "
      if [ -f "${TarBallSourcesPath}/${pkg}" ]; then
         printf "${KGRN}found${KNRM}\n"
      else
         printf "${KYEL}not found${KNRM}\n"
         printf "${KBLU}Downloading ${KNRM}${pkg} ... "
         curl -Lsf "${pkgURL}" -o "${TarBallSourcesPath}/${pkg}"
         printf "${KGRN}done${KNRM}\n"
      fi
      printf "${KBLU}Decompressing ${KNRM}${pkg} ... "
      tar -xzf "${TarBallSourcesPath}/${pkg}" -C "${CT_TOP_DIR}/src"
      printf "${KGRN}done${KNRM}\n"
   fi

   cd "${CT_TOP_DIR}/src/${srcDir}"

   #
   #   Configure
   #

   printf "${KBLU}Configuring ${KNRM}${name}. Logging to config.log\n"

   # We will catch any error
   set +e

   if [ "${LoggingOpt}" == "none" ]; then
      CFLAGS=-I${ToolsIncludePath}   \
      CPPFLAGS=-I${ToolsIncludePath}  \
      LDFLAGS=-L${ToolsLibPath}      \
      ./configure   ${configCmdOptions}  > config.log 2>&1 &

      pid="$!"
      # printf "configure pid is $pid\n"
      waitForPid "$pid"
   else
      CFLAGS=-I${ToolsIncludePath}   \
      CPPFLAGS=-I${ToolsIncludePath}  \
      LDFLAGS=-L${ToolsLibPath}      \
      ./configure  $configCmdOptions > config.log 
      rc=$?
   fi

   if [ $rc != 0 ]; then
      printf "${KRED}Error : [${rc}] ${KNRM} Check the config.log for more info\n"
      exit $rc
   fi

   #
   #   Build
   #

   numberOfCores=$(sysctl -n hw.ncpu)

   printf "${KBLU}Building ${KNRM}${name}. Logging to build.log\n"
   if [ "${LoggingOpt}" == "none" ]; then
      # make -j$numberOfCores > build.log 2>&1 &
      make > build.log 2>&1 &

      pid="$!"
      # printf "Build pid is $pid\n"
      waitForPid "$pid"
   else
      make > build.log 
      rc=$?
   fi

   if [ $rc != 0 ]; then
      printf "${KRED}Error : [${rc}] ${KNRM} Check the build.log for more info\n"
      exit $rc
   fi

   #
   #   Install
   #

   printf "${KBLU}Installing ${KNRM}${name}. Logging to install.log\n"
   if [ "${LoggingOpt}" == "none" ]; then
      make install > install.log 2>&1

      pid="$!"
      # printf "Install pid is $pid\n"
      waitForPid "$pid"
   else
      make install > install.log
      rc=$?
   fi

   if [ $rc != 0 ]; then
      printf "${KRED}Error : [${rc}] ${KNRM} Check the install.log for more info\n"
      exit $rc
   fi

   # There should not be any errors past this
   set -e

}

function buildM4ForOSX()
{
   pkgURL="http://gnu.mirror.globo.tech/m4/m4-1.4.18.tar.gz"
   pkg="${pkgURL##*/}"
   checkFile="bin/m4"
   srcDir=${pkg%.tar.*}
   name="m4"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}

function buildReadlineForOSX()
{
   pkgURL="https://ftp.gnu.org/gnu/readline/readline-7.0.tar.gz"
   pkg="${pkgURL##*/}"
   checkFile="lib/libreadline.a"
   srcDir=${pkg%.tar.*}
   name="readline"
   configCmdOptions="--with-curses --prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}

function buildGMPForOSX()
{
   pkgURL="https://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.bz2"
   pkg="${pkgURL##*/}"
   checkFile="lib/libgmp.a"
   srcDir=${pkg%.tar.*}
   name="gmp"
   configCmdOptions=" --prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}

function buildLibISLForOSX()
{

   pkgURL="http://isl.gforge.inria.fr/isl-0.18.tar.gz"
   pkg="${pkgURL##*/}"
   checkFile="lib/libisl.a"
   srcDir=${pkg%.tar.*}
   name="libisl"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildLibIconvForOSX()
{
   pkgURL="https://ftp.gnu.org/gnu/libiconv/libiconv-1.15.tar.gz"
   pkg="${pkgURL##*/}"
   checkFile="lib/libiconv.la"
   srcDir=${pkg%.tar.*}
   name="libiconv"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildPkgConfigForOSX()
{
   pkgURL="https://pkg-config.freedesktop.org/releases/pkg-config-0.29.2.tar.gz"
   pkg="${pkgURL##*/}"
   checkFile="bin/pkg-config"
   srcDir=${pkg%.tar.*}
   name="pkg-config"
   configCmdOptions="--prefix=${ToolsPath} --disable-debug --with-pc-path=${ToolsPath}/lib/pkgconfig:${ToolsPath}/share/pkgconfig:/usr/lib/pkgconfig --with-internal-glib"

   touch ${ToolsIncludePath}/malloc.h
   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
   rm ${ToolsIncludePath}/malloc.h
}
function buildGettextForOSX()
{  
   pkgURL="http://gnu.mirror.globo.tech/gettext/gettext-0.19.8.tar.xz"
   pkg="${pkgURL##*/}"
   checkFile="lib/libasprintf.a"
   srcDir=${pkg%.tar.*}
   name="gettext"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildLibPthForOSX()
{
   pkgURL="http://gnu.mirror.globo.tech/pth/pth-2.0.7.tar.gz"
   pkg="${pkgURL##*/}"
   checkFile="lib/libpth.a"
   srcDir=${pkg%.tar.*}
   name="pth"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildFindutilsForOSX()
{
   pkgURL="https://ftp.gnu.org/gnu/findutils/findutils-4.6.0.tar.gz"
   pkg="${pkgURL##*/}"
   checkFile="bin/find"
   srcDir=${pkg%.tar.*}
   name="findUtils"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildXZForOSX()
{
   pkgURL="https://tukaani.org/xz/xz-5.2.4.tar.gz"
   pkg="${pkgURL##*/}"
   checkFile="bin/xz"
   srcDir=${pkg%.tar.*}
   name="xz"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildMPFRForOSX()
{
   pkgURL="http://gnu.mirror.globo.tech/mpfr/mpfr-4.0.1.tar.xz"
   pkg="${pkgURL##*/}"
   checkFile="lib/libmpfr.a"
   srcDir=${pkg%.tar.*}
   name="mpfr"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildMPCForOSX()
{
   pkgURL="http://gnu.mirror.globo.tech/mpc/mpc-1.1.0.tar.gz"
   pkg="${pkgURL##*/}"
   checkFile="lib/libmpc.a"
   srcDir=${pkg%.tar.*}
   name="mpc"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildBisonForOSX()
{
   pkgURL="http://gnu.mirror.globo.tech/bison/bison-3.0.5.tar.gz"
   pkg="${pkgURL##*/}"
   checkFile="bin/bison"
   srcDir=${pkg%.tar.*}
   name="bison"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
buildBashForOSX()
{
   pkgURL="http://gnu.mirror.globo.tech/bash/bash-4.4.18.tar.gz"
   pkg="${pkgURL##*/}"
   checkFile="bin/bash"
   srcDir=${pkg%.tar.*}
   name="bash"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildSedForOSX()
{
   pkgURL="http://gnu.mirror.globo.tech/sed/sed-4.5.tar.xz"
   pkg="${pkgURL##*/}"
   checkFile="bin/sed"
   srcDir=${pkg%.tar.*}
   name="sed"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildGawkForOSX()
{
   pkgURL="http://gnu.mirror.globo.tech/gawk/gawk-4.2.1.tar.xz"
   pkg="${pkgURL##*/}"
   checkFile="bin/gawk"
   srcDir=${pkg%.tar.*}
   name="gawk"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildHelp2manForOSX()
{
   pkgURL="http://gnu.mirror.globo.tech/help2man/help2man-1.47.6.tar.xz"
   pkg="${pkgURL##*/}"
   checkFile="bin/help2man"
   srcDir=${pkg%.tar.*}
   name="help2man"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildGrepForOSX()
{
   pkgURL="http://gnu.mirror.globo.tech/grep/grep-3.1.tar.xz"
   pkg="${pkgURL##*/}"
   checkFile="bin/grep"
   srcDir=${pkg%.tar.*}
   name="grep"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildLibtoolForOSX()
{
   pkgURL="http://gnu.mirror.globo.tech/libtool/libtool-2.4.6.tar.xz"
   pkg="${pkgURL##*/}"
   checkFile="bin/libtoolize"
   srcDir=${pkg%.tar.*}
   name="libtool"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildAutoconfForOSX()
{
   pkgURL="http://gnu.mirror.globo.tech/autoconf/autoconf-2.69.tar.xz"
   pkg="${pkgURL##*/}"
   checkFile="bin/autoconf"
   srcDir=${pkg%.tar.*}
   name="autoconf"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildAutomakeForOSX()
{
   pkgURL="http://gnu.mirror.globo.tech/automake/automake-1.16.1.tar.xz"
   pkg="${pkgURL##*/}"
   checkFile="bin/automake"
   srcDir=${pkg%.tar.*}
   name="automake"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildWgetForOSX()
{
   pkgURL="http://gnu.mirror.globo.tech/wget/wget-1.19.5.tar.gz"
   pkg="${pkgURL##*/}"
   checkFile="bin/wget"
   srcDir=${pkg%.tar.*}
   name="wget"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildWgetForOSX()
{
   pkgURL="http://gnu.mirror.globo.tech/wget/wget-1.19.5.tar.gz"
   pkg="${pkgURL##*/}"
   checkFile="bin/wget"
   srcDir=${pkg%.tar.*}
   name="wget"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildBinutilsForOSX()
{
   pkgURL="http://gnu.mirror.globo.tech/binutils/binutils-2.30.tar.xz"
   pkg="${pkgURL##*/}"
   checkFile="bin/objcopy"
   srcDir=${pkg%.tar.*}
   name="binutils"
   configCmdOptions="--prefix=${ToolsPath}"

   buildAndInstallOSXTool "${pkgURL}" "${pkg}" "${checkFile}" "${srcDir}" "${name}" "${configCmdOptions}"
}
function buildMissingOSXTools()
{
   export PATH="${ToolsBinPath}:${PATH}"
   printf "${KBLU}Checking for our own tools path ${KNRM} ${ToolsPath} ... "
   if [ -d "${ToolsPath}" ]; then
      printf "${KGRN}found${KNRM}\n"
   else
      printf "${KYEL}not found${KNRM}\n"
      printf "${KBLU}Creating our own tools path ${KNRM}${ToolsPath} ... "
      mkdir "${ToolsPath}" 
      printf "${KGRN}done${KNRM}\n"
   fi

   printf "${KBLU}Checking for our own tools path/include ${KNRM} ${ToolsPath}/include ... "
   if [ -d "${ToolsIncludePath}" ]; then
      printf "${KGRN}found${KNRM}\n"
   else
      printf "${KYEL}not found${KNRM}\n"
      printf "${KBLU}Creating our own tools path/include ${KNRM}${ToolsIncludePath} ... "
      mkdir "${ToolsIncludePath}" 
      printf "${KGRN}done${KNRM}\n"
   fi

   printf "${KBLU}Checking for our own tools path/lib ${KNRM} ${ToolsLibPath} ... "
   if [ -d "${ToolsLibPath}" ]; then
      printf "${KGRN}found${KNRM}\n"
   else
      printf "${KYEL}not found${KNRM}\n"
      printf "${KBLU}Creating our own tools path/lib ${KNRM}${ToolsLibPath} ... "
      mkdir "${ToolsLibPath}" 
      printf "${KGRN}done${KNRM}\n"
   fi

   printf "${KBLU}Checking for our own tools path/bin ${KNRM} ${ToolsBinPath} ... "
   if [ -d "${ToolsBinPath}" ]; then
      printf "${KGRN}found${KNRM}\n"
   else
      printf "${KYEL}not found${KNRM}\n"
      printf "${KBLU}Creating our own tools path/bin ${KNRM}${ToolsBinPath} ... "
      mkdir "${ToolsBinPath}" 
      printf "${KGRN}done${KNRM}\n"
   fi

   # M4 is for Bison
   buildM4ForOSX

   # Readline is for GMP
   buildReadlineForOSX
   # ISL needs GMP
   buildGMPForOSX
   # FindUtils needs ISL
   buildLibISLForOSX

   # FindUtils needs Iconv
   # wget needs Iconv
   buildLibIconvForOSX

   # wget says ours is to old
   buildPkgConfigForOSX

   # gettext is for ct-ng
   buildGettextForOSX

   # FindUtils needs libpth
   buildLibPthForOSX

   buildFindutilsForOSX


   buildXZForOSX
   buildMPFRForOSX
   buildMPCForOSX

   buildBisonForOSX

   # Too old for ct-ng
   buildBashForOSX

   buildSedForOSX

   # help2man says awk is to old
   buildGawkForOSX

   # Required for ct-ng
   buildHelp2manForOSX

   buildGrepForOSX

   # Missing
   buildLibtoolForOSX

   # Missing
   buildAutoconfForOSX
   # Missing
   buildAutomakeForOSX

   # Missing for ct-ng
   #buildWgetForOSX

   # Missing objcopy for ct-ng
   buildBinutilsForOSX

}


# This is a lit of all MacPorts tools to build gcc
# The list is as long for HomeBrew


# Locations where to get the above sources
# DO NOT CHANGE THE ORDER. They must be the same
declare -a MacPortsToolsToBuildGCC=(                                                    \
       "gcc_select-0.1"                                                      \
       "libmacho-headers-895"                                                \
       "db48-4.8.30"                                                         \
       "python_select-0.3"                                                   \
       "python2_select-0.0"                                                  \
       "lzo2-2.10"                                                           \
       "expat-2.2.5"                                                         \
       "lz4-1.8.2"                                                           \
       "libffi-3.2.1"                                                        \
       "gpatch-2.7.6"                                                        \
       "http://gnu.mirror.globo.tech/m4/m4-1.4.18.tar.gz"                    \
       "https://ftp.gnu.org/gnu/readline/readline-7.0.tar.gz"                \
       "https://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.bz2"                       \
       "http://isl.gforge.inria.fr/isl-0.18.tar.gz"                          \
       "bzip2-1.0.6"                                                         \
       "Ncurses-5.3"                                                         \
       "gdbm-1.16"                                                           \
       "perl5.26-5.26.2"                                                     \
       "p5.26-locale-gettext 1.70.0"                                         \
       "libedit-20170329-3.1"                                                \
       "gperf-3.1"                                                           \
       "https://ftp.gnu.org/gnu/libiconv/libiconv-1.15.tar.gz"               \
       "https://pkg-config.freedesktop.org/releases/pkg-config-0.29.2.tar.gz" \
       "gettext-0.19.8.1"                                                    \
       "http://gnu.mirror.globo.tech/pth/pth-2.0.7.tar.gz"                   \
       "https://ftp.gnu.org/gnu/findutils/findutils-4.6.0.tar.gz"            \
       "gmake-4.2.1"                                                         \
       "https://tukaani.org/xz/xz-5.2.4.tar.gz"                              \
       "http://gnu.mirror.globo.tech/mpfr/mpfr-4.0.1.tar.xz"                 \
       "libmpc-1.1.0"                                                        \
       "libgcc8-8.2.0"                                                       \
       "libgcc-1.0"                                                          \
       "libgcc45-4.5.4"                                                      \
       "libgcc7-7.3.0"                                                       \
       "libgcc6-6.4.0"                                                       \
       "libunwind-headers-5.0.1"                                             \
       "cctools-895"                                                         \
       "libcxx 5.0.1"                                                        \
       "ld64-latest 274.2"                                                   \
       "bison-runtime"                                                       \
       "http://gnu.mirror.globo.tech/bison/bison-3.0.5.tar.gz"               \
       "http://gnu.mirror.globo.tech/bash/bash-4.4.18.tar.gz"                \
       "diffutils-3.6"                                                       \
       "coreutils-8.30"                                                      \
       "http://gnu.mirror.globo.tech/gawk/gawk-4.2.1.tar.xz"                 \
       "http://ftp.gnu.org/gnu/sed/sed-4.5.tar.xz"                           \
       "http://gnu.mirror.globo.tech/help2man/help2man-1.47.6.tar.xz"        \
       "texinfo-6.5"                                                         \
       "gzip-1.9"                                                            \
       "unzip 6.0"                                                           \
       "xattr-0.1"                                                           \
       "http://gnu.mirror.globo.tech/libtool/libtool-2.4.6.tar.xz"           \
       "http://gnu.mirror.globo.tech/autoconf/autoconf-2.69.tar.xz"          \
       "http://gnu.mirror.globo.tech/automake/automake-1.16.1.tar.xz"        \
       "libunistring-0.9.10"                                                 \
       "libidn2-2.0.5"                                                       \
       "libuv-1.22.0"                                                        \
       "gnutar-1.29"                                                         \
       "zlib-1.2.11"                                                         \
       "http://gnu.mirror.globo.tech/wget/wget-1.19.5.tar.gz"                \
       "sqlite3-3.24.0"                                                      \
       "openssl-1.0.2o"                                                      \
       "xar-1.6.1"                                                           \
       "libxml2-2.9.7"                                                       \
       "http://gnu.mirror.globo.tech/binutils/binutils-2.30.tar.xz"          \
       "bzip2-1.0.6"                                                         \
       "curl-ca-bundle-7.61.0"                                               \
       "curl 7.61.0"                                                         \
       "cmake-3.12.1"                                                        \
       "llvm-5.0-5.0.2"                                                      \
       "ld64-latest-274.2"                                                   \
       "ld64-3"                                                              \
       "libarchive-3.3.2"                                                    \
       "python27-2.7.15"                                                     \
       "libpsl-0.20.2-20180522"                                              \
       "pcre-8.42"                                                           \
       "glib2-2.56.1"                                                        \
       "http://gnu.mirror.globo.tech/grep/grep-3.1.tar.xz"                   \
       "gcc43-4.3.6"                                                         \
       "Glibc-2.2.5"                                                         \
)


function showHelp()
{
cat <<'HELP_EOF'
   This shell script is a front end to crosstool-ng to help build a cross compiler on your Mac.  It downloads all the necessary files to build the cross compiler.  It only assumes you have Xcode command line tools installed.

   Options:
     -I <ImageName>   - Instead of CrosstoolNG.sparseImage use <ImageName>.sparseImageI
     -V <Volume>      - Instead of /Volumes/CrosstoolNG/ and
                                   /Volumes/CrosstoolNGBase/
                              use
                                  /Volumes/<Volume> and
                                  /Volumes/<Volume>Base
                          Note: To do this the .config file is changed automatically
                                from CrosstoolNG  to <Volume>

     -O <OutputDir>  - Instead of /Volumes/<Volume>/x-tools
                        use
                           /Volumes/<Volume>/<OutputDir>
                        Note: To do this the .config file is changed automatically
                              from x-tools  to <OutputDir>

     -c ct-ng         - Run make clean in crosstool-ng path
     -c realClean     - Unmounts the image and removes it. This destroys EVERYTHING!
     -c raspbian      - run make clean in the RaspbianSrcDir.
     -f <configFile>  - The name and path of the config file to use.
                        Default is arm-rpi3-eabihf.config
     -b               - Build the cross compiler AFTER building the necessary tools
                        and you have defined the crosstool-ng .config file.
     -b <last_step+>    * If last_step+ is specified ct-ng is executed with LAST_SUCCESSFUL_STETP_NAME+ 
                        This is accomplished when CT_DEBUG=y and CT_SAVE_STEPS=y
     -b list-steps      * This could also be list-steps to show steps available. 
     -b raspbian>     - Download and build Raspbian.
     -t               - After the build, run a Hello World test on it.
     -T <Toolchain>   - The ToolchainName created.
                        The default used is: arm-rpi3-eabihf
                        The actual result is based on what is in your
                           -f <configFile>
                        The product of which would be: arm-rpi3-eabihf-gcc ...
     -P               - Just Print the PATH variableH
     -h               - This menu.
     -help
     -L               - For build of OSX tools, log output to stdout instead of to files
     -Logging           default is to files
     "none"           - Go for it all if no options given. it will always try to 
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

function ct-ngMakeClean()
{
   printf "${KBLU}Cleaning ct-ng...${KNRM}\n"
   ctDir="/Volumes/${VolumeBase}/${CrossToolSourceDir}"
   printf "Checking for ${KNRM}${ctDir} ..."
   if [ -d "${ctDir}" ]; then
      printf "${KGRN}OK${KNRM}\n"
   else
      printf "${KRED}not found${KNRM}\n"
      exit -1
   fi
   cd "${ctDir}"
   make clean
}
function raspbianClean()
{
   printf "${KBLU}Cleaning raspbian (make mrproper)...${KNRM}\n"

   # Remove our elf.h
   cleanupElfHeaderForOSX

   printf "${KBLU}Checking for ${KNRM}${CT_TOP_DIR}/${RaspbianSrcDir} ... "
   if [ -d "${CT_TOP_DIR}/${RaspbianSrcDir}" ]; then
      printf "${KGRN}OK${KNRM}\n"
   else
      printf "${KRED}not found${KNRM}\n"
      exit -1
   fi
   printf "${KBLU}Checking for ${KNRM}${CT_TOP_DIR}/${RaspbianSrcDir}/linux ... "
   if [ -d "${CT_TOP_DIR}/${RaspbianSrcDir}/linux" ]; then
      printf "${KGRN}OK${KNRM}\n"
   else
      printf "${KRED}not found${KNRM}\n"
      exit -1
   fi
   cd ${CT_TOP_DIR}/$RaspbianSrcDir/linux
   make mrproper
}
function realClean()
{

   # Remove our elf.h
   cleanupElfHeaderForOSX

   if [ -d  "/Volumes/${VolumeBase}" ]; then 
      printf "${KBLU}Unmounting  /Volumes/${VolumeBase}${KNRM}\n"
      hdiutil unmount /Volumes/${VolumeBase}
   fi

   # Since everything is on the image, just remove it does it all
   printf "${KBLU}Removing ${ImageNameExt}${KNRM}\n"
   removeFileWithCheck ${ImageNameExt}
   printf "${KBLU}Removing ${ImageNameExtBase}${KNRM}\n"
   removeFileWithCheck ${ImageNameExtBase}
}

# For smaller more permanent stuff
function createCaseSensitiveVolumeBase()
{
    VolumeDir="/Volumes/${VolumeBase}"
    printf "${KBLU}Creating 4G volume for tools mounted as ${VolumeDir}...${KNRM}\n"
    if [  -d "${VolumeDir}" ]; then
       printf "${KYEL}WARNING${KNRM}: Volume already exists: ${VolumeDir}${KNRM}\n"
      
       # Give a couple of seconds for the user to react
       sleep 1

       return;
    fi

   if [ -f "${ImageNameExtBase}" ]; then
      printf "${KRED}WARNING:${KNRM}\n"
      printf "         File already exists: ${ImageNameExtBase}${KNRM}\n"
      printf "         This file will be mounted as ${VolumeDir}${KNRM}\n"
      
      # Give a couple of seconds for the user to react
      sleep 1

   else
      hdiutil create ${ImageNameBase}        \
                      -volname ${VolumeBase} \
                      -type SPARSE           \
                      -size 2g               \
                      -fs HFSX               \
                      -puppetstrings
   fi

   hdiutil mount ${ImageNameExtBase}
}

function createTarBallSourcesDir()
{
    printf "${KBLU}Checking for saved tarballs directory ${KNRM}${TarBallSourcesPath}...${KNRM}"
    if [ -d "${TarBallSourcesPath}" ]; then
       printf "${KGRN}found${KNRM}\n"
       return
    fi
    printf "${KNRM}Creating ${KNRM}${TarBallSourcesPath}...${KNRM}"
    mkdir "${TarBallSourcesPath}"
    printf "${KGRN}done${KNRM}\n"
    return
}

# This is where the cross compiler and Raspbian will go
function createCaseSensitiveVolume()
{
    VolumeDir="${CT_TOP_DIR}"
    printf "${KBLU}Creating volume mounted as ${KNRM}${VolumeDir}...${KNRM}\n"
    if [  -d "${VolumeDir}" ]; then
       printf "${KYEL}WARNING${KNRM}: Volume already exists: ${VolumeDir}${KNRM}\n"
      
       # Give a couple of seconds for the user to react
       sleep 1

       return;
    fi

   if [ -f "${ImageNameExt}" ]; then
      printf "${KRED}WARNING:${KNRM}\n"
      printf "         File already exists: ${ImageNameExt}${KNRM}\n"
      printf "         This file will be mounted as ${VolumeDir}${KNRM}\n"
      
      # Give a couple of seconds for the user to react
      sleep 1

   else
      hdiutil create ${ImageName}           \
                      -volname ${Volume}    \
                      -type SPARSE          \
                      -size 32              \
                      -fs HFSX              \
                      -puppetstrings
   fi

   hdiutil mount ${ImageNameExt}
}

function downloadCrossTool()
{
   cd /Volumes/${VolumeBase}
   printf "${KBLU}Downloading crosstool-ng... to ${PWD}${KNRM}\n"
   CrossToolArchive=${CrossToolVersion}.tar.bz2
   if [ -f "$CrossToolArchive" ]; then
      printf "   -Using existing archive $CrossToolArchive${KNRM}\n"
   else
      CrossToolUrl="http://crosstool-ng.org/download/crosstool-ng/${CrossToolArchive}"
      curl -L -o ${CrossToolArchive} $CrossToolUrl
   fi

   if [ -d "${CrossToolSourceDir}" ]; then
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
   cd /Volumes/${VolumeBase}
   printf "${KBLU}Downloading crosstool-ng... to ${PWD}${KNRM}\n"
   if [ -x "/Volumes/${VolumeBase}/ctng/bin/ct-ng" ]; then
      printf "${KGRN}    - found existing ct-ng. Using it instead${KNRM}\n"
      return
   fi


   if [ -d "${CrossToolSourceDir}" ]; then 
      printf "   ${KRED}WARNING${KNRM} - ${CrossToolSourceDir} exists and will be used.\n"
      printf "   ${KRED}WARNING${KNRM} - Remove it to start fresh\n"
      return
   fi

   CrossToolUrl="https://github.com/crosstool-ng/crosstool-ng.git"
   git clone ${CrossToolUrl}  ${CrossToolSourceDir}

   # We need to creat the configure tool
   printf "${KBLU}Running  crosstool bootstrap... to ${PWD}${KNRM}\n"
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
    printf "${KBLU}Patching crosstool-ng...${KNRM}\n"
    if [ -x "/Volumes/${VolumeBase}/ctng/bin/ct-ng" ]; then
      printf "${KGRN}    - found existing ct-ng. Using it instead${KNRM}\n"
      return
    fi

    cd "/Volumes/${VolumeBase}/${CrossToolSourceDir}"
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
   printf "${KBLU}Configuring crosstool-ng... in ${PWD}${KNRM}\n"
   if [ -x "/Volumes/${VolumeBase}/ctng/bin/ct-ng" ]; then
      printf "${KGRN}    - found existing ct-ng. Using it instead${KNRM}\n"
      return
   fi
   cd "/Volumes/${VolumeBase}/${CrossToolSourceDir}"


   # It is strange that gettext is put in opt
   gettextDir=${ToolsLibPath}/gettext
   
   printf "${KBLU} Executing configure --with-libintl-prefix=$gettextDir ${KNRM}\n"
   printf "${KBLU} Executing configure  ${KNRM}\n"

   # export LDFLAGS
   # export CPPFLAGS

   # --with-libintl-prefix should have been enough, but it seems LDFLAGS and
   # CPPFLAGS is required too to fix libintl.h not found
   LDFLAGS="  -L${ToolsLibPath} -lintl " \
   CPPFLAGS=" -I${ToolsIncludePath} " \
    ./configure  --with-libintl-prefix=$gettextDir --prefix="/Volumes/${VolumeBase}/ctng"


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

   printf "${KBLU}Compiling crosstool-ng... in ${PWD}${KNRM}\n"

   make
   printf "${KBLU}Installing  crosstool-ng... in /Volumes/${VolumeBase}/ctng${KNRM}\n"
   make install
   printf "${KGRN}Compilation of ct-ng is Complete ${KNRM}\n"
}

function createToolchain()
{
   printf "${KBLU}Creating toolchain ${ToolchainName}...${KNRM}\n"


   cd ${CT_TOP_DIR}

   if [ ! -d "${ToolchainName}" ]; then
      mkdir $ToolchainName
   fi

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
      if [ "$OutputDir" == 'x-tools' ];then
         printf "${KBLU}.config file not being patched as -O was not specified${KNRM}\n"
      else
         patchConfigFileForOutputDir
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
        /Volumes/$Volume/$OutputDir/${CT_TARGET}

- Target options
    By default this script builds the configuration for arm-rpi3-eabihf as this is my focus; However, crosstool-ng can build so many different types of cross compilers.  If you are interested in them, check out the samples with:

      ct-ng list-samples

    You could also just go to the crosstool-ng-src/samples directory and peruse them all.

   At least using this script will help you try configurations more easily.
   

CONFIG_EOF

   # Give the user a chance to digest this
   sleep 5

   export PATH=${CT_TOP_DIR}/$OutputDir/$ToolchainName/bin:$ToolsBinPath:/Volumes/${VolumeBase}/ctng/bin:$PATH 

   # Use 'menuconfig' target for the fine tuning.

   # It seems ct-ng menuconfig dies without some kind of target
   export CT_TARGET="changeMe"
   ct-ng menuconfig

   printf "${KBLU}Once your finished tinkering with ct-ng menuconfig${KNRM}\n"
   printf "${KBLU}to contineu the build${KNRM}\n"
   printf "${KBLU}Execute:${KNRM}bash build.sh -b${KNRM}"
   if [ $Volume != 'CrossToolNG' ]; then
      printf "${KNRM} -V ${Volume}${KNRM}"
   fi
   if [ $OutputDir != 'x-tools' ]; then
      printf "${KNRM} -O ${OutputDir}${KNRM}"
   fi
   printf "${KBLU}     or${KNRM}\n"
   printf "PATH=$PATH${KNRM}\n"
   printf "cd ${CT_TOP_DIR}${KNRM}\n"
   printf "ct-ng build${KNRM}\n"
   

}

function buildToolchain()
{
   printf "${KBLU}Building toolchain...${KNRM}\n"

   cd ${CT_TOP_DIR}

   # Allow the source that crosstools-ng downloads to be saved
   printf "${KBLU}Checking for:${KNRM} ${PWD}/src ...${KNRM}"
   if [ ! -d "src" ]; then
      mkdir "src"
      printf "${KGRN}   -created${KNRM}\n"
   else
      printf "${KGRN}   -Done${KNRM}\n"
   fi

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
   export PATH=${CT_TOP_DIR}/$OutputDir/$ToolchainName/bin:$ToolsBinPath:/Volumes/${VolumeBase}/ctng/bin:$PATH 

   if [ "$1" == "list-steps" ]; then
      ct-ng "$1"
   else
      ct-ng "$1"
      printf "And if all went well, you are done! Go forth and compile.${KNRM}\n"
   fi
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

   printf "${KBLU}Checking for ${KNRM}zlib.h and libz.a ... ${KNRM}"
   if [ -f "${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/${ToolchainName}/include/zlib.h" ] && [ -f  "${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/${ToolchainName}/lib/libz.a" ]; then
      printf "${KGRN}found${KNRM}\n"
      return
   fi
   printf "${KYEL}not found${KNRM}\n"

   printf "${KBLU}Checking for ${KNRM}${CT_TOP_DIR}/src/zlib-1.2.11 ...${KNRM}"
   if [ -d "${CT_TOP_DIR}/src/zlib-1.2.11" ]; then
      printf "${KGRN}found${KNRM}\n"
      printf "${KNRM}Using existing zlib source${KNRM}\n"
   else
      printf "${KYEL}not found${KNRM}\n"
      cd "${CT_TOP_DIR}/src/"
      printf "${KBLU}Checking for saved ${KNRM}${zlibFile} ... ${KNRM}"
      if [ -f "${TarBallSourcesPath}/${zlibFile}" ]; then
         printf "${KGRN}found${KNRM}\n"
      else
         printf "${KYEL}not found${KNRM}\n"
         printf "${KBLU}Downloading ${KNRM}${zlibFile} ... ${KNRM}"
         curl -Lsf "${zlibURL}" -o "${TarBallSourcesPath}/${zlibFile}"
         printf "${KGRN}done${KNRM}\n"
      fi
      printf "${KBLU}Copying ${zlibFile} to working directory ${KNRM}"
      cp "${TarBallSourcesPath}/${zlibFile}" "${CT_TOP_DIR}/src/."
      printf "${KGRN}done${KNRM}\n"
      printf "${KBLU}Decompressing ${KNRM}${zlibFile} ... ${KNRM}"
      cd "${CT_TOP_DIR}/src/"
      tar -xzf "${zlibFile}"
      printf "${KGRN}done${KNRM}\n"
   fi

    cd "${CT_TOP_DIR}/src/zlib-1.2.11"
    CHOST=${ToolchainName} ./configure \
          --prefix=${CT_TOP_DIR}/${OutputDir}/${ToolchainName} \
          --static \
          --libdir=${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/${ToolchainName}/lib \
          --includedir=${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/${ToolchainName}/include

    make
    make install
}

function testBuild
{
   gpp="${CT_TOP_DIR}/$OutputDir/$ToolchainName/bin/${ToolchainName}-g++"
   if [ ! -f "${gpp}" ]; then
      printf "${KRED}No executable compiler found. ${KNRM}\n"
      printf "${KRED}${gpp}${KNRM}\n"
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

   PATH=${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/bin:$PATH

   ${ToolchainName}-g++ -fno-exceptions /tmp/HelloWorld.cpp -o /tmp/HelloWorld
   rc=$?

}

function downloadRaspbianKernel
{
RaspbianURL="https://github.com/raspberrypi/linux.git"

   cd "${CT_TOP_DIR}"
   printf "${KBLU}Downloading Raspbian Kernel latest... to ${KNRM}${PWD}${KNRM}\n"

   if [ -d "${RaspbianSrcDir}" ]; then
      printf "${KRED}WARNING ${KNRM}Path already exists ${RaspbianSrcDir}${KNRM}\n"
      printf "        A fetch will be done instead to keep tree up to date{KNRM}\n"
      printf "\n"
      cd "${RaspbianSrcDir}/linux"
      git fetch
    
   else
      printf "${KBLU}Creating ${KNRM}${RaspbianSrcDir} ... ${KNRM}"
      mkdir "${RaspbianSrcDir}"
      printf "${KGRN}done${KNRM}\n"

      cd "${RaspbianSrcDir}"
      git clone --depth=1 ${RaspbianURL}
   fi
}
function downloadElfHeaderForOSX
{
   ElfHeaderFile="/usr/local/include/elf.h"
   printf "${KBLU}Checking for ${KNRM}${ElfHeaderFile}${KNRM}\n"
   if [ -f "${ElfHeaderFile}" ]; then
      printf "${KGRN}found${KNRM}\n"
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
      #Placing it here too is a flag for us to remember to remove it from /usr/local
      cp "${ElfHeaderFile}" "${CT_TOP_DIR}/${RaspbianSrcDir}/linux/elf.h"
   fi
}

function cleanupElfHeaderForOSX
{
   ElfHeaderFile="/usr/local/include/elf.h"
   printf "${KBLU}Checking for my ${KNRM}${ElfHeaderFile}${KNRM} ..."
   if [ -f "${ElfHeaderFile}" ]; then
      printf "${KGRN}found${KNRM}\n"
      if [ -f "${CT_TOP_DIR}/${RaspbianSrcDir}/linux/elf.h" ]; then
         printf "${KGRN}Removing ${ElfHeaderFile}${KNRM} ... "
         rm "${ElfHeaderFile}"
         rm "${CT_TOP_DIR}/${RaspbianSrcDir}/linux/elf.h"
         printf "${KGRN}done${KNRM}\n"
      else
         printf "${KRED}Warning. There is a ${KNRM}${ElfHeaderFile}\n"
         printf "${KRED}But it was not put there by this tool, I believe${KNRM}"
         sleep 4
      fi
   else
      printf "${KGRN}Not found - OK${KNRM}\n"

   fi
}

function configureRaspbianKernel
{
   cd "${CT_TOP_DIR}/${RaspbianSrcDir}/linux"
   printf "${KBLU}Configuring Raspbian Kernel in ${PWD}${KNRM}\n"

   export PATH=${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/bin:$ToolsBinPath:/Volumes/${VolumeBase}/ctng/bin:$PATH 
   echo $PATH


   # for bzImage
   export KERNEL=kernel7

   export CROSS_PREFIX=${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/bin/${ToolchainName}-

   printf "${KBLU}Make bcm2709_defconfig in ${PWD}${KNRM}\n"
   export LFS_CFLAGS=-I${CT_TOP_DIR}/$OutputDir/$ToolchainName/$ToolchainName/include
   export LFS_LDFLAGS=-I${CT_TOP_DIR}/$OutputDir/$ToolchainName/$ToolchainName/lib
   # make ARCH=arm O=${CT_TOP_DIR}/build/kernel mrproper 
    make ARCH=arm CONFIG_CROSS_COMPILE=${ToolchainName}- CROSS_COMPILE=${ToolchainName}- --include-dir=${CT_TOP_DIR}/$OutputDir/$ToolchainName/$ToolchainName/include  bcm2709_defconfig

   make nconfig


   printf "${KBLU}Make zImage in ${PWD}${KNRM}\n"
   printf "ls of ${CT_TOP_DIR}/$OutputDir/$ToolchainName/$ToolchainName/include\n"
   ls ${CT_TOP_DIR}/$OutputDir/$ToolchainName/$ToolchainName/include
   printf "running: make  CROSS_COMPILE=${ToolchainName}- CC=${ToolchainName}-gcc --include-dir=${CT_TOP_DIR}/$OutputDir/$ToolchainName/$ToolchainName/include -I ${CT_TOP_DIR}/$OutputDir/$ToolchainName/$ToolchainName/include zImage\n"
export KBUILD_VERBOSE=1

   KBUILD_CFLAGS=-I${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/include \
   KBUILD_LDLAGS=-L${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/lib \
   HOSTCC=${ToolchainName}-gcc \
   ARCH=arm \
      make  -j4 CROSS_COMPILE=${ToolchainName}- \
        CC=${ToolchainName}-gcc \
        --include-dir=${CT_TOP_DIR}/$OutputDir/$ToolchainName/$ToolchainName/include \
        zImage modules dtbs

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

   # make O=${CT_TOP_DIR}/build/kernel nconfig
   # make O=${CT_TOP_DIR}/build/kernel


}

# Define this once and you save yourself some trouble
# Omit the : for the b as we will check for optional option
OPTSTRING='h?P?c:I:V:O:f:btT:L?'

# Getopt #1 - To enforce order
while getopts "$OPTSTRING" opt; do
   case $opt in
      c)
          if  [ $OPTARG == "raspbian" ] || [ $OPTARG == "Raspbian" ]; then
             CleanRaspbianOpt="y";
          fi
          ;;
          #####################
      I)
          ImageName=$OPTARG
          ImageNameExt=${ImageName}.sparseimage   # This cannot be changed
          ;;
          #####################
      V)
          Volume=$OPTARG

          # Do not change the name of VolumeBase. It would
          # defeat its purpose of being solid and separate

          # Change all variables that require this
          BrewHome="/Volumes/${VolumeBase}/brew"
          export BREW_PREFIX=$BrewHome
          CT_TOP_DIR="/Volumes/${Volume}"
          ;;
      O)
          OutputDir=$OPTARG
          ;;
          #####################
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
             BuildToolchainOpt="y"
          fi

          ;;
          #####################
       T)
          ToolchainName=$OPTARG
          CrossToolNGConfigFile="${ToolchainName}.config"
          ;;
          #####################
       L)
          LoggingOpt="full"
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
             if  [ $BuildRaspbianOpt == "n" ]; then
                exit 0
             fi
             # so not to do it twicw
             CleanRaspbianOpt="n"
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
                buildToolchain $nextOpt
             fi
          else
             # minus gcc alone is build the cross compiler
             buildToolchain "build"
          fi

          # Check to continue and build Raspbian
          if [ $BuildRaspbianOpt == "n" ]; then
             exit 0
          fi

          if  [ $CleanRaspbianOpt == "y" ]; then
             raspbianClean
          fi

          printf "${KYEL}Checking for cross compiler first ... ${KNRM}"
          testBuild   # testBuild sets rc
          if [ ${rc} == '0' ]; then
             printf "${KGRN}  OK ${KNRM}\n"
          else
             printf "${KRED}  failed ${KNRM}\n"
             exit -1
          fi
          BuildRaspbianOpt=y

          downloadAndBuildzlib

          downloadRaspbianKernel
          downloadElfHeaderForOSX
          configureRaspbianKernel
          cleanupElfHeaderForOSX

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
      T)
          # Done in first getopt for proper order
          ;;
          #####################
      P)
          export PATH=${CT_TOP_DIR}/${OutputDir}/${ToolchainName}/bin:$ToolsBinPath:/Volumes/${VolumeBase}/ctng/bin:$PATH
  
          printf "${KNRM}PATH=${PATH}${KNRM}\n"
          printf "./configure  ARCH=arm  CROSS_COMPILE=${CT_TOP_DIR}/$OutputDir/${ToolchainName}/bin/${ToolchainName}- --prefix=${CT_TOP_DIR}/${OutputDir}/${ToolchainName}\n"
    printf "make ARCH=arm --include-dir=${CT_TOP_DIR}/$OutputDir/${ToolchainName}/${ToolchainName}/include CROSS_COMPILE=${CT_TOP_DIR}/$OutputDir/${ToolchainName}/bin/${ToolchainName}-\n"
          exit 0
          ;;
          #####################
       L)
          # Done in first getopt for proper order
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

# We will put Brew and ct-ng here too so they dont need rebuilding
# all the time
createCaseSensitiveVolumeBase

# Create a directory to save/reuse tarballs
createTarBallSourcesDir

# Create the case sensitive volume first.
createCaseSensitiveVolume

# Start with downloading missing OSX tools to our own
# tools directory 
buildMissingOSXTools

# The 1.23  archive is busted and does not contain CT_Mirror, until
# it is fixed, use git Latest
if [ ${downloadCrosstoolLatestOpt} == 'y' ]; then
   downloadCrossTool_LATEST
else
   downloadCrossTool
fi

printf "zarf - done"

patchCrosstool
buildCrosstool
createToolchain


exit 0
