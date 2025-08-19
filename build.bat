@echo off
setlocal EnableDelayedExpansion

REM =================================================================
REM 1. SETTINGS
REM =================================================================
set CURL_VERSION=8.15.0
set DOWNLOAD_URL=https://curl.se/download/curl-%CURL_VERSION%.zip
set EXTRACTED_FOLDER_NAME=curl-%CURL_VERSION%

REM =================================================================
REM 2. FIND VISUAL STUDIO (HYBRID METHOD)
REM =================================================================
echo Looking for Visual Studio...

REM --- Modern Method (Primary) ---
set "VSWHERE_PATH=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if exist "%VSWHERE_PATH%" (
    echo Found vswhere, using modern detection method...
    for /f "usebackq tokens=*" %%i in (`"%VSWHERE_PATH%" -latest -property installationPath`) do (set "VS_INSTALL_PATH=%%i")
    for /f "usebackq delims=. tokens=1" %%v in (`"%VSWHERE_PATH%" -latest -property installationVersion`) do (set VCVERSION=%%v)
    
    if defined VS_INSTALL_PATH (
        set "VCVARSALL_PATH=%VS_INSTALL_PATH%\VC\Auxiliary\Build\vcvarsall.bat"
        if exist "%VCVARSALL_PATH%" (
            echo Found Visual Studio v%VCVERSION% at: %VS_INSTALL_PATH%
            goto FoundCompiler
        )
    )
)

REM --- Legacy Method (Fallback) ---
echo vswhere not found or failed. Falling back to legacy path checking...
set PROGFILES=%ProgramFiles%
if not "%ProgramFiles(x86)%" == "" set PROGFILES=%ProgramFiles(x86)%

REM Check for Visual Studio 2019
set VCVARSALL_PATH="%PROGFILES%\Microsoft Visual Studio\2019\Professional\VC\Auxiliary\Build\vcvarsall.bat"
if exist %VCVARSALL_PATH% ( set VCVERSION=16 & echo Found VS 2019 & goto FoundCompiler )

REM Check for Visual Studio 2017
set VCVARSALL_PATH="%PROGFILES%\Microsoft Visual Studio\2017\Professional\VC\Auxiliary\Build\vcvarsall.bat"
if exist %VCVARSALL_PATH% ( set VCVERSION=15 & echo Found VS 2017 & goto FoundCompiler )
set VCVARSALL_PATH="%PROGFILES%\Microsoft Visual Studio\2017\Community\VC\Auxiliary\Build\vcvarsall.bat"
if exist %VCVARSALL_PATH% ( set VCVERSION=15 & echo Found VS 2017 Community & goto FoundCompiler )

REM Check for Visual Studio 2015
set VCVARSALL_PATH="%PROGFILES%\Microsoft Visual Studio 14.0\VC\vcvarsall.bat"
if exist %VCVARSALL_PATH% ( set VCVERSION=14 & echo Found VS 2015 & goto FoundCompiler )


echo Error: No suitable Visual Studio installation found.
goto end

:FoundCompiler
echo Using compiler version VC%VCVERSION%

REM Set paths to your utilities
set "ROOT_DIR=%CD%"
set "RM=%ROOT_DIR%\bin\unxutils\rm.exe"
set "CP=%ROOT_DIR%\bin\unxutils\cp.exe"
set "MKDIR=%ROOT_DIR%\bin\unxutils\mkdir.exe"
set "SEVEN_ZIP=%ROOT_DIR%\bin\7-zip\7za.exe"

if not exist "%SEVEN_ZIP%" (echo Error: 7za.exe not found. & goto end)


REM =================================================================
REM 3. PREPARATION
REM =================================================================
echo Cleaning up old files...
%RM% -rf tmp_libcurl
%RM% -rf third-party
%RM% -f curl.zip

echo Downloading curl %CURL_VERSION%...
set "LOCAL_CURL_PATH=%ROOT_DIR%\curl.zip"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%LOCAL_CURL_PATH%'"
if %ERRORLEVEL% neq 0 (echo Failed to download curl.zip. & goto end)

echo Extracting curl.zip...
%SEVEN_ZIP% x curl.zip -y -otmp_libcurl > NUL
if %ERRORLEVEL% neq 0 (echo Failed to extract curl.zip. & goto end)

cd tmp_libcurl\%EXTRACTED_FOLDER_NAME%\winbuild

REM =================================================================
REM 4. BUILD THE LIBRARY
REM =================================================================
set "RTLIBCFG="
if /I "%1"=="-static" (
    set "RTLIBCFG=RTLIBCFG=static"
    echo Building with STATIC C-Runtime (/MT, /MTd)
) else (
    echo Building with DYNAMIC C-Runtime (/MD, /MDd)
)

set "DEPRECATE_ACK=WINBUILD_ACKNOWLEDGE_DEPRECATED=yes"

echo Building x86 versions...
call %VCVARSALL_PATH% x86
echo  - Compiling static-debug-x86...
nmake /f Makefile.vc mode=static VC=%VCVERSION% DEBUG=yes MACHINE=x86 %RTLIBCFG% %DEPRECATE_ACK%
if %ERRORLEVEL% neq 0 (echo NMAKE FAILED! & goto end)
echo  - Compiling static-release-x86...
nmake /f Makefile.vc mode=static VC=%VCVERSION% DEBUG=no MACHINE=x86 %RTLIBCFG% %DEPRECATE_ACK%
if %ERRORLEVEL% neq 0 (echo NMAKE FAILED! & goto end)

echo Building x64 versions...
call %VCVARSALL_PATH% x64
echo  - Compiling static-debug-x64...
nmake /f Makefile.vc mode=static VC=%VCVERSION% DEBUG=yes MACHINE=x64 %RTLIBCFG% %DEPRECATE_ACK%
if %ERRORLEVEL% neq 0 (echo NMAKE FAILED! & goto end)
echo  - Compiling static-release-x64...
nmake /f Makefile.vc mode=static VC=%VCVERSION% DEBUG=no MACHINE=x64 %RTLIBCFG% %DEPRECATE_ACK%
if %ERRORLEVEL% neq 0 (echo NMAKE FAILED! & goto end)

REM =================================================================
REM 5. COPY BUILD ARTIFACTS
REM =================================================================
echo Copying build artifacts...
set "BUILD_DIR_BASE=%ROOT_DIR%\tmp_libcurl\%EXTRACTED_FOLDER_NAME%\builds"
set "DEST_DIR=%ROOT_DIR%\third-party\libcurl"

:CopyFiles
set "ARCH=%1" & set "CONFIG=%2" & set "LINK_TYPE=%3"
set "SRC_DIR_SUFFIX=libcurl-vc%VCVERSION%-%ARCH%-%CONFIG%-%LINK_TYPE%-ipv6-sspi-winssl"
set "SRC_DIR=%BUILD_DIR_BASE%\%SRC_DIR_SUFFIX%"
set "DEST_SUBDIR=%DEST_DIR%\lib\%LINK_TYPE%-%CONFIG%-%ARCH%"
echo  - Copying from %SRC_DIR_SUFFIX%
%MKDIR% -p "%DEST_SUBDIR%"
%CP% "%SRC_DIR%\lib\*.lib" "%DEST_SUBDIR%"
goto:eof

call:CopyFiles x86 debug static
call:CopyFiles x86 release static
call:CopyFiles x64 debug static
call:CopyFiles x64 release static

echo  - Copying include files...
%MKDIR% -p "%DEST_DIR%\include"
%CP% -r "%ROOT_DIR%\tmp_libcurl\%EXTRACTED_FOLDER_NAME%\include\curl" "%DEST_DIR%\include"

REM =================================================================
REM 6. CLEANUP
REM =================================================================
echo Cleaning up temporary files...
cd %ROOT_DIR%
%RM% -rf tmp_libcurl
%RM% -f curl.zip

:end
echo Done.
exit /b