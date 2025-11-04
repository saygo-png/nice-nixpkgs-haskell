{
  pkgs,
  lib,
  ...
}: {
  projectRootFile = "flake.nix";

  programs = {
    alejandra.enable = true;
    statix.enable = true;
  };

  settings.formatter = {
    trim-newlines = {
      command = "${lib.getExe pkgs.gnused}";
      options = lib.strings.splitString " " ''-i -e :a -e /^\n*$/{$d;N;ba -e }'';
      includes = ["*"];
    };
  };
}
