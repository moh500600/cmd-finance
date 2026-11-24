<div align="center">

# CMD Finance

**إدارة مالية شخصية**

Personal finance on your device

`v0.1.0` · Android 7.0+ · no internet permission · no account, no server

</div>

> **Status: first release, NOT yet tested on a physical device.** Screenshots in the PDFs are automated UI test renders with demo data, not device screenshots.

## Download

Open the release page and pick **`cmd-finance-0.1.0-arm64-v8a.apk`** for most phones (`armeabi-v7a` for older 32-bit phones, `x86_64` for emulators):

**https://github.com/moh500600/cmd-finance/releases/tag/v0.1.0**

SHA-256 of the arm64-v8a file:

```
31f8718a4758f3b18b977ed0847d089c995b447027525f802ee5a82f498a9eee
```

Android will ask you to allow installing from an unknown source. The APK is signed with a new CMD key made for this app.

## Documents

- [Visual README (PDF, 4 pages)](docs/CMD-Finance-README-visual.pdf)
- [Showcase (PDF, 5 pages, 16:9)](docs/CMD-Finance-Showcase.pdf)

## ما هو التطبيق

- **الحسابات والمعاملات** (Accounts & transactions): دخل ومصروف وتحويل بين الحسابات.
- **الميزانيات** (Budgets): حدود للفئات مع تنبيه التجاوز.
- **الديون** (Debts): ما لك وما عليك مع مواعيد الاستحقاق.
- **أهداف الادخار** (Savings goals): أهداف بمبالغ وتقدّم.
- **الفواتير والمتكرر** (Bills & recurring): فواتير ومعاملات متكررة بتذكير.
- **الأصول والاستثمارات** (Assets & investments): صافي الثروة وعملات متعددة.
- **استيراد وتصدير** (Import & export): تصدير المعاملات CSV واستيراد CSV أو Excel.
- **المساعد المحلي** (On-device assistant): يجيب من بياناتك على الجهاز، ولا يرسل شيئًا للإنترنت.

## What it does

- **Accounts & transactions**
- **Budgets**
- **Debts**
- **Savings goals**
- **Bills & recurring**
- **Assets & investments**
- **Import & export**
- **On-device assistant**

## Privacy and limits

- All data lives in a database on your phone. The release manifest has no INTERNET permission, there is no cloud account, no backend and no hosted AI.
- المزامنة السحابية والخادم أُزيلا. المشاركة صارت بملف CSV.
- It installs **next to** the old app (new package id `com.cmdapps.finance`). It does not replace it and does not move data automatically. Old server data was not touched.
- Sharing between people is done by exporting a file and importing it on the other phone.
- Deleting the app or its data deletes your data. Keep a backup file.
- Not tested on a physical device yet. Report problems in the repository issues.

## Build

Flutter project. CI (`.github/workflows/android.yml`) runs analyze, tests and a release build. The APKs in the release were re-signed locally with the CMD key.

## License

No license has been chosen yet.
