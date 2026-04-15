# ADSL Multi-WAN Bonding (تقسيم الحمل)

هذا المشروع يحتوي أدوات تساعدك على استخدام أكثر من خط ADSL/WAN.

## الملفات
- `adsl_bonding.sh`: سكربت Linux للتفعيل/الإلغاء (nftables + policy routing).
- `windows_precheck.ps1`: فحص سريع على Windows لمعرفة هل عندك أكثر من WAN حقيقي.
- `windows_bonding.ps1`: تطبيق مشاركة حمل على Windows (تقسيم الوجهات 0.0.0.0/1 و 128.0.0.0/1 بين خطين WAN).

> **مهم:** على Windows هذا ليس packet bonding حقيقي لاتصال واحد، بل **destination-split load sharing** على نفس الجهاز.

## تشغيل Windows (المطلوب لديك)

### 1) فحص أولي
```powershell
powershell -ExecutionPolicy Bypass -File .\windows_precheck.ps1
echo $LASTEXITCODE
```

- إذا كانت النتيجة `2` فأنت لا تملك خطين WAN مستقلين.

### 2) تشغيل المشاركة بين خطين WAN
شغّل PowerShell كـ Administrator ثم:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows_bonding.ps1 -Action up -Wan1Alias "Ethernet" -Wan2Alias "Ethernet 2" -Wan1Gateway "192.168.1.1" -Wan2Gateway "192.168.2.1"
```

### 3) عرض الحالة
```powershell
powershell -ExecutionPolicy Bypass -File .\windows_bonding.ps1 -Action status -Wan1Alias "Ethernet" -Wan2Alias "Ethernet 2" -Wan1Gateway "192.168.1.1" -Wan2Gateway "192.168.2.1"
```

### 4) الإلغاء والرجوع
```powershell
powershell -ExecutionPolicy Bypass -File .\windows_bonding.ps1 -Action down -Wan1Alias "Ethernet" -Wan2Alias "Ethernet 2" -Wan1Gateway "192.168.1.1" -Wan2Gateway "192.168.2.1"
```

## Linux script (اختياري)
### المتطلبات
- Linux
- أدوات: `ip`, `nft`, `sysctl`, `awk`
- صلاحية root
- واجهتان WAN (مثل `ppp0` و `ppp1`) وواجهة LAN (مثل `eth0`)

### التشغيل
```bash
sudo ./adsl_bonding.sh up
```

### الإيقاف
```bash
sudo ./adsl_bonding.sh down
```

## ملاحظة مهمة
- إذا لديك كرت/خط واحد فقط، لا يمكن تحقيق Multi-WAN فعليًا.
- لدمج سرعة اتصال واحد فعليًا تحتاج غالبًا MPTCP أو VPN Bonding مع سيرفر خارجي.
