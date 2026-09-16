# -*- coding: utf-8 -*-
# 任务1：主页面标题加大加清晰（topbar brand 17px -> 22px，加粗）
import sys
sys.stdout.reconfigure(encoding='utf-8')

p = r'D:\202609webgis实习\Java-\frontend\main.html'
with open(p, encoding='utf-8') as f:
    s = f.read()

old = '''.topbar .brand {
    font-size: 17px; font-weight: 700;
    background: linear-gradient(90deg,#1676d6,#2ec4b6);
    -webkit-background-clip: text; background-clip: text; color: transparent;
    white-space: nowrap;
}'''
# 注意：这个是 common.css 里的，不是 main.html。main.html 里没有 brand 样式。
if old in s:
    s = s.replace(old, new, 1)
    print('main.html 命中')
else:
    print('main.html 未命中（brand样式在common.css）')
    # 检查 main.html 顶部导航栏 brand 定义
    import re
    for m in re.finditer(r'.{0,60}brand.{0,120}', s):
        print('>>>', m.group(0).replace('\n', ' | '))
