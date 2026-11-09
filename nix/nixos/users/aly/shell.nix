_: {
  flake.nixosModules.aly = {pkgs, ...}: {
    users.users.aly.packages = with pkgs; [
      age
      duf
      dust
      eza
      fzf
      htop
      just
      neovim
      ripgrep
      starship
      tmux
      zoxide
    ];
  };
}
