{extraargs, lib, ...}: lib.mkIf (!extraargs.isVM) {
  fileSystems."/" = private."${extraargs.hostname}".devices.root;

  fileSystems."/efi" = private."${extraargs.hostname}".devices.efi;

  boot.initrd.luks.devices."root" = private."${extraargs.hostname}".devices.luksroot;

  /*
  swapDevices = [
    { device = ""; }
    ];
  */
}
