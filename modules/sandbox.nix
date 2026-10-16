# The sandboxed install: every enabled app runs in a rootless podman container
# (nixos-container-podman's mkApp) and still shows up on the host as an
# ordinary Wayland application, with its menu entry, icon, file associations,
# GPU, clipboard and audio. What it cannot see is the rest of the machine; see
# the README for exactly what each app is given.
#
# Next to the app itself each one gets three commands:
#
#   <app>-cli           the app's own CLI, inside the same sandbox
#   <app>-mcp           an MCP server attached to the window you have open, so
#                       an agent and you edit the same document; only if the
#                       app has such a mode and `control.enable` is on
#   <app>-mcp-headless  an MCP server with its own engine, for when no window
#                       is open
#
# The window's control port lives on the app's private loopback. The host and
# every other program on it cannot reach it; `<app>-mcp` and `<app>-cli` run
# in the same network namespace and can.
{
  config,
  lib,
  ...
}:

let
  inherit (lib) mkOption mkEnableOption types;
  cfg = config.programs.craftapps;
  sb = cfg.sandbox;
  meta = import ../sandbox-apps.nix;

  names = builtins.filter (n: cfg.apps.${n}.enable) (builtins.attrNames cfg.apps);

  shared = name: "{runtime_dir}/craftapps/${name}";

  entriesFor =
    name:
    let
      m = meta.${name};
      control = sb.control.enable;
      common = {
        paths = lib.optional (m.sharedDir or false) { path = shared name; };
        ensureDirs = lib.optional (m.sharedDir or false) {
          mode = "700";
          template = shared name;
        };
      };
    in
    {
      ${name} = common // {
        exec = "bin/${name}";
        display = true;
        args = lib.optionals control (m.gui.args or [ ]);
        env = lib.optionalAttrs control (m.gui.env or { });
      };
      "${name}-cli" = common // {
        exec = "bin/${name}-cli";
        stdio = true;
        tty = "auto";
        cwd = true;
      };
      "${name}-mcp-headless" = {
        exec = "bin/${name}-cli";
        args = [ "mcp" ] ++ (m.headless or [ ]);
        stdio = true;
        joinNetwork = false;
      };
    }
    // lib.optionalAttrs (control && m ? live) {
      "${name}-mcp" = common // {
        exec = "bin/${name}-cli";
        args = m.live;
        stdio = true;
      };
    };

  sandboxed =
    name:
    config.appSandbox.mkApp {
      inherit name;
      prefix = "craft";
      appId = meta.${name}.desktopId or "ai.storyteller.${name}";
      package = cfg.apps.${name}.package;
      inherit (sb)
        network
        homeVisible
        userDirs
        paths
        audio
        ;
      entries = entriesFor name;
    };
in
{
  options.programs.craftapps.sandbox = {
    enable = mkEnableOption ''
      running each app in a rootless podman container instead of installing it
      directly. The apps still appear as ordinary Wayland applications'';

    network = mkOption {
      type = types.enum [
        "pasta"
        "none"
      ];
      default = "pasta";
      description = ''
        What network an app's namespace gets. `pasta` reaches the internet (and
        what the host can reach); `none` is loopback only, which is enough for
        everything except the apps' online features. Either way the namespace's
        own loopback is private to the app.
      '';
    };

    homeVisible = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Show every non-hidden entry of the home directory, read-write, as
        snap's `home` interface does. Files in `~/.ssh`, `~/.config` and every
        other dotfile stay out of reach; loose files directly in the home
        directory do not. Without this, only `userDirs` and `paths` are visible,
        and opening a file anywhere else fails inside the app.
      '';
    };

    userDirs = mkOption {
      type = types.listOf types.str;
      default = [
        "Documents"
        "Pictures"
        "Videos"
        "Music"
        "Downloads"
        "Desktop"
      ];
      description = "Directories under the home directory that are visible, read-write.";
    };

    paths = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            path = mkOption {
              type = types.str;
              description = "Absolute host path (a trailing `*` matches every entry); the same path inside. `{home}`, `{user}` and `{uid}` are the user's.";
            };
            mode = mkOption {
              type = types.enum [
                "rw"
                "ro"
              ];
              default = "rw";
              description = "Whether the app may change it.";
            };
          };
        }
      );
      default = [ ];
      example = lib.literalExpression ''[ { path = "/run/media/{user}/*"; } { path = "/mnt/datasets"; mode = "ro"; } ]'';
      description = "More host paths to make visible, for example removable media.";
    };

    audio = mkOption {
      type = types.bool;
      default = true;
      description = "Give the apps the PipeWire and PulseAudio sockets.";
    };

    control.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Start each window with its control port, so `<app>-mcp` can attach to
        it. The port is on the app's private loopback, which only the app's
        own `-mcp` and `-cli` commands can reach. Turn off to run the windows
        with no control port at all; `<app>-mcp-headless` still works.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && sb.enable) {
    appSandbox.enable = true;
    environment.systemPackages = map sandboxed names;
  };
}
