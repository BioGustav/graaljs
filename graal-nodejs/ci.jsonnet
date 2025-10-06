local common = import '../common.jsonnet';
local ci = import '../ci.jsonnet';
local cicommon = import '../ci/common.jsonnet';

{
  local graalNodeJs = ci.jobtemplate + cicommon.deps.graalnodejs + {
    cd:: 'graal-nodejs',
    suite_prefix:: 'nodejs', # for build job names
    components+: ['nodejs'],
    // increase default timelimit on windows
    timelimit: if 'os' in self && (self.os == 'windows') then '2:00:00' else '1:10:00',
    defined_in: std.thisFile,
  },

  local ce = ci.ce,
  local ee = ci.ee,

  local vm_env = {
    local enabled = true,
    artifact:: if enabled then 'nodejs' else '',
    suiteimports+:: if enabled then ['substratevm', 'tools', 'wasm'] else [],
    nativeimages+:: if enabled then ['lib:graal-nodejs', 'lib:jvmcicompiler'] else [],
    build_dependencies+:: (if enabled then ['GRAALNODEJS_NATIVE_STANDALONE'] else []) + ['GRAALNODEJS_JVM_STANDALONE'],
    build_standalones:: true,
  },

  local gateTags(tags) = common.gateTags + {
    environment+: {
      TAGS: tags,
    },
  },

  local build = {
    run+: [
      // build only if no artifact is being used to avoid rebuilding
      ['[', '${ARTIFACT_NAME}', ']', '||', 'mx', 'build', '--force-javac'] + (if self.build_dependencies == [] then [] else ['--dependencies', std.join(',', self.build_dependencies)]),
    ],
  },

  local defaultGateTags = gateTags('all') + {
    local tags = if 'os' in super && super.os == 'windows' then 'windows' else 'all',
    environment+: {
      TAGS: tags,
    }
  },

  local gateVmSmokeTest = {
    run+: [
      # standalone smoke tests
      ['set-export', 'STANDALONE_HOME', ['mx', '--quiet', '--no-warning', 'paths', '--output', 'GRAALNODEJS_JVM_STANDALONE']],
      ['${STANDALONE_HOME}/bin/node', '-e', "console.log('Hello, World!')"],
      ['${STANDALONE_HOME}/bin/npm', '--version'],
      # maven-downloader smoke test
      ['set-export', 'VERBOSE_GRAALVM_LAUNCHERS', 'true'],
      ['${STANDALONE_HOME}/bin/node-polyglot-get', '-o', 'maven downloader output', '-a', 'java', '-v', '23.1.8', '-r', ['mx', '--quiet', '--no-warning', 'urlrewrite', 'https://curio.ssw.jku.at/nexus/content/repositories/maven-releases']],
      ['unset', 'VERBOSE_GRAALVM_LAUNCHERS'],
    ] + (if std.find('lib:graal-nodejs', super.nativeimages) != [] then ([
      ['set-export', 'STANDALONE_HOME', ['mx', '--quiet', '--no-warning', 'paths', '--output', 'GRAALNODEJS_NATIVE_STANDALONE']],
      ['${STANDALONE_HOME}/bin/node', '-e', "console.log('Hello, World!')"],
      ['${STANDALONE_HOME}/bin/npm', '--version'],
    ] + if 'os' in super && super.os == 'windows' then [] else [
      # Uses node-gyp which requires Visual Studio on Windows.
      # Note: `npm --prefix` does not work on Windows.
      ['cd', 'test/graal'],
      ['${STANDALONE_HOME}/bin/npm', 'install'],
      ['${STANDALONE_HOME}/bin/npm', 'test'],
      ['cd', '../..'],
    ]) else []),
  },

  local gateCoverage = common.oraclejdk21.tools_java_home + {
    suiteimports+:: ['wasm', 'tools'],
    coverage_gate_args:: ['--jacoco-omit-excluded', '--jacoco-relativize-paths', '--jacoco-omit-src-gen', '--jacoco-format', 'lcov', '--jacocout', 'coverage'],
    run+: [
      ['mx', 'gate', '-B=--force-deprecation-as-warning', '-B=-A-J-Dtruffle.dsl.SuppressWarnings=truffle', '--strict-mode', '--tags', 'build,coverage'] + self.coverage_gate_args,
    ],
    teardown+: [
      ['mx', 'sversions', '--print-repositories', '--json', '|', 'coverage-uploader.py', '--associated-repos', '-'],
    ],
    timelimit: '1:00:00',
  },

  local checkoutNodeJsBenchmarks = {
    setup+: [
      ['git', 'clone', '--depth', '1', ['mx', 'urlrewrite', 'https://github.com/graalvm/nodejs-benchmarks.git'], '../nodejs-benchmarks'],
    ],
  },

  local auxEngineCache = {
    graalvmtests:: '../../graalvm-tests',
    run+: [
      ['python', self.graalvmtests + '/test.py', '-g', ['mx', '--quiet', '--no-warning', 'paths', '--output', 'GRAALNODEJS_NATIVE_STANDALONE'], '--print-revisions', '--keep-on-error', 'test/graal/aux-engine-cache'],
    ],
    timelimit: '1:00:00',
  },

  local testNode(suite, part='-r0,1', max_heap='4G') = gateTags('testnode') + {
    environment+:
      {NODE_SUITE: suite} +
      (if part != '' then {NODE_PART: part} else {}) +
      (if max_heap != '' then {NODE_MAX_HEAP: max_heap} else {}),
    timelimit: '1:30:00',
  },
  local maxHeapOnWindows(max_heap) = {
    environment+: if 'os' in super && super.os == 'windows' then {
      NODE_MAX_HEAP: max_heap,
    } else {},
  },

  // mx makeinnodeenv requires NASM on Windows.
  local makeinnodeenv_deps = {
    downloads+: if 'os' in super && super.os == 'windows' then {
      NASM: {name: 'nasm', version: '2.14.02', platformspecific: true},
    } else {},
    setup+: if 'os' in super && super.os == 'windows' then [
      ['set-export', 'PATH', '$PATH;$NASM'],
    ] else [],
  },

  local buildAddons = build + makeinnodeenv_deps + {
    run+: [
      ['mx', 'makeinnodeenv', 'build-addons'],
    ],
  },

  local buildNodeAPI = build + makeinnodeenv_deps + {
    run+: [
      ['mx', 'makeinnodeenv', 'build-node-api-tests'],
    ],
  },

  local buildJSNativeAPI = build + makeinnodeenv_deps + {
    run+: [
      ['mx', 'makeinnodeenv', 'build-js-native-api-tests'],
    ],
  },

  local parallelHttp2 = 'parallel/test-http2-.*',
  local parallelNoHttp2 = 'parallel/(?!test-http2-).*',

  local generateBuilds = ci.generateBuilds,
  local promoteToTarget = ci.promoteToTarget,
  local defaultToTarget = ci.defaultToTarget,
  local includePlatforms = ci.includePlatforms,
  local excludePlatforms = ci.excludePlatforms,
  local tier1 = ci.promoteToTier1(),
  local tier2 = ci.promoteToTier2(),

  // Style gates
  local styleBuilds = generateBuilds([
    graalNodeJs + common.gateStyleFullBuild                                                                           + tier2      + {name: 'style-fullbuild'}
  ], platforms=ci.styleGatePlatforms, defaultTarget=common.tier3),

  // Builds that should run on all supported platforms
  local testingBuilds = generateBuilds([
    graalNodeJs          + build            + defaultGateTags          + {dynamicimports+:: ['/wasm']}                             + {name: 'default'} +
      promoteToTarget(common.tier3, ci.tier3Platforms),

    graalNodeJs + vm_env + build            + gateVmSmokeTest                                                                 + ce + {name: 'graalvm-ce'} +
      promoteToTarget(common.tier3, [common.jdklatest + common.linux_amd64, common.jdklatest + common.darwin_aarch64, common.jdklatest + common.windows_amd64]),
    graalNodeJs + vm_env + build            + gateVmSmokeTest                                                                 + ee + {name: 'graalvm-ee'} +
      promoteToTarget(common.tier3, [ci.mainGatePlatform]),

    graalNodeJs + vm_env + build            + auxEngineCache                                                                  + ee + {name: 'aux-engine-cache'} +
      promoteToTarget(common.tier3, [ci.mainGatePlatform]) +
      excludePlatforms([common.windows_amd64]), # unsupported on windows
  ] +
  // mx makeinnodeenv requires Visual Studio build tools on Windows.
  [promoteToTarget(common.tier3, [ci.mainGatePlatform]) + excludePlatforms([common.windows_amd64]) + b for b in [
    graalNodeJs          + buildAddons      + testNode('addons',        max_heap='4G') + maxHeapOnWindows('512M')                  + {name: 'addons'},
    graalNodeJs          + buildNodeAPI     + testNode('node-api',      max_heap='4G') + maxHeapOnWindows('512M')                  + {name: 'node-api'},
    graalNodeJs          + buildJSNativeAPI + testNode('js-native-api', max_heap='4G') + maxHeapOnWindows('512M')                  + {name: 'js-native-api'},
  ]] +
  [promoteToTarget(common.tier3, [common.jdklatest + common.linux_amd64, common.jdklatest + common.windows_amd64]) + b for b in [
    graalNodeJs + vm_env + build            + testNode('async-hooks',   max_heap='4G') + maxHeapOnWindows('512M')                  + {name: 'async-hooks'},
    graalNodeJs + vm_env + build            + testNode('es-module',     max_heap='4G') + maxHeapOnWindows('512M')                  + {name: 'es-module'},
    # We run the `sequential` tests with a smaller heap because `test/sequential/test-child-process-pass-fd.js` starts 80 child processes.
    graalNodeJs + vm_env + build            + testNode('sequential',    max_heap='4G') + maxHeapOnWindows('512M')                  + {name: 'sequential'},
  ]] +
  [promoteToTarget(common.tier3, [ci.mainGatePlatform]) + b for b in [
    graalNodeJs + vm_env + build            + testNode(parallelNoHttp2, part='-r0,5', max_heap='4G')                               + {name: 'parallel-1'},
    graalNodeJs + vm_env + build            + testNode(parallelNoHttp2, part='-r1,5', max_heap='4G')                               + {name: 'parallel-2'},
    graalNodeJs + vm_env + build            + testNode(parallelNoHttp2, part='-r2,5', max_heap='4G')                               + {name: 'parallel-3'},
    graalNodeJs + vm_env + build            + testNode(parallelNoHttp2, part='-r3,5', max_heap='4G')                               + {name: 'parallel-4'},
    graalNodeJs + vm_env + build            + testNode(parallelNoHttp2, part='-r4,5', max_heap='4G')                               + {name: 'parallel-5'},

    graalNodeJs + vm_env + build            + testNode(parallelHttp2, max_heap='4G')                                               + {name: 'parallel-http2'} +
      promoteToTarget(common.postMerge, [ci.mainGatePlatform], override=true),
  ]], platforms=ci.jdklatestPlatforms, defaultTarget=common.weekly),

  // Builds that only need to run on one platform
  local otherBuilds = generateBuilds([
    # Note: weekly coverage is sync'ed with the graal repo (while ondemand is not).
    graalNodeJs + common.weekly    + gateCoverage                                                                                  + {name: 'coverage'},
    graalNodeJs + common.ondemand  + gateCoverage                                                                                  + {name: 'coverage'},

  ], platforms=[common.jdklatest + common.linux_amd64]),

  builds: styleBuilds + testingBuilds + otherBuilds,
}
