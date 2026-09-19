#----------------------------------------------------------------
# Generated CMake target import file for configuration "RelWithDebInfo".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "ada::ada" for configuration "RelWithDebInfo"
set_property(TARGET ada::ada APPEND PROPERTY IMPORTED_CONFIGURATIONS RELWITHDEBINFO)
set_target_properties(ada::ada PROPERTIES
  IMPORTED_LOCATION_RELWITHDEBINFO "${_IMPORT_PREFIX}/lib64/libada.so.3.4.4"
  IMPORTED_SONAME_RELWITHDEBINFO "libada.so.3"
  )

list(APPEND _cmake_import_check_targets ada::ada )
list(APPEND _cmake_import_check_files_for_ada::ada "${_IMPORT_PREFIX}/lib64/libada.so.3.4.4" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
