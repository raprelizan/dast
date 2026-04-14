# ADSL Multi-WAN Bonding (تقسيم الحمل)

هذا المشروع يحتوي سكربت Bash بسيط يساعدك على استخدام أكثر من خط ADSL في نفس الوقت عبر **Load Balancing** باستخدام:
- `nftables`
- `ip rule` / `ip route` (Policy Routing)

> **مهم:** هذا الحل يرفع السرعة الإجمالية عند وجود عدة تحميلات/اتصالات في نفس الوقت، لكنه غالبًا لا يجمع السرعة لِـ **اتصال واحد فقط** (مثل تنزيل ملف واحد) إلا إذا استخدمت MPTCP أو VPN bonding مع سيرفر خارجي.

## الملفات
- `adsl_bonding.sh`: سكربت التفعيل/الإلغاء.

## المتطلبات
- Linux
- أدوات: `ip`, `nft`, `sysctl`, `awk`
- صلاحية root
- واجهتان WAN (مثل `ppp0` و `ppp1`) وواجهة LAN (مثل `eth0`)

## التعديل قبل التشغيل
افتح السكربت وعدّل القيم حسب جهازك:
- `WAN_IFACES=(ppp0 ppp1)`
- `LAN_IFACE="eth0"`

## التشغيل
```bash
sudo ./adsl_bonding.sh up
```

## الإيقاف
```bash
sudo ./adsl_bonding.sh down
```

## كيف يعمل؟
1. يفعّل التوجيه (`ip_forward`).
2. ينشئ Route Table مستقل لكل خط ADSL.
3. يوزع الاتصالات الجديدة عشوائيًا على الخطوط عبر `nftables`.
4. يحافظ على ثبات كل اتصال على نفس الخط باستخدام `conntrack mark`.
5. يفعّل NAT (Masquerade) على كل خط.

## لو تريد Bonding حقيقي لاتصال واحد
تحتاج عادةً:
- سيرفر VPS خارجي.
- تقنية مثل MPTCP أو VPN Bonding (مثل OpenMPTCProuter).

