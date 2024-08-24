{ config, lib, ... }: {
  options.services.holePunch = {
    enable = lib.mkEnableOption "holePunch";

    ssh = {
      user = lib.mkOption {
        type = lib.types.str;

        description = ''
          The SSH user that will connect to this host to establish the tunnel
        '';

        default = "tunnel";
      };
    };
  };

  config = lib.mkIf config.services.holePunch.enable {
    networking.firewall.allowedTCPPorts = [ config.services.squid.proxyPort ];

    services = {
      openssh.enable = true;

      squid = {
        enable = true;

        configText =
          ''
          acl CONNECT method CONNECT
          acl localdst dst 127.0.0.1/32 ::1/128
          acl ssh port ${toString (lib.head config.services.openssh.ports)}

          http_access allow CONNECT localdst ssh
          http_access deny all

          access_log syslog:daemon.info

          pid_filename /run/squid.pid

          cache_effective_user squid squid

          coredump_dir /var/cache/squid

          http_port ${toString config.services.squid.proxyPort}
          '';
      };
    };

    users.users."${config.services.holePunch.ssh.user}" = {
      group = "nogroup";

      isSystemUser = true;
    };
  };
}
