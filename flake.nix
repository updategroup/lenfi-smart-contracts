# future: can use specific binary release, without aiken as a flake,
# then pin the built blueprint file by using a pure derivation.
{
  inputs = {
    aiken.url = "github:aiken-lang/aiken?rev=8e602345629412a88d747c35dd4cf146430e4fd5";
    nixpkgs.follows = "aiken/nixpkgs";
  };
  outputs = {nixpkgs, aiken, ...}: let
    defaultSystems = ["x86_64-linux"];
    perSystem = nixpkgs.lib.genAttrs defaultSystems;
  in {
    devShell = perSystem (system: aiken.devShells.${system}.aiken);
  };
}