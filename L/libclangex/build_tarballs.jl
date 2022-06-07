# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg
using Base.BinaryPlatforms

const YGGDRASIL_DIR = "../.."
include(joinpath(YGGDRASIL_DIR, "fancy_toys.jl"))
include(joinpath(YGGDRASIL_DIR, "platforms", "llvm.jl"))

name = "libclangex"
version = v"0.1.6"

llvm_versions = [#=v"11.0.1",=# v"12.0.1", v"13.0.1", v"14.0.2"]


# Collection of sources required to complete build
sources = [
    GitSource("https://github.com/Gnimuc/libclangex.git", "527f22f606f43682c89ef76746d5d9652b2db1dc")
]

# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir
cd libclangex/
mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=$prefix -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TARGET_TOOLCHAIN} \
     -DLLVM_DIR=$prefix \
     -DCLANG_DIR=$prefix \
     -DLLVM_ASSERT_BUILD=false \
     -DCMAKE_BUILD_TYPE=Release \
     -DCMAKE_EXPORT_COMPILE_COMMANDS=true
make -j${nproc}
make install
install_license ../COPYRIGHT ../LICENSE-APACHE ../LICENSE-MIT
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = expand_cxxstring_abis(supported_platforms(; experimental=true))

augment_platform_block = """
    using Base.BinaryPlatforms

    $(LLVM.augment)

    function augment_platform!(platform::Platform)
        augment_llvm!(platform)
    end"""

# determine exactly which tarballs we should build
builds = []
for llvm_version in llvm_versions, llvm_assertions in (false, true)
    # Dependencies that must be installed before this package can be built
    llvm_name = llvm_assertions ? "LLVM_full_assert_jll" : "LLVM_full_jll"
    dependencies = [
        BuildDependency(PackageSpec(name=llvm_name, version=llvm_version))
    ]

    # The products that we will ensure are always built
    products = Product[
        # Life is horrible and we can't add Clang_jll as a dependency, thus
        # loading the library will always fail. We can fix this in the consumer
        # so don't dlopen
        LibraryProduct("libclangex", :libclangex, dont_dlopen=true),
    ]
    
    for platform in platforms
        augmented_platform = deepcopy(platform)
        augmented_platform[LLVM.platform_name] = LLVM.platform(llvm_version, llvm_assertions)

        should_build_platform(triplet(augmented_platform)) || continue
        push!(builds, (;
            dependencies, products,
            platforms=[augmented_platform],
        ))
    end
end

# don't allow `build_tarballs` to override platform selection based on ARGS.
# we handle that ourselves by calling `should_build_platform`
non_platform_ARGS = filter(arg -> startswith(arg, "--"), ARGS)

# `--register` should only be passed to the latest `build_tarballs` invocation
non_reg_ARGS = filter(arg -> arg != "--register", non_platform_ARGS)

for (i,build) in enumerate(builds)
    build_tarballs(i == lastindex(builds) ? non_platform_ARGS : non_reg_ARGS,
                   name, version, sources, script,
                   build.platforms, build.products, build.dependencies;
                   preferred_gcc_version=v"8", julia_compat="1.6",
                   augment_platform_block)
end

# bump
