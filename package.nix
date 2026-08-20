{
  lib,
  stdenv,
  autoPatchelfHook,
  fetchPnpmDeps,
  makeWrapper,
  nodejs,
  pnpmConfigHook,
  pnpm_11,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "deepseek-harness";
  version = "0.1.0-rc.8";

  src = ./npm;

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 4;
    hash = "sha256-ANVmUqkyNTshYOJTRxBaMwfJuf7nHVHXGeuB05D/ePo=";
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs
    pnpm_11
    pnpmConfigHook
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/deepseek-harness
    cp -r node_modules $out/lib/deepseek-harness/node_modules
    rm -rf $out/lib/deepseek-harness/node_modules/@koromix/koffi-*/musl_*

    makeWrapper ${lib.getExe nodejs} $out/bin/dsh \
      --add-flags $out/lib/deepseek-harness/node_modules/@deepseek-ai/dsh/lib/bin.js \
      --suffix PATH : ${lib.makeBinPath [ pnpm_11 ]}

    runHook postInstall
  '';

  doInstallCheck = true;

  installCheckPhase = ''
    runHook preInstallCheck

    export HOME=$(mktemp -d)
    export DSH_TELEMETRY_DISABLED=1

    actual=$($out/bin/dsh --version)
    if [ "$actual" != "${finalAttrs.version}" ]; then
      echo "version mismatch: expected '${finalAttrs.version}', got '$actual'" >&2
      exit 1
    fi

    $out/bin/dsh --profile web --dump-default-config >/dev/null

    node --input-type=commonjs -e '
      const { createRequire } = require("node:module");
      const load = createRequire(process.argv[1]);
      for (const addon of ["node-pty", "sharp", "node-addon-require-builtin"]) load(addon);
    ' $out/lib/deepseek-harness/node_modules/@deepseek-ai/dsh/package.json

    runHook postInstallCheck
  '';

  meta = {
    description = "Plugin-composed agent harness by DeepSeek AI";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    downloadPage = "https://www.npmjs.com/package/@deepseek-ai/dsh/v/${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "dsh";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
})
