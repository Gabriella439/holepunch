# `holepunch`

This repository contains a reusable NixOS configuration for tunneling an
inbound SSH connection over an outbound HTTPS connection.

This comes in handy in on-premise enterprise deployments where you might have
to work with restrictive firewall rules.  Most enterprise customers will be
reluctant to open up the firewall for anything other than outbound HTTPS
connections.  In particular, they will tend to **NOT** be okay with permitting
inbound `ssh` access to machines that you install inside of their data center.

However, a lot of them do not know that you can tunnel an inbound SSH
connection over an outbound HTTPS connection.  It's normally not *easy* (it
requires stitching together a bunch of tools), but it's *possible* and (more
importantly) it can be mostly automated using NixOS.

This repository provides two NixOS modules:

- [`internal.nix`](./internal.nix)

  This is the NixOS module you add and enable on the "internal" host (the one
  that you install inside of the customer's datacenter).

- [`external.nix`](./external.nix)

  This is the NixOS module you add and enable on the "external" host (a
  publicly reachable gateway server that you host in your cloud/datacenter).

These NixOS modules are also available via the
`nixosModules.{internal,external}` flake outputs.

## Usage

[`flake.nix`](./flake.nix) contains a heavily-commented NixOS test that
documents an example of how to use this repository (which you can run using
`nix flake check github:Gabriella439/holepunch`).  However, I'll also briefly
mention the important bits here.

The only options that you need to enable on the internal host are:

```nix
services.holePunch = {
  enable = true;

  address = "gateway.example.com";
};
```

In other words, the only thing you need to specify is the public gateway that
the internal server is allowed to connect to.

The only options that you need to enable on the external host are:

```nix
services.holePunch = {
  enable = true;

  certificate = "/path/to/your-certificate.pem";
};
```

In other words, the only thing you need to provide is a PEM file containing
server's certificate's public key stapled to its private key *in that order*
(this is the format expected by `stunnel`, which is used internally).

Finally, you will need to create `ssh` accounts that the user can log into on
the internal server (otherwise what's the point of doing this?).  That's
outside of the scope of this repository and not managed by these NixOS modules.

If you set this all up correctly then you will be able to `ssh` into the
internal host by connecting to port 17705 on the external host, like this:

```ShellSession
$ ssh -p 17705 gateway.example.com
```

… assuming of course that you have a user account installed on the internal
host that you have credentials to log into over `ssh`.
