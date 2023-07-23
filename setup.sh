#!/bin/bash

if [ $# -lt 2 ]; then
    echo "setup.sh <built prefix> <wine prefix>"
    return
fi

export HODLL=fexcore.dll
export WINEPREFIX=$2
export PATH="$1/bin:$PATH"

if [ $# -gt 2 ]; then
wineserver -k
WINDIR=$WINEPREFIX/drive_c/windows/
mkdir -p $WINDIR/system32
cp $1/dlls/aarch64-w64-mingw32/bin/libhofex.dll  $WINDIR/system32
wineboot -u
cp $1/dlls/aarch64-w64-mingw32/bin/* $WINDIR/system32
cp $1/dlls/i686-w64-mingw32/bin/* $WINDIR/syswow64
fi

export TU_DEBUG=mmap_32
export WINEDLLOVERRIDES="d3d9=n,d3d11=n,d3d10core=n,dxgi=n,opengl32=n"
wineboot

