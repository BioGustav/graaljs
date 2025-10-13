local common = import '../common.jsonnet';
local ci = import '../ci.jsonnet';

{
  local graalJs = ci.jobtemplate + {
    cd:: 'graal-js',
    suite_prefix:: 'js', # for build job names
    components+: ['js'],
    // increase default timelimit on windows
    timelimit: if 'os' in self && (self.os == 'windows') then '1:30:00' else '45:00',
    defined_in: std.thisFile,
  },

  local compiler = {suiteimports+:: ['compiler']},
  local ce = ci.ce + compiler,
  local ee = ci.ee + compiler,

  local gateTags(tags) = common.build + common.gateTags + {
    environment+: {
      TAGS: tags,
    },
  },

  local gateCoverage = common.oraclejdk21.tools_java_home + {
    coverage_gate_args:: ['--jacoco-omit-excluded', '--jacoco-relativize-paths', '--jacoco-omit-src-gen', '--jacoco-format', 'lcov', '--jacocout', 'coverage'],
    run+: [
      ['mx', '--dynamicimports', '/wasm', 'gate', '-B=--force-deprecation-as-warning', '-B=-A-J-Dtruffle.dsl.SuppressWarnings=truffle', '--strict-mode', '--tags', 'build,coverage'] + self.coverage_gate_args,
    ],
    teardown+: [
      ['mx', 'sversions', '--print-repositories', '--json', '|', 'coverage-uploader.py', '--associated-repos', '-'],
    ],
    timelimit: '1:00:00',
  },

  local checkoutJsBenchmarks = {
    setup+: [
      ['git', 'clone', '--depth', '1', ['mx', 'urlrewrite', 'https://github.com/graalvm/js-benchmarks.git'], '../js-benchmarks'],
    ],
  },

  local nativeImageSmokeTest = checkoutJsBenchmarks + {
    suiteimports+:: ['substratevm', 'wasm'],
    nativeimages+:: ['lib:jsvm', 'lib:jvmcicompiler'],
    extraimagebuilderarguments+:: ['-H:+ReportExceptionStackTraces'],
    run+: [
      # build legacy graalvm component without native image
      ['mx', '--native-images=', 'build', '--dependencies=GRAALVM'],
      ['set-export', 'GRAALVM_HOME', ['mx', '--native-images=', '--quiet', '--no-warning', 'graalvm-home']],
      ['${GRAALVM_HOME}/bin/js', '--version:graalvm'],
      ['${GRAALVM_HOME}/bin/js', '-e', "print('hello:' + Array.from(new Array(10), (x,i) => i*i ).join('|'))"],
      ['${GRAALVM_HOME}/bin/js', '../../js-benchmarks/harness.js', '--', '../../js-benchmarks/octane-richards.js', '--show-warmup'],
      # standalone smoke tests
      ['mx', 'build', '--dependencies=GRAALJS_JVM_STANDALONE,GRAALJS_NATIVE_STANDALONE'],
      ['set-export', 'STANDALONE_HOME', ['mx', '--quiet', '--no-warning', 'paths', '--output', 'GRAALJS_NATIVE_STANDALONE']],
      ['${STANDALONE_HOME}/bin/js', '--version:graalvm'],
      ['${STANDALONE_HOME}/bin/js', '-e', "print('hello:' + Array.from(new Array(10), (x,i) => i*i ).join('|'))"],
      ['${STANDALONE_HOME}/bin/js', '../../js-benchmarks/harness.js', '--', '../../js-benchmarks/octane-richards.js', '--show-warmup'],
      ['${STANDALONE_HOME}/bin/js', '--js.webassembly', '-e', 'new WebAssembly.Module(new Uint8Array([0x00,0x61,0x73,0x6d,0x01,0x00,0x00,0x00]))'],
      ['${STANDALONE_HOME}/bin/js', '--vm.Xss16m', '../../js-benchmarks/harness.js', '--', '../../js-benchmarks/misc/havlak.js', '--show-warmup'],
      ['set-export', 'STANDALONE_HOME', ['mx', '--quiet', '--no-warning', 'paths', '--output', 'GRAALJS_JVM_STANDALONE']],
      ['${STANDALONE_HOME}/bin/js', '--version:graalvm'],
      ['${STANDALONE_HOME}/bin/js', '-e', "print('hello:' + Array.from(new Array(10), (x,i) => i*i ).join('|'))"],
      ['${STANDALONE_HOME}/bin/js', '../../js-benchmarks/harness.js', '--', '../../js-benchmarks/octane-richards.js', '--show-warmup'],
      ['${STANDALONE_HOME}/bin/js', '--js.webassembly', '-e', 'new WebAssembly.Module(new Uint8Array([0x00,0x61,0x73,0x6d,0x01,0x00,0x00,0x00]))'],
      ['${STANDALONE_HOME}/bin/js', '--vm.Xss16m', '../../js-benchmarks/harness.js', '--', '../../js-benchmarks/misc/havlak.js', '--show-warmup'],
      # maven-downloader smoke test
      ['set-export', 'VERBOSE_GRAALVM_LAUNCHERS', 'true'],
      ['${STANDALONE_HOME}/bin/js-polyglot-get', '-o', 'maven downloader output', '-a', 'java', '-v', '23.1.8', '-r', ['mx', '--quiet', '--no-warning', 'urlrewrite', 'https://curio.ssw.jku.at/nexus/content/repositories/maven-releases']],
      ['unset', 'VERBOSE_GRAALVM_LAUNCHERS'],
    ],
    timelimit: '45:00',
  },

  local mavenDeployDryRun = {
    run+: [
      ['mx', 'build'],
      ['mx', '-v', 'maven-deploy', '--suppress-javadoc', '--validate', 'full', '--licenses', 'UPL,MIT', '--dry-run', 'ossrh', 'https://this-is-only-a-test'],
      ['mx', '-p', '../../graal/vm', '--dynamicimports', '/tools,/compiler,/graal-js,/wasm', 'build'],
      ['mx', '-p', '../../graal/vm', '--dynamicimports', '/tools,/regex,/compiler,/truffle,/sdk,/graal-js,/wasm', 'maven-deploy', '--suppress-javadoc', '--all-suites', '--version-string', 'GATE'],
      ['cd', 'test/maven-demo'],
      ['mvn', '-Dgraalvm.version=GATE', '--batch-mode', 'package'],
      ['mvn', '-Dgraalvm.version=GATE', '--batch-mode', 'exec:exec'],
      ['mvn', '-Dgraalvm.version=GATE', '--batch-mode', 'jlink:jlink'],
      ['target/maven-jlink/default/bin/myapp'],
    ],
    timelimit: '30:00',
  },

  local webassemblyTest = {
    run+: [
      ['mx', '--dynamicimports', '/wasm', 'build'],
      ['mx', '--dynamicimports', '/wasm', 'testv8', 'gate', 'polyglot'],
      ['mx', '--dynamicimports', '/wasm', 'gate', '--tags', 'webassembly'],
    ],
    timelimit: '45:00',
  },

  local downstreamGraal = {
    run+: [
      ['cd', '../../graal/vm'],
      ['set-export', 'NATIVE_IMAGES', 'native-image'],
      ['mx', '--dynamicimports', '/graal-js,/substratevm', 'gate', '--no-warning-as-error', '--strict-mode', '--tags', 'build,truffle-native-tck-js'],
    ],
  },

  local downstreamSubstratevmEE = checkoutJsBenchmarks + ee + {
    suiteimports+:: ['substratevm'],
    run+: [
      ['mx', 'gate', '--all-suites', '--no-warning-as-error', '--strict-mode', '--tags', 'build,${TAGS}'],
    ],
    timelimit: '1:00:00',
  },

  local interopJmhBenchmarks = common.buildCompiler + {
    run+: [
        ['mx', '--dynamicimports', '/compiler', '--kill-with-sigquit', 'benchmark', '--results-file', 'bench-results.json', 'js-interop-jmh:JS_INTEROP_MICRO_BENCHMARKS', '--', '--jvm=server', '-Dpolyglot.engine.TraceCompilation=true'],
        ['bench-uploader.py', 'bench-results.json'],
    ],
  },

  local auxEngineCache = {
    suiteimports+:: ['substratevm', 'tools'],
    nativeimages+:: ['lib:jsvm'],
    graalvmtests:: '../../graalvm-tests',
    run+: [
      ['mx', 'build', '--dependencies=GRAALJS_NATIVE_STANDALONE'],
      ['python', self.graalvmtests + '/test.py', '-g', ['mx', '--quiet', '--no-warning', 'paths', '--output', 'GRAALJS_NATIVE_STANDALONE'], '--print-revisions', '--keep-on-error', 'test/aux-engine-cache', 'test/repl'],
    ],
    timelimit: '1:00:00',
  },

  local generateBuilds = ci.generateBuilds,
  local promoteToTarget = ci.promoteToTarget,
  local defaultToTarget = ci.defaultToTarget,
  local includePlatforms = ci.includePlatforms,
  local excludePlatforms = ci.excludePlatforms,
  local tier1 = ci.promoteToTier1(),
  local tier2 = ci.promoteToTier2(),
  local tier3 = ci.promoteToTarget(common.tier3, [ci.mainGatePlatform]),

  // Style gates
  local styleBuilds = generateBuilds([
    graalJs + common.gateStyleFullBuild                                                      + tier1      + {name: 'style-fullbuild'}
  ], platforms=ci.styleGatePlatforms, defaultTarget=common.tier3),

  // Builds that should run on all supported platforms

  local testingBuilds = local bs = [
    graalJs + gateTags('default')                                                            + tier2 + ce + {name: 'default-ce'} +
      promoteToTarget(common.tier3, [common.jdklatest + common.linux_aarch64, common.jdklatest + common.windows_amd64]),
    graalJs + gateTags('default')                                                            + tier2 + ee + {name: 'default-ee'} +
      promoteToTarget(common.tier3, [common.jdklatest + common.darwin_aarch64]),

    graalJs + gateTags('noic')                                                               + tier3      + {name: 'noic'},
    graalJs + gateTags('directbytebuffer')                                                   + tier3      + {name: 'directbytebuffer'},
    graalJs + gateTags('cloneuninitialized')                                                 + tier3      + {name: 'cloneuninitialized'},
    graalJs + gateTags('lazytranslation')                                                    + tier3      + {name: 'lazytranslation'},
    graalJs + gateTags('shareengine')                                                        + tier3      + {name: 'shareengine'},
    graalJs + gateTags('latestversion')                                                      + tier3      + {name: 'latestversion'},
    graalJs + gateTags('instrument')                                                         + tier2      + {name: 'instrument'},
    graalJs + gateTags('tck')                                                                + tier2      + {name: 'tck'},
    graalJs + webassemblyTest                                                                + tier2      + {name: 'webassembly'},
    graalJs + nativeImageSmokeTest                                                           + tier2      + {name: 'native-image-smoke-test'},
    graalJs + auxEngineCache                                                                 + tier2 + ee + {name: 'aux-engine-cache'} +
      excludePlatforms([common.windows_amd64]), # unsupported on windows

    // downstream graal gate
    graalJs + downstreamGraal                                                                + tier2      + {name: 'downstream-graal'} +
      includePlatforms([ci.mainGatePlatform]),   # GR-62152: language permissions tool supports only linux
    graalJs + downstreamSubstratevmEE   + {environment+: {TAGS: 'downtest_js'}}              + tier3      + {name: 'downstream-substratevm-enterprise'} +
      excludePlatforms([common.linux_aarch64]), # Fails on Linux AArch64 with "Creation of the VM failed."

    // js.zone-rules-based-time-zones
    graalJs + gateTags('zonerulesbasedtimezones')                                                         + {name: 'zonerulesbasedtimezones'} +
      promoteToTarget(common.postMerge, [ci.mainGatePlatform]),

    // PGO profiles
    graalJs + downstreamSubstratevmEE   + {environment+: {TAGS: 'pgo_collect_js'}}                        + {name: 'pgo-profiles'} +
      promoteToTarget(common.postMerge, [ci.mainGatePlatform]),
  ];
    generateBuilds(bs, platforms=ci.jdklatestPlatforms, defaultTarget=common.weekly) +
    # jobs that depend on neither compiler nor substratevm should still run on jdk21
    generateBuilds([b + {suiteimports:: std.setDiff(std.set(b.suiteimports), std.set(['compiler', 'substratevm']))} for b in bs
      if std.setInter(std.set(b.suiteimports), std.set(['compiler', 'substratevm'])) == []],
      platforms=ci.jdk21Platforms, defaultTarget=common.weekly) +
    # build and test standalones using jdk-latest + bootstrap graalvm jdk21
    generateBuilds([b for b in bs
      if std.count(['native-image-smoke-test', 'aux-engine-cache'], b.name) > 0],
      platforms=ci.jdk21unchainedPlatforms, defaultTarget=common.weekly),

  // Builds that only need to run on one platform
  local otherBuilds = generateBuilds([
    graalJs + common.tier3     + mavenDeployDryRun                                                        + {name: 'maven-dry-run'},
    # Note: weekly coverage is sync'ed with the graal repo (while ondemand is not).
    graalJs + common.weekly    + gateCoverage                                                             + {name: 'coverage'},
    graalJs + common.ondemand  + gateCoverage                                                             + {name: 'coverage'},
  ], platforms=[common.jdklatest + common.linux_amd64]),

  // Benchmark builds; need to run on a benchmark machine
  local benchBuilds = generateBuilds([
    graalJs + common.weeklyBench + interopJmhBenchmarks                                                   + {name: 'interop-jmh'},
  ], platforms=[common.jdklatest + common.x52]),

  builds: styleBuilds + testingBuilds + otherBuilds + benchBuilds,
}
