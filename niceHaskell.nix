{
  pkgs,
  lib,
}: let
  hlib = pkgs.haskell.lib.compose;

  # Flags from the Nixpkgs haskell.lib API: https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/haskell-modules/lib/default.nix
  # Every flag is also an argument of mkPackage and mkPackageNoIFD.
  # Some are excluded as they are stupid. For example there is `doCheck` AND `dontCheck`. Or flags that simply turn on other flags.
  flagDefaults = {
    # Generate and apply completions from the optparse-applicative library. Done with a postInstall hook.
    # Needs executable names of the programs you want completed.
    shellCompletions = [];
    #
    # Escape the version bounds from the cabal file. You may want to avoid this function.
    doJailbreak = false;
    #
    # Enables dependency checking, compilation and execution
    # of test suites listed in the package description file.
    doCheck = false;
    #
    # Create a source distribution tarball like those found on hackage, instead of building the package.
    sdistTarball = false;
    #
    # Build a source distribution tarball instead of using the source files
    # directly. The effect is that the package is built as if it were published
    # on hackage. This can be used as a test for the source distribution,
    # assuming the build fails when packaging mistakes are in the cabal file.
    buildFromSdist = false;
    #
    # Turn all warnings into errors (-Werror)
    failOnAllWarnings = false;
    enableDeadCodeElimination = true;
    #
    # Disabled GHC code optimizations make build/tolling/dev loops faster.
    # Works also for Haskel IDE Engine and GHCID.
    # Otherwise the package is built with -O2.
    disableOptimization = false;
    #
    # Provide an inventory of performance events and timings for the execution. Provides information in an absolute sense. Nothing is timestamped.
    enableLibraryProfiling = false;
    enableExecutableProfiling = false;
    #
    # Include DWARF debugging information and abilities.
    enableDWARFDebugging = false;
    #
    # Nixpkgs expects shared libraries.
    enableSharedLibraries = true;
    #
    # Ability to make static libraries.
    enableStaticLibraries = false;
    #
    # Make hybrid executable that is also a shared library.
    enableSharedExecutables = false;
    #
    # link executables statically against Haskell libs to reduce closure size.
    justStaticExecutables = false;
    enableSeparateBinOutput = false;
    #
    # Adds a post-build check to verify that dependencies declared in the cabal file are actually used.
    checkUnusedPackages = false;
    #
    # Generation and installation of Haddock's API documentation.
    doHaddock = false;
    #
    # Generate hyperlinked source code for documentation using HsColour, and have Haddock documentation link to it.
    doHyperlinkSource = false;
    #
    # Generation and installation of a coverage report. See https://wiki.haskell.org/Haskell_program_coverage
    doCoverage = false;
    #
    # Dependency checking and compilation and execution for benchmarks listed in the package description file.
    doBenchmark = false;
    #
    # Don't fail at configure time if there are multiple versions of the
    # same package in the (recursive) dependencies of the package being
    # built. Will delay failures, if any, to compile time.
    allowInconsistentDependencies = false;
  };

  # developPackage, with cabal2nix's output for the package read from the file `cabal2nix`
  # instead of generated while Nix evaluates.
  developPackageNoIFD = hpkgs: cabal2nix: {
    root,
    name ? baseNameOf (toString root),
    source-overrides ? {},
    overrides ? _self: _super: {},
    modifier ? lib.id,
    returnShellEnv ? lib.inNixShell,
    withHoogle ? returnShellEnv,
    cabal2nixOptions ? "",
  }:
    assert lib.assertMsg (cabal2nixOptions == "")
    "niceHaskell: ${name} can't use cabal2nixOptions without IFD, pass them to cabal2nix when generating ${toString cabal2nix}"; let
      extendedSrc = hpkgs.extend (lib.composeExtensions (hpkgs.packageSourceOverrides source-overrides) overrides);
      drv = modifier (hlib.overrideCabal {src = root;} (extendedSrc.callPackage cabal2nix {}));
    in
      if returnShellEnv
      then drv.envFunc {inherit withHoogle;}
      else drv;

  build = developPackage: {
    src,
    #
    # Attribute name of a package set in `pkgs.haskell.packages`, e.g. "ghc984".
    # Defaults to `null`, which uses `pkgs.haskellPackages`, the package set of nixpkgs' default GHC.
    # Only the default package set is fully built by Hydra and therefore available from cache.nixos.org,
    compiler ? null,
    #
    # A whole Haskell package set to build with instead of one from `pkgs`, e.g. `haskellPackages`
    # from another nixpkgs. Use it when the result has to match packages built from that set.
    # Takes precedence over `compiler`.
    haskellPackages ?
      if compiler == null
      then pkgs.haskellPackages
      else pkgs.haskell.packages.${compiler},
    #
    # Arguments of developPackage: https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/haskell-modules/make-package-set.nix
    # e.g. `overrides = self: super: {...}`, `modifier`, `returnShellEnv`, `cabal2nixOptions`.
    # `modifier` runs after the flags have been applied.
    developPackageArgs ? {},
    #
    # Attributes to set on the Haskell derivation, or a function from its old attributes to them.
    overrideCabal ? {},
    ...
  } @ args: let
    unknownArgs = lib.attrNames (removeAttrs args (["src" "compiler" "haskellPackages" "developPackageArgs" "overrideCabal"] ++ lib.attrNames flagDefaults));
    flags = flagDefaults // builtins.intersectAttrs flagDefaults args;
    when = cond: f:
      if cond
      then f
      else lib.id;
    applyFlags = drv:
      lib.pipe drv [
        (hlib.overrideCabal (old:
          {
            configureFlags =
              (old.configureFlags or [])
              ++ lib.optional (!flags.disableOptimization) "--enable-optimization=2";

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
          // lib.toFunction overrideCabal old))
        # Applied from top to bottom. Some depend on and override others.
        # If enabling some causes a Nix error or an unexpected result - try changing the order.
        # Please do not change this order without proper testing.
        (when flags.doHyperlinkSource hlib.doHyperlinkSource)
        (when (flags.shellCompletions != []) (haskellPackages.generateOptparseApplicativeCompletions flags.shellCompletions))
        (when flags.checkUnusedPackages (hlib.checkUnusedPackages {}))
        (when flags.justStaticExecutables hlib.justStaticExecutables)
        (when flags.failOnAllWarnings hlib.failOnAllWarnings)
        (when flags.enableDWARFDebugging hlib.enableDWARFDebugging)
        (when flags.doJailbreak hlib.doJailbreak)
        (when flags.disableOptimization hlib.disableOptimization)
        (when flags.buildFromSdist hlib.buildFromSdist)
        (when flags.sdistTarball hlib.sdistTarball)
      ];
  in
    assert lib.assertMsg (unknownArgs == []) "niceHaskell: unknown arguments: ${toString unknownArgs}";
      developPackage haskellPackages ({
          root = src;
          returnShellEnv = false;
        }
        // developPackageArgs
        // {modifier = drv: (developPackageArgs.modifier or lib.id) (applyFlags drv);});
in {
  # haskellPackages.developPackage, which runs cabal2nix on the .cabal file in `src` while Nix evaluates
  # (import from derivation).
  mkPackage = build (hpkgs: hpkgs.developPackage);

  # The same, but `cabal2nix` is the committed output of `cabal2nix . > cabal.nix`, run next to
  # the .cabal file, so evaluation never builds anything. Regenerate it when the .cabal file changes.
  mkPackageNoIFD = {cabal2nix, ...} @ args:
    build (hpkgs: developPackageNoIFD hpkgs cabal2nix) (removeAttrs args ["cabal2nix"]);
}
