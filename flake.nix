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
                
                sshDirectory = "/home/${user}/.ssh";

                privateKey = "${sshDirectory}/id_ed25519";
              };

              test = rec {
                user = "test";

                sshDirectory = "/home/${user}/.ssh";

                privateKey = "${sshDirectory}/id_ed25519";
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

                    # This user is only created for testing purposes
                    users.users."${test.user}" = {
                      isNormalUser = true;

                      openssh.authorizedKeys.keyFiles = [
                        ./keys/test_ed25519.pub
                      ];
                    };
                  };

                  external = {
                    imports = [ self.nixosModules.external ];

                    # This is the only option you need to set on the internal
                    # machine
                    services.holePunch.enable = true;

                    # You need to grant the "tunnel" user on the internal
                    # machine SSH access to the "tunnel" user on the external
                    # machine.  In this integration test we just install a
                    # hard-coded key pair, but you will probably want to do
                    # something different.
                    users.users."${tunnel.user}".openssh.authorizedKeys.keyFiles = [
                      ./keys/tunnel_ed25519.pub
                    ];

                    # This user is only created for testing purposes
                    users.users."${test.user}".isNormalUser = true;
                  };
                };

            testScript = ''
              start_all()

              internal.succeed('install --directory --owner=${tunnel.user} --mode=700 ${tunnel.sshDirectory}')
              internal.succeed('install --owner=${tunnel.user} --mode=400 ${./keys/tunnel_ed25519} ${tunnel.privateKey}')

              external.succeed('install --directory --owner=${test.user} --mode=700 ${test.sshDirectory}')
              external.succeed('install --owner=${test.user} --mode=400 ${./keys/test_ed25519} ${test.privateKey}')

              external.wait_for_unit('squid.service')

              internal.succeed('systemctl restart hole-punch.service')

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
