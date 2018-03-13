# crosstool-arm-osx
Raspberry Pi Cross Compiler Script for OSX - Updated for crosstools-ng.1.23.0
# Raspberry Pi Cross Compiler Script for OSX - Updated for crosstools-ng.1.23.0

Note: The default is now crosstool-ng latest that will be downloaded
      automatially from  GitHub because I believe there is a problems
      with the 1.23.0 tarball

**build.sh** Installs a gcc cross compiler for compiling code for raspberry pi on OSX.
This script is based on several scripts and forum posts I've found around 
the web, the most significant being: 

Table of Contents
----------------------
* [**About the build.sh Script**](#about-the-build-script)
* [**How the build.sh Script Works**](#how-the-build-script-works)
* [**Features**](#features)
* [**Installation and Execution**](#installation_and_execution)
* [**Smoke Test**](#smoke_test)
* [**Inspiration and special thanks**](#inspiration-and-special-thanks)
* [**Refrence Materials**](#reference-materials)
* [**License**](#license)


About the build Script
---------------------------
The script downloads, compiles and installs all necessary software. The only prerequisite I know of is to have the latest version of XCode and have the command line tools installed. It works for me without modification on OSX 10.13.3 with XCode 9.2


How the build Script Works
---------------------------------
The script starts by creating a sparse HFSX (case sensitive) filesystem on which to perform the build. The filesystem image is a file that lives in the same directory as the script. 

The script will then install some HomeBrew packages on the sparse volume. I currently use MacPorts. At some time during my attempts to setup this cross compiler it interfered with the install, and as such HomeBrew is placed on the same sparse image as the compiler.  In this fashion, all tools are kept together in a completely controlled environment.

The script then downlaods and installs crosstool-ng. It helps to be a little familiar with the tool. See http://crosstool-ng.org/ 

Once crosstool is installed, it is configured with the arm-unknown-linux-gnueabi.config file by copying that file to the approproite location where crosstool will pick it up. The script then automatically fires up the crosstool config menu (menuconfig) so you can make changes. The menuconfig program is basically a front end for the config file. You can either make changes or just exit. You can also just edit the config file before running the script and remove call to:

       PATH=/Volumes/${ImageName}:$PATH ../${CrossToolVersion}/ct-ng menuconfig

Once that is all done, we run the build. If all goes well, you will then have a toolchain for comiling arm code on osx. The default install is in /Volumes/CrossToolNG/install/arm-unknown-linux-gnueabi

Features
-----------
   - The script can be restarted at any time and it will continue where it left off

Installation and Execution
--------------------------------
To use: open and read the build.sh script to suite your needs. Then run the script from within the folder it is contained. It will need to access the arm-unknown-linux-gnueabi.config file. 

     bash build.sh 

At any time, you can re-run the script and it will try to continue where you left off, or you can run: bash build.sh realClean to start over.  For further options try:

    bash build.sh -help

License
-----------
See [LICENSE](LICENSE)


Smoke Test
---------------
As a smoke test you can create a simple HelloWorld program and compile it. That would be something like:

```bash
cat <<EOF >> HelloWorld.cpp
#include <iostream>
using namespace std;

int main ()
{
  cout << "Hello World!";
  return 0;
}
EOF

PATH=/Volumes/CrossToolNG/install/arm-unknown-linux-gnueabi/bin:$PATH arm-linux-gnueabihf-g++ HelloWorld.cpp -o HelloWorld
```

Go forth and compile.


Inspiration and special thanks
------------------------------
Based on:<br>
* [crosstool-arm-osx]https://github.com/asymptotik/crosstool-arm-osx<<BR>
  
So much was changed and the previous version was from 5 years ago, that it deserved its own repository.  I do thank Rick Boykin very much though.  It was a great place to start.
  
Reference Materials
------------------------
* [crosstool-arm-osx]http://github.com/asymptotik/crosstool-arm-osx<BR>
* [osx-crosstool-ng-cmd]http://okertanov.github.com/2012/12/24/osx-crosstool-ng<BR>
* [MacOS-X]http://crosstool-ng.org/hg/crosstool-ng/file/715b711da3ab/docs/MacOS-X.txt<BR>
* [Toolchain_installation_on_OS_X]http://gnuarmeclipse.livius.net/wiki/Toolchain_installation_on_OS_Xt<BR>
* [RPI_Kernel_compilation]http://elinux.org/RPi_Kernel_Compilationt<BR>



<!---
Link References
-->



[about-the-build-script]:https://github.com/ztalbot2000/crosstool-arm-osx/#about-the-build-script
[how-the-build-script-works]:https://github.com/ztalbot2000/crosstool-arm-osx/#how-the-build-script-works
[features]:https://github.com/ztalbot2000/crosstool-arm-osx/#features
[smoke-test]:https://github.com/ztalbot2000/crosstool-arm-osx/#smoke-test
[reference-material]:https://github.com/ztalbot2000/crosstool-arm-osx/#reference-material
[license]:https://github.com/ztalbot2000/crosstool-arm-osx/#license


