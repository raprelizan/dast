# ADSL Multi-WAN Bonding (تقسيم الحمل)

هذا المشروع يحتوي سكربت Bash بسيط يساعدك على استخدام أكثر من خط ADSL في نفس الوقت عبر **Load Balancing** باستخدام:
- `nftables`
- `ip rule` / `ip route` (Policy Routing)

> **مهم:** هذا الحل يرفع السرعة الإجمالية عند وجود عدة تحميلات/اتصالات في نفس الوقت، لكنه غالبًا لا يجمع السرعة لِـ **اتصال واحد فقط** (مثل تنزيل ملف واحد) إلا إذا استخدمت MPTCP أو VPN bonding مع سيرفر خارجي.

## الملفات
- `adsl_bonding.sh`: سكربت Linux للتفعيل/الإلغاء.
- `windows_precheck.ps1`: فحص سريع على Windows لمعرفة هل عندك أكثر من WAN حقيقي قبل محاولة bonding.

## المتطلبات (Linux script)
- Linux
- أدوات: `ip`, `nft`, `sysctl`, `awk`
- صلاحية root
- واجهتان WAN (مثل `ppp0` و `ppp1`) وواجهة LAN (مثل `eth0`)

## التعديل قبل التشغيل (Linux)
افتح السكربت وعدّل القيم حسب جهازك:
- `WAN_IFACES=(ppp0 ppp1)`
- `LAN_IFACE="eth0"`

## التشغيل (Linux)
```bash
sudo ./adsl_bonding.sh up
```

## الإيقاف (Linux)
```bash
sudo ./adsl_bonding.sh down
```

## فحص البيئة على Windows (قبل أي Bonding)
إذا كنت على Windows، شغّل:
```powershell
powershell -ExecutionPolicy Bypass -File .\windows_precheck.ps1
echo $LASTEXITCODE
```

- `windows_precheck.ps1` هو فقط للفحص على Windows.
- `adsl_bonding.sh` لا يعمل مباشرة على Windows PowerShell.
- أوامر `sudo ./adsl_bonding.sh up` و `sudo ./adsl_bonding.sh down` يجب تشغيلها داخل Linux (أو WSL مع صلاحيات مناسبة).
- إذا ظهرت نتيجة أن لديك WAN واحد فقط، فهذا يعني لا يمكن عمل Multi-WAN فعليًا من وضعك الحالي.
- تحتاج على الأقل اتصالين إنترنت مستقلين (مثال: DSL1 + DSL2 أو DSL + 4G).

## كيف يعمل سكربت Linux؟
1. يفعّل التوجيه (`ip_forward`).
2. ينشئ Route Table مستقل لكل خط ADSL.
3. يوزع الاتصالات الجديدة عشوائيًا على الخطوط عبر `nftables`.
4. يحافظ على ثبات كل اتصال على نفس الخط باستخدام `conntrack mark`.
5. يفعّل NAT (Masquerade) على كل خط.

## لو تريد Bonding حقيقي لاتصال واحد
تحتاج عادةً:
- سيرفر VPS خارجي.
- تقنية مثل MPTCP أو VPN Bonding (مثل OpenMPTCProuter).

