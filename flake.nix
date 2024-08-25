{ inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/24.05";

    flake-utils.url = "github:numtide/flake-utils/v1.0.0";
  };

  outputs = { flake-utils, nixpkgs, self }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;

          config.permittedInsecurePackages = [
            "squid-6.8"
          ];

          overlays = [];
        };

      in
        { packages.default = self.checks.${system}.default.driverInteractive;

          checks.default =
            let
              tunnel = rec {
                user = "tunnel";
                
                ssh = rec {
                  directory = "/home/${user}/.ssh";

                  key = "${directory}/id_ed25519";
                };

                certificate =
                  let
                    baseName = "/tmp/shared/external";

                  in
                    { key = "${baseName}.key";

                      crt = "${baseName}.crt";

                      pem = "${baseName}.pem";
                    };
              };

              test = rec {
                user = "test";

                ssh = rec {
                  directory = "/home/${user}/.ssh";

                  key = "${directory}/id_ed25519";
                };
              };

              port = 8080;

            in
              pkgs.nixosTest {
                name = "test";

                nodes = {
                  internal = {
                    imports = [ self.nixosModules.internal ];

                    # These are the options you're always going to want to set
                    # on the internal machine
                    services.holePunch = {
                      enable = true;

                      listen = { inherit port; };

                      proxy.address = "external";
                    };

                    # These options are only for testing purposes
                    users.users."${test.user}" = {
                      isNormalUser = true;

                      openssh.authorizedKeys.keyFiles = [
                        ./keys/test_ed25519.pub
                      ];
                    };

                    services.stunnel.clients.default = {
                      verifyChain = false;

                      OCSPaia = false;
                    };
                  };

                  external = { pkgs, ...}: {
                    imports = [ self.nixosModules.external ];

                    # These are the options you're always going to want to set
                    # on the external machine
                    services.holePunch = {
                      enable = true;

                      proxy.certificate = tunnel.certificate.pem;
                    };

                    # You need to grant the "tunnel" user on the internal
                    # machine SSH access to the "tunnel" user on the external
                    # machine.  In this integration test we just install a
                    # hard-coded key pair, but you will probably want to do
                    # something different.
                    users.users."${tunnel.user}".openssh.authorizedKeys.keyFiles = [
                      ./keys/tunnel_ed25519.pub
                    ];

                    # These options are only for testing purposes
                    users.users."${test.user}".isNormalUser = true;

                    environment.systemPackages = [ pkgs.openssl ];
                  };
                };

            testScript = ''
              start_all()

              # NixOS doesn't have a simple way to dynamically set a user's
              # authorized keys, so for this test I hardcode the public keys as
              # authorized keys (above) and then install the corresponding
              # private keys here.
              internal.succeed('install --directory --owner=${tunnel.user} --mode=700 ${tunnel.ssh.directory}')
              internal.succeed('install --owner=${tunnel.user} --mode=400 ${./keys/tunnel_ed25519} ${tunnel.ssh.key}')
              external.succeed('install --directory --owner=${test.user} --mode=700 ${test.ssh.directory}')
              external.succeed('install --owner=${test.user} --mode=400 ${./keys/test_ed25519} ${test.ssh.key}')

              # Normally I'd be fine hard-coding the self-signed certificate
              # for this test, but there's no way to generate a certificate
              # that doesn't expire, so this test generates a self-signed
              # certificate each run.
              external.succeed('openssl req -x509 -newkey rsa:2048 -keyout ${tunnel.certificate.key} -out ${tunnel.certificate.crt} -days 1 -nodes -subj "/C=NL/ST=Utrecht/L=Utrecht/O=NixOS/CN=external"')

              # `stunnel` requires the public and private key of the
              # certificate pair to be stapled together in that order.
              external.succeed('cat ${tunnel.certificate.crt} ${tunnel.certificate.key} > ${tunnel.certificate.pem}')

              # `stunnel` fails the first time it runs because the certificate
              # was not yet present, so now that the certificate is in place
              # we can restart `stunnel`, which will now succeed.  In a real
              # deploy of this configuration the certificate would likely
              # already be in place before `stunnel` starts.
              external.systemctl('restart stunnel.service')

              # Verify that we can now make an  inbound `ssh` connection from
              # the `external` machine to the `internal` machine.
              external.wait_until_succeeds('sudo --user ${test.user} ssh -o "StrictHostKeyChecking accept-new" -o "BatchMode yes" -p ${toString port} localhost :')
            '';
        };
    }) // {
      nixosModules = {
        internal = import ./internal.nix;

        external = import ./external.nix;
      };
    };
}
