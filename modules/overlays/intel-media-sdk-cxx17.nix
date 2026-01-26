final: prev: {
  intel-media-sdk = prev.intel-media-sdk.overrideAttrs (old: {
    NIX_CXXFLAGS_COMPILE =
      (old.NIX_CXXFLAGS_COMPILE or [ ])
      ++ [
        "-std=c++17"
        "-Wno-stringop-overflow"
        "-Wno-error=stringop-overflow"
      ];
    cmakeFlags =
      (old.cmakeFlags or [ ])
      ++ [
        "-DBUILD_TESTS=OFF"
        "-DCMAKE_CXX_STANDARD=17"
        "-DCMAKE_CXX_STANDARD_REQUIRED=ON"
      ];
    doCheck = false;
  });
}
