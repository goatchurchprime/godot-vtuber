{
  description = "Godot VTuber MediaPipe bridge development shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/b6018f87da91d19d0ab4cf979885689b469cdd41";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      wheelLibraries = with pkgs; [
        stdenv.cc.cc.lib
        zlib
        libGL
        glib
        libxcb
        libxkbcommon
        fontconfig
        freetype
        dbus
        xorg.libX11
        xorg.libXext
        xorg.libXrender
        xorg.libICE
        xorg.libSM
        xorg.xcbutil
        xorg.xcbutilimage
        xorg.xcbutilkeysyms
        xorg.xcbutilrenderutil
        xorg.xcbutilwm
      ];
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.python312 ];
        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath wheelLibraries;
      };
    };
}
