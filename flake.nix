{
  description = "nixbox — microVM sandbox for AI agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      microvm,
    }:
    let
      lib = nixpkgs.lib;

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # Host → guest mapping (darwin hosts run linux guests)
      guestSystem = {
        "x86_64-linux" = "x86_64-linux";
        "aarch64-linux" = "aarch64-linux";
        "aarch64-darwin" = "aarch64-linux";
      };

      isDarwin = hostSystem: builtins.match ".*-darwin" hostSystem != null;

      # --- Constants ---

      vcpus = 256; # Headroom ceiling — actual boot value patched by CLI at launch (defaults to nproc)
      memMB = 65536; # 64GB headroom ceiling — patched at launch; balloon returns unused pages
      rootDiskGB = 64;

      # --- Host-independent config (resolved from build dir files) ---

      projectConfig =
        let
          path = ./project-config.nix;
          resolved = import ./lib/resolve.nix {
            configPath = path;
            pluginsDir = ./plugins;
          };
        in
        if builtins.pathExists path then resolved else { };

      hostInfo =
        let
          path = ./host-info.nix;
        in
        if builtins.pathExists path then import path else { };

      vmUser = hostInfo.username or "user";

      # --- Per-host NixOS configuration builder ---

      mkNixboxConfig =
        hostSystem:
        let
          guest = guestSystem.${hostSystem};
          darwin = isDarwin hostSystem;
        in
        nixpkgs.lib.nixosSystem {
          system = guest;
          modules = [
            microvm.nixosModules.microvm
            (
              {
                config,
                pkgs,
                lib,
                ...
              }:
              {
                nixpkgs.config.allowUnfree = true;

                microvm =
                  {
                    vcpu = vcpus;
                    mem = memMB;
                    socket = "api.sock";

                    volumes = [
                      {
                        image = "root.img";
                        mountPoint = "/";
                        size = rootDiskGB * 1024;
                        autoCreate = true;
                      }
                    ];

                    shares = [
                      {
                        proto = "virtiofs";
                        tag = "nix-store";
                        source = "/nix/store";
                        mountPoint = "/nix/.ro-store";
                      }
                    ];
                  }
                  // (
                    if darwin then
                      {
                        hypervisor = "vfkit";
                        balloon = false;
                        vsock.cid = null;
                        vmHostPackages = import nixpkgs { system = hostSystem; };
                        interfaces = [
                          {
                            type = "user";
                            mac = "02:00:00:00:00:01";
                          }
                        ];
                      }
                    else
                      {
                        hypervisor = "cloud-hypervisor";
                        balloon = true;
                        vsock.cid = 3;
                        interfaces = [
                          {
                            type = "tap";
                            id = "vmtap0";
                            mac = "02:00:00:00:00:01";
                          }
                        ];
                      }
                  );

                # Workaround: nixpkgs removed the default fsType="auto" (NixOS/nixpkgs#444829)
                # and microvm.nix's bind mount for /nix/store doesn't set it (astro/microvm.nix#500).
                # Remove once microvm.nix merges astro/microvm.nix#502.
                fileSystems."/nix/store".fsType = lib.mkDefault "none";

                # --- Packages ---

                environment.systemPackages =
                  let
                    basePackages = with pkgs; [
                      curl
                      git
                      htop
                      jq
                      openssh
                      python3
                      tmux
                      vim
                    ];
                    extraPackages = map (name: pkgs.${name}) ((projectConfig.nix or { }).packages or [ ]);
                  in
                  basePackages ++ extraPackages;

                # --- Environment ---

                environment.shellInit = ''
                  [ -f "$HOME/.env" ] && set -a && . "$HOME/.env" && set +a
                '';

                # --- User ---

                users.users.${vmUser} = {
                  isNormalUser = true;
                  uid = 1000;
                  home = "/home/${vmUser}";
                  extraGroups = [
                    "wheel"
                    "docker"
                  ];
                  openssh.authorizedKeys.keyFiles = [ ./ssh_key.pub ];
                };

                security.sudo.wheelNeedsPassword = false;

                # --- Services ---

                services.openssh = {
                  enable = true;
                  settings = {
                    PasswordAuthentication = false;
                    PermitRootLogin = "no";
                  };
                };

                virtualisation.docker = {
                  enable = true;
                  storageDriver = "overlay2";
                };

                # --- Networking ---

                # Use traditional interface names (eth0) instead of predictable names (enp0s*)
                boot.kernelParams = [ "net.ifnames=0" ];

                networking =
                  {
                    hostName = "nixbox";
                    firewall.enable = false;
                    useDHCP = false;
                  }
                  // (
                    if darwin then
                      {
                        interfaces.eth0.useDHCP = true;
                        nameservers = [
                          "8.8.8.8"
                          "8.8.4.4"
                        ];
                      }
                    else
                      {
                        interfaces.eth0 = {
                          useDHCP = false;
                          ipv4.addresses = [
                            {
                              address = "172.16.0.2";
                              prefixLength = 30;
                            }
                          ];
                        };
                        defaultGateway = {
                          address = "172.16.0.1";
                          interface = "eth0";
                        };
                        nameservers = [ "172.16.0.1" ];
                      }
                  );

                # --- systemd: Inject environment from host via hot-plugged disk ---

                systemd.services.inject-env = {
                  description = "Inject environment from host";
                  before = [ "sshd.service" ];
                  wantedBy = [ "multi-user.target" ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                  };
                  path = with pkgs; [
                    util-linux
                    coreutils
                  ];
                  script = ''
                    set -euo pipefail
                    timeout=10
                    while [ ! -b /dev/vdb ] && [ "$timeout" -gt 0 ]; do
                      sleep 1; timeout=$((timeout - 1))
                    done
                    [ ! -b /dev/vdb ] && { echo "WARNING: env disk not found"; exit 0; }
                    mkdir -p /mnt/env-disk
                    mount -o ro /dev/vdb /mnt/env-disk
                    VM_HOME=/home/${vmUser}

                    # Environment file
                    [ -f /mnt/env-disk/env ] && cp /mnt/env-disk/env "$VM_HOME/.env"

                    chown -R ${vmUser}:users "$VM_HOME"
                    umount /mnt/env-disk; rmdir /mnt/env-disk
                  '';
                };

                system.stateVersion = "25.05";
              }
            )
          ];
        };
    in
    {
      nixosConfigurations = lib.genAttrs (map (s: "nixbox-${s}") supportedSystems) (
        name:
        let
          hostSystem = lib.removePrefix "nixbox-" name;
        in
        mkNixboxConfig hostSystem
      );

      packages = lib.genAttrs supportedSystems (
        hostSystem:
        let
          darwin = isDarwin hostSystem;
          pkgs = import nixpkgs {
            system = hostSystem;
            config.allowUnfree = true;
          };
          hypervisor = if darwin then "vfkit" else "cloud-hypervisor";

          nixbox = pkgs.stdenvNoCC.mkDerivation {
            pname = "nixbox";
            version = "0.1.0";
            src = ./.;
            nativeBuildInputs = [ pkgs.makeWrapper ];
            installPhase =
              let
                commonDeps = with pkgs; [
                  jq
                  e2fsprogs
                  openssh
                  curl
                  git
                  gnused
                ];
                linuxDeps = [ pkgs.virtiofsd ];
                wrapDeps = commonDeps ++ (if darwin then [ ] else linuxDeps);
              in
              ''
                mkdir -p $out/bin $out/share/nixbox
                cp bin/nixbox $out/bin/nixbox
                cp flake.nix flake.lock $out/share/nixbox/
                cp -r lib $out/share/nixbox/
                cp -r plugins $out/share/nixbox/
                cp config.example.nix $out/share/nixbox/

                wrapProgram $out/bin/nixbox \
                  --prefix PATH : ${pkgs.lib.makeBinPath wrapDeps}
              '';
          };
        in
        {
          inherit nixbox;
          vm-runner = self.nixosConfigurations."nixbox-${hostSystem}".config.microvm.runner.${hypervisor};
          default = nixbox;
        }
      );

      apps = lib.genAttrs supportedSystems (hostSystem: {
        default = {
          type = "app";
          program = "${self.packages.${hostSystem}.nixbox}/bin/nixbox";
        };
      });
    };
}
