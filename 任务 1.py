# amap_poi_crawler.py
import requests, time, csv, os

AMAP_KEY = "18c043aa248a03f916c199a416943870"
CITY = "张店区"          # 显示用的区名
ADCODE = "370303"
BASE_URL = "https://restapi.amap.com/v3/place/text"
OUT_DIR = "data/raw"
os.makedirs(OUT_DIR, exist_ok=True)

# 每个类别给多个关键词, 覆盖面更全(高德"商超"这类口语词不一定命中)
POI_CATEGORIES = {
    "学校": ["学校", "小学", "中学", "大学"],
    "医院": ["医院", "社区卫生服务中心"],
    "商超": ["商场", "超市", "便利店"],
    "公交站": ["公交站", "公交车站"],
    "公园": ["公园"],
    "银行": ["银行", "ATM"],
}

def fetch_poi(keyword, category, page_size=25, max_pages=100):
    """按关键词分页抓取, 返回 list[dict]"""
    results = []
    for page in range(1, max_pages + 1):
        params = {
            "key": AMAP_KEY,
            "keywords": keyword,
            "city": ADCODE,
            "citylimit": "true",   # 只返回该城市范围
            "offset": page_size,
            "page": page,
            "extensions": "base",
        }
        data = requests.get(BASE_URL, params=params, timeout=10).json()
        if data["status"] != "1":
            print(f"[警告] {category}/{keyword} 第{page}页: {data.get('info')}")
            break
        pois = data.get("pois", [])
        if not pois:
            break
        for p in pois:
            lng, lat = p["location"].split(",")
            results.append({
                "类别": category, "名称": p["name"],
                "经度": lng, "纬度": lat, "地址": p.get("address", ""),
                "类型": p.get("type", ""),
                "省": p.get("pname", ""), "市": p.get("cityname", ""), "区县": p.get("adname", ""),
            })
        print(f"[{category}] 已抓 {page} 页, 累计 {len(results)} 条")
        time.sleep(0.4)   # 控制 QPS, 防封
    return results

def save_csv(rows, filename):
    if not rows:
        print(f"[跳过] {filename} 无数据"); return
    path = os.path.join(OUT_DIR, filename)
    with open(path, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader(); w.writerows(rows)
    print(f"[完成] {path} 共 {len(rows)} 条")

if __name__ == "__main__":
    for cat, kws in POI_CATEGORIES.items():
        rows = []
        for kw in kws:
            rows += fetch_poi(kw, cat)
        save_csv(rows, f"poi_{cat}.csv")
