#!/usr/bin/env python3
"""Write Orchard.xcodeproj from the source tree.

XcodeGen is not available on this Linux VM. The committed project.yml describes
the same targets; rerun this script after adding or removing files.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "Orchard.xcodeproj"


def uid(seed: str) -> str:
    return hashlib.sha1(seed.encode()).hexdigest()[:24].upper()


def quote(value: str) -> str:
    if value == "":
        return '""'
    if any(character in value for character in ' $()@=+;,"\''):
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    return value


class FileRef:
    def __init__(self, path: Path, kind: str):
        self.path = path
        self.kind = kind
        self.rel = path.relative_to(ROOT).as_posix()
        self.ref_id = uid("file:" + self.rel)


def collect_files() -> list[FileRef]:
    files: list[FileRef] = []
    for path in sorted((ROOT / "Orchard").rglob("*")):
        if not path.is_file():
            continue
        if ".xcassets/" in path.relative_to(ROOT).as_posix():
            continue
        if path.suffix == ".swift":
            files.append(FileRef(path, "source"))
        elif path.name == "catalogue.json":
            files.append(FileRef(path, "json"))
        elif path.name == "Info.plist":
            files.append(FileRef(path, "plist"))
    assets = ROOT / "Orchard" / "Resources" / "Assets.xcassets"
    files.append(FileRef(assets, "asset"))
    for path in sorted((ROOT / "OrchardTests").rglob("*.swift")):
        files.append(FileRef(path, "test"))
    return files


def group_tree(files: list[FileRef]) -> dict:
    """Nested dict of directories to file lists, keyed by posix relative dir."""
    tree: dict[str, list[FileRef]] = {}
    for item in files:
        parent = str(Path(item.rel).parent.as_posix())
        if parent == ".":
            parent = ""
        tree.setdefault(parent, []).append(item)
    return tree


def build_settings(extra: dict[str, str], debug: bool) -> dict[str, str]:
    settings = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CODE_SIGN_STYLE": "Automatic",
        "COPY_PHASE_STRIP": "NO",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": "HN9GXZ5384",
        "ENABLE_NS_ASSERTIONS": "YES" if debug else "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0" if debug else "s",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "MARKETING_VERSION": "1.0",
        "SDKROOT": "iphoneos",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "SUPPORTS_MACCATALYST": "NO",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": "1",
    }
    if debug:
        settings["DEBUG_INFORMATION_FORMAT"] = "dwarf"
        settings["ENABLE_TESTABILITY"] = "YES"
        settings["GCC_DYNAMIC_NO_PIC"] = "NO"
        settings["MTL_ENABLE_DEBUG_INFO"] = "INCLUDE_SOURCE"
        settings["ONLY_ACTIVE_ARCH"] = "YES"
        settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
        settings["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone"
    else:
        settings["DEBUG_INFORMATION_FORMAT"] = "dwarf-with-dsym"
        settings["ENABLE_NS_ASSERTIONS"] = "NO"
        settings["MTL_ENABLE_DEBUG_INFO"] = "NO"
        settings["SWIFT_COMPILATION_MODE"] = "wholemodule"
        settings["SWIFT_OPTIMIZATION_LEVEL"] = "-O"
        settings["VALIDATE_PRODUCT"] = "YES"
    settings.update(extra)
    return settings


def emit_settings(settings: dict[str, str], indent: str) -> str:
    lines = []
    for key in sorted(settings):
        lines.append(f"{indent}{key} = {quote(settings[key])};")
    return "\n".join(lines)


def main() -> None:
    files = collect_files()
    dir_set = {""}
    for item in files:
        parent = Path(item.rel).parent
        parts = parent.parts
        for index in range(len(parts)):
            dir_set.add(Path(*parts[: index + 1]).as_posix())
    dirs = sorted(dir_set)

    app_sources = [item for item in files if item.kind == "source"]
    test_sources = [item for item in files if item.kind == "test"]
    json_file = next(item for item in files if item.kind == "json")
    asset_file = next(item for item in files if item.kind == "asset")

    def build_id(seed: str) -> str:
        return uid("build:" + seed)

    app_source_builds = {item.rel: build_id("app-src:" + item.rel) for item in app_sources}
    test_source_builds = {item.rel: build_id("test-src:" + item.rel) for item in test_sources}
    app_json_build = build_id("app-json")
    test_json_build = build_id("test-json")
    app_asset_build = build_id("app-asset")

    group_ids = {directory: uid("group:" + directory) for directory in dirs}
    root_group = uid("group:root")
    products_group = uid("group:products")
    frameworks_group = uid("group:frameworks")

    project_id = uid("project")
    app_target = uid("target:app")
    test_target = uid("target:test")
    app_product = uid("product:app")
    test_product = uid("product:test")
    app_sources_phase = uid("phase:app-sources")
    app_resources_phase = uid("phase:app-resources")
    app_frameworks_phase = uid("phase:app-frameworks")
    test_sources_phase = uid("phase:test-sources")
    test_resources_phase = uid("phase:test-resources")
    test_frameworks_phase = uid("phase:test-frameworks")
    proxy_id = uid("proxy")
    dependency_id = uid("dependency")
    xctest_ref = uid("file:XCTest")
    xctest_build = uid("build:XCTest")

    configs = {
        "project-debug": uid("config:project-debug"),
        "project-release": uid("config:project-release"),
        "app-debug": uid("config:app-debug"),
        "app-release": uid("config:app-release"),
        "test-debug": uid("config:test-debug"),
        "test-release": uid("config:test-release"),
    }
    lists = {
        "project": uid("list:project"),
        "app": uid("list:app"),
        "test": uid("list:test"),
    }

    lines: list[str] = []
    a = lines.append
    a("// !$*UTF8*$!")
    a("{")
    a("\tarchiveVersion = 1;")
    a("\tclasses = {")
    a("\t};")
    a("\tobjectVersion = 56;")
    a("\tobjects = {")
    a("")
    a("/* Begin PBXBuildFile section */")
    for item in app_sources:
        a(f"\t\t{app_source_builds[item.rel]} /* {item.path.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {item.ref_id} /* {item.path.name} */; }};")
    for item in test_sources:
        a(f"\t\t{test_source_builds[item.rel]} /* {item.path.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {item.ref_id} /* {item.path.name} */; }};")
    a(f"\t\t{app_json_build} /* catalogue.json in Resources */ = {{isa = PBXBuildFile; fileRef = {json_file.ref_id} /* catalogue.json */; }};")
    a(f"\t\t{test_json_build} /* catalogue.json in Resources */ = {{isa = PBXBuildFile; fileRef = {json_file.ref_id} /* catalogue.json */; }};")
    a(f"\t\t{app_asset_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {asset_file.ref_id} /* Assets.xcassets */; }};")
    a(f"\t\t{xctest_build} /* XCTest.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {xctest_ref} /* XCTest.framework */; }};")
    a("/* End PBXBuildFile section */")
    a("")
    a("/* Begin PBXContainerItemProxy section */")
    a(f"\t\t{proxy_id} /* PBXContainerItemProxy */ = {{")
    a("\t\t\tisa = PBXContainerItemProxy;")
    a(f"\t\t\tcontainerPortal = {project_id} /* Project object */;")
    a("\t\t\tproxyType = 1;")
    a(f"\t\t\tremoteGlobalIDString = {app_target};")
    a("\t\t\tremoteInfo = Orchard;")
    a("\t\t};")
    a("/* End PBXContainerItemProxy section */")
    a("")
    a("/* Begin PBXFileReference section */")
    for item in files:
        name = item.path.name
        if item.kind == "source" or item.kind == "test":
            file_type = "sourcecode.swift"
        elif item.kind == "json":
            file_type = "text.json"
        elif item.kind == "plist":
            file_type = "text.plist.xml"
        else:
            file_type = "folder.assetcatalog"
        a(f"\t\t{item.ref_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type}; path = {quote(name)}; sourceTree = \"<group>\"; }};")
    a(f"\t\t{app_product} /* Orchard.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Orchard.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    a(f"\t\t{test_product} /* OrchardTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = OrchardTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
    a(f"\t\t{xctest_ref} /* XCTest.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = XCTest.framework; path = XCTest.framework; sourceTree = SDKROOT; }};")
    a("/* End PBXFileReference section */")
    a("")
    a("/* Begin PBXFrameworksBuildPhase section */")
    a(f"\t\t{app_frameworks_phase} /* Frameworks */ = {{")
    a("\t\t\tisa = PBXFrameworksBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a("\t\t\tfiles = (")
    a("\t\t\t);")
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a(f"\t\t{test_frameworks_phase} /* Frameworks */ = {{")
    a("\t\t\tisa = PBXFrameworksBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a("\t\t\tfiles = (")
    a(f"\t\t\t\t{xctest_build} /* XCTest.framework in Frameworks */,")
    a("\t\t\t);")
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a("/* End PBXFrameworksBuildPhase section */")
    a("")

    children_of: dict[str, list[str]] = {directory: [] for directory in dirs}

    def ensure_dir(directory: str) -> None:
        if directory in children_of:
            return
        children_of[directory] = []

    for directory in list(dirs):
        if directory == "":
            continue
        parent = str(Path(directory).parent.as_posix())
        if parent == ".":
            parent = ""
        ensure_dir(parent)
        child = group_ids[directory]
        if child not in children_of[parent]:
            children_of[parent].append(child)

    files_in: dict[str, list[FileRef]] = {}
    for item in files:
        parent = str(Path(item.rel).parent.as_posix())
        if parent == ".":
            parent = ""
        files_in.setdefault(parent, []).append(item)

    a("/* Begin PBXGroup section */")
    for directory in sorted(children_of):
        name = Path(directory).name if directory else "Orchard-root-unused"
        if directory == "":
            continue
        a(f"\t\t{group_ids[directory]} /* {name} */ = {{")
        a("\t\t\tisa = PBXGroup;")
        a("\t\t\tchildren = (")
        for child in children_of[directory]:
            child_name = next(path.name for path, group in ((Path(d), group_ids[d]) for d in group_ids) if group == child)
            a(f"\t\t\t\t{child} /* {child_name} */,")
        for item in sorted(files_in.get(directory, []), key=lambda entry: entry.path.name):
            a(f"\t\t\t\t{item.ref_id} /* {item.path.name} */,")
        a("\t\t\t);")
        a(f"\t\t\tpath = {quote(name)};")
        a('\t\t\tsourceTree = "<group>";')
        a("\t\t};")

    a(f"\t\t{frameworks_group} /* Frameworks */ = {{")
    a("\t\t\tisa = PBXGroup;")
    a("\t\t\tchildren = (")
    a(f"\t\t\t\t{xctest_ref} /* XCTest.framework */,")
    a("\t\t\t);")
    a("\t\t\tname = Frameworks;")
    a('\t\t\tsourceTree = "<group>";')
    a("\t\t};")
    a(f"\t\t{products_group} /* Products */ = {{")
    a("\t\t\tisa = PBXGroup;")
    a("\t\t\tchildren = (")
    a(f"\t\t\t\t{app_product} /* Orchard.app */,")
    a(f"\t\t\t\t{test_product} /* OrchardTests.xctest */,")
    a("\t\t\t);")
    a("\t\t\tname = Products;")
    a('\t\t\tsourceTree = "<group>";')
    a("\t\t};")
    a(f"\t\t{root_group} = {{")
    a("\t\t\tisa = PBXGroup;")
    a("\t\t\tchildren = (")
    a(f"\t\t\t\t{group_ids['Orchard']} /* Orchard */,")
    a(f"\t\t\t\t{group_ids['OrchardTests']} /* OrchardTests */,")
    a(f"\t\t\t\t{frameworks_group} /* Frameworks */,")
    a(f"\t\t\t\t{products_group} /* Products */,")
    a("\t\t\t);")
    a('\t\t\tsourceTree = "<group>";')
    a("\t\t};")
    a("/* End PBXGroup section */")
    a("")
    a("/* Begin PBXNativeTarget section */")
    a(f"\t\t{app_target} /* Orchard */ = {{")
    a("\t\t\tisa = PBXNativeTarget;")
    a(f"\t\t\tbuildConfigurationList = {lists['app']} /* Build configuration list for PBXNativeTarget \"Orchard\" */;")
    a("\t\t\tbuildPhases = (")
    a(f"\t\t\t\t{app_sources_phase} /* Sources */,")
    a(f"\t\t\t\t{app_frameworks_phase} /* Frameworks */,")
    a(f"\t\t\t\t{app_resources_phase} /* Resources */,")
    a("\t\t\t);")
    a("\t\t\tbuildRules = (")
    a("\t\t\t);")
    a("\t\t\tdependencies = (")
    a("\t\t\t);")
    a("\t\t\tname = Orchard;")
    a(f"\t\t\tproductName = Orchard;")
    a(f"\t\t\tproductReference = {app_product} /* Orchard.app */;")
    a("\t\t\tproductType = \"com.apple.product-type.application\";")
    a("\t\t};")
    a(f"\t\t{test_target} /* OrchardTests */ = {{")
    a("\t\t\tisa = PBXNativeTarget;")
    a(f"\t\t\tbuildConfigurationList = {lists['test']} /* Build configuration list for PBXNativeTarget \"OrchardTests\" */;")
    a("\t\t\tbuildPhases = (")
    a(f"\t\t\t\t{test_sources_phase} /* Sources */,")
    a(f"\t\t\t\t{test_frameworks_phase} /* Frameworks */,")
    a(f"\t\t\t\t{test_resources_phase} /* Resources */,")
    a("\t\t\t);")
    a("\t\t\tbuildRules = (")
    a("\t\t\t);")
    a("\t\t\tdependencies = (")
    a(f"\t\t\t\t{dependency_id} /* PBXTargetDependency */,")
    a("\t\t\t);")
    a("\t\t\tname = OrchardTests;")
    a("\t\t\tproductName = OrchardTests;")
    a(f"\t\t\tproductReference = {test_product} /* OrchardTests.xctest */;")
    a("\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";")
    a("\t\t};")
    a("/* End PBXNativeTarget section */")
    a("")
    a("/* Begin PBXProject section */")
    a(f"\t\t{project_id} /* Project object */ = {{")
    a("\t\t\tisa = PBXProject;")
    a("\t\t\tattributes = {")
    a("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    a("\t\t\t\tLastSwiftUpdateCheck = 1500;")
    a("\t\t\t\tLastUpgradeCheck = 1500;")
    a("\t\t\t\tTargetAttributes = {")
    a(f"\t\t\t\t\t{app_target} = {{")
    a("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
    a("\t\t\t\t\t\tDevelopmentTeam = HN9GXZ5384;")
    a("\t\t\t\t\t\tProvisioningStyle = Automatic;")
    a("\t\t\t\t\t};")
    a(f"\t\t\t\t\t{test_target} = {{")
    a("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
    a("\t\t\t\t\t\tDevelopmentTeam = HN9GXZ5384;")
    a("\t\t\t\t\t\tProvisioningStyle = Automatic;")
    a(f"\t\t\t\t\t\tTestTargetID = {app_target};")
    a("\t\t\t\t\t};")
    a("\t\t\t\t};")
    a("\t\t\t};")
    a(f"\t\t\tbuildConfigurationList = {lists['project']} /* Build configuration list for PBXProject \"Orchard\" */;")
    a('\t\t\tcompatibilityVersion = "Xcode 14.0";')
    a("\t\t\tdevelopmentRegion = en;")
    a("\t\t\thasScannedForEncodings = 0;")
    a("\t\t\tknownRegions = (")
    a("\t\t\t\ten,")
    a("\t\t\t\tBase,")
    a("\t\t\t);")
    a(f"\t\t\tmainGroup = {root_group};")
    a(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
    a('\t\t\tprojectDirPath = "";')
    a('\t\t\tprojectRoot = "";')
    a("\t\t\ttargets = (")
    a(f"\t\t\t\t{app_target} /* Orchard */,")
    a(f"\t\t\t\t{test_target} /* OrchardTests */,")
    a("\t\t\t);")
    a("\t\t};")
    a("/* End PBXProject section */")
    a("")
    a("/* Begin PBXResourcesBuildPhase section */")
    a(f"\t\t{app_resources_phase} /* Resources */ = {{")
    a("\t\t\tisa = PBXResourcesBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a("\t\t\tfiles = (")
    a(f"\t\t\t\t{app_json_build} /* catalogue.json in Resources */,")
    a(f"\t\t\t\t{app_asset_build} /* Assets.xcassets in Resources */,")
    a("\t\t\t);")
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a(f"\t\t{test_resources_phase} /* Resources */ = {{")
    a("\t\t\tisa = PBXResourcesBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a("\t\t\tfiles = (")
    a(f"\t\t\t\t{test_json_build} /* catalogue.json in Resources */,")
    a("\t\t\t);")
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a("/* End PBXResourcesBuildPhase section */")
    a("")
    a("/* Begin PBXSourcesBuildPhase section */")
    a(f"\t\t{app_sources_phase} /* Sources */ = {{")
    a("\t\t\tisa = PBXSourcesBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a("\t\t\tfiles = (")
    for item in app_sources:
        a(f"\t\t\t\t{app_source_builds[item.rel]} /* {item.path.name} in Sources */,")
    a("\t\t\t);")
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a(f"\t\t{test_sources_phase} /* Sources */ = {{")
    a("\t\t\tisa = PBXSourcesBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a("\t\t\tfiles = (")
    for item in test_sources:
        a(f"\t\t\t\t{test_source_builds[item.rel]} /* {item.path.name} in Sources */,")
    a("\t\t\t);")
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a("/* End PBXSourcesBuildPhase section */")
    a("")
    a("/* Begin PBXTargetDependency section */")
    a(f"\t\t{dependency_id} /* PBXTargetDependency */ = {{")
    a("\t\t\tisa = PBXTargetDependency;")
    a(f"\t\t\ttarget = {app_target} /* Orchard */;")
    a(f"\t\t\ttargetProxy = {proxy_id} /* PBXContainerItemProxy */;")
    a("\t\t};")
    a("/* End PBXTargetDependency section */")
    a("")

    app_extra = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CODE_SIGN_STYLE": "Automatic",
        "DEVELOPMENT_TEAM": "HN9GXZ5384",
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "Orchard/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.chrismartin.orchard",
        "PRODUCT_NAME": "Orchard",
    }
    test_extra = {
        "BUNDLE_LOADER": "$(TEST_HOST)",
        "CODE_SIGN_STYLE": "Automatic",
        "DEVELOPMENT_TEAM": "HN9GXZ5384",
        "FRAMEWORK_SEARCH_PATHS": "$(inherited) $(PLATFORM_DIR)/Developer/Library/Frameworks",
        "GENERATE_INFOPLIST_FILE": "YES",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.chrismartin.orchard.tests",
        "PRODUCT_NAME": "OrchardTests",
        "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Orchard.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Orchard",
    }

    def config_block(config_id: str, name: str, settings: dict[str, str]) -> None:
        a(f"\t\t{config_id} /* {name} */ = {{")
        a("\t\t\tisa = XCBuildConfiguration;")
        a("\t\t\tbuildSettings = {")
        a(emit_settings(settings, "\t\t\t\t"))
        a("\t\t\t};")
        a(f"\t\t\tname = {name};")
        a("\t\t};")

    a("/* Begin XCBuildConfiguration section */")
    config_block(configs["project-debug"], "Debug", build_settings({}, True))
    config_block(configs["project-release"], "Release", build_settings({}, False))
    config_block(configs["app-debug"], "Debug", build_settings(app_extra, True))
    config_block(configs["app-release"], "Release", build_settings(app_extra, False))
    config_block(configs["test-debug"], "Debug", build_settings(test_extra, True))
    config_block(configs["test-release"], "Release", build_settings(test_extra, False))
    a("/* End XCBuildConfiguration section */")
    a("")
    a("/* Begin XCConfigurationList section */")
    for list_id, name, debug_id, release_id in (
        (lists["project"], "PBXProject \"Orchard\"", configs["project-debug"], configs["project-release"]),
        (lists["app"], "PBXNativeTarget \"Orchard\"", configs["app-debug"], configs["app-release"]),
        (lists["test"], "PBXNativeTarget \"OrchardTests\"", configs["test-debug"], configs["test-release"]),
    ):
        a(f"\t\t{list_id} /* Build configuration list for {name} */ = {{")
        a("\t\t\tisa = XCConfigurationList;")
        a("\t\t\tbuildConfigurations = (")
        a(f"\t\t\t\t{debug_id} /* Debug */,")
        a(f"\t\t\t\t{release_id} /* Release */,")
        a("\t\t\t);")
        a("\t\t\tdefaultConfigurationIsVisible = 0;")
        a("\t\t\tdefaultConfigurationName = Release;")
        a("\t\t};")
    a("/* End XCConfigurationList section */")
    a("\t};")
    a(f"\trootObject = {project_id} /* Project object */;")
    a("}")
    a("")

    pbx = PROJECT / "project.pbxproj"
    pbx.parent.mkdir(parents=True, exist_ok=True)
    pbx.write_text("\n".join(lines), encoding="utf-8")

    scheme_dir = PROJECT / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target}"
               BuildableName = "Orchard.app"
               BlueprintName = "Orchard"
               ReferencedContainer = "container:Orchard.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO"
            parallelizable = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{test_target}"
               BuildableName = "OrchardTests.xctest"
               BlueprintName = "OrchardTests"
               ReferencedContainer = "container:Orchard.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableReference
         BuildableIdentifier = "primary"
         BlueprintIdentifier = "{app_target}"
         BuildableName = "Orchard.app"
         BlueprintName = "Orchard"
         ReferencedContainer = "container:Orchard.xcodeproj">
      </BuildableReference>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableReference
         BuildableIdentifier = "primary"
         BlueprintIdentifier = "{app_target}"
         BuildableName = "Orchard.app"
         BlueprintName = "Orchard"
         ReferencedContainer = "container:Orchard.xcodeproj">
      </BuildableReference>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    (scheme_dir / "Orchard.xcscheme").write_text(scheme, encoding="utf-8")
    workspace = PROJECT / "project.xcworkspace"
    workspace.mkdir(parents=True, exist_ok=True)
    (workspace / "contents.xcworkspacedata").write_text(
        """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
""",
        encoding="utf-8",
    )
    print(f"Wrote {pbx} with {len(app_sources)} app sources and {len(test_sources)} tests")


if __name__ == "__main__":
    main()
