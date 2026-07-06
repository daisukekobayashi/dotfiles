{
  description = "Daisuke dotfiles Home Manager scaffold";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      inherit (nixpkgs) lib;

      username = "daisuke";
      supportedSystems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      isDarwin = system: lib.hasSuffix "-darwin" system;
      homeName = system: "${username}-${system}";
      homeDirectory = system:
        if isDarwin system
        then "/Users/${username}"
        else "/home/${username}";
      osModule = system:
        if isDarwin system
        then ./nix/modules/darwin.nix
        else ./nix/modules/linux.nix;

      mkHome = system:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs { inherit system; };
          modules = [
            ./nix/home.nix
            (osModule system)
            {
              home.username = username;
              home.homeDirectory = homeDirectory system;
            }
          ];
        };

      homeConfigurations = builtins.listToAttrs
        (map
          (system: {
            name = homeName system;
            value = mkHome system;
          })
          supportedSystems);
    in
    {
      inherit homeConfigurations;

      packages = lib.genAttrs supportedSystems (system:
        let
          name = homeName system;
        in
        {
          default = homeConfigurations.${name}.activationPackage;
          home = homeConfigurations.${name}.activationPackage;
        });
    };
}
