{
  lib,
  stdenv,
  autoPatchelfHook,
  fetchPnpmDeps,
  makeWrapper,
  nodejs,
  patchelfUnstable,
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
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
    patchelfUnstable
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/deepseek-harness
    cp -r node_modules $out/lib/deepseek-harness/node_modules
    rm -rf $out/lib/deepseek-harness/node_modules/@koromix/koffi-*/musl_*
    rm -f $out/lib/deepseek-harness/node_modules/.modules.yaml \
      $out/lib/deepseek-harness/node_modules/.pnpm-workspace-state-v1.json

    makeWrapper ${lib.getExe nodejs} $out/bin/dsh \
      --add-flags --expose-internals \
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
      load("sharp")({ create: { width: 8, height: 8, channels: 3, background: "red" } })
        .png()
        .toBuffer()
        .then(() => process.exit(0), (e) => { console.error(e); process.exit(1); });
    ' $out/lib/deepseek-harness/node_modules/@deepseek-ai/dsh/package.json

    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      $out/bin/dsh web --no-open --port 0 >"$TMPDIR/web.log" 2>&1 &
      webPid=$!
      for _ in $(seq 1 30); do
        grep -q '^dsh web: http://' "$TMPDIR/web.log" && break
        sleep 1
      done
      sleep 2
      if ! kill -0 "$webPid" 2>/dev/null || ! grep -q '^dsh web: http://' "$TMPDIR/web.log"; then
        echo "web profile failed to boot:" >&2
        cat "$TMPDIR/web.log" >&2
        exit 1
      fi
      kill "$webPid"
      wait "$webPid" || true
    ''}

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
