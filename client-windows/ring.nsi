!define APPNAME "Ring"
!define COMPANYNAME "Savoir-Faire Linux"
!define DESCRIPTION "The Ring client for Windows"
# These three must be integers
!define VERSIONMAJOR 1
!define VERSIONMINOR 0
!define VERSIONBUILD 0
# These will be displayed by the "Click here for support information" link in "Add/Remove Programs"
# It is possible to use "mailto:" links in here to open the email client
!define HELPURL "https://projects.savoirfairelinux.com/projects/ring/wiki" # "Support Information" link
!define UPDATEURL "http://ring.cx/en/documentation/windows-installation" # "Product Updates" link
!define ABOUTURL "http://ring.cx/en#about" # "Publisher" link

!include "MUI2.nsh"

!define MUI_WELCOMEPAGE
!define MUI_LICENSEPAGE
!define MUI_DIRECTORYPAGE
!define MUI_ABORTWARNING
!define MUI_UNINSTALLER
!define MUI_UNCONFIRMPAGE
   !define MUI_FINISHPAGE_RUN
   !define MUI_FINISHPAGE_RUN_TEXT "Launch Ring"
   !define MUI_FINISHPAGE_RUN_FUNCTION "LaunchLink"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "License.rtf"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

RequestExecutionLevel admin ;Require admin rights on NT6+ (When UAC is turned on)

InstallDir "$PROGRAMFILES\${COMPANYNAME}\${APPNAME}"

# This will be in the installer/uninstaller's title bar
Name "${COMPANYNAME} - ${APPNAME}"

outFile "ring-windows-nightly.exe"

!include LogicLib.nsh
!include "FileFunc.nsh"

!macro VerifyUserIsAdmin
UserInfo::GetAccountType
pop $0
${If} $0 != "admin" ;Require admin rights on NT4+
        messageBox mb_iconstop "Administrator rights required!"
        setErrorLevel 740 ;ERROR_ELEVATION_REQUIRED
        quit
${EndIf}
!macroend

function .onInit
        setShellVarContext all
        !insertmacro VerifyUserIsAdmin
functionEnd

Function LaunchLink
  ExecShell "" "$DESKTOP\Ring.lnk"
FunctionEnd

section "install"
        # Files for the install directory - to build the installer, these should be in the same directory as the install script (this file)
        setOutPath $INSTDIR
        # Files added here should be removed by the uninstaller (see section "uninstall")
        file "Ring.exe"
        file "ring.ico"
        file *.dll
        setOutPath $INSTDIR\platforms
        file platforms/*
        setOutPath $INSTDIR\imageformats
        file imageformats/*
        setOutPath $INSTDIR\ringtones
        file ringtones/*
        setOutPath $INSTDIR\share\ring\translations
        file share/ring/translations/*
        setOutPath $INSTDIR\share\libringclient\translations
        file share/libringclient/translations/*

        # Uninstaller - See function un.onInit and section "uninstall" for configuration
        writeUninstaller "$INSTDIR\uninstall.exe"

        SetOutPath $INSTDIR
        #Desktop
        CreateShortCut "$DESKTOP\Ring.lnk" "$INSTDIR\Ring.exe" ""

        # Start Menu
        createDirectory "$SMPROGRAMS\${COMPANYNAME}"
        createShortCut "$SMPROGRAMS\${COMPANYNAME}\${APPNAME}.lnk" "$INSTDIR\Ring.exe" "" "$INSTDIR\ring.ico"

        # Registry information for add/remove programs
        WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${COMPANYNAME} ${APPNAME}" "DisplayName" ${APPNAME}
        WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${COMPANYNAME} ${APPNAME}" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
        WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${COMPANYNAME} ${APPNAME}" "QuietUninstallString" "$\"$INSTDIR\uninstall.exe$\" /S"
        WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${COMPANYNAME} ${APPNAME}" "InstallLocation" "$\"$INSTDIR$\""
        WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${COMPANYNAME} ${APPNAME}" "DisplayIcon" "$\"$INSTDIR\ring.ico$\""
        WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${COMPANYNAME} ${APPNAME}" "Publisher" "${COMPANYNAME}"
        WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${COMPANYNAME} ${APPNAME}" "HelpLink" "$\"${HELPURL}$\""
        WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${COMPANYNAME} ${APPNAME}" "URLUpdateInfo" "$\"${UPDATEURL}$\""
        WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${COMPANYNAME} ${APPNAME}" "URLInfoAbout" "$\"${ABOUTURL}$\""
        WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${COMPANYNAME} ${APPNAME}" "DisplayVersion" "${VERSIONMAJOR}.${VERSIONMINOR}.${VERSIONBUILD}"
        WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${COMPANYNAME} ${APPNAME}" "VersionMajor" ${VERSIONMAJOR}
        WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${COMPANYNAME} ${APPNAME}" "VersionMinor" ${VERSIONMINOR}
        # There is no option for modifying or repairing the install
        WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${COMPANYNAME} ${APPNAME}" "NoModify" 1
        WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${COMPANYNAME} ${APPNAME}" "NoRepair" 1
        ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
        IntFmt $0 "0x%08X" $0
        WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${COMPANYNAME} ${APPNAME}" "EstimatedSize" "$0"

        # Write ring protocol in registry
        WriteRegStr HKCR "ring" "URL Protocol" "$\"$\""
        WriteRegStr HKCR "ring\DefaultIcon" "" "$\"$INSTDIR\Ring.exe,1$\""
        WriteRegStr HKCR "ring\shell\open\command" "" "$\"$INSTDIR\Ring.exe$\" $\"%1$\""
sectionEnd

# Uninstaller

function un.onInit
        SetShellVarContext all

        #Verify the uninstaller - last chance to back out
        MessageBox MB_OKCANCEL "Permanantly remove ${APPNAME}?" IDOK next
                Abort
        next:
        !insertmacro VerifyUserIsAdmin
functionEnd

section "uninstall"

        # Remove Start Menu launcher
        delete "$SMPROGRAMS\${COMPANYNAME}\${APPNAME}.lnk"
        # Try to remove the Start Menu folder - this will only happen if it is empty
        rmDir "$SMPROGRAMS\${COMPANYNAME}"

        # Remove files
        delete $INSTDIR\Ring.exe
        delete $INSTDIR\ring.ico
        delete $INSTDIR\*.dll
        rmDir /r $INSTDIR\platforms
        rmDir /r $INSTDIR\imageformats
        rmDir /r $INSTDIR\ringtones
        rmDir /r $INSTDIR\share

        # Always delete uninstaller as the last action
        delete $INSTDIR\uninstall.exe

        # Try to remove the install directory - this will only happen if it is empty

        rmDir $INSTDIR

        # Remove uninstaller information from the registry
        DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${COMPANYNAME} ${APPNAME}"
sectionEnd
