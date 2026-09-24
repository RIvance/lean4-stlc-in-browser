{
  description = "Lean STLC native and WebAssembly development tools";
  inputs.nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.zst";
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      eachSystem = nixpkgs.lib.genAttrs systems;
    in {
      devShells = eachSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
          nodeMajor = pkgs.lib.removeSuffix "\n" (builtins.readFile ./.node-version);
          node = builtins.getAttr ("nodejs_" + nodeMajor) pkgs;
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [ elan emscripten cmake gnumake coreutils node git ];
          };
        });
    };
}
