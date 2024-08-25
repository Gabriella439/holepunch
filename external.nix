{ config, lib, ... }: {
  options.services.holePunch = {
    enable = lib.mkEnableOption "holePunch";

    port = lib.mkOption {
      type = lib.types.port;

      description = ''
        The public port that you `ssh` into in order to access the internal
        machine
      '';

      default = 17705;
    };

    proxy.certificate = lib.mkOption {
      type = lib.types.str;

      description = ''
        Path to the certificate private key
      '';
    };
  };

  config = lib.mkIf config.services.holePunch.enable {
    networking.firewall.allowedTCPPorts = [
      config.services.holePunch.port
      443
    ];

    services = {
      openssh = {
        enable = true;

        settings.GatewayPorts = "clientspecified";
      };

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

      stunnel = {
        enable = true;

        logLevel = "notice";

        servers.default = {
          accept = "443";

          cert = config.services.holePunch.proxy.certificate;

          connect = "localhost:${toString config.services.squid.proxyPort}";
        };
      };
    };

    users.users.tunnel = {
      group = "nogroup";

      isSystemUser = true;

      useDefaultShell = true;
    };
  };
}
