craftapps: appSandbox:
{ config, lib, ... }:

let
  cfg = config.programs.craftapps;
  sandboxed = cfg.sandbox.enable;
in
{
  imports = [
    (import ./common.nix craftapps)
    appSandbox
    ./sandbox.nix
  ];

  options.programs.craftapps.linkFonts = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Link /usr/share/fonts to the system fonts. The apps' text tools look
      for fonts only there and do not use fontconfig. With `sandbox.enable`
      the sandbox serves the system fonts to the apps itself, so this link is
      not needed and not made.
    '';
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (!sandboxed) { environment.systemPackages = cfg.packages; })
      (lib.mkIf (cfg.linkFonts && !sandboxed) {
        fonts.fontDir.enable = true;
        systemd.tmpfiles.rules = [
          "d /usr/share 0755 root root -"
          "L+ /usr/share/fonts - - - - /run/current-system/sw/share/X11/fonts"
        ];
      })
    ]
  );
}
