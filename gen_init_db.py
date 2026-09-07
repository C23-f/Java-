# -*- coding: utf-8 -*-
"""
城市社区 15 分钟生活圈便民设施评价与管理系统 —— init_db.sql 生成器
生成一个可直接在 SSMS 中一键执行的完整建库建表 + 测试数据脚本。
"""
import math
import random
import csv

random.seed(20260903)

# ---------------------------------------------------------------
# 1. 测试坐标生成（以淄博市张店区中心片区为示范，围绕中心点布点）
# ---------------------------------------------------------------
CENTER_LAT, CENTER_LNG = 36.8100, 118.0550


def offset(base_lat, base_lng, dist_m, bearing_deg):
    """从(base_lat, base_lng)按 bearing(度, 北为0顺时针)偏移 dist_m 米"""
    R = 6371000.0
    d = dist_m / R
    br = math.radians(bearing_deg)
    lat1 = math.radians(base_lat)
    lng1 = math.radians(base_lng)
    lat2 = math.asin(math.sin(lat1) * math.cos(d) +
                     math.cos(lat1) * math.sin(d) * math.cos(br))
    lng2 = lng1 + math.atan2(math.sin(br) * math.sin(d) * math.cos(lat1),
                             math.cos(d) - math.sin(lat1) * math.sin(lat2))
    return math.degrees(lat2), math.degrees(lng2)


def rand_pt(base_lat, base_lng, dmin, dmax):
    """在距中心 dmin~dmax 米范围内随机取一个点"""
    d = random.uniform(dmin, dmax)
    b = random.uniform(0, 360)
    return offset(base_lat, base_lng, d, b)


# 示范片区的小区（2个，种子数据，后续补充）
communities = [
    # (名称, 地址, 经度, 纬度, 户数, 建成年份)
    ("阳光花园社区", "张店区人民路 88 号", *rand_pt(CENTER_LAT, CENTER_LNG, 80, 260), 1280, 2012),
    ("幸福里社区", "张店区中心路 156 号", *rand_pt(CENTER_LAT, CENTER_LNG, 60, 300), 960, 2016),
]

# 设施分类：(code, 名称, 权重, 排序, 说明)
categories = [
    ("EDU", "教育设施", 1.00, 1, "幼儿园、小学、中学等"),
    ("MED", "医疗卫生", 1.20, 2, "社区医院、药店、诊所、综合医院"),
    ("MKT", "商业服务", 1.30, 3, "超市、便利店、菜市场、商场、餐饮"),
    ("CUL", "文体活动", 0.80, 4, "图书馆、文化广场、健身、公园绿地"),
    ("LIFE", "生活服务", 0.90, 5, "银行、快递、理发、维修"),
    ("AGE", "养老助残", 1.00, 6, "养老服务中心、日间照料"),
    ("TRA", "公共交通", 0.70, 7, "公交站、停车场"),
]

# 设施：(分类code, 名称, 距中心距离范围m) —— 2条种子数据，后续补充
facilities = [
    ("EDU", "阳光实验幼儿园", 150, 500),
    ("MED", "社区卫生服务中心", 100, 500),
]

f6 = lambda v: f"{v:.6f}"

# ---------------------------------------------------------------
# 2. 生成 INSERT 语句片段
# ---------------------------------------------------------------

def community_inserts():
    lines = []
    for i, (name, addr, lat, lng, hc, yr) in enumerate(communities, start=1):
        lines.append(
            f"INSERT INTO dbo.community (community_id, community_name, address, region_id, "
            f"longitude, latitude, location, house_count, build_year) VALUES\n"
            f"  ({i}, N'{name}', N'{addr}', 2, {f6(lng)}, {f6(lat)}, "
            f"geography::Point({f6(lat)}, {f6(lng)}, 4326), {hc}, {yr});"
        )
    return "\n".join(lines)


def category_inserts():
    lines = []
    for code, name, w, sort, desc in categories:
        lines.append(
            f"INSERT INTO dbo.facility_category (category_code, category_name, weight, sort_order, description) "
            f"VALUES (N'{code}', N'{name}', {w:.2f}, {sort}, N'{desc}');"
        )
    return "\n".join(lines)


def facility_inserts():
    lines = []
    cat_id = {c[0]: i + 1 for i, c in enumerate(categories)}
    poi = 0
    for code, name, dmin, dmax in facilities:
        poi += 1
        lat, lng = rand_pt(CENTER_LAT, CENTER_LNG, dmin, dmax)
        cid = cat_id[code]
        lines.append(
            f"INSERT INTO dbo.facility (facility_id, facility_name, category_id, address, "
            f"longitude, latitude, location, source, poi_id) VALUES\n"
            f"  ({poi}, N'{name}', {cid}, N'张店区示例路 {poi} 号', {f6(lng)}, {f6(lat)}, "
            f"geography::Point({f6(lat)}, {f6(lng)}, 4326), N'高德地图', N'POI2026{poi:06d}');"
        )
    return "\n".join(lines)


# ---------------------------------------------------------------
# 2b. 爬虫采集的真实 POI 数据（自动主键，不与种子数据冲突）
#     坐标为高德 GCJ-02，按 SRID 4326 入库；课程项目可接受，
#     如需精确 WGS84 可由数据处理模块做坐标纠偏。
# ---------------------------------------------------------------
CRAWLED_CSVS = [
    # (文件路径, 分类ID, poi_id前缀)
    (r"D:\Edge下载\poi_银行_cleaned.csv", 5, "BANK"),  # LIFE 生活服务
    (r"D:\Edge下载\poi_学校_cleaned.csv", 1, "SCH"),   # EDU 教育设施
    (r"D:\Edge下载\poi_商超_cleaned.csv", 3, "MKT"),   # MKT 商业服务
    (r"D:\Edge下载\poi_公园_cleaned.csv", 4, "PARK"),  # CUL 文体活动
    (r"D:\Edge下载\poi_公交站_cleaned.csv", 7, "BUS"), # TRA 公共交通
]


def _sql_escape(s):
    if s is None:
        return ""
    return str(s).replace("'", "''")


def crawled_facility_inserts():
    """读取爬虫CSV，生成不带显式主键的INSERT语句（IDENTITY自动分配）"""
    lines = []
    total = 0
    for path, cat_id, prefix in CRAWLED_CSVS:
        with open(path, "r", encoding="utf-8-sig") as f:
            reader = csv.DictReader(f)
            idx = 0
            for row in reader:
                name = _sql_escape(row.get("名称", "").strip())
                addr = _sql_escape(row.get("地址", "").strip())
                lng = row.get("经度", "").strip()
                lat = row.get("纬度", "").strip()
                if not name or not lng or not lat:
                    continue
                idx += 1
                total += 1
                poi_id = f"POI_{prefix}_{idx:04d}"
                lines.append(
                    f"INSERT INTO dbo.facility (facility_name, category_id, address, "
                    f"longitude, latitude, location, source, poi_id, status) VALUES\n"
                    f"  (N'{name}', {cat_id}, N'{addr}', {lng}, {lat}, "
                    f"geography::Point({lat}, {lng}, 4326), N'高德地图', N'{poi_id}', 1);"
                )
    print(f"  爬虫POI共生成 {total} 条INSERT")
    return "\n".join(lines)


# ---------------------------------------------------------------
# 3. 组装完整 SQL
# ---------------------------------------------------------------
HEADER = r"""/* ============================================================================
   城市社区 15 分钟生活圈便民设施评价与管理系统
   —— 数据库初始化脚本 init_db.sql（方案A：共享SQL脚本）

   使用说明（SSMS）：
   1. 打开本文件（SQL Server Management Studio）
   2. 直接点击工具栏“执行”(F5)
   3. 脚本会自动：创建数据库 -> 建表 -> 建索引 -> 灌入测试数据 -> 创建视图/存储过程

   说明：
   - 数据库名：LifeCircleDB，排序规则 Chinese_PRC_CI_AS（支持中文）
   - 空间数据统一使用 SQL Server 原生 geography 类型，SRID=4326（WGS84经纬度）
     geography::Point(纬度, 经度, 4326) 构建点位；STBuffer(米) 生成缓冲区；
     STIntersects() 判断相交；STDistance() 返回米制距离。
   - 空间索引用于加速缓冲区相交、距离计算等分析查询。
   - 脚本可重复执行：每次执行会先删除旧表/视图/存储过程再重建，刷新测试数据。
   - 测试数据围绕“淄博市张店区示范片区”布点，方便直接演示生活圈分析。
   ============================================================================ */

-- ======================================================================
-- 0. 创建数据库（如不存在）
-- ======================================================================
IF DB_ID(N'LifeCircleDB') IS NULL
BEGIN
    CREATE DATABASE LifeCircleDB COLLATE Chinese_PRC_CI_AS;
END
GO

USE LifeCircleDB;
GO

-- ======================================================================
-- 1. 清理旧对象（保证脚本可重复执行）
--    先删子表/视图/存储过程，再删主表
-- ======================================================================
IF OBJECT_ID('dbo.accessibility_score', 'U') IS NOT NULL DROP TABLE dbo.accessibility_score;
IF OBJECT_ID('dbo.operation_log', 'U') IS NOT NULL DROP TABLE dbo.operation_log;
IF OBJECT_ID('dbo.facility', 'U') IS NOT NULL DROP TABLE dbo.facility;
IF OBJECT_ID('dbo.community', 'U') IS NOT NULL DROP TABLE dbo.community;
IF OBJECT_ID('dbo.facility_staging', 'U') IS NOT NULL DROP TABLE dbo.facility_staging;
IF OBJECT_ID('dbo.facility_category', 'U') IS NOT NULL DROP TABLE dbo.facility_category;
IF OBJECT_ID('dbo.region', 'U') IS NOT NULL DROP TABLE dbo.region;
IF OBJECT_ID('dbo.sys_user', 'U') IS NOT NULL DROP TABLE dbo.sys_user;
IF OBJECT_ID('dbo.sys_role', 'U') IS NOT NULL DROP TABLE dbo.sys_role;
IF OBJECT_ID('dbo.v_facility_category', 'V') IS NOT NULL DROP VIEW dbo.v_facility_category;
IF OBJECT_ID('dbo.v_community_score', 'V') IS NOT NULL DROP VIEW dbo.v_community_score;
IF OBJECT_ID('dbo.sp_community_15min_stats', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_community_15min_stats;
IF OBJECT_ID('dbo.sp_calc_accessibility', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_calc_accessibility;
GO

-- ======================================================================
-- 2. 建表（含空间字段与约束）
-- ======================================================================

-- ---------------------------------------------------------------
-- 2.1 角色表 sys_role
-- ---------------------------------------------------------------
CREATE TABLE dbo.sys_role (
    role_id     INT IDENTITY(1,1) PRIMARY KEY,
    role_code   NVARCHAR(50)  NOT NULL,                       -- 角色编码 admin/operator/viewer
    role_name   NVARCHAR(50)  NOT NULL,                       -- 角色名称
    description NVARCHAR(200) NULL,                           -- 说明
    create_time DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_sys_role_code UNIQUE (role_code)
);
GO

-- ---------------------------------------------------------------
-- 2.2 用户表 sys_user（登录/权限）
-- ---------------------------------------------------------------
CREATE TABLE dbo.sys_user (
    user_id     INT IDENTITY(1,1) PRIMARY KEY,
    username    NVARCHAR(50)  NOT NULL,                       -- 登录名
    password    NVARCHAR(100) NOT NULL,                       -- 密码（存哈希，示例用SHA2_256）
    real_name   NVARCHAR(50)  NULL,                           -- 真实姓名
    phone       NVARCHAR(20)  NULL,
    role_id     INT           NOT NULL,                       -- 所属角色
    status      TINYINT       NOT NULL DEFAULT 1,             -- 1启用 0禁用
    create_time DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    update_time DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_sys_user_username UNIQUE (username),
    CONSTRAINT FK_sys_user_role FOREIGN KEY (role_id) REFERENCES dbo.sys_role(role_id)
);
GO

-- ---------------------------------------------------------------
-- 2.3 行政区划表 region（用于区域裁剪 / 分区统计）
-- ---------------------------------------------------------------
CREATE TABLE dbo.region (
    region_id   INT IDENTITY(1,1) PRIMARY KEY,
    region_name NVARCHAR(100) NOT NULL,
    parent_id   INT           NULL,                           -- 父级区域（省->市->区县->街道）
    region_level TINYINT      NOT NULL DEFAULT 4,             -- 1省 2市 3区县 4街道/片区
    geom        GEOGRAPHY     NULL,                           -- 区域边界（面）
    center      GEOGRAPHY     NULL,                           -- 区域中心点
    create_time DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_region_parent FOREIGN KEY (parent_id) REFERENCES dbo.region(region_id)
);
GO

-- ---------------------------------------------------------------
-- 2.4 居住小区表 community
--     空间字段：location(geography点)，同时冗余经纬度便于Excel导入导出/调试
-- ---------------------------------------------------------------
CREATE TABLE dbo.community (
    community_id   INT IDENTITY(1,1) PRIMARY KEY,
    community_name NVARCHAR(100) NOT NULL,
    address        NVARCHAR(200) NULL,
    region_id      INT           NULL,                        -- 所属片区
    longitude      FLOAT         NULL,                        -- 经度(冗余,便于查看/导入)
    latitude       FLOAT         NULL,                        -- 纬度(冗余,便于查看/导入)
    location       GEOGRAPHY     NULL,                        -- 空间点(geography,4326)
    house_count    INT           NULL,                        -- 户数
    build_year     INT           NULL,                        -- 建成年份
    walk_speed     FLOAT         NOT NULL DEFAULT 1.2,        -- 步行速度(米/秒)，默认1.2≈15分钟1000米
    description    NVARCHAR(500) NULL,
    create_time    DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    update_time    DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_community_lat CHECK (latitude  IS NULL OR (latitude  BETWEEN -90  AND 90)),
    CONSTRAINT CK_community_lng CHECK (longitude IS NULL OR (longitude BETWEEN -180 AND 180)),
    CONSTRAINT FK_community_region FOREIGN KEY (region_id) REFERENCES dbo.region(region_id)
);
GO

-- ---------------------------------------------------------------
-- 2.5 设施分类表 facility_category（生活圈评分权重在此配置）
-- ---------------------------------------------------------------
CREATE TABLE dbo.facility_category (
    category_id   INT IDENTITY(1,1) PRIMARY KEY,
    category_code NVARCHAR(30)  NOT NULL,                     -- 编码 EDU/MED/MKT...
    category_name NVARCHAR(50)  NOT NULL,                     -- 分类名称
    weight        DECIMAL(5,2)  NOT NULL DEFAULT 1.00,        -- 可达性评分权重
    sort_order    INT           NOT NULL DEFAULT 0,           -- 展示排序
    description   NVARCHAR(200) NULL,
    CONSTRAINT UQ_facility_category_code UNIQUE (category_code)
);
GO

-- ---------------------------------------------------------------
-- 2.6 便民设施表 facility（POI 点）
--     空间字段：location(geography点)
--     poi_id：原始POI唯一标识，用于数据去重（过滤唯一索引，允许NULL）
-- ---------------------------------------------------------------
CREATE TABLE dbo.facility (
    facility_id   INT IDENTITY(1,1) PRIMARY KEY,
    facility_name NVARCHAR(100) NOT NULL,
    category_id   INT           NOT NULL,                     -- 所属分类
    address       NVARCHAR(500) NULL,                         -- 地址(公交站存线路列表,可能较长)
    longitude     FLOAT         NULL,
    latitude      FLOAT         NULL,
    location      GEOGRAPHY     NULL,                         -- 空间点(geography,4326)
    source        NVARCHAR(50)  NULL,                         -- 数据来源(高德/百度等)
    poi_id        NVARCHAR(64)  NULL,                         -- 原始POI ID(去重依据)
    status        TINYINT       NOT NULL DEFAULT 1,           -- 1有效 0停用
    create_time   DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_facility_lat CHECK (latitude  IS NULL OR (latitude  BETWEEN -90  AND 90)),
    CONSTRAINT CK_facility_lng CHECK (longitude IS NULL OR (longitude BETWEEN -180 AND 180)),
    CONSTRAINT FK_facility_category FOREIGN KEY (category_id) REFERENCES dbo.facility_category(category_id)
);
GO

-- poi_id 过滤唯一索引：只对非空值去重（SQL Server 普通唯一约束对NULL只允许一个，故用过滤索引）
CREATE UNIQUE INDEX UX_facility_poi ON dbo.facility(poi_id) WHERE poi_id IS NOT NULL;
GO

-- ---------------------------------------------------------------
-- 2.7 可达性评分结果表 accessibility_score（一次批量分析一条记录）
-- ---------------------------------------------------------------
CREATE TABLE dbo.accessibility_score (
    score_id       INT IDENTITY(1,1) PRIMARY KEY,
    community_id   INT           NOT NULL,                    -- 小区
    buffer_radius  INT           NOT NULL DEFAULT 1000,       -- 缓冲区半径(米)
    total_score    DECIMAL(6,2)  NULL,                        -- 综合评分(0-100)
    score_level    NVARCHAR(20)  NULL,                        -- 等级: 优/良/中/差
    facility_count INT           NULL,                        -- 缓冲区内设施总数
    category_count INT           NULL,                        -- 覆盖到的设施类别数
    score_detail   NVARCHAR(MAX) NULL,                        -- 分类明细(JSON: [{category,count}])
    analyze_time   DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_score_community FOREIGN KEY (community_id) REFERENCES dbo.community(community_id)
);
GO
CREATE INDEX IX_score_community ON dbo.accessibility_score(community_id, analyze_time DESC);
GO

-- ---------------------------------------------------------------
-- 2.8 操作日志表 operation_log
-- ---------------------------------------------------------------
CREATE TABLE dbo.operation_log (
    log_id      BIGINT IDENTITY(1,1) PRIMARY KEY,
    user_id     INT           NULL,
    action      NVARCHAR(100) NOT NULL,                       -- 操作内容
    module      NVARCHAR(50)  NULL,                           -- 所属模块
    detail      NVARCHAR(500) NULL,
    ip          NVARCHAR(50)  NULL,
    create_time DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_log_user FOREIGN KEY (user_id) REFERENCES dbo.sys_user(user_id)
);
GO

-- ---------------------------------------------------------------
-- 2.9 原始POI暂存表 facility_staging（数据处理工程师：清洗/去重/纠偏后再入正式表）
-- ---------------------------------------------------------------
CREATE TABLE dbo.facility_staging (
    staging_id      BIGINT IDENTITY(1,1) PRIMARY KEY,
    poi_id          NVARCHAR(64)  NULL,
    raw_name        NVARCHAR(200) NULL,                       -- 原始名称
    raw_category    NVARCHAR(50)  NULL,                       -- 原始分类文本
    raw_lng         FLOAT         NULL,
    raw_lat         FLOAT         NULL,
    source          NVARCHAR(50)  NULL,                       -- 来源(高德/百度)
    raw_json        NVARCHAR(MAX) NULL,                       -- 原始接口返回JSON
    import_time     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
    process_status  TINYINT       NOT NULL DEFAULT 0          -- 0待处理 1已清洗 2已入库
);
GO

-- ======================================================================
-- 3. 空间索引（加速缓冲区/相交/距离分析）
--    注意：SQL Server 每张表每个空间列只能建一个空间索引
-- ======================================================================
CREATE SPATIAL INDEX SIdx_community_location
    ON dbo.community(location)
    WITH (GRIDS = (LEVEL_1 = MEDIUM, LEVEL_2 = MEDIUM, LEVEL_3 = MEDIUM, LEVEL_4 = MEDIUM),
          CELLS_PER_OBJECT = 16);
GO

CREATE SPATIAL INDEX SIdx_facility_location
    ON dbo.facility(location)
    WITH (GRIDS = (LEVEL_1 = MEDIUM, LEVEL_2 = MEDIUM, LEVEL_3 = MEDIUM, LEVEL_4 = MEDIUM),
          CELLS_PER_OBJECT = 16);
GO

CREATE SPATIAL INDEX SIdx_region_geom
    ON dbo.region(geom)
    WITH (GRIDS = (LEVEL_1 = MEDIUM, LEVEL_2 = MEDIUM, LEVEL_3 = MEDIUM, LEVEL_4 = MEDIUM),
          CELLS_PER_OBJECT = 16);
GO

-- ======================================================================
-- 4. 测试数据
-- ======================================================================

-- 4.1 角色
INSERT INTO dbo.sys_role (role_code, role_name, description) VALUES
 (N'admin',    N'系统管理员', N'拥有全部管理权限'),
 (N'operator', N'运营人员',   N'可管理小区与设施数据'),
 (N'viewer',   N'访客',       N'仅可查看地图与分析结果');
GO

-- 4.2 用户（2个种子账号，密码示例统一为 123456 的 SHA2_256 哈希）
INSERT INTO dbo.sys_user (username, password, real_name, phone, role_id, status) VALUES
 (N'admin',    CONVERT(NVARCHAR(64), HASHBYTES('SHA2_256', N'123456'), 2), N'张老师', N'13800000001', 1, 1),
 (N'operator', CONVERT(NVARCHAR(64), HASHBYTES('SHA2_256', N'123456'), 2), N'李运营', N'13800000002', 2, 1);
GO

-- 4.3 行政区划（2行：区县 + 示范片区，演示父子层级，显式主键需开启 IDENTITY_INSERT）
SET IDENTITY_INSERT dbo.region ON;
INSERT INTO dbo.region (region_id, region_name, parent_id, region_level, geom, center) VALUES
 (1, N'张店区', NULL, 3, NULL, NULL),
 (2, N'中心城区示范片区', 1, 4,
     geography::STGeomFromText(
       'POLYGON((118.045 36.800, 118.068 36.800, 118.068 36.822, 118.045 36.822, 118.045 36.800))', 4326),
     geography::Point(36.8100, 118.0550, 4326));
SET IDENTITY_INSERT dbo.region OFF;
GO

-- 4.4 设施分类（评分权重）
"""

DATA_INSERT = """
INSERT INTO dbo.facility_category (category_code, category_name, weight, sort_order, description) VALUES
{category_rows};
GO

-- 4.5 居住小区（测试数据，显式主键需开启 IDENTITY_INSERT）
SET IDENTITY_INSERT dbo.community ON;
{community_rows}
SET IDENTITY_INSERT dbo.community OFF;
GO

-- 4.6 便民设施（种子数据，显式主键需开启 IDENTITY_INSERT）
SET IDENTITY_INSERT dbo.facility ON;
{facility_rows}
SET IDENTITY_INSERT dbo.facility OFF;
GO

-- 4.7 爬虫采集的便民设施 POI（自动主键，坐标为高德GCJ-02按4326入库）
{crawled_rows}
GO
"""

FOOTER = r"""
-- ======================================================================
-- 5. 常用视图
-- ======================================================================

-- 设施+分类视图（前端列表 / GeoJSON 输出常用）
CREATE VIEW dbo.v_facility_category AS
SELECT f.facility_id,
       f.facility_name,
       f.category_id,
       c.category_code,
       c.category_name,
       c.weight,
       f.address,
       f.longitude,
       f.latitude,
       f.location,
       f.source,
       f.poi_id,
       f.status
FROM dbo.facility f
JOIN dbo.facility_category c ON f.category_id = c.category_id;
GO

-- 小区+最近评分视图
CREATE VIEW dbo.v_community_score AS
SELECT c.community_id,
       c.community_name,
       c.address,
       c.longitude,
       c.latitude,
       c.location,
       c.house_count,
       s.total_score,
       s.score_level,
       s.facility_count,
       s.category_count,
       s.buffer_radius,
       s.analyze_time
FROM dbo.community c
LEFT JOIN dbo.accessibility_score s
       ON s.score_id = (SELECT TOP 1 s2.score_id
                        FROM dbo.accessibility_score s2
                        WHERE s2.community_id = c.community_id
                        ORDER BY s2.analyze_time DESC, s2.score_id DESC);
GO

-- ======================================================================
-- 6. 存储过程
-- ======================================================================

-- ----------------------------------------------------------------------
-- 6.1 15分钟生活圈缓冲区分类统计
--     入参：@community_id 小区ID，@radius_m 缓冲区半径(米)，默认1000
--     返回：缓冲区内各设施分类的数量 + 缓冲区内设施总数
-- ----------------------------------------------------------------------
CREATE PROCEDURE dbo.sp_community_15min_stats
    @community_id INT,
    @radius_m     FLOAT = 1000
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @buf GEOGRAPHY;
    SELECT @buf = location.STBuffer(@radius_m)
    FROM dbo.community
    WHERE community_id = @community_id;

    IF @buf IS NULL
    BEGIN
        RAISERROR(N'小区不存在或缺少坐标：community_id=%d', 16, 1, @community_id);
        RETURN;
    END

    -- 按分类汇总（无设施的类别也返回0，便于前端制表）
    SELECT c.category_code,
           c.category_name,
           c.weight,
           COUNT(f.facility_id) AS facility_count
    FROM dbo.facility_category c
    LEFT JOIN dbo.facility f
           ON f.category_id = c.category_id
          AND f.status = 1
          AND f.location.STIntersects(@buf) = 1
    GROUP BY c.category_code, c.category_name, c.weight, c.sort_order
    ORDER BY c.sort_order;

    -- 缓冲区内设施总数
    SELECT COUNT(*) AS total_in_buffer
    FROM dbo.facility f
    WHERE f.status = 1
      AND f.location.STIntersects(@buf) = 1;
END
GO

-- ----------------------------------------------------------------------
-- 6.2 可达性加权评分（参考实现，与后端评分模型一致）
--     模型：每类设施取 min(数量, 上限)/上限 × 100 作为该类得分，
--           再按 category.weight 加权平均得到综合分(0~100)
--     等级：>=85 优，>=70 良，>=55 中，其余 差
--     结果写入 accessibility_score，并返回明细
-- ----------------------------------------------------------------------
CREATE PROCEDURE dbo.sp_calc_accessibility
    @community_id     INT,
    @radius_m         FLOAT = 1000,
    @per_category_cap INT   = 5
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @buf GEOGRAPHY;
    DECLARE @total_score    DECIMAL(6,2);
    DECLARE @facility_count INT;
    DECLARE @category_count INT;
    DECLARE @score_level    NVARCHAR(20);
    DECLARE @detail         NVARCHAR(MAX);

    SELECT @buf = location.STBuffer(@radius_m)
    FROM dbo.community
    WHERE community_id = @community_id;

    IF @buf IS NULL
    BEGIN
        RAISERROR(N'小区不存在或缺少坐标：community_id=%d', 16, 1, @community_id);
        RETURN;
    END

    -- 加权综合得分（覆盖全部分类：某类缺设施按0分计，计入惩罚）
    SELECT @total_score = ROUND(
             SUM(c.weight * (CASE WHEN ISNULL(t.cnt, 0) > @per_category_cap
                                  THEN @per_category_cap ELSE ISNULL(t.cnt, 0) END)
                 * 100.0 / @per_category_cap)
             / NULLIF(SUM(c.weight), 0), 2)
    FROM dbo.facility_category c
    LEFT JOIN (
        SELECT f.category_id, COUNT(*) AS cnt
        FROM dbo.facility f
        WHERE f.status = 1
          AND f.location.STIntersects(@buf) = 1
        GROUP BY f.category_id
    ) t ON t.category_id = c.category_id;

    -- 设施总数 / 类别数
    SELECT @facility_count = COUNT(*)
    FROM dbo.facility f
    WHERE f.status = 1 AND f.location.STIntersects(@buf) = 1;

    SELECT @category_count = COUNT(DISTINCT category_id)
    FROM dbo.facility f
    WHERE f.status = 1 AND f.location.STIntersects(@buf) = 1;

    -- 等级
    SET @score_level = CASE
        WHEN @total_score >= 85 THEN N'优'
        WHEN @total_score >= 70 THEN N'良'
        WHEN @total_score >= 55 THEN N'中'
        ELSE N'差' END;

    -- 分类明细 JSON
    SET @detail = (
        SELECT c.category_code,
               c.category_name,
               COUNT(f.facility_id) AS cnt
        FROM dbo.facility_category c
        LEFT JOIN dbo.facility f
               ON f.category_id = c.category_id
              AND f.status = 1
              AND f.location.STIntersects(@buf) = 1
        GROUP BY c.category_code, c.category_name, c.sort_order
        ORDER BY c.sort_order
        FOR JSON PATH
    );

    INSERT INTO dbo.accessibility_score
        (community_id, buffer_radius, total_score, score_level,
         facility_count, category_count, score_detail)
    VALUES
        (@community_id, @radius_m, @total_score, @score_level,
         @facility_count, @category_count, @detail);

    -- 返回结果
    SELECT @community_id  AS community_id,
           @radius_m      AS buffer_radius,
           @total_score   AS total_score,
           @score_level   AS score_level,
           @facility_count AS facility_count,
           @category_count AS category_count,
           @detail        AS score_detail;
END
GO

-- ======================================================================
-- 7. 自检：运行一次示例分析，验证空间链路可用
-- ======================================================================
PRINT N'== 数据库初始化完成 ==';
SELECT COUNT(*) AS 小区数量 FROM dbo.community;
SELECT COUNT(*) AS 设施数量 FROM dbo.facility;

-- 示例：对 1 号小区做一次 15 分钟生活圈分析（缓冲区1000米）
EXEC dbo.sp_calc_accessibility @community_id = 1, @radius_m = 1000;

-- 示例：查看缓冲区分类统计
EXEC dbo.sp_community_15min_stats @community_id = 1, @radius_m = 1000;
GO

PRINT N'init_db.sql 执行完毕：数据库 LifeCircleDB 已就绪。';
"""


def build():
    cat_rows = ",\n".join(
        f" (N'{c[0]}', N'{c[1]}', {c[2]:.2f}, {c[3]}, N'{c[4]}')" for c in categories
    )
    sql = (
        HEADER
        + DATA_INSERT.format(
            category_rows=cat_rows,
            community_rows=community_inserts(),
            facility_rows=facility_inserts(),
            crawled_rows=crawled_facility_inserts(),
        )
        + FOOTER
    )
    return sql


if __name__ == "__main__":
    sql = build()
    with open(r"C:\Users\Administrator\Doubao\chats\2026-09-03\new-chat\init_db.sql",
              "w", encoding="utf-8-sig", newline="\r\n") as f:
        f.write(sql)
    print("生成完成，字符数:", len(sql))
