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
      system = "x86_64-linux";
      vcpus = 256; # Headroom ceiling — actual boot value patched by CLI at launch (defaults to nproc)
      memMB = 65536; # 64GB headroom ceiling — patched at launch; balloon returns unused pages
      rootDiskGB = 64;

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

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      nixosConfigurations.nixbox = nixpkgs.lib.nixosSystem {
        inherit system;
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

              microvm = {
                hypervisor = "cloud-hypervisor";
                vcpu = vcpus;
                mem = memMB;
                socket = "api.sock";
                vsock.cid = 3;
                balloon = true;

                interfaces = [
                  {
                    type = "tap";
                    id = "vmtap0";
                    mac = "02:00:00:00:00:01";
                  }
                ];

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
              };

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

              # --- Dynamic linker for generic Linux binaries ---
              # Many dev tools (scala-cli-fetched scalafmt, Node native deps, etc.)
              # ship prebuilt glibc binaries that need /lib64/ld-linux-x86-64.so.2.
              # Extra libraries can be added via `nix.ldLibraries` in project config
              # or plugins. Names support dotted paths (e.g. "stdenv.cc.cc.lib").
              programs.nix-ld = {
                enable = true;
                libraries =
                  let
                    baseLibs = with pkgs; [
                      stdenv.cc.cc.lib
                      zlib
                      openssl
                      curl
                      icu
                      libxcrypt
                    ];
                    extraLibs = map (
                      name: lib.getAttrFromPath (lib.splitString "." name) pkgs
                    ) ((projectConfig.nix or { }).ldLibraries or [ ]);
                  in
                  baseLibs ++ extraLibs;
              };

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

              # net.ifnames=0 ensures the virtio-net NIC is always named eth0
              boot.kernelParams = [ "net.ifnames=0" ];

              networking = {
                hostName = "nixbox";
                firewall.enable = false;
                useNetworkd = true;
              };

              systemd.network.networks."10-vm" = {
                matchConfig.Name = "eth0";
                networkConfig.DHCP = "ipv4";
              };

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

      packages.${system} =
        let
          nixbox = pkgs.stdenvNoCC.mkDerivation {
            pname = "nixbox";
            version = "0.1.0";
            src = ./.;
            nativeBuildInputs = [ pkgs.makeWrapper ];
            installPhase = ''
              mkdir -p $out/bin $out/share/nixbox
              cp bin/nixbox $out/bin/nixbox
              cp flake.nix flake.lock $out/share/nixbox/
              cp -r lib $out/share/nixbox/
              cp -r plugins $out/share/nixbox/
              cp config.example.nix $out/share/nixbox/

              wrapProgram $out/bin/nixbox \
                --prefix PATH : ${
                  pkgs.lib.makeBinPath [
                    pkgs.jq
                    pkgs.e2fsprogs
                    pkgs.virtiofsd
                    pkgs.openssh
                    pkgs.curl
                    pkgs.git
                    pkgs.gnused
                  ]
                }
            '';
          };
        in
        {
          inherit nixbox;
          vm-runner = self.nixosConfigurations.nixbox.config.microvm.runner.cloud-hypervisor;
          default = nixbox;
        };

      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.nixbox}/bin/nixbox";
      };
    };
}
