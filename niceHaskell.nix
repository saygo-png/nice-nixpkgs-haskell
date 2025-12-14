{
  pkgs,
  lib,
}: {
  # Flags from the Nixpkgs haskell.lib API: https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/haskell-modules/lib/default.nix
  # Some are excluded as they are stupid. For example there is `doCheck` AND `dontCheck`. Or flags that simply turn on other flags.
  mkFlags = {
    # Allow a shell environment to be requested
    returnShellEnv ? false,
    #
    # Generate and apply completions from the optparse-applicative library. Done with a postInstall hook.
    generateOptparseApplicativeCompletions ? false,
    executableNamesToShellComplete ? [], # The executable names to generate completions for.
    #
    # Escape the version bounds from the cabal file. You may want to avoid this function.
    doJailbreak ? false,
    #
    # Enables dependency checking, compilation and execution
    # of test suites listed in the package description file.
    doCheck ? false,
    #
    # Create a source distribution tarball like those found on hackage, instead of building the package.
    sdistTarball ? false,
    #
    # Build a source distribution tarball instead of using the source files
    # directly. The effect is that the package is built as if it were published
    # on hackage. This can be used as a test for the source distribution,
    # assuming the build fails when packaging mistakes are in the cabal file.
    buildFromSdist ? true,
    #
    #
    # Turn all warnings into errors (-Werror)
    failOnAllWarnings ? false,
    enableDeadCodeElimination ? true,
    #
    # Disabled GHC code optimizations make build/tolling/dev loops faster.
    # Works also for Haskel IDE Engine and GHCID.
    # Enable optimizations for production use and/or to pass benchmarks.
    disableOptimization ? false,
    #
    # Use faster `gold` ELF linker from GNU binutils instead of older and slower but more versatile GNU linker. Unsupported on macOS.
    linkWithGold ? false,
    #
    # Provide an inventory of performance events and timings for the execution. Provides information in an absolute sense. Nothing is timestamped.
    enableLibraryProfiling ? false,
    enableExecutableProfiling ? false,
    #
    # Include tracing information and abilities. Tracing records the chronology, often with timestamps and is extensive in time.
    doTracing ? false,
    #
    # Include DWARF debugging information and abilities.
    enableDWARFDebugging ? false,
    #
    # Strip results from all debugging symbols. This decreases binary size.
    doStrip ? true,
    #
    # Nixpkgs expects shared libraries.
    enableSharedLibraries ? true,
    #
    # Ability to make static libraries.
    enableStaticLibraries ? false,
    #
    # Make hybrid executable that is also a shared library.
    enableSharedExecutables ? false,
    #
    # link executables statically against Haskell libs to reduce closure size.
    justStaticExecutables ? false,
    enableSeparateBinOutput ? false,
    #
    # Adds a post-build check to verify that dependencies declared in the cabal file are actually used.
    checkUnusedPackages ? false,
    #
    # Generation and installation of Haddock's API documentation.
    doHaddock ? false,
    #
    # Generate hyperlinked source code for documentation using HsColour, and have Haddock documentation link to it.
    doHyperlinkSource ? false,
    #
    # Generation and installation of a coverage report. See https://wiki.haskell.org/Haskell_program_coverage
    doCoverage ? false,
    #
    # Dependency checking and compilation and execution for benchmarks listed in the package description file.
    doBenchmark ? false,
    #
    # Include Hoogle executable and database into derivation.
    withHoogle ? false,
    #
    # Don't fail at configure time if there are multiple versions of the
    # same package in the (recursive) dependencies of the package being
    # built. Will delay failures, if any, to compile time.
    allowInconsistentDependencies ? false,
  }: {
    inherit
      allowInconsistentDependencies
      doJailbreak
      doCheck
      sdistTarball
      buildFromSdist
      returnShellEnv
      failOnAllWarnings
      enableDeadCodeElimination
      disableOptimization
      linkWithGold
      enableLibraryProfiling
      enableExecutableProfiling
      doTracing
      enableDWARFDebugging
      doStrip
      enableSharedLibraries
      enableStaticLibraries
      enableSharedExecutables
      justStaticExecutables
      enableSeparateBinOutput
      checkUnusedPackages
      doHaddock
      doHyperlinkSource
      doCoverage
      doBenchmark
      generateOptparseApplicativeCompletions
      executableNamesToShellComplete
      withHoogle
      ;
  };

  mkPackage = {
    flags,
    cabalName,
    #
    # For current default and explicitly supported GHCs https://search.nixos.org/packages?query=ghc&from=0&size=500&channel=unstable, Nixpkgs implicitly supports older minor versions also, until the configuration departs from compatibility with them.
    compiler ? "ghc984",
    #
    packageRoot,
    enableNiceAbstractions ? true,
    developPackageArgs ? {},
    overrideCabalOverride ? (_: {}),
  }: let
    hlib = pkgs.haskell.lib;

    hpkgs = pkgs.haskell.packages.${compiler};
    makeCompletions = hpkgs.generateOptparseApplicativeCompletions flags.executableNamesToShellComplete;

    # Application of functions from this list to the package in code here happens from top to bottom.
    # Some options depend on and override others.
    # If enabling some causes a Nix error or an unexpected result - try changing the order.
    # Please do not change this order without proper testing.
    listSwitchFunc = let
      mkSwitch = switch: function: {inherit switch function;};
    in
      lib.reverseList [
        (mkSwitch flags.doHyperlinkSource hlib.doHyperlinkSource)
        (mkSwitch flags.generateOptparseApplicativeCompletions makeCompletions)
        (mkSwitch flags.checkUnusedPackages (hlib.checkUnusedPackages {}))
        (mkSwitch flags.justStaticExecutables hlib.justStaticExecutables)
        (mkSwitch flags.failOnAllWarnings hlib.failOnAllWarnings)
        (mkSwitch flags.linkWithGold hlib.linkWithGold)
        (mkSwitch flags.enableDWARFDebugging hlib.enableDWARFDebugging)
        (mkSwitch flags.doStrip hlib.doStrip)
        (mkSwitch flags.doJailbreak hlib.doJailbreak)
        (mkSwitch flags.disableOptimization hlib.disableOptimization)
        (mkSwitch flags.buildFromSdist hlib.buildFromSdist)
        (mkSwitch flags.sdistTarball hlib.sdistTarball)
      ];

    onSwitchApplyFunc = set: object:
      if set.switch
      then set.function object
      else object;

    package =
      hpkgs.developPackage ({
        name = cabalName;
        root = pkgs.nix-gitignore.gitignoreSource [] packageRoot;

        inherit (flags) returnShellEnv withHoogle;

        modifier = drv:
          hlib.overrideCabal drv (old:
            {
              configureFlags =
                (old.configureFlags or [])
                ++ lib.optional (!flags.disableOptimization && enableNiceAbstractions) [
                  "--ghc-options=-O2"
                  "--enable-optimization=2"
                  "--enable-split-sections"
                  "--enable-executable-stripping"
                ]
                ++ lib.optional flags.doTracing "--flags=tracing";

              inherit
                (flags)
                allowInconsistentDependencies
                doCheck
                enableDeadCodeElimination
                enableLibraryProfiling
                enableExecutableProfiling
                enableSharedLibraries
                enableStaticLibraries
                enableSharedExecutables
                enableSeparateBinOutput
                doBenchmark
                doCoverage
                doHaddock
                ;
            }
            // overrideCabalOverride old);
      }
      // developPackageArgs);
  in
    if flags.returnShellEnv
    then package
    else lib.foldr onSwitchApplyFunc package listSwitchFunc;
}
