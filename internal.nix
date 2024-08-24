{ config, lib, pkgs, ... }: {
  options.services.holePunch = {
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

        default = 3128;
      };
    };

    ssh = {
      user = lib.mkOption {
        type = lib.types.str;

        description = ''
          The SSH user that will connect to the external host to establish the
          tunnel
        '';

        default = "tunnel";
      };

      extraOptions = lib.mkOption {
        type = lib.types.listOf (lib.types.either lib.types.str lib.types.path);

        description = ''
          Extra options to pass to the SSH command
        '';

        default = [];
      };
    };
  };

  config = lib.mkIf config.services.holePunch.enable {
    services.openssh.enable = true;

    systemd.services."hole-punch" = {
      wantedBy = [ "multi-user.target" ];

      wants = [ "network-online.target" ];

      after = [ "network-online.target" ];

      serviceConfig = {
        Restart = "on-failure";

        RestartSec = "20s";
      };

      path = [ pkgs.openssh ];

      script =
        let
          inherit (config.services.holePunch) listen proxy ssh;

        in
          ''
          ssh ${lib.escapeShellArgs ([
            "-R" "${toString listen.port}:localhost:${toString (lib.head config.services.openssh.ports)}"
            "-o" "ProxyCommand ${pkgs.corkscrew}/bin/corkscrew ${proxy.address} ${toString proxy.port} %h %p"
            "-o" "StrictHostKeyChecking accept-new"
            "-o" "BatchMode yes"
            "-N"
            "${ssh.user}@localhost"
          ] ++ ssh.extraOptions)}
          '';
    };

    users.users."${config.services.holePunch.ssh.user}" = {
      group = "nogroup";

      isSystemUser = true;
    };
  };
}
