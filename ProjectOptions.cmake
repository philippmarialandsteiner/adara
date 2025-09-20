include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


include(CheckCXXSourceCompiles)


macro(adara_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)

    message(STATUS "Sanity checking UndefinedBehaviorSanitizer, it should be supported on this platform")
    set(TEST_PROGRAM "int main() { return 0; }")

    # Check if UndefinedBehaviorSanitizer works at link time
    set(CMAKE_REQUIRED_FLAGS "-fsanitize=undefined")
    set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=undefined")
    check_cxx_source_compiles("${TEST_PROGRAM}" HAS_UBSAN_LINK_SUPPORT)

    if(HAS_UBSAN_LINK_SUPPORT)
      message(STATUS "UndefinedBehaviorSanitizer is supported at both compile and link time.")
      set(SUPPORTS_UBSAN ON)
    else()
      message(WARNING "UndefinedBehaviorSanitizer is NOT supported at link time.")
      set(SUPPORTS_UBSAN OFF)
    endif()
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    if (NOT WIN32)
      message(STATUS "Sanity checking AddressSanitizer, it should be supported on this platform")
      set(TEST_PROGRAM "int main() { return 0; }")

      # Check if AddressSanitizer works at link time
      set(CMAKE_REQUIRED_FLAGS "-fsanitize=address")
      set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=address")
      check_cxx_source_compiles("${TEST_PROGRAM}" HAS_ASAN_LINK_SUPPORT)

      if(HAS_ASAN_LINK_SUPPORT)
        message(STATUS "AddressSanitizer is supported at both compile and link time.")
        set(SUPPORTS_ASAN ON)
      else()
        message(WARNING "AddressSanitizer is NOT supported at link time.")
        set(SUPPORTS_ASAN OFF)
      endif()
    else()
      set(SUPPORTS_ASAN ON)
    endif()
  endif()
endmacro()

macro(adara_setup_options)
  option(adara_ENABLE_HARDENING "Enable hardening" ON)
  option(adara_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    adara_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    adara_ENABLE_HARDENING
    OFF)

  adara_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR adara_PACKAGING_MAINTAINER_MODE)
    option(adara_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(adara_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(adara_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(adara_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(adara_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(adara_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(adara_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(adara_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(adara_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(adara_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(adara_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(adara_ENABLE_PCH "Enable precompiled headers" OFF)
    option(adara_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(adara_ENABLE_IPO "Enable IPO/LTO" ON)
    option(adara_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(adara_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(adara_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(adara_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(adara_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(adara_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(adara_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(adara_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(adara_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(adara_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(adara_ENABLE_PCH "Enable precompiled headers" OFF)
    option(adara_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      adara_ENABLE_IPO
      adara_WARNINGS_AS_ERRORS
      adara_ENABLE_USER_LINKER
      adara_ENABLE_SANITIZER_ADDRESS
      adara_ENABLE_SANITIZER_LEAK
      adara_ENABLE_SANITIZER_UNDEFINED
      adara_ENABLE_SANITIZER_THREAD
      adara_ENABLE_SANITIZER_MEMORY
      adara_ENABLE_UNITY_BUILD
      adara_ENABLE_CLANG_TIDY
      adara_ENABLE_CPPCHECK
      adara_ENABLE_COVERAGE
      adara_ENABLE_PCH
      adara_ENABLE_CACHE)
  endif()

  adara_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (adara_ENABLE_SANITIZER_ADDRESS OR adara_ENABLE_SANITIZER_THREAD OR adara_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(adara_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(adara_global_options)
  if(adara_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    adara_enable_ipo()
  endif()

  adara_supports_sanitizers()

  if(adara_ENABLE_HARDENING AND adara_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR adara_ENABLE_SANITIZER_UNDEFINED
       OR adara_ENABLE_SANITIZER_ADDRESS
       OR adara_ENABLE_SANITIZER_THREAD
       OR adara_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${adara_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${adara_ENABLE_SANITIZER_UNDEFINED}")
    adara_enable_hardening(adara_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(adara_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(adara_warnings INTERFACE)
  add_library(adara_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  adara_set_project_warnings(
    adara_warnings
    ${adara_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(adara_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    adara_configure_linker(adara_options)
  endif()

  include(cmake/Sanitizers.cmake)
  adara_enable_sanitizers(
    adara_options
    ${adara_ENABLE_SANITIZER_ADDRESS}
    ${adara_ENABLE_SANITIZER_LEAK}
    ${adara_ENABLE_SANITIZER_UNDEFINED}
    ${adara_ENABLE_SANITIZER_THREAD}
    ${adara_ENABLE_SANITIZER_MEMORY})

  set_target_properties(adara_options PROPERTIES UNITY_BUILD ${adara_ENABLE_UNITY_BUILD})

  if(adara_ENABLE_PCH)
    target_precompile_headers(
      adara_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(adara_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    adara_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(adara_ENABLE_CLANG_TIDY)
    adara_enable_clang_tidy(adara_options ${adara_WARNINGS_AS_ERRORS})
  endif()

  if(adara_ENABLE_CPPCHECK)
    adara_enable_cppcheck(${adara_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(adara_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    adara_enable_coverage(adara_options)
  endif()

  if(adara_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(adara_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(adara_ENABLE_HARDENING AND NOT adara_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR adara_ENABLE_SANITIZER_UNDEFINED
       OR adara_ENABLE_SANITIZER_ADDRESS
       OR adara_ENABLE_SANITIZER_THREAD
       OR adara_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    adara_enable_hardening(adara_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
