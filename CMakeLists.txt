cmake_minimum_required(VERSION 3.21)
project(KeenRouterManager VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Qt6 6.5 REQUIRED COMPONENTS Widgets Network Svg)
qt_standard_project_setup()

set(APP_SOURCES
    src/main.cpp
    src/core/Models.h
    src/core/ConfigStore.h
    src/core/ConfigStore.cpp
    src/core/Localizer.h
    src/core/Localizer.cpp
    src/core/KeeneticClient.h
    src/core/KeeneticClient.cpp
    src/ui/AddEditRouterDialog.h
    src/ui/AddEditRouterDialog.cpp
    src/ui/Icons.h
    src/ui/Icons.cpp
    src/ui/pages/MePage.h
    src/ui/pages/MePage.cpp
    src/ui/pages/VpnPage.h
    src/ui/pages/VpnPage.cpp
    src/ui/pages/ClientsPage.h
    src/ui/pages/ClientsPage.cpp
    src/ui/pages/SettingsPage.h
    src/ui/pages/SettingsPage.cpp
    src/ui/MainWindow.h
    src/ui/MainWindow.cpp
)

# Генерируем version.h из version.h.in
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/src/version.h.in ${CMAKE_CURRENT_BINARY_DIR}/src/version.h @ONLY)

# Добавляем сгенерированный version.h в исходники
list(APPEND APP_SOURCES ${CMAKE_CURRENT_BINARY_DIR}/src/version.h)

qt_add_resources(APP_RESOURCES resources/icons.qrc)

if(APPLE)
    list(APPEND APP_SOURCES resources/app.icns)
    set_source_files_properties(resources/app.icns PROPERTIES MACOSX_PACKAGE_LOCATION "Resources")
endif()

qt_add_executable(KeenRouterManager
    MANUAL_FINALIZATION
    ${APP_SOURCES}
    ${APP_RESOURCES}
)

set_target_properties(KeenRouterManager PROPERTIES
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

if(APPLE)
    set_target_properties(KeenRouterManager PROPERTIES
        MACOSX_BUNDLE_ICON_FILE app.icns
    )
endif()

target_link_libraries(KeenRouterManager PRIVATE Qt6::Widgets Qt6::Network Qt6::Svg)

target_compile_definitions(KeenRouterManager PRIVATE
    QT_NO_KEYWORDS
)

if(APPLE)
    add_custom_command(TARGET KeenRouterManager POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_DIR:KeenRouterManager>/Contents/Resources"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/resources/language_packs.json"
            "$<TARGET_BUNDLE_DIR:KeenRouterManager>/Contents/Resources/language_packs.json"
    )
else()
    add_custom_command(TARGET KeenRouterManager POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/resources/language_packs.json"
            "$<TARGET_FILE_DIR:KeenRouterManager>/language_packs.json"
    )
endif()

install(TARGETS KeenRouterManager
    BUNDLE DESTINATION .
    RUNTIME DESTINATION bin
)

if(APPLE)
    install(FILES resources/language_packs.json
        DESTINATION KeenRouterManager.app/Contents/Resources)
else()
    install(FILES resources/language_packs.json
        DESTINATION bin)
endif()

qt_finalize_executable(KeenRouterManager)
