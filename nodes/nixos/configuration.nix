args@{ pkgs, config, lib, ... }:
let
  #TODO feels hacky, basically gets the dir name, which is also the host name
  hostname = builtins.baseNameOf ./.;
  isVM = builtins.hasAttr "vm" config.system.build; #TODO find a more reliable way to do this
in {
  imports = [
    ../../modules/private.nix
    (import ./hardware.nix (args // { inherit isVM; }))
    #(import ./partitions.nix (args // { inherit isVM; }))

    ];

  nixpkgs.config.allowUnfree = true;
  networking.hostId = config.mine.private."${hostname}".hostId; #TODO is this ok?

  } // { #misc todo
    system.copySystemConfiguration = true;
    boot.kernelPackages = pkgs.linuxPackages_5_3;
    #hardware stuff?
    boot.initrd.availableKernelModules = [ "xhci_pci" "ehci_pci" "ahci" "uas" "sd_mod" ]; #TODO?
    boot.kernelModules = [ "kvm-intel" ];
    users.users.root.initialPassword = "test";
  }
