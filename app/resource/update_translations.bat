@echo off
echo Updating translation files...

cd /d %~dp0

echo 正在扫描源代码提取待翻译文本...
pyside6-lupdate ../../view/*.py ../../common/*.py -ts i18n/gallery.zh_CN.ts i18n/gallery.zh_HK.ts

echo.
echo 请使用 Qt Linguist 翻译新增的条目:
echo 1. 打开 Qt Linguist
echo 2. 加载 i18n/gallery.zh_CN.ts 进行翻译
echo 3. 加载 i18n/gallery.zh_HK.ts 进行翻译
echo.
echo 翻译完成后按任意键编译翻译文件...
pause

echo.
echo 正在编译翻译文件...
pyside6-lrelease i18n/gallery.zh_CN.ts -qm i18n/gallery.zh_CN.qm
pyside6-lrelease i18n/gallery.zh_HK.ts -qm i18n/gallery.zh_HK.qm

echo.
echo 正在重新编译资源文件...
pyside6-rcc resource.qrc -o resource.py

echo.
echo 所有操作完成！请重启程序以应用更改。
pause