{ config, lib, pkgs, ... }:

let
  user = "tunnel";

in

{ options.services.holePunch = {
    enable = lib.mkEnableOption "holePunch";

    listen = {
      port = lib.mkOption {
        type = lib.types.port;

        description = ''
          The port that the hole punch will listen on that will accept incoming
          SSH connections

          This should not be the same port as `sshd`.
        '';
      };
    };

    proxy = {
      address = lib.mkOption {
        type = lib.types.str;

        description = ''
          Address of the forward proxy that `corkscrew` connects to
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;

        description = ''
          Port for the forward proxy that `corkscrew` connects to
        '';

        default = 443;
      };
    };

    ssh.extraOptions = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.str lib.types.path);

      description = ''
        Extra options to pass to the SSH command
      '';

      default = [];
    };

    stunnel.port = lib.mkOption {
      type = lib.types.port;

      description = ''
        Internal port used by the hole punch
      '';

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
            inherit (config.services.holePunch) proxy stunnel;

          in
            { accept = "localhost:${toString stunnel.port}";

              connect = "${proxy.address}:${toString proxy.port}";
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
          inherit (config.services.holePunch) listen ssh stunnel;

        in
          "${pkgs.openssh}/bin/ssh ${lib.escapeShellArgs ([
            "-R" "${toString listen.port}:localhost:${toString (lib.head config.services.openssh.ports)}"
            "-o" "ProxyCommand ${pkgs.corkscrew}/bin/corkscrew localhost ${toString stunnel.port} %h %p"
            "-o" "StrictHostKeyChecking accept-new"
            "-o" "BatchMode yes"
            "-N"
            "localhost"
          ] ++ ssh.extraOptions)}";
    };

    users.users."${user}" = {
      isSystemUser = true;

      createHome = true;

      group = "nogroup";

      home = "/home/${user}";

      useDefaultShell = true;
    };
  };
}
