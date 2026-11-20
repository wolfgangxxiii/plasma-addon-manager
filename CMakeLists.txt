cmake_minimum_required(VERSION 3.24)
project(PlasmaAddonManager VERSION 0.4.5 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

include(GNUInstallDirs)
find_package(ECM 6.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(ECMFindQmlModule)
ecm_find_qmlmodule(org.kde.kirigami REQUIRED)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)
find_package(KF6 REQUIRED COMPONENTS QQC2DesktopStyle ColorScheme Config)

qt_add_executable(plasma-addon-manager
    src/main.cpp
    src/DesktopIconIntegration.cpp
    src/DesktopIconIntegration.h
    src/BackendBridge.cpp
    src/BackendBridge.h
    src/ThemeBridge.cpp
    src/ThemeBridge.h
    resources.qrc
)

set_target_properties(plasma-addon-manager PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
target_link_libraries(plasma-addon-manager PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2
    KF6::ColorScheme KF6::ConfigCore
)

find_program(CARGO_EXECUTABLE cargo REQUIRED)
set(BACKEND_MANIFEST "${CMAKE_SOURCE_DIR}/backend/Cargo.toml")
set(BACKEND_OUTPUT "${CMAKE_BINARY_DIR}/bin/plasma-addon-helper")
set(AGENT_OUTPUT "${CMAKE_BINARY_DIR}/bin/plasma-addon-manager-agent")

add_custom_target(plasma-addon-helper-build ALL
    COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_BINARY_DIR}/bin"
    COMMAND ${CMAKE_COMMAND} -E env
        "CARGO_TARGET_DIR=${CMAKE_BINARY_DIR}/cargo-target"
        ${CARGO_EXECUTABLE} build --release --manifest-path "${BACKEND_MANIFEST}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_BINARY_DIR}/cargo-target/release/plasma-addon-helper"
        "${BACKEND_OUTPUT}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_BINARY_DIR}/cargo-target/release/plasma-addon-manager-agent"
        "${AGENT_OUTPUT}"
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    COMMENT "Building the Rust helper"
    VERBATIM
)
add_dependencies(plasma-addon-manager plasma-addon-helper-build)

install(TARGETS plasma-addon-manager RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(PROGRAMS "${BACKEND_OUTPUT}"
    DESTINATION "${CMAKE_INSTALL_LIBEXECDIR}/plasma-addon-manager")
install(PROGRAMS "${AGENT_OUTPUT}"
    DESTINATION "${CMAKE_INSTALL_LIBEXECDIR}/plasma-addon-manager")
install(FILES packaging/io.github.wolfgangxxiii.PlasmaAddonManager.desktop
    DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES assets/plasma-addon-manager-icon-v2.svg
    DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps
    RENAME io.github.wolfgangxxiii.PlasmaAddonManager.svg)
foreach(pam_icon_size 16 32 48 64 128 256 512)
    install(FILES "assets/plasma-addon-manager-icon-${pam_icon_size}.png"
        DESTINATION "${CMAKE_INSTALL_DATADIR}/icons/hicolor/${pam_icon_size}x${pam_icon_size}/apps"
        RENAME io.github.wolfgangxxiii.PlasmaAddonManager.png)
endforeach()
install(FILES packaging/io.github.wolfgangxxiii.PlasmaAddonManager.metainfo.xml
    DESTINATION ${CMAKE_INSTALL_DATADIR}/metainfo)
