# Automated Web Backup System (ระบบสำรองข้อมูลเว็บไซต์อัตโนมัติ)

สคริปต์นี้ออกแบบมาเพื่อช่วยให้คุณสำรองข้อมูลเว็บไซต์จาก Server (ผ่าน SFTP) มายังเครื่อง Local และบีบอัดไฟล์พร้อมส่งไปยัง External Drive โดยอัตโนมัติ พร้อมระบบแจ้งเตือนผ่าน Email

## 📋 ฟีเจอร์หลัก (Features)
*   **Multi-Server Support**: รองรับการดึงข้อมูลจาก 2 Server พร้อมกัน
*   **Smart Sync**:
    *   **Day 1 (วันที่ 1 ของเดือน)**: ทำการลบข้อมูลเก่าในเครื่อง Local ทั้งหมดและดึงใหม่ (Full Wipe & Sync) เพื่อเคลียร์ขยะ
    *   **Normal Day**: ดึงเฉพาะไฟล์ที่มีการเปลี่ยนแปลง (Incremental Sync) เพื่อความรวดเร็ว
*   **Backup Retention Policy (ระบบหมุนเวียนไฟล์)**:
    *   **จันทร์ - พฤหัสฯ, เสาร์ - อาทิตย์**: ระบบจะเก็บไฟล์สำรองข้อมูลไว้เพียง 1 ชุดต่อวันในสัปดาห์ (หมุนเวียนทับไฟล์เดิมของวันนั้นๆ)
    *   **วันศุกร์ (Friday)**: ระบบจะ **ไม่ลบ** ไฟล์เก่าของวันศุกร์ (สะสมไฟล์ Backup ทุกๆ วันศุกร์ไว้เป็น Weekly Archive)
*   **Auto Compression**: บีบอัดไฟล์เป็น `.7z` อัตโนมัติด้วย 7-Zip
*   **Safety Lock**: ระบบป้องกันการรันผิดเครื่องด้วยไฟล์ Key (`allow_backup.key`)
*   **Email Notification**: แจ้งเตือนสถานะการทำงานผ่าน Gmail

---

## 🛠️ สิ่งที่ต้องเตรียม (Prerequisites)

1.  **OS:** Windows 10, 11 หรือ Windows Server (64-bit)
2.  **Software:**
    *   **WinSCP:** ติดตั้งไว้ที่ `C:\Program Files (x86)\WinSCP\WinSCP.com`
    *   **7-Zip:** ติดตั้งไว้ที่ `C:\Program Files\7-Zip\7z.exe`
3.  **Gmail App Password:** สำหรับระบบส่งอีเมล
4.  **Directory Structure (โครงสร้างโฟลเดอร์):**
    *   คุณต้องสร้างโฟลเดอร์สำหรับพักข้อมูล (Local Sync) ภายใน `backupDir` ด้วยตนเอง (ชื่อโฟลเดอร์กำหนดใน `config.txt`) ระบบจะ **ไม่** สร้างให้โดยอัตโนมัติเพื่อยืนยันความถูกต้อง

---

## ⚙️ การตั้งค่า (Configuration)

**สำคัญ**: การตั้งค่าทั้งหมดจะทำผ่านไฟล์ **`config.txt`** (ไม่ต้องแก้ไขไฟล์ .bat)

1.  เปิดไฟล์ `config.txt` ด้วย Text Editor
2.  แก้ไขค่าต่างๆ ดังนี้:

### 1. การเชื่อมต่อ Server & Email
```ini
enable_srv1=ON                  # เปิด/ปิด การใช้งาน Server 1
enable_email=ON                 # เปิด/ปิด การแจ้งเตือน Email

# Email Settings
email_user=YOUR_EMAIL@gmail.com
email_pass=YOUR_APP_PASSWORD    # รหัส App Password 16 หลัก

# Server 1 Settings
srv1_name=MyWebServer
srv1_sftpname=sftp://user:pass@192.168.1.1/   # Connection String หรือ Session Name ใน WinSCP
srv1_hostkeyssh=ssh-rsa 2048...               # ดูได้จาก WinSCP (Session > Server/Protocol Information)
```

### 2. ที่อยู่โฟลเดอร์ (Paths)
```ini
backupDir=D:\Backup             # โฟลเดอร์พักข้อมูลบนเครื่องนี้
subfolder_name=LocalSync        # ชื่อโฟลเดอร์ย่อยที่จะเก็บไฟล์ (ต้องสร้างเอง!)
backupDirTo=F:\BackupWeb        # โฟลเดอร์ปลายทาง (External Drive)
logDir=F:\WinSCP\log            # ที่เก็บ Log
```

### 3. รายการไฟล์ที่จะ Sync
```ini
# Server 1: ระบุรายชื่อโฟลเดอร์ที่ต้องการ Backup (คั่นด้วยวรรค)
srv1_remote_path=/var/www/html
srv1_folders_list=images uploads conf
```

### 4. 🔑 สร้างไฟล์ Safety Key **(จำเป็น)**
เพื่อป้องกันความผิดพลาด ระบบจะทำงานก็ต่อเมื่อมีไฟล์กุญแจอยู่ใน `backupDir`
*   **วิธีทำ**: สร้างไฟล์เปล่าชื่อ **`allow_backup.key`** ไว้ในโฟลเดอร์ `backupDir` ที่ตั้งค่าไว้

---

## 🚀 วิธีการใช้งาน (Usage)

### การรันแบบ Manual
ดับเบิ้ลคลิกไฟล์ **`automated_backup.bat`** โปรแกรมจะอ่านค่าจาก `config.txt` และเริ่มทำงาน

### การตั้งเวลาอัตโนมัติ (Task Scheduler)
1.  เปิด **Task Scheduler** > **Create Basic Task**
2.  ตั้งเวลา Trigger (เช่น Daily เวลา 03:00 น.)
3.  Action: **Start a program** เลือกไฟล์ `automated_backup.bat`
4.  **Start in (Optional)**: ระบุ Path ที่เก็บไฟล์ bat (**สำคัญมาก** เพื่อให้หา config.txt เจอ) เช่น `C:\Users\Admin\Desktop\Backup-Script\`

---

## ⚠️ การแก้ไขปัญหา (Troubleshooting)

*   **[CRITICAL ERROR] Configuration file 'config.txt' NOT FOUND!**
    *   โปรแกรมหาไฟล์ `config.txt` ไม่เจอ ตรวจสอบว่าไฟล์วางอยู่คู่กับ `.bat` หรือไม่
*   **[CRITICAL ERROR] FOLDER MISSING**
    *   คุณยังไม่ได้สร้างโฟลเดอร์ย่อย (ตามตัวแปร `subfolder_name`) ใน `backupDir`
*   **[ERROR] Safety Key NOT FOUND!**
    *   ไม่พบไฟล์ `allow_backup.key` ในโฟลเดอร์ Backup
*   **WinSCP เชื่อมต่อไม่ได้**
    *   เช็ค `srv1_hostkeyssh` หาก Server มีการเปลี่ยน Key ต้องเอามาอัพเดทใหม่

---
**Note**: สคริปต์นี้จัดทำขึ้นเพื่อการศึกษาและใช้งานส่วนตัว ผู้พัฒนาไม่รับผิดชอบต่อความเสียหายของข้อมูลที่อาจเกิดขึ้น กรุณาทดสอบระบบก่อนนำไปใช้งานจริง

---

## 📝 License & Credit
*   **Developer**: Computer Technical Officer
*   **Organization**: Phetchabun Rajabhat University
*   **System**: Internal Automated Web Backup Workflow