{ compiler }:
pkgsSelf: pkgsSuper: {
  haskell = pkgsSuper.haskell // {
    packages = pkgsSuper.haskell.packages // {
      "${compiler}" = pkgsSuper.haskell.packages."${compiler}".override (old: {
        overrides = let
          # callHackage can't find these in the current nixpkgs
          haskus = pkgsSuper.fetchgit {
            url = "https://github.com/haskus/packages.git";
            rev = "de117fb9ce390dd99297fc5eac03b6559874115e";
            sha256 = "0qkm42whsv0g7s3c9kzhzn59f2bdx8zzlcchnq30lig1ss7cngq9";
          };
          mkfirExtension = haskellPackagesSelf: haskellPackagesSuper: {

            # Tests fail on darwin with ghc881
            generic-lens = pkgsSuper.haskell.lib.dontCheck
              (haskellPackagesSuper.callHackage "generic-lens" "1.2.0.1" { });
            vector-sized =
              haskellPackagesSuper.callHackage "vector-sized" "1.4.0.0" { };
            ghc-typelits-natnormalise =
              haskellPackagesSuper.callHackage "ghc-typelits-natnormalise" "0.7"
              { };
            ghc-typelits-knownnat =
              haskellPackagesSuper.callHackage "ghc-typelits-knownnat" "0.7.1"
              { };
            bytes = haskellPackagesSuper.callHackage "bytes" "0.16" { };
            fir = pkgsSuper.haskell.lib.dontCheck
              (haskellPackagesSuper.callCabal2nix "fir" ./. { });

          };
        in pkgsSelf.lib.fold pkgsSelf.lib.composeExtensions
        (old.overrides or (_: _: { })) [ mkfirExtension ];
      });
    };
  };
}
