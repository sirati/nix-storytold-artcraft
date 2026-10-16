# What the sandbox needs to know about each app, none of which is in apps.json:
# how its GUI is told to open its control port, how its CLI's MCP server
# attaches to that port, and how to confine a headless MCP server to files.
#
# The control port is only reachable inside the app's own network namespace
# (see modules/sandbox.nix), so the port numbers never collide and need no
# firewall. They are each app's documented default where it has one.
#
# Facts come from `<app>-cli --help`, the shipped binaries and the upstream
# docs at the packaged tags, checked against 0.7 to 0.11. `{home}` and
# `{runtime_dir}` are filled in for each user.
#
#   port      the loopback port the GUI listens on
#   gui       what the GUI is started with (args, env) to open it
#   live      the `<app>-cli` arguments of an MCP server attached to that GUI;
#             absent when the app has no such attach mode
#   headless  extra `<app>-cli mcp` arguments for an MCP server with its own
#             engine, no GUI needed
#   sharedDir the GUI and the CLI both read a credential or control file the
#             GUI writes there (PhotoCraft's token, PdfCraft's control file)
let
  roots = [
    "--automation-read-root"
    "{home}"
    "--automation-write-root"
    "{home}"
  ];
  shared = name: "{runtime_dir}/craftapps/${name}";
in
{
  photocraft = rec {
    port = 7878;
    sharedDir = true;
    gui.args = [
      "--control"
      (toString port)
      "--control-token-file"
      "${shared "photocraft"}/token"
    ]
    ++ roots;
    live = [
      "mcp"
      "--bridge"
      "127.0.0.1:${toString port}"
      "--control-token-file"
      "${shared "photocraft"}/token"
    ];
    headless = roots;
  };

  vectorcraft = {
    port = 7979;
    gui.env = {
      VECTORCRAFT_CONTROL_PORT = "7979";
      VECTORCRAFT_AUTOMATION_READ_ROOT = "{home}";
      VECTORCRAFT_AUTOMATION_WRITE_ROOT = "{home}";
    };
    live = [
      "mcp"
      "--connect"
      "127.0.0.1:7979"
    ];
    headless = [ "--headless" ] ++ roots;
  };

  lightcraft = {
    port = 7980;
    gui.env.LIGHTCRAFT_CONTROL_PORT = "7980";
    live = [
      "mcp"
      "--connect"
      "127.0.0.1:7980"
    ];
    headless = [ ];
  };

  # The control file holds a random port and a token. There is no MCP attach
  # mode: `pdfcraft-cli ui --control <file> <method>` drives the live window.
  pdfcraft = {
    sharedDir = true;
    gui.args = [
      "--control"
      "${shared "pdfcraft"}/control.json"
    ];
    headless = [
      "--root"
      "{home}"
    ];
  };

  effectcraft = {
    port = 9877;
    gui.env.EFFECTCRAFT_CONTROL_PORT = "9877";
    live = [
      "mcp"
      "--bridge"
      "9877"
    ];
    headless = roots;
  };

  designcraft = {
    port = 7979;
    gui.env.DESIGNCRAFT_CONTROL_PORT = "7979";
    live = [
      "mcp"
      "--connect"
      "7979"
    ];
    headless = [ ];
  };

  filmcraft = {
    port = 9876;
    gui.env.FILMCRAFT_CONTROL_PORT = "9876";
    live = [
      "mcp"
      "--bridge"
      "127.0.0.1:9876"
    ];
    headless = [ ];
  };

  gridcraft = {
    port = 7979;
    gui.env.GRIDCRAFT_CONTROL_PORT = "7979";
    live = [
      "mcp"
      "--connect"
      "7979"
    ];
    headless = [ ];
  };

  soundcraft = {
    port = 7801;
    gui.env.SOUNDCRAFT_CONTROL_PORT = "7801";
    live = [
      "mcp"
      "--connect"
      "7801"
    ];
    headless = roots;
  };

  # `--lazy` lets the MCP server start before the window exists.
  cadcraft = {
    port = 7979;
    gui.env.CADCRAFT_CONTROL_PORT = "7979";
    live = [
      "mcp"
      "--connect"
      "127.0.0.1:7979"
      "--lazy"
    ];
    headless = [ ];
  };

  # The GUI writes a key file under its config directory, which the GUI and
  # the CLI share through the app's persistent state.
  wordcraft = {
    port = 7981;
    gui.env.WORDCRAFT_CONTROL_PORT = "7981";
    live = [
      "mcp"
      "--connect"
      "127.0.0.1:7981"
    ];
    headless = roots;
  };

  deckcraft = {
    port = 7990;
    gui.env.DECKCRAFT_CONTROL_PORT = "7990";
    live = [
      "mcp"
      "--connect"
      "7990"
    ];
    headless = [ ];
  };
}
