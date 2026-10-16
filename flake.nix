{
  description = "The ArtCraft Crafting Apps (storytold) for Nix: 12 pure-Rust creative apps";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # Runs each app in a rootless podman container as an ordinary Wayland app
  # (`programs.craftapps.sandbox`). Only the NixOS module reads it.
  inputs.nixos-container-podman = {
    url = "github:sirati/NixOS-Container-Podman";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-container-podman,
    }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      craftapps = pkgs: import ./default.nix { inherit pkgs; };
      names = builtins.attrNames (lib.importJSON ./apps.json);
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          apps = craftapps pkgs;
        in
        apps // { default = apps.craftapps-all; }
      );

      overlays.default = final: _prev: { craftapps = craftapps final; };

      nixosModules.default = import ./modules/nixos.nix craftapps nixos-container-podman.nixosModules.app-sandbox;
      homeManagerModules.default = import ./modules/home-manager.nix craftapps;

      checks = forAllSystems (
        pkgs:
        let
          system = pkgs.stdenv.hostPlatform.system;
          node = lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              {
                programs.craftapps = {
                  enable = true;
                  enableAll = true;
                  apps.soundcraft.enable = false;
                };
                boot.loader.grub.enable = false;
                fileSystems."/" = {
                  device = "none";
                  fsType = "tmpfs";
                };
                system.stateVersion = "26.05";
              }
            ];
          };
          sandboxNode = lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              {
                users.users.tester = {
                  isNormalUser = true;
                  uid = 1000;
                };
                appSandbox.users = [ "tester" ];
                programs.craftapps = {
                  enable = true;
                  enableAll = true;
                  apps.soundcraft.enable = false;
                  sandbox.enable = true;
                };
                boot.loader.grub.enable = false;
                fileSystems."/" = {
                  device = "none";
                  fsType = "tmpfs";
                };
                system.stateVersion = "26.05";
              }
            ];
          };
          sandboxed = builtins.filter (p: lib.hasSuffix "-sandboxed" (p.pname or "")) sandboxNode.config.environment.systemPackages;
          sandboxedNames = map (p: lib.removeSuffix "-sandboxed" p.pname) sandboxed;
        in
        lib.removeAttrs self.packages.${system} [ "default" ]
        // {
          # Every enabled app is wrapped, with the entries the README promises:
          # `-mcp` where the app can attach to its window, and none for PdfCraft.
          sandbox =
            let
              ok =
                builtins.length sandboxed == builtins.length names - 1
                && !builtins.elem "soundcraft" sandboxedNames
                && !builtins.any (lib.hasInfix "/usr/share/fonts") sandboxNode.config.systemd.tmpfiles.rules
                && sandboxNode.config.fonts.fontDir.enable;
            in
            assert lib.assertMsg ok
              "craftapps sandbox: every enabled app must be wrapped, none directly installed, and no host font link made";
            pkgs.runCommand "craftapps-sandbox-check" { } ''
              ${lib.concatMapStringsSep "\n" (
                p:
                let
                  n = lib.removeSuffix "-sandboxed" p.pname;
                in
                ''
                  for e in ${n} ${n}-cli ${n}-mcp-headless; do test -x ${p}/bin/$e || { echo "missing $e" >&2; exit 1; }; done
                  ${if n == "pdfcraft" then "! test -e ${p}/bin/${n}-mcp" else "test -x ${p}/bin/${n}-mcp"}
                  test -e ${p}/share/applications/ai.storyteller.${n}.desktop
                ''
              ) sandboxed}
              touch $out
            '';
          module =
            let
              cfg = node.config;
              ok =
                builtins.length cfg.programs.craftapps.packages == builtins.length names - 1
                && !builtins.elem "soundcraft" (map (p: p.pname) cfg.programs.craftapps.packages)
                && builtins.any (lib.hasInfix "/usr/share/fonts") cfg.systemd.tmpfiles.rules
                && cfg.fonts.fontDir.enable;
            in
            assert lib.assertMsg ok
              "craftapps NixOS module: enableAll with one exclusion, or the font link, is wrong";
            pkgs.runCommand "craftapps-module-check" { } "touch $out";
          cli = pkgs.runCommand "craftapps-cli-check" { } ''
            ${lib.concatMapStringsSep "\n" (
              name:
              let
                app = self.packages.${system}.${name};
              in
              "HOME=$TMPDIR ${app}/bin/${name}-cli --version | grep -qF ${app.version}"
            ) names}
            touch $out
          '';
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
