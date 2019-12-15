{pkgs, ...}:
  let
    privpath = (builtins.getEnv "PRIVATE") + "/private.nix";
    exists = builtins.pathExists privpath;
    priv = (if exists then (builtins.trace "Loading impure PRIVATE=${privpath}" privpath)
                           else (throw "PRIVATE=${privpath} does not exist"));
  in {
    imports = [ priv ];
    }
/*
  let
    salt = "7DC03B96584031776E91EB4D7A5D4472";
    target = "81c82cd090df5eed4a287305c0ee8a8e27ee30650c4c7fab46c577f270852925";
  in
    import (pkgs.runCommand "find" ''
      find.py /
      '';)
*/
