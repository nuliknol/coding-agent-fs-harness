cmake_minimum_required(VERSION 3.16)
project(context_index_fixture C CXX)

add_library(context_calc STATIC src/calc.c)
target_include_directories(context_calc PUBLIC include)

add_executable(context_calc_test tests/test_calc.c)
target_link_libraries(context_calc_test PRIVATE context_calc)

enable_testing()
add_test(NAME context_calc_test COMMAND context_calc_test)

add_library(context_calc_cpp STATIC src/calc.cpp)
target_include_directories(context_calc_cpp PUBLIC include)
target_compile_features(context_calc_cpp PUBLIC cxx_std_17)

add_executable(context_calc_cpp_test tests/test_calc_cpp.cpp)
target_link_libraries(context_calc_cpp_test PRIVATE context_calc_cpp)
add_test(NAME context_calc_cpp_test COMMAND context_calc_cpp_test)

set(CONTEXT_NESTED_BASE 10)
set(CONTEXT_GENERATED_OFFSET 7)
configure_file(
    generated/context_generated.hpp.in
    generated/context_generated.hpp
    @ONLY
)
configure_file(
    generated/context_nested.hpp.in
    generated/context_nested.hpp
    @ONLY
)
add_library(context_generated STATIC src/generated.cpp)
target_include_directories(context_generated PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")

# A portable HIP-containing fixture: the .hip translation unit is valid C++ so
# non-ROCm CI can index it, while the provider report must still identify the
# absence of HIP-specific semantic relationships rather than claiming them.
set_source_files_properties(src/kernel.hip PROPERTIES LANGUAGE CXX COMPILE_FLAGS "-x c++")
add_library(context_hip STATIC src/kernel.hip)
