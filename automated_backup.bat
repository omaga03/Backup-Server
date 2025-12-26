@echo off
setlocal EnableDelayedExpansion

REM ============================================================================
REM [ INITIALIZATION ] โหลดค่าจากไฟล์ Text (config.txt)
REM ============================================================================
color 0A
title Automated Web Backup System - Monitoring...

REM --- [START TIMER] เก็บเวลาเริ่มเป็นตัวเลข Ticks (แม่นยำกว่าวันที่) ---
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "(Get-Date).Ticks"`) do set "start_ticks=%%a"

REM ตรวจสอบหาไฟล์ config.txt
if not exist "config.txt" (
    color 0C
    echo.
    echo    [CRITICAL ERROR] Configuration file 'config.txt' NOT FOUND!
    echo    Please create 'config.txt' in the same folder.
    echo.
    pause
    exit
)

echo    [*] Loading configuration from config.txt...

REM อ่านไฟล์ Config
for /f "eol=# tokens=1,* delims==" %%a in (config.txt) do (
    set "key=%%a"
    set "val=%%b"
    if not "!key!"=="" (
        set "!key!=!val!"
    )
)

REM ** ตรวจสอบค่า timeout_val กันเหนียว (ถ้าไม่มีใน config ให้ตั้งเป็น 10 วิ) **
if "%timeout_val%"=="" set timeout_val=10

REM ** ตัวแปรสถานะเริ่มต้น **
set "global_error=0"
set "stat_srv1=NONE"
set "stat_srv2=NONE"
set "stat_zip=NONE"
set "stat_trans=NONE"
set "stat_email=NONE"
set "size_folder=Calculating..."
set "size_zip=Calculating..."
set "total_duration=Calculating..."

REM ** กำหนดตัวแปร Derived **
if "%subfolder_name%"=="" set "subfolder_name=LocalSync"
set "localsyn=%backupDir%\%subfolder_name%"

REM ** Advanced Settings Defaults **
if "%safety_key_name%"=="" set "safety_key_name=allow_backup.key"
if "%zip_mode%"=="" set "zip_mode=u"
if "%zip_switches%"=="" set "zip_switches=-up0q0r2x2y2z1w2 -mx1 -r -ssw -ms=off"
if "%winscp_raw_settings%"=="" set "winscp_raw_settings=ProxyPort=0"
if "%email_subject_prefix%"=="" set "email_subject_prefix=[Web-Backup]"
if "%enable_delete_old_files%"=="" set "enable_delete_old_files=ON"

REM ============================================================================
REM [ SAFETY CHECKS ] ระบบตรวจสอบความปลอดภัย
REM ============================================================================

REM 1. เช็คตัวแปร backupDir
if "%backupDir%"=="" (
    color 0C
    echo [CRITICAL ERROR] Variable 'backupDir' is EMPTY! Check config.txt format.
    pause & exit
)

REM 1.1 เช็คตัวแปร backupDirTo (ปลายทาง)
if "%backupDirTo%"=="" (
    color 0C
    echo [CRITICAL ERROR] Variable 'backupDirTo' is EMPTY! Check config.txt.
    pause & exit
)

REM 2. เช็คไฟล์กุญแจ (%safety_key_name%)
if not exist "%backupDir%\%safety_key_name%" (
    color 0C
    echo.
    echo    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    echo    !!!             SAFETY LOCK ENGAGED                 !!!
    echo    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    echo.
    echo    [ERROR] Safety Key NOT FOUND!
    echo    Path Checked: "%backupDir%\%safety_key_name%"
    echo.
    echo    [WAIT] System halted. Press any key to exit.
    pause >nul
    exit
)

REM 3. เช็คโฟลเดอร์ย่อย (Sub-folder Check)
if not exist "%localsyn%\" (
    color 0C
    echo.
    echo    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    echo    !!!      CRITICAL ERROR: FOLDER MISSING             !!!
    echo    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    echo.
    echo    [ERROR] Sub-folder NOT FOUND!
    echo    Expected Path: "%localsyn%"
    echo.
    echo    Security Policy: The system will NOT create this folder automatically.
    echo    You must manually create it to confirm the structure is correct.
    echo.
    echo    [WAIT] System halted. Press any key to exit.
    pause >nul
    exit
)

REM ============================================================================
REM [ DATE PARSING ]
REM ============================================================================
for /f "tokens=1-4 delims=/ " %%i in ("%date%") do (
     set dow=%%i
     set month=%%j
     set day=%%k
     set year=%%l
)
set hr=%time:~0,2%
if "%hr:~0,1%" == " " set hr=0%hr:~1,1%
set strTime=%year%_%month%_%day%_%hr%%time:~3,2%%time:~6,2%
set dateSTRName=%strTime%_%dow%

REM ============================================================================
REM [ HEADER ]
REM ============================================================================
cls
echo.
echo    [ SYSTEM STATUS : ONLINE ]
echo    [ DATE : %day%/%month%/%year% ]
echo    [ STARTED AT : %time% ]
echo.
echo    -------------------------------------------------------
echo    [ CONFIGURATION LOADED ]
echo.
if /I "%enable_srv1%"=="ON" (echo    [ / ] SERVER 1 : ENABLED) else (echo    [ X ] SERVER 1 : DISABLED)
if /I "%enable_srv2%"=="ON" (echo    [ / ] SERVER 2 : ENABLED) else (echo    [ X ] SERVER 2 : DISABLED)
if /I "%enable_email%"=="ON" (echo    [ / ] EMAIL    : ENABLED) else (echo    [ X ] EMAIL    : DISABLED)
echo.
echo    -------------------------------------------------------
echo    [STEP] Initial Check Completed.

REM ============================================================================
REM [ LOGIC: MANUAL SELECTION WITH TIMEOUT ] ตัวเลือกแบบจับเวลา
REM ============================================================================
echo.
echo    -------------------------------------------------------
echo    [ SELECT OPERATION MODE ]
echo    -------------------------------------------------------
echo    [ 1 ]   : Perform FULL WIPE (Delete Local & Re-Sync)
echo    [ N ]   : Normal Backup (Update Only) - Default
echo.

REM --- คำสั่ง choice ---
REM /C 1N       = รับค่าปุ่ม 1 หรือ N (และรวมถึงกรณี Timeout จะดีดไปค่า Default)
REM /N          = ซ่อนลิสต์ปุ่ม [1,N]?
REM /T %timeout%= กำหนดเวลาถอยหลัง
REM /D N        = เมื่อหมดเวลา ให้เลือก N (Normal)
REM /M          = ข้อความแจ้งเตือน

choice /C 1N /N /T %timeout_val% /D N /M "   > Press [1] for Full Wipe, or wait %timeout_val%s for Normal: "

REM ตรวจสอบค่า ErrorLevel (ต้องเรียงจากมากไปน้อย)
REM ErrorLevel 2 = กด N หรือ หมดเวลา (Timeout)
if errorlevel 2 goto NORMALBACKUP

REM ErrorLevel 1 = กด 1
if errorlevel 1 goto FULLBACKUP

REM กันเหนียว ถ้าหลุดเงื่อนไข
goto NORMALBACKUP


:FULLBACKUP
    color 0C
    echo.
    echo    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    echo    !!! TODAY IS : PERFORMING FULL WIPE & SYNC    !!!
    echo    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    echo.
    echo.
    echo    [*] Status: Removing old local data...
    if /I "%enable_delete_old_files%"=="ON" (
        if exist "%localsyn%" rmdir /s /q "%localsyn%"
        echo    [*] Status: Re-creating directory structure...
        mkdir "%localsyn%"
    ) else (
        echo    [INFO] Full Wipe SKIPPED (Delete is DISABLED in config)
        if not exist "%localsyn%" mkdir "%localsyn%"
    )
  
    for %%f in (%folders_list%) do (
        if not exist "%localsyn%\%%f" mkdir "%localsyn%\%%f"
    )
    if exist "%backupDir%\localsyn.7z" del /f /q "%backupDir%\localsyn.7z"
    echo    [*] Ready for Full Download.
    echo    [STEP] Day Preparation Done. Starting WinSCP in %timeout_val%s...
    timeout /t %timeout_val%
    
    if /I "%enable_srv1%"=="OFF" (color 0E) else (if /I "%enable_srv2%"=="OFF" (color 0E) else (color 0A))
    goto STARTWINSCP

:NORMALBACKUP
    echo.
    echo    [*] Mode: Incremental Update [Sync Only]
    echo    [*] Clearing old logs...
    if exist "%logDir%\WinSCP.log" del "%logDir%\WinSCP.log" /s /f /q
    if exist "%localsyn%\WinSCP_log\WinSCP.log" del "%localsyn%\WinSCP_log\WinSCP.log" /s /f /q
    if exist "%logDir%\WinSCP2.log" del "%logDir%\WinSCP2.log" /s /f /q
    if exist "%localsyn%\WinSCP_log\WinSCP2.log" del "%localsyn%\WinSCP_log\WinSCP2.log" /s /f /q
    echo    [STEP] Log Cleared.
    echo    Starting WinSCP in %timeout_val%s...
    timeout /t %timeout_val%

:STARTWINSCP
    echo.
    echo    -------------------------------------------------------
    echo    [ PROCESS 1/3 ] SYNCHRONIZING WITH SERVER...
    echo    -------------------------------------------------------

REM ============================================================================
REM [ EXECUTION ]
REM ============================================================================

    REM ------------------- SERVER 1 Logic -------------------
    if /I "%enable_srv1%"=="ON" (
        echo    [*] Connecting to Server %srv1_name%...
        color 0A
        
        REM 1. สร้างไฟล์สคริปต์ชั่วคราว (script_srv1.txt)
        (
            echo option batch continue
            echo option confirm off
            echo open %srv1_sftpname% -hostkey="%srv1_hostkeyssh%"
            
            REM 2. วนลูปสร้างคำสั่ง Sync ตามรายชื่อใน Config
            for %%f in (%srv1_folders_list%) do (
                echo synchronize local -delete "%localsyn%\%%f" "%srv1_remote_path%/%%f"
            )
            
            echo exit
        ) > script_srv1.txt

        REM 3. สั่ง WinSCP ให้ทำงานตามไฟล์สคริปต์ที่สร้าง
        "%winscp%" /log="%logDir%\WinSCP.log" /ini=nul /script=script_srv1.txt
        
        if !ERRORLEVEL! equ 0 ( 
            echo    [OK] Server %srv1_name% Synced.
            set "stat_srv1=SUCCESS"
        ) else ( 
            echo    [XX] Server %srv1_name% Completed with errors.
            set "stat_srv1=FAILED"
            set "global_error=1"
        )

        REM ลบไฟล์สคริปต์ชั่วคราวทิ้งเพื่อความสะอาด
        del script_srv1.txt >nul 2>&1

    ) else (
        color 0E
        echo    [ - ] Skipping Server %srv1_name% [DISABLED].
        set "stat_srv1=SKIPPED"
        color 0A
    )

    echo.
    echo    [WAIT] Server 1 Logic Done. Next step in %timeout_val%s...
    timeout /t %timeout_val%


    REM ------------------- SERVER 2 Logic -------------------
    if /I "%enable_srv2%"=="ON" (
        echo    [*] Connecting to Server %srv2_name%...
        color 0A
        "%winscp%" /log="%logDir%\WinSCP2.log" /ini=nul /command ^
            "option batch continue" ^
            "option confirm off" ^
            "open %srv2_sftpname% -hostkey=""%srv2_hostkeyssh%"" -rawsettings %winscp_raw_settings%" ^
            "synchronize -filemask=""%srv2_exclude_mask%"" local -delete ""%localsyn%\%srv2_name%"" ""%srv2_remote_path%/""" ^
            "exit"
        
        if !ERRORLEVEL! equ 0 ( 
            echo    [OK] Server %srv2_name% Synced.
            set "stat_srv2=SUCCESS"
        ) else ( 
            echo    [XX] Server %srv2_name% Completed with errors.
            set "stat_srv2=FAILED"
            set "global_error=1"
        )
    ) else (
        color 0E
        echo    [ - ] Skipping Server %srv2_name% [DISABLED].
        set "stat_srv2=SKIPPED"
        color 0A
    )

    echo.
    echo    [WAIT] Server 2 Logic Done. Backup Logs in %timeout_val%s...
    timeout /t %timeout_val%

    REM ------------------- Backup Logs Logic -------------------
    robocopy "%logDir%" "%localsyn%\WinSCP_log" *.log /njh /njs /ndl /nc 
    echo    [WAIT] Logs Copied. Compressing in %timeout_val%s...
    timeout /t %timeout_val%

    echo.
    echo    -------------------------------------------------------
    echo    [ PROCESS 2/3 ] COMPRESSING DATA (7-Zip)
    echo    -------------------------------------------------------
    echo.
    color 0A
    
    set "targetZip=%backupDir%\localsyn.7z"
    
    echo    [*] UNLOCKING: Checking for stuck 7z processes...
    taskkill /F /IM 7z.exe /T >nul 2>&1
    
    echo    [*] ATTRIBUTES: Removing Read-only/System flags...
    if exist "%targetZip%" attrib -r -s -h "%targetZip%"
    
    REM เริ่มการบีบอัด
    "%zip%" %zip_mode% "%targetZip%" %zip_switches% "%localsyn%\*" 
    
    REM Auto-Repair Logic
    if !ERRORLEVEL! NEQ 0 (
        color 0E
        echo    [!] WARNING: Archive corrupted or Locked. Switching to EMERGENCY MODE...
        set "targetZip=%backupDir%\localsyn_fresh.7z"
        if exist "!targetZip!" del /f /q "!targetZip!"
        echo    [*] Creating NEW archive: !targetZip!
        "%zip%" a "!targetZip!" "%localsyn%\*" %zip_switches% 
    )

    if !ERRORLEVEL! EQU 0 (
        set "stat_zip=SUCCESS"
    ) else (
        set "stat_zip=FAILED"
        set "global_error=1"
        color 0C
        echo    [CRITICAL ERROR] Compression Failed.
    )
    
    echo.
    echo    [WAIT] Compression Finished. Transferring in %timeout_val%s...
    timeout /t %timeout_val%

    REM Check Friday
    REM Check Retention Day (Default: Fri)
    IF NOT "%retention_day%"=="" (
        IF NOT "%dow%" == "%retention_day%" (
            if /I "%enable_delete_old_files%"=="ON" (
                del "%backupDirTo%\%filename%*%dow%.7z" /s /f /q >nul 2>&1
            ) else (
               echo    [INFO] Accumulating File (Delete Disabled)
            )
        )
    )

    echo.
    echo    -------------------------------------------------------
    echo    [ PROCESS 3/3 ] TRANSFERRING TO EXTERNAL DRIVE
    echo    -------------------------------------------------------
    echo.
    color 0A
    
    esentutl /y "%targetZip%" /d "%backupDirTo%\%filename%_%dateSTRName%.7z" /o
    
    if !ERRORLEVEL! EQU 0 (
        color 0A
        echo    [OK] Transfer COMPLETED Successfully.
        set "stat_trans=SUCCESS"
    ) else (
        color 0C
        echo    [XX] ERROR: Transfer FAILED! [Code: !ERRORLEVEL!]
        set "stat_trans=FAILED"
        set "global_error=1"
    )

    REM ----------------------------------------------------------------------------
    REM [ CALCULATE SIZES & DURATION ] คำนวณขนาดและเวลา
    REM ----------------------------------------------------------------------------
    echo.
    echo    [*] Calculating Final Stats (Size & Duration)...
    
    REM 1. คำนวณขนาด
    set "P_FOLDER=%localsyn%"
    set "P_FILE=%targetZip%"
    for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "$path=$env:P_FOLDER; if(Test-Path $path){ '{0:N2} MB' -f ((Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB) } else { '0.00 MB' }"`) do set "size_folder=%%a"
    for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "$path=$env:P_FILE; if(Test-Path $path){ $file=Get-Item -LiteralPath $path; '{0:N2} MB' -f ($file.Length / 1MB) } else { 'File Not Found' }"`) do set "size_zip=%%a"

    REM 2. [STOP TIMER] คำนวณเวลา
    if "%start_ticks%"=="" set "start_ticks=0"
    for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "$ts = [TimeSpan]::FromTicks((Get-Date).Ticks - %start_ticks%); if($ts.Hours -gt 0){ '{0} hrs {1} mins {2} secs' -f $ts.Hours, $ts.Minutes, $ts.Seconds } else { '{0} mins {1} secs' -f $ts.Minutes, $ts.Seconds }"`) do set "total_duration=%%a"

    if "%total_duration%"=="" set "total_duration=0 mins 0 secs"

    echo    [INFO] Source Folder Size : %size_folder%
    echo    [INFO] Final Zip Size     : %size_zip%
    echo    [INFO] Total Time Used    : %total_duration%
    
    echo.
    echo    [WAIT] Process 3 Finished. Sending Email in %timeout_val%s...
    timeout /t %timeout_val%

    if !global_error! EQU 0 (
        set "mail_subject=%email_subject_prefix% Success"
    ) else (
        set "mail_subject=%email_subject_prefix% FAILED (Check Logs)"
    )

REM ============================================================================
REM [ EMAIL NOTIFICATION ]
REM ============================================================================

    if /I "%enable_email%"=="ON" (
        echo.
        echo    -------------------------------------------------------
        echo    [ NOTIFICATION ] SENDING EMAIL REPORT...
        echo    -------------------------------------------------------
        color 0E
        
        if exist sendmail.ps1 del /f /q sendmail.ps1
        
        (
            echo $SMTPServer = '%smtp_server%'
            echo $SMTPPort = '%smtp_port%'
            echo $Username = '%email_user%'
            echo $Password = '%email_pass%'
            echo $to = '%email_to%'
            echo $subject = '%mail_subject%'
            echo $body = "BACKUP SUMMARY REPORT [%date% %time%]`n"
            echo $body += "----------------------------------------`n"
            echo $body += "1. Server 1 (Sync)       : %stat_srv1%`n"
            echo $body += "2. Server 2 (Sync)       : %stat_srv2%`n"
            echo $body += "3. Compression (Zip)     : %stat_zip%`n"
            echo $body += "4. Transfer (Drive)      : %stat_trans%`n"
            echo $body += "----------------------------------------`n"
            echo $body += "5. Folder Size           : %size_folder%`n"
            echo $body += "6. Final Zip Size        : %size_zip%`n"
            echo $body += "7. Total Duration        : %total_duration%`n"
            echo $body += "----------------------------------------`n"
            echo $body += "End of Report."
            echo $message = New-Object System.Net.Mail.MailMessage $Username, $to, $subject, $body
            echo $smtp = New-Object System.Net.Mail.SmtpClient $SMTPServer, $SMTPPort
            echo $smtp.EnableSsl = $true
            echo $smtp.Credentials = New-Object System.Net.NetworkCredential^($Username, $Password^)
            echo try { $smtp.Send^($message^); Write-Host "Email Sent Successfully" } catch { Write-Host "Error sending email: $_"; exit 1 }
        ) > sendmail.ps1
        
        powershell -ExecutionPolicy ByPass -File sendmail.ps1
        
        if !ERRORLEVEL! EQU 0 (
            color 0A
            echo    [OK] Email Report Sent.
            set "stat_email=SUCCESS"
        ) else (
            color 0C
            echo    [XX] Failed to send email. Check Internet or App Password.
            set "stat_email=FAILED"
        )
        
        del sendmail.ps1 >nul 2>&1
    ) else (
        set "stat_email=DISABLED"
    )

REM ============================================================================
REM [ FINISH ] แสดงผลสรุปหน้าจอ
REM ============================================================================
    if !global_error! EQU 0 (color 0A) else (color 0C)
echo.
echo.
echo    =======================================================
echo                   FINAL EXECUTION SUMMARY
echo    =======================================================
echo.
echo      1. Server 1 (Sync)   : %stat_srv1%
echo      2. Server 2 (Sync)   : %stat_srv2%
echo      3. Compression (Zip) : %stat_zip%
echo      4. Transfer (Drive)  : %stat_trans%
echo      5. Email Status      : %stat_email%
echo.
echo      6. Folder Size       : %size_folder%
echo      7. Final Zip Size    : %size_zip%
echo      8. Total Duration    : %total_duration%
echo.
echo    =======================================================
echo      OVERALL STATUS       : %mail_subject%
echo    =======================================================
echo.
echo    [WAIT] SYSTEM HALTED. Press any key to exit and open folders.
pause

start "" "%windir%\explorer.exe" "%logDir%"
start "" "%windir%\explorer.exe" "%backupDirTo%"

exit /B
