@echo off
setlocal enabledelayedexpansion

REM Build a Windows release bundle for Fiji Macro Bridge.
REM Run this from the repository root in a regular cmd.exe session.

set ROOT=%~dp0..
pushd "%ROOT%" >nul

set VENV_DIR=.venv-release
set RELEASE_DIR=release\windows-x64
set DIST_EXE=dist\fiji-mcp-server.exe
set JAR_FILE=plugin\target\fiji-macro-bridge-1.0.0.jar

if not exist "%VENV_DIR%\Scripts\python.exe" (
    py -3 -m venv "%VENV_DIR%" || goto :fail
)

call "%VENV_DIR%\Scripts\activate.bat" || goto :fail

python -m pip install --upgrade pip || goto :fail
python -m pip install -r requirements-build.txt || goto :fail

if exist build rmdir /s /q build
if exist dist rmdir /s /q dist
if exist "%RELEASE_DIR%" rmdir /s /q "%RELEASE_DIR%"

python -m pip freeze > requirements-lock.txt || goto :fail
pip-licenses --format=markdown --with-urls --with-license-file > PYTHON_BUNDLE_LICENSES.md || goto :fail

pyinstaller --clean fiji_mcp_macro.spec || goto :fail

if not exist "%JAR_FILE%" (
    pushd plugin >nul
    call mvn package || goto :fail_plugin
    popd >nul
)

if not exist "%DIST_EXE%" (
    echo Missing built executable: %DIST_EXE%
    goto :fail
)

if not exist "%JAR_FILE%" (
    echo Missing plugin jar: %JAR_FILE%
    goto :fail
)

mkdir "%RELEASE_DIR%" || goto :fail
copy /y "%DIST_EXE%" "%RELEASE_DIR%\fiji-mcp-server.exe" >nul || goto :fail
copy /y "%JAR_FILE%" "%RELEASE_DIR%\fiji-macro-bridge-1.0.0.jar" >nul || goto :fail
copy /y "LICENSE" "%RELEASE_DIR%\LICENSE.txt" >nul || goto :fail
copy /y "THIRD_PARTY_NOTICES.md" "%RELEASE_DIR%\THIRD_PARTY_NOTICES.md" >nul || goto :fail
copy /y "PYTHON_BUNDLE_LICENSES.md" "%RELEASE_DIR%\PYTHON_BUNDLE_LICENSES.md" >nul || goto :fail
copy /y "requirements-lock.txt" "%RELEASE_DIR%\requirements-lock.txt" >nul || goto :fail

echo.
echo Windows release bundle created in %RELEASE_DIR%
goto :done

:fail_plugin
popd >nul

:fail
echo.
echo Build failed.
exit /b 1

:done
popd >nul
endlocal
