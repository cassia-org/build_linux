cmake_minimum_required(VERSION 3.10.2)

project(proj LANGUAGES C CXX ASM VERSION 1.0)

include(ExternalProject)

set(OUTPUT_PREFIX_DIR ${CMAKE_BINARY_DIR}/prefix)
set(MINGW_SYSROOT_PATH "" CACHE PATH "Path to a mingw compiler sysroot built for the host")
set(DLL_BUILD_ARCHITECTURES "" CACHE STRING "List of DLL architectures to build")

set(MINGW_DLL_BUILD_TRIPLES "")
string(REPLACE "," ";" DLL_BUILD_ARCHITECTURES_LIST ${DLL_BUILD_ARCHITECTURES})
foreach(DLL_ARCH IN LISTS DLL_BUILD_ARCHITECTURES_LIST)
  if (${DLL_ARCH} STREQUAL "aarch64")
    list(APPEND MINGW_DLL_BUILD_TRIPLES "aarch64-w64-mingw32")
  elseif(${DLL_ARCH} STREQUAL "x86_64")
    list(APPEND MINGW_DLL_BUILD_TRIPLES "x86_64-w64-mingw32")
  elseif(${DLL_ARCH} STREQUAL "i386")
    list(APPEND MINGW_DLL_BUILD_TRIPLES "i686-w64-mingw32")
  else()
    message(FATAL_ERROR "Unsupported DLL build architecture")
  endif()
endforeach()

set(COMPILER_SETTINGS
  # Autotools strips target from CFLAGS so need to use CC instead
  "CXX=${CMAKE_CXX_COMPILER_LAUNCHER} ${CMAKE_CXX_COMPILER}"
  "AS=${CMAKE_ASM_COMPILER}"
  "CPP=${CMAKE_C_COMPILER_LAUNCHER} ${CMAKE_C_COMPILER} -E"
  "CC=${CMAKE_C_COMPILER_LAUNCHER} ${CMAKE_C_COMPILER}"
  "AR=${CMAKE_AR}"
  "RANLIB=${CMAKE_RANLIB}"
  "NM=${CMAKE_NM}"
  "STRIP=${CMAKE_STRIP}"

  "CFLAGS=${CMAKE_C_FLAGS} ${CMAKE_C_FLAGS_${BUILD_TYPE_UC}}"
  "ASMFLAGS=${CMAKE_ASM_FLAGS} ${CMAKE_ASM_FLAGS_${BUILD_TYPE_UC}}"
  "CPPFLAGS=${CMAKE_C_FLAGS} ${CMAKE_C_FLAGS_${BUILD_TYPE_UC}}"
  "CXXFLAGS=${CMAKE_CXX_FLAGS} ${CMAKE_CXX_FLAGS_${BUILD_TYPE_UC}}"
  "LDFLAGS=${CMAKE_SHARED_LINKER_FLAGS} ${CMAKE_SHARED_LINKER_FLAGS_${BUILD_TYPE_UC}}"
  "x86_64_CC=${MINGW_SYSROOT_PATH}/bin/clang"
)

# Executes the appended program with MinGW compilers added to path
set(MINGW_COMMAND "${CMAKE_COMMAND}" -E env "PATH=${MINGW_SYSROOT_PATH}/bin:$ENV{PATH}")

function(add_autotools_project name)
  cmake_parse_arguments(PARSE_ARGV 1 ARG "BUILD_ALWAYS" "MAKE_TARGET;INSTALL_TARGET" "PRE_CONFIGURE_COMMAND;DEPENDS;CONFIGURE_FLAGS")

  if (NOT DEFINED ARG_PRE_CONFIGURE_COMMAND)
    set(ARG_PRE_CONFIGURE_COMMAND "true")
  endif()
  if (NOT DEFINED ARG_INSTALL_TARGET)
    set(ARG_INSTALL_TARGET "install")
  endif()

  ExternalProject_Add(${name}
    INSTALL_DIR         ${OUTPUT_PREFIX_DIR}
    SOURCE_DIR          ${CMAKE_CURRENT_SOURCE_DIR}/${name}
    DOWNLOAD_COMMAND    COMMAND cd <SOURCE_DIR> && ${ARG_PRE_CONFIGURE_COMMAND}
    CONFIGURE_COMMAND   ${MINGW_COMMAND} <SOURCE_DIR>/configure ${COMPILER_SETTINGS} --prefix=<INSTALL_DIR> --host=${CMAKE_C_COMPILER_TARGET} ${ARG_CONFIGURE_FLAGS}
    BUILD_COMMAND       ${MINGW_COMMAND} make -j ${ARG_MAKE_TARGET}
    INSTALL_COMMAND     ${MINGW_COMMAND} make prefix=<INSTALL_DIR> -j ${ARG_INSTALL_TARGET}
    LOG_CONFIGURE       TRUE
    LOG_BUILD           TRUE
    LOG_INSTALL         TRUE
    BUILD_ALWAYS        ${ARG_BUILD_ALWAYS}
    DEPENDS             ${ARG_DEPENDS}
  )
endfunction()

function(add_dll_meson_project_intl name triple cross_file prefix build_always configure_flags)
  if (${configure_flags} STREQUAL " ")
    unset(configure_flags)
  endif()
  ExternalProject_Add(${name}_${triple}
    INSTALL_DIR         ${prefix}
    SOURCE_DIR          ${CMAKE_CURRENT_SOURCE_DIR}/${name}
    CONFIGURE_COMMAND   ${MINGW_COMMAND} meson setup --strip --buildtype release ${configure_flags} --cross-file=${cross_file} --prefix=<INSTALL_DIR> . <SOURCE_DIR>
    BUILD_COMMAND       ${MINGW_COMMAND} meson compile
    INSTALL_COMMAND     ${MINGW_COMMAND} meson install --no-rebuild
    LOG_CONFIGURE       TRUE
    LOG_BUILD           TRUE
    LOG_INSTALL         TRUE
    BUILD_ALWAYS        ${build_always}
  )

endfunction()

function(add_dll_meson_project name)
  cmake_parse_arguments(PARSE_ARGV 1 ARG "BUILD_ALWAYS" "" "CONFIGURE_FLAGS")
  if (NOT DEFINED ARG_BUILD_ALWAYS)
    set(ARG_BUILD_ALWAYS FALSE)
  endif()

  if (NOT DEFINED ARG_CONFIGURE_FLAGS)
    set(ARG_CONFIGURE_FLAGS " ")
  endif()

  foreach(DLL_TRIPLE IN LISTS MINGW_DLL_BUILD_TRIPLES)
    set(DLL_TRIPLE_PREFIX "${OUTPUT_PREFIX_DIR}/dlls/${DLL_TRIPLE}")
    set(DLL_TRIPLE_CROSS_FILE "${CMAKE_CURRENT_SOURCE_DIR}/meson_cross_files/${DLL_TRIPLE}.txt")
    add_dll_meson_project_intl(${name}
                               ${DLL_TRIPLE}
                               ${DLL_TRIPLE_CROSS_FILE}
                               ${DLL_TRIPLE_PREFIX}
                               ${ARG_BUILD_ALWAYS}
                               ${ARG_CONFIGURE_FLAGS})
  endforeach()
endfunction()
      

add_autotools_project(wine
                      PRE_CONFIGURE_COMMAND autoreconf -i
                      CONFIGURE_FLAGS --disable-win16 --disable-tests --with-alsa --with-udev --without-usb --without-v4l2 --with-x --with-vulkan --with-freetype --with-mingw --with-pthread --with-gstreamer --enable-archs=${DLL_BUILD_ARCHITECTURES}
                      BUILD_ALWAYS)
add_dll_meson_project(mesa
                      CONFIGURE_FLAGS -Dgallium-drivers=zink
                      BUILD_ALWAYS)
add_dll_meson_project(dxvk
                      BUILD_ALWAYS)

if ("aarch64-w64-mingw32" IN_LIST MINGW_DLL_BUILD_TRIPLES)
  set(DLL_TRIPLE "aarch64-w64-mingw32")
  set(DLL_TRIPLE_PREFIX "${OUTPUT_PREFIX_DIR}/dlls/${DLL_TRIPLE}")

  ExternalProject_Add(FEX_${DLL_TRIPLE}
    INSTALL_DIR         ${DLL_TRIPLE_PREFIX}
    SOURCE_DIR          ${CMAKE_CURRENT_SOURCE_DIR}/FEX
    CMAKE_ARGS          -DCMAKE_TOOLCHAIN_FILE=${CMAKE_CURRENT_SOURCE_DIR}/FEX/toolchain_mingw.cmake -DENABLE_JEMALLOC=0 -DENABLE_JEMALLOC_GLIBC_ALLOC=0 -DMINGW_TRIPLE=${DLL_TRIPLE} -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_TESTS=False -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
    CMAKE_COMMAND       ${MINGW_COMMAND} cmake
    LOG_CONFIGURE       TRUE
    LOG_BUILD           TRUE
    LOG_INSTALL         TRUE
    BUILD_ALWAYS        TRUE
  )
endif()
