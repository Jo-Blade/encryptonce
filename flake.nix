{
  description = "Prevent double encryption in wireguard VPN when payload is already encrypted";

  # Nixpkgs / NixOS version to use.
  inputs.nixpkgs.url = "nixpkgs/nixos-23.11";

  outputs = { self, nixpkgs }:
    let

      # to work with older version of flakes
      lastModifiedDate = self.lastModifiedDate or self.lastModified or "19700101";

      # Generate a user-friendly version number.
      version = builtins.substring 0 1 lastModifiedDate;

      # System types to support.
      supportedSystems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });

    in
    {

      # enable nix fmt
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;

      # Provide some binary packages for selected system types.
      packages = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};

          wireguard-go = pkgs.buildGoModule {
            pname = "wireguard-go";
            inherit version;

            src = ./.;

            postPatch = ''
              # Skip formatting tests
                          rm -f format_test.go
            '';

            vendorHash = "sha256-RqZ/3+Xus5N1raiUTUpiKVBs/lrJQcSwr1dJib2ytwc=";

            subPackages = [ "." ];

            ldflags = [ "-s" "-w" ];

            postInstall = ''
              mv $out/bin/wireguard $out/bin/wireguard-go
            '';

            meta = with pkgs.lib; {
              description = "Userspace Go implementation of WireGuard";
              homepage = "https://git.zx2c4.com/wireguard-go/about/";
              license = licenses.mit;
              maintainers = with maintainers; [ kirelagin yana zx2c4 ];
              mainProgram = "wireguard-go";
            };
          };
        in
        {
          encryptonceTestEnv = pkgs.stdenv.mkDerivation rec {
            pname = "encryptonceTestEnv";
            inherit version;
            src = ./.;

            buildInputs = [
              wireguard-go # compile from source from this repository
              pkgs.wireguard-tools
              pkgs.wireshark
              pkgs.python3 # for http.server, useful for testing
              pkgs.util-linux
              pkgs.makeWrapper
              pkgs.iperf
            ];

            buildPhase = ''
              echo "test"
            '';

            postFixup = ''
              wrapProgram $out/bin/run_archi.sh --prefix PATH : ${pkgs.lib.makeBinPath ( buildInputs)}
            '';

            installPhase = ''
              # create the bin directory
                        mkdir -p $out/bin
                        cp run_archi.sh $out/bin/

              # create a wrapper to run testing environnement
                        makeWrapper ${pkgs.util-linux}/bin/unshare $out/bin/${pname} \
                        --add-flags "-Urpfn --mount-proc $out/bin/run_archi.sh"
            '';
          };

          wireguard-go = wireguard-go;
        });

      # Add dependencies that are only needed for development
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};
        in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [ go gopls gotools go-tools ];
          };
        });

      # The default package for 'nix build'. This makes sense if the
      # flake provides only one package or there is a clear "main"
      # package.
      defaultPackage = forAllSystems (system: self.packages.${system}.wireguard-go);
    };
}
