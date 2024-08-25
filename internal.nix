{ config, lib, pkgs, ... }:

let
  user = "tunnel";

in

{ options.services.holePunch = {
    enable = lib.mkEnableOption "holePunch";

    address = lib.mkOption {
      type = lib.types.str;

      description = ''
        Address of the public gateway server
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;

      description = ''
        The port on the public gateway server that the hole punch will listen
        to for inbound SSH connections.
      '';

      default = 17705;
    };

    ssh.extraOptions = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.str lib.types.path);

      description = ''
        Extra options to pass to the SSH command
      '';

      example = [
        "-o" "ServerAliveInterval 60"
        "-o" "ServerAliveCountMax 3"
      ];

      default = [];
    };

    stunnel.port = lib.mkOption {
      type = lib.types.port;

      description = ''
        Internal port used by the hole punch.  You don't need to change this
        unless it conflicts with another port.
      '';

      # This is the same as the default squid port.  It doesn't have to be the
      # same, but I think this is conceptually the most elegant choice because
      # all that our internal and external stunnels are doing is tunneling
      # squid connections on this internal machine to squid connections on the
      # external machine.
      default = 3128;
    };
  };

  config = lib.mkIf config.services.holePunch.enable {
    services = {
      openssh.enable = true;

      stunnel = {
        enable = true;

        logLevel = "notice";

        clients.default =
          let
            inherit (config.services.holePunch) address stunnel;

          in
            { accept = stunnel.port;

              connect = "${address}:443";
            };
      };
    };

    systemd.services."hole-punch" = {
      wantedBy = [ "multi-user.target" ];

      wants = [ "network-online.target" ];

      after = [ "network-online.target" ];

      serviceConfig = {
        Restart = "on-failure";

        RestartSec = "7s";

        StartLimitIntervalSec = 0;

        User = user;

        Type = "exec";
      };

      script =
        let
          inherit (config.services.holePunch) port ssh stunnel;

        in
          "${pkgs.openssh}/bin/ssh ${lib.escapeShellArgs ([
            "-R" ":${toString port}:localhost:${toString (lib.head config.services.openssh.ports)}"
            "-o" "ProxyCommand ${pkgs.corkscrew}/bin/corkscrew localhost ${toString stunnel.port} %h %p"
            "-o" "StrictHostKeyChecking accept-new"
            "-o" "BatchMode yes"
            "-N"
            "localhost"
          ] ++ ssh.extraOptions)}";
    };

    users.users."${user}" = {
      isSystemUser = true;

      group = "nogroup";

      # We create a home directory just in case the user wants to install
      # SSH private keys underneath `~tunnel/.ssh`
      createHome = true;

      home = "/home/${user}";

      # The `ssh` command will fail without a login shell
      useDefaultShell = true;
    };
  };
}
