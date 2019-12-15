{isVM, lib, ...}: lib.mkIf (!isVM) {
  hardware.bluetooth.enable = true;

  nix.maxJobs = lib.mkDefault 4;
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";

  services.xserver.layout = "us";
}
