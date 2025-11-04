{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    systems = {
      url = "path:./systems.nix";
      flake = false;
    };
  };
  outputs = {
    nixpkgs,
    systems,
    treefmt-nix,
    ...
  }: let
    eachSystem = f: nixpkgs.lib.genAttrs (import systems) f;
    eachSystemPkgs = f: eachSystem (system: f (import nixpkgs {inherit system;}));
    treefmtEval = eachSystemPkgs (pkgs: treefmt-nix.lib.evalModule pkgs ./treefmt.nix);
  in {
    formatter = eachSystem (system: treefmtEval.${system}.config.build.wrapper);
    niceHaskell = eachSystemPkgs (pkgs:
      import ./niceHaskell.nix {
        inherit pkgs;
        inherit (nixpkgs) lib;
      });
  };
}
