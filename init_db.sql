/* ============================================================================
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

INSERT INTO dbo.facility_category (category_code, category_name, weight, sort_order, description) VALUES
 (N'EDU', N'教育设施', 1.00, 1, N'幼儿园、小学、中学等'),
 (N'MED', N'医疗卫生', 1.20, 2, N'社区医院、药店、诊所、综合医院'),
 (N'MKT', N'商业服务', 1.30, 3, N'超市、便利店、菜市场、商场、餐饮'),
 (N'CUL', N'文体活动', 0.80, 4, N'图书馆、文化广场、健身、公园绿地'),
 (N'LIFE', N'生活服务', 0.90, 5, N'银行、快递、理发、维修'),
 (N'AGE', N'养老助残', 1.00, 6, N'养老服务中心、日间照料'),
 (N'TRA', N'公共交通', 0.70, 7, N'公交站、停车场');
GO

-- 4.5 居住小区（测试数据，显式主键需开启 IDENTITY_INSERT）
SET IDENTITY_INSERT dbo.community ON;
INSERT INTO dbo.community (community_id, community_name, address, region_id, longitude, latitude, location, house_count, build_year) VALUES
  (1, N'阳光花园社区', N'张店区人民路 88 号', 2, 118.057458, 36.809748, geography::Point(36.809748, 118.057458, 4326), 1280, 2012);
INSERT INTO dbo.community (community_id, community_name, address, region_id, longitude, latitude, location, house_count, build_year) VALUES
  (2, N'幸福里社区', N'张店区中心路 156 号', 2, 118.051761, 36.810704, geography::Point(36.810704, 118.051761, 4326), 960, 2016);
SET IDENTITY_INSERT dbo.community OFF;
GO

-- 4.6 便民设施（种子数据，显式主键需开启 IDENTITY_INSERT）
SET IDENTITY_INSERT dbo.facility ON;
INSERT INTO dbo.facility (facility_id, facility_name, category_id, address, longitude, latitude, location, source, poi_id) VALUES
  (1, N'阳光实验幼儿园', 1, N'张店区示例路 1 号', 118.058579, 36.810087, geography::Point(36.810087, 118.058579, 4326), N'高德地图', N'POI2026000001');
INSERT INTO dbo.facility (facility_id, facility_name, category_id, address, longitude, latitude, location, source, poi_id) VALUES
  (2, N'社区卫生服务中心', 2, N'张店区示例路 2 号', 118.054921, 36.807902, geography::Point(36.807902, 118.054921, 4326), N'高德地图', N'POI2026000002');
SET IDENTITY_INSERT dbo.facility OFF;
GO

-- 4.7 爬虫采集的便民设施 POI（自动主键，坐标为高德GCJ-02按4326入库）
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(淄博分行)', 5, N'金晶大道158号', 118.063992, 36.813264, geography::Point(36.813264, 118.063992, 4326), N'高德地图', N'POI_BANK_0001', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(淄博张店支行)', 5, N'体育场街道金晶大道146号', 118.063226, 36.810634, geography::Point(36.810634, 118.063226, 4326), N'高德地图', N'POI_BANK_0002', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行(淄博分行营业部)', 5, N'人民西路32号', 118.04272, 36.814771, geography::Point(36.814771, 118.04272, 4326), N'高德地图', N'POI_BANK_0003', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国银行(淄博高新支行)', 5, N'开发区火炬广场北侧(火炬大厦西)', 118.0562, 36.839156, geography::Point(36.839156, 118.0562, 4326), N'高德地图', N'POI_BANK_0004', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(淄博分行营业部)', 5, N'柳泉路168号', 118.052073, 36.812763, geography::Point(36.812763, 118.052073, 4326), N'高德地图', N'POI_BANK_0005', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国人民银行(淄博市分行)', 5, N'心环东路8号', 117.991995, 36.822841, geography::Point(36.822841, 117.991995, 4326), N'高德地图', N'POI_BANK_0006', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行', 5, N'柳泉路政通路路口东北角', 118.059245, 36.840676, geography::Point(36.840676, 118.059245, 4326), N'高德地图', N'POI_BANK_0007', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(淄博张店支行)', 5, N'华光路60号', 118.050488, 36.821167, geography::Point(36.821167, 118.050488, 4326), N'高德地图', N'POI_BANK_0008', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东张店农村商业银行(营业部)', 5, N'柳泉路256号', 118.057487, 36.832725, geography::Point(36.832725, 118.057487, 4326), N'高德地图', N'POI_BANK_0009', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国银行(淄博分行)', 5, N'柳泉路49号中银大厦', 118.051486, 36.815622, geography::Point(36.815622, 118.051486, 4326), N'高德地图', N'POI_BANK_0010', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'招商银行(淄博分行营业部)', 5, N'人民西路12号甲1号', 118.050056, 36.814129, geography::Point(36.814129, 118.050056, 4326), N'高德地图', N'POI_BANK_0011', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行(淄博西城支行)', 5, N'联通路290号', 117.999292, 36.830662, geography::Point(36.830662, 117.999292, 4326), N'高德地图', N'POI_BANK_0012', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'青岛银行(淄博分行)', 5, N'联通路266号', 118.005473, 36.830409, geography::Point(36.830409, 118.005473, 4326), N'高德地图', N'POI_BANK_0013', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中信银行(淄博分行)', 5, N'柳泉路230号中信大厦F1层', 118.054694, 36.823486, geography::Point(36.823486, 118.054694, 4326), N'高德地图', N'POI_BANK_0014', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(高新区支行营业室)', 5, N'柳泉路121路上城名府7号楼', 118.061078, 36.85405, geography::Point(36.85405, 118.061078, 4326), N'高德地图', N'POI_BANK_0015', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'兴业银行(淄博分行)', 5, N'淄博市高新区世纪路218号医药创新中心A综合楼101、201号', 118.027963, 36.84825, geography::Point(36.84825, 118.027963, 4326), N'高德地图', N'POI_BANK_0016', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'招商银行(淄博高新区支行)', 5, N'鲁泰大道51号高分子创新园B座一楼东南角', 118.045891, 36.847872, geography::Point(36.847872, 118.045891, 4326), N'高德地图', N'POI_BANK_0017', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(淄博高新支行营业室)', 5, N'高新区柳泉路268号', 118.059253, 36.84133, geography::Point(36.84133, 118.059253, 4326), N'高德地图', N'POI_BANK_0018', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'威海银行(淄博分行)', 5, N'金誉花园西邻', 118.004672, 36.804277, geography::Point(36.804277, 118.004672, 4326), N'高德地图', N'POI_BANK_0019', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'交通银行(淄博分行)', 5, N'金晶大道100号', 118.061172, 36.805371, geography::Point(36.805371, 118.061172, 4326), N'高德地图', N'POI_BANK_0020', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国银行(淄博北京路支行)', 5, N'北京路33号甲2号', 117.994253, 36.82556, geography::Point(36.82556, 117.994253, 4326), N'高德地图', N'POI_BANK_0021', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'平安银行(淄博分行营业部)', 5, N'高新技术开发区中润大道1号中润华侨城综合楼', 118.03173, 36.838982, geography::Point(36.838982, 118.03173, 4326), N'高德地图', N'POI_BANK_0022', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业发展银行(淄博市分行)', 5, N'高新区万杰路113号', 118.057201, 36.843841, geography::Point(36.843841, 118.057201, 4326), N'高德地图', N'POI_BANK_0023', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国银行(淄博张店支行)', 5, N'新村西路99号东方商务F1层', 118.041443, 36.800945, geography::Point(36.800945, 118.041443, 4326), N'高德地图', N'POI_BANK_0024', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(淄博高新技术产业开发区支行营业部)', 5, N'鲁泰大道99号汇金大厦西裙楼1层', 118.061012, 36.848084, geography::Point(36.848084, 118.061012, 4326), N'高德地图', N'POI_BANK_0025', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国光大银行(淄博分行)', 5, N'柳泉路107号国贸大厦1层', 118.056332, 36.835226, geography::Point(36.835226, 118.056332, 4326), N'高德地图', N'POI_BANK_0026', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'恒丰银行(淄博分行)', 5, N'鲁泰大道51号高分子材料创新园A座一楼', 118.044828, 36.847881, geography::Point(36.847881, 118.044828, 4326), N'高德地图', N'POI_BANK_0027', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'上海浦东发展银行(淄博分行)', 5, N'柳泉路45号甲3号', 118.051127, 36.814154, geography::Point(36.814154, 118.051127, 4326), N'高德地图', N'POI_BANK_0028', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐鲁银行淄博分行', 5, N'北北京路29号', 117.993375, 36.822825, geography::Point(36.822825, 117.993375, 4326), N'高德地图', N'POI_BANK_0029', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'招商银行(淄博西城支行)', 5, N'人民西路222号中德大厦102', 117.991785, 36.817392, geography::Point(36.817392, 117.991785, 4326), N'高德地图', N'POI_BANK_0030', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国银行(淄博西五路支行)', 5, N'中润大道与西五路交汇处(荷香园办公楼1层)', 118.037363, 36.835255, geography::Point(36.835255, 118.037363, 4326), N'高德地图', N'POI_BANK_0031', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(张店北京路支行)', 5, N'北京路中欧国际大厦一层11、12号', 117.993467, 36.820621, geography::Point(36.820621, 117.993467, 4326), N'高德地图', N'POI_BANK_0032', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国银行(淄博齐盛支行)', 5, N'北北京路77号百合花园玉兰园1号楼-3', 117.996027, 36.84445, geography::Point(36.84445, 117.996027, 4326), N'高德地图', N'POI_BANK_0033', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国银行(淄博西城支行)', 5, N'人民路与世纪路交叉口富尔玛家居广场1楼', 118.025931, 36.814661, geography::Point(36.814661, 118.025931, 4326), N'高德地图', N'POI_BANK_0034', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国银行(新村西路支行)', 5, N'马尚镇新村西路大学生创业园A座一层', 118.014888, 36.803372, geography::Point(36.803372, 118.014888, 4326), N'高德地图', N'POI_BANK_0035', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'渤海银行(淄博分行)', 5, N'华光路和北西六路交汇处黄金1号公馆', 118.031609, 36.822191, geography::Point(36.822191, 118.031609, 4326), N'高德地图', N'POI_BANK_0036', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行(淄博植物园支行)', 5, N'王舍路235号', 118.030294, 36.789618, geography::Point(36.789618, 118.030294, 4326), N'高德地图', N'POI_BANK_0037', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(淄博支行)', 5, N'柳泉路115号金达大厦C座', 118.058019, 36.842258, geography::Point(36.842258, 118.058019, 4326), N'高德地图', N'POI_BANK_0038', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行(共青团东路支行)', 5, N'共青团东路6号甲1号', 118.061887, 36.804504, geography::Point(36.804504, 118.061887, 4326), N'高德地图', N'POI_BANK_0039', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中信银行(淄博高新支行)', 5, N'中润大道33号', 118.031427, 36.837882, geography::Point(36.837882, 118.031427, 4326), N'高德地图', N'POI_BANK_0040', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'兴业银行淄博柳泉路社区支行', 5, N'柳泉路103号', 118.056034, 36.833281, geography::Point(36.833281, 118.056034, 4326), N'高德地图', N'POI_BANK_0041', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行淄博张店和平路支行', 5, N'淄博市张店区和平路169号甲8商铺', 117.992025, 36.799475, geography::Point(36.799475, 117.992025, 4326), N'高德地图', N'POI_BANK_0042', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(经开区支行)', 5, N'王舍路生态环境管理服务中心1楼', 118.013164, 36.791468, geography::Point(36.791468, 118.013164, 4326), N'高德地图', N'POI_BANK_0043', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行(学府支行)', 5, N'南京路11号', 118.012343, 36.810248, geography::Point(36.810248, 118.012343, 4326), N'高德地图', N'POI_BANK_0044', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'济宁银行(淄博分行)', 5, N'南京路宏程国际广场济宁银行', 118.011365, 36.826343, geography::Point(36.826343, 118.011365, 4326), N'高德地图', N'POI_BANK_0045', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'青岛银行(淄博高新支行)', 5, N'张店区高新区中润大道39号', 118.036013, 36.837675, geography::Point(36.837675, 118.036013, 4326), N'高德地图', N'POI_BANK_0046', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(鲁中支行营业室)', 5, N'新村西路142号', 118.045369, 36.801369, geography::Point(36.801369, 118.045369, 4326), N'高德地图', N'POI_BANK_0047', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(南京路支行)', 5, N'南京路与联通路交叉口淄博住房公积金中心办公大楼东侧', 118.015295, 36.830016, geography::Point(36.830016, 118.015295, 4326), N'高德地图', N'POI_BANK_0048', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行(张店支行营业室)', 5, N'共青团路95号钻石商务大厦9层西半层', 118.048228, 36.806518, geography::Point(36.806518, 118.048228, 4326), N'高德地图', N'POI_BANK_0049', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(淄博湖田分理处)', 5, N'湖田镇湖光路17号', 118.125782, 36.789846, geography::Point(36.789846, 118.125782, 4326), N'高德地图', N'POI_BANK_0050', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国银行(淄博金晶大道支行)', 5, N'新村东路2号', 118.05945, 36.797797, geography::Point(36.797797, 118.05945, 4326), N'高德地图', N'POI_BANK_0051', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国银行(淄博经济开发区支行)', 5, N'南定镇张南路13号', 118.046681, 36.749524, geography::Point(36.749524, 118.046681, 4326), N'高德地图', N'POI_BANK_0052', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行(淄博南京路支行)', 5, N'联通路190号', 118.014253, 36.830012, geography::Point(36.830012, 118.014253, 4326), N'高德地图', N'POI_BANK_0053', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行股份有限公司淄博盛湖路支行', 5, N'北京路与盛湖路交叉路口东北角盛湖大厦一楼', 117.997802, 36.844273, geography::Point(36.844273, 117.997802, 4326), N'高德地图', N'POI_BANK_0054', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(张店支行营业室)', 5, N'金晶大道130号', 118.061823, 36.808142, geography::Point(36.808142, 118.061823, 4326), N'高德地图', N'POI_BANK_0055', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(张店理工大学支行)', 5, N'人民西路石村南巷水晶街H座一层', 118.006335, 36.816142, geography::Point(36.816142, 118.006335, 4326), N'高德地图', N'POI_BANK_0056', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(王舍支行)', 5, N'南西五路40号', 118.033401, 36.789286, geography::Point(36.789286, 118.033401, 4326), N'高德地图', N'POI_BANK_0057', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(世纪路支行)', 5, N'世纪路106号', 118.025867, 36.8133, geography::Point(36.8133, 118.025867, 4326), N'高德地图', N'POI_BANK_0058', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(华侨城支行)', 5, N'高新区中润华侨城北商业楼6号7', 118.032373, 36.846553, geography::Point(36.846553, 118.032373, 4326), N'高德地图', N'POI_BANK_0059', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(淄博天津路支行)', 5, N'天津路和汇英路交叉路口西100米', 117.971116, 36.827547, geography::Point(36.827547, 117.971116, 4326), N'高德地图', N'POI_BANK_0060', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(人民西路支行)', 5, N'人民西路43号甲1号', 118.034348, 36.813874, geography::Point(36.813874, 118.034348, 4326), N'高德地图', N'POI_BANK_0061', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(盛湖支行)', 5, N'盛湖路与丰泰路交叉口东北80米', 118.002083, 36.844188, geography::Point(36.844188, 118.002083, 4326), N'高德地图', N'POI_BANK_0062', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(淄博市张店区支行)', 5, N'重庆路与人民西路交叉口水晶街F-07号', 118.004158, 36.816305, geography::Point(36.816305, 118.004158, 4326), N'高德地图', N'POI_BANK_0063', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(淄博马尚支行)', 5, N'共青团西路120号(时代大厦1层)', 118.031756, 36.808476, geography::Point(36.808476, 118.031756, 4326), N'高德地图', N'POI_BANK_0064', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(中心路支行)', 5, N'中心路39号', 118.057853, 36.794566, geography::Point(36.794566, 118.057853, 4326), N'高德地图', N'POI_BANK_0065', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'交通银行(淄博经济开发区支行)', 5, N'山泉路221甲22号1层、23号1-2层', 118.034982, 36.761225, geography::Point(36.761225, 118.034982, 4326), N'高德地图', N'POI_BANK_0066', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(开发支行)', 5, N'柳泉路97号', 118.054975, 36.829783, geography::Point(36.829783, 118.054975, 4326), N'高德地图', N'POI_BANK_0067', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行(淄博翡翠书院支行)', 5, N'盛湖路111号翡翠书院24号楼101号-105号', 118.009128, 36.841076, geography::Point(36.841076, 118.009128, 4326), N'高德地图', N'POI_BANK_0068', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行(淄博华光路支行)', 5, N'华光路68号甲16号', 118.047017, 36.821203, geography::Point(36.821203, 118.047017, 4326), N'高德地图', N'POI_BANK_0069', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(城西支行)', 5, N'人民西路188号钱裕园小区甲1号楼', 117.999133, 36.816601, geography::Point(36.816601, 117.999133, 4326), N'高德地图', N'POI_BANK_0070', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国银行(淄博王舍路支行)', 5, N'王舍路237号国华大厦F1层', 118.029545, 36.789493, geography::Point(36.789493, 118.029545, 4326), N'高德地图', N'POI_BANK_0071', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(世纪花园支行)', 5, N'联通路166号', 118.016356, 36.830052, geography::Point(36.830052, 118.016356, 4326), N'高德地图', N'POI_BANK_0072', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'恒丰银行(淄博张店支行)', 5, N'金晶大道187甲26号-29号', 118.061192, 36.809171, geography::Point(36.809171, 118.061192, 4326), N'高德地图', N'POI_BANK_0073', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(建筑陶瓷城支行)', 5, N'昌国路105号', 118.019237, 36.785456, geography::Point(36.785456, 118.019237, 4326), N'高德地图', N'POI_BANK_0074', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东营银行(淄博分行)', 5, N'华光路28号云龙国际A座F1层', 118.063547, 36.819139, geography::Point(36.819139, 118.063547, 4326), N'高德地图', N'POI_BANK_0075', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'交通银行(淄博张店支行)', 5, N'人民西路222号中德国际大厦1层', 117.991548, 36.817434, geography::Point(36.817434, 117.991548, 4326), N'高德地图', N'POI_BANK_0076', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(淄博中心路分理处)', 5, N'金晶大道44号甲7号温州大厦青年家园F1层', 118.059504, 36.798483, geography::Point(36.798483, 118.059504, 4326), N'高德地图', N'POI_BANK_0077', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行(淄博经济开发区支行)', 5, N'花园路与青年公园路交叉口东北20米', 118.048475, 36.757425, geography::Point(36.757425, 118.048475, 4326), N'高德地图', N'POI_BANK_0078', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'交通银行(淄博高新区支行)', 5, N'柳泉路111号火炬广场102', 118.057148, 36.840432, geography::Point(36.840432, 118.057148, 4326), N'高德地图', N'POI_BANK_0079', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(新城区支行营业部)', 5, N'新村西路177号汇美大厦F1层', 118.019987, 36.803111, geography::Point(36.803111, 118.019987, 4326), N'高德地图', N'POI_BANK_0080', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行(淄博华侨城支行)', 5, N'中润大道1号新玛特购物广场中润店F1层', 118.027207, 36.838426, geography::Point(36.838426, 118.027207, 4326), N'高德地图', N'POI_BANK_0081', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(丽景苑支行)', 5, N'科苑街道北西五路38号甲4号', 118.037465, 36.825341, geography::Point(36.825341, 118.037465, 4326), N'高德地图', N'POI_BANK_0082', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(北京路分理处)', 5, N'宏程金融中心1楼心环东路2号', 117.990746, 36.820039, geography::Point(36.820039, 117.990746, 4326), N'高德地图', N'POI_BANK_0083', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(淄博市分行)', 5, N'华光路88号远通大厦F1层', 118.040738, 36.821586, geography::Point(36.821586, 118.040738, 4326), N'高德地图', N'POI_BANK_0084', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'济宁银行(淄博张店支行)', 5, N'新村西路158号凤阳大厦附楼一楼', 118.042492, 36.80264, geography::Point(36.80264, 118.042492, 4326), N'高德地图', N'POI_BANK_0085', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(淄博经开区支行)', 5, N'南定镇花园路23号', 118.045571, 36.753603, geography::Point(36.753603, 118.045571, 4326), N'高德地图', N'POI_BANK_0086', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行(金晶大道支行)', 5, N'金晶大道170号', 118.065378, 36.818012, geography::Point(36.818012, 118.065378, 4326), N'高德地图', N'POI_BANK_0087', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行(淄博西七路支行)', 5, N'共青团西路138号金茂大厦A座F1层', 118.027461, 36.808882, geography::Point(36.808882, 118.027461, 4326), N'高德地图', N'POI_BANK_0088', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(淄博张店体坛支行)', 5, N'南西六路31号', 118.032116, 36.80306, geography::Point(36.80306, 118.032116, 4326), N'高德地图', N'POI_BANK_0089', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(淄博名尚银泰支行)', 5, N'鲁泰大道9号银泰·金街1F层', 118.036586, 36.848351, geography::Point(36.848351, 118.036586, 4326), N'高德地图', N'POI_BANK_0090', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(淄博城西支行)', 5, N'和平路131号甲4号', 117.999063, 36.79888, geography::Point(36.79888, 117.999063, 4326), N'高德地图', N'POI_BANK_0091', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(华侨城支行)', 5, N'中润大道5号5号甲1号', 118.033659, 36.837805, geography::Point(36.837805, 118.033659, 4326), N'高德地图', N'POI_BANK_0092', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东张店农村商业银行(世纪路支行)', 5, N'共青团西路181号', 118.024128, 36.808525, geography::Point(36.808525, 118.024128, 4326), N'高德地图', N'POI_BANK_0093', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(淄博重庆路支行)', 5, N'联通路266号', 118.004764, 36.830453, geography::Point(36.830453, 118.004764, 4326), N'高德地图', N'POI_BANK_0094', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(淄博理工大学支行)', 5, N'张周路12号山东理工大学校内(博大花园淄博商厦超市旁)', 118.006127, 36.811187, geography::Point(36.811187, 118.006127, 4326), N'高德地图', N'POI_BANK_0095', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'兴业银行(张店支行)', 5, N'首丰大厦南门旁', 118.026103, 36.785986, geography::Point(36.785986, 118.026103, 4326), N'高德地图', N'POI_BANK_0096', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(淄博张店鑫城支行)', 5, N'马尚街道新村西路179号鑫城中心C座1楼西首', 118.016158, 36.803244, geography::Point(36.803244, 118.016158, 4326), N'高德地图', N'POI_BANK_0097', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(淄博张店丽景苑支行)', 5, N'马尚镇北西五路36号', 118.037318, 36.824632, geography::Point(36.824632, 118.037318, 4326), N'高德地图', N'POI_BANK_0098', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国银行股份有限公司淄博潘南东路支行', 5, N'潘南东路19号甲6甲7甲8号甲9号', 118.078412, 36.811882, geography::Point(36.811882, 118.078412, 4326), N'高德地图', N'POI_BANK_0099', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(淄博高新丰悦支行)', 5, N'丰悦路富力万达广场项目S2号沿街商用房(S107-109、S207-209)', 118.009708, 36.841749, geography::Point(36.841749, 118.009708, 4326), N'高德地图', N'POI_BANK_0100', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'交通银行(淄博颐丰支行)', 5, N'颐丰花园颐盛园21号楼5号一层', 118.001445, 36.841483, geography::Point(36.841483, 118.001445, 4326), N'高德地图', N'POI_BANK_0101', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东张店农村商业银行(新村西路支行)', 5, N'新村西路150号甲1号', 118.044794, 36.801424, geography::Point(36.801424, 118.044794, 4326), N'高德地图', N'POI_BANK_0102', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'渤海银行(中润大道支行)', 5, N'中润大道与西八路交叉口东150米路北', 118.016298, 36.838123, geography::Point(36.838123, 118.016298, 4326), N'高德地图', N'POI_BANK_0103', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'交通银行(淄博体育馆支行)', 5, N'新村西路186号甲8号(金梦园大酒店东邻)', 118.028238, 36.803144, geography::Point(36.803144, 118.028238, 4326), N'高德地图', N'POI_BANK_0104', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(城中支行)', 5, N'华光路46号甲13号', 118.058253, 36.819981, geography::Point(36.819981, 118.058253, 4326), N'高德地图', N'POI_BANK_0105', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(淄博南京路分理处)', 5, N'南京路宏程国际广场11号楼101', 118.011407, 36.826725, geography::Point(36.826725, 118.011407, 4326), N'高德地图', N'POI_BANK_0106', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国银行(淄博黄金国际支行)', 5, N'华光路116号德泰智汇广场F1层', 118.027919, 36.822268, geography::Point(36.822268, 118.027919, 4326), N'高德地图', N'POI_BANK_0107', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东营银行(张店支行)', 5, N'南西六路27号', 118.03208, 36.802717, geography::Point(36.802717, 118.03208, 4326), N'高德地图', N'POI_BANK_0108', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(通济支行)', 5, N'世纪路44号', 118.025461, 36.802596, geography::Point(36.802596, 118.025461, 4326), N'高德地图', N'POI_BANK_0109', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(共青团支行)', 5, N'共青团西路3号', 118.05796, 36.805085, geography::Point(36.805085, 118.05796, 4326), N'高德地图', N'POI_BANK_0110', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(凯瑞园支行)', 5, N'人民西路166号', 118.015091, 36.815435, geography::Point(36.815435, 118.015091, 4326), N'高德地图', N'POI_BANK_0111', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(柳泉路支行)', 5, N'共青团西路71号园林大厦F1层', 118.049245, 36.806448, geography::Point(36.806448, 118.049245, 4326), N'高德地图', N'POI_BANK_0112', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农商银行(中埠支行)', 5, N'中埠镇中埠村南首', 118.188753, 36.846304, geography::Point(36.846304, 118.188753, 4326), N'高德地图', N'POI_BANK_0113', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(兴学街营业所)', 5, N'兴学街93号', 118.047149, 36.793986, geography::Point(36.793986, 118.047149, 4326), N'高德地图', N'POI_BANK_0114', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农村商业银行(西二路支行)', 5, N'西二路175号金丰商务楼F1层', 118.054951, 36.804917, geography::Point(36.804917, 118.054951, 4326), N'高德地图', N'POI_BANK_0115', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(公园支行)', 5, N'共青团西路84号', 118.04578, 36.807539, geography::Point(36.807539, 118.04578, 4326), N'高德地图', N'POI_BANK_0116', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(山铝支行)', 5, N'南定镇山铝西山五街1号', 118.042813, 36.754503, geography::Point(36.754503, 118.042813, 4326), N'高德地图', N'POI_BANK_0117', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行(政务中心支行)', 5, N'新村西路与西四路交叉口东北(凤阳大厦一层)', 118.042525, 36.802, geography::Point(36.802, 118.042525, 4326), N'高德地图', N'POI_BANK_0118', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行(淄博人民西路支行)', 5, N'人民西路1号华润中央公园5号楼', 118.0602, 36.811537, geography::Point(36.811537, 118.0602, 4326), N'高德地图', N'POI_BANK_0119', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农村商业银行(华光路支行)', 5, N'华光路36号', 118.062533, 36.819322, geography::Point(36.819322, 118.062533, 4326), N'高德地图', N'POI_BANK_0120', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农商银行(高新区支行)', 5, N'中心路271号', 118.072134, 36.843463, geography::Point(36.843463, 118.072134, 4326), N'高德地图', N'POI_BANK_0121', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(张店西城支行)(装修中)', 5, N'义乌商城街47号', 118.018275, 36.824125, geography::Point(36.824125, 118.018275, 4326), N'高德地图', N'POI_BANK_0122', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(丽景苑支行)', 5, N'北西五路38甲2丽景苑小区2号综合楼', 118.03763, 36.824871, geography::Point(36.824871, 118.03763, 4326), N'高德地图', N'POI_BANK_0123', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(科学城支行)', 5, N'裕民路与北西六路交汇处南石社区5号沿街房', 118.03551, 36.864697, geography::Point(36.864697, 118.03551, 4326), N'高德地图', N'POI_BANK_0124', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(莲池支行)', 5, N'北西六路98号', 118.032719, 36.829156, geography::Point(36.829156, 118.032719, 4326), N'高德地图', N'POI_BANK_0125', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(华光路支行)', 5, N'华光路46号甲23号', 118.057721, 36.820093, geography::Point(36.820093, 118.057721, 4326), N'高德地图', N'POI_BANK_0126', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'上海浦东发展银行(世纪花园社区支行)', 5, N'世纪花园冬韵园13号楼', 118.016778, 36.833089, geography::Point(36.833089, 118.016778, 4326), N'高德地图', N'POI_BANK_0127', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行', 5, N'北西五路6号甲1号', 118.037257, 36.810048, geography::Point(36.810048, 118.037257, 4326), N'高德地图', N'POI_BANK_0128', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(和平支行)', 5, N'世纪路与复兴路交叉口西南角', 118.023276, 36.780479, geography::Point(36.780479, 118.023276, 4326), N'高德地图', N'POI_BANK_0129', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(淄博张店车站支行)', 5, N'金晶大道19号泰星大酒店', 118.057606, 36.792793, geography::Point(36.792793, 118.057606, 4326), N'高德地图', N'POI_BANK_0130', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(杏园路支行)', 5, N'杏园东路58号', 118.071983, 36.786976, geography::Point(36.786976, 118.071983, 4326), N'高德地图', N'POI_BANK_0131', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(体坛支行)', 5, N'柳泉路13号甲5号', 118.046526, 36.795888, geography::Point(36.795888, 118.046526, 4326), N'高德地图', N'POI_BANK_0132', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(淄博先创区支行)', 5, N'傅山村商贸中心西侧', 118.140554, 36.87663, geography::Point(36.87663, 118.140554, 4326), N'高德地图', N'POI_BANK_0133', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(科技支行)', 5, N'北西六路5号甲5号山东齐赛创意动漫科技大厦F1层', 118.032527, 36.811395, geography::Point(36.811395, 118.032527, 4326), N'高德地图', N'POI_BANK_0134', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行淄博市高新技术产业开发区支行', 5, N'九宏大厦', 118.035773, 36.837717, geography::Point(36.837717, 118.035773, 4326), N'高德地图', N'POI_BANK_0135', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东张店农村商业银行(怡海世家支行)', 5, N'科苑街道世纪路170号', 118.026715, 36.831666, geography::Point(36.831666, 118.026715, 4326), N'高德地图', N'POI_BANK_0136', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(人民路支行)', 5, N'人民西路23号', 118.044842, 36.813905, geography::Point(36.813905, 118.044842, 4326), N'高德地图', N'POI_BANK_0137', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农商银行(马尚支行)', 5, N'和平路169号甲4号', 117.992865, 36.799286, geography::Point(36.799286, 117.992865, 4326), N'高德地图', N'POI_BANK_0138', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'上海浦东发展银行股份有限公司淄博鲁中家具城小微支行', 5, N'南西四路路东家具城1层西南角', 118.042385, 36.803451, geography::Point(36.803451, 118.042385, 4326), N'高德地图', N'POI_BANK_0139', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行(联通路分理处)(装修中)', 5, N'联通路62-8号', 118.044856, 36.828423, geography::Point(36.828423, 118.044856, 4326), N'高德地图', N'POI_BANK_0140', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(黄金国际支行)', 5, N'黄金国际北2门旁', 118.029687, 36.828806, geography::Point(36.828806, 118.029687, 4326), N'高德地图', N'POI_BANK_0141', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行金晶大道支行', 5, N'车站街道金晶大道105号齐商银行信息科技部', 118.05875, 36.799661, geography::Point(36.799661, 118.05875, 4326), N'高德地图', N'POI_BANK_0142', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农商银行(南定支行)', 5, N'南定镇张南路127号', 118.042332, 36.738178, geography::Point(36.738178, 118.042332, 4326), N'高德地图', N'POI_BANK_0143', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行(淄博城中支行)', 5, N'华光路116号彩世界精品皮草广场F1层', 118.030458, 36.822104, geography::Point(36.822104, 118.030458, 4326), N'高德地图', N'POI_BANK_0144', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(共青团东路支行)', 5, N'凯旋门东门旁', 118.063229, 36.802749, geography::Point(36.802749, 118.063229, 4326), N'高德地图', N'POI_BANK_0145', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(淄博山铝分理处)', 5, N'山铝花园路29号铝城购物中心东邻', 118.045932, 36.752906, geography::Point(36.752906, 118.045932, 4326), N'高德地图', N'POI_BANK_0146', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农商银行(付家支行)', 5, N'华福大道与重庆路交叉口东北40米', 117.99847, 36.762456, geography::Point(36.762456, 117.99847, 4326), N'高德地图', N'POI_BANK_0147', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店区农村商业银行(颐丰苑支行)', 5, N'颐丰花园颐臻园南门东170米', 118.000704, 36.84147, geography::Point(36.84147, 118.000704, 4326), N'高德地图', N'POI_BANK_0148', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国民生银行(淄博齐盛湖社区支行)', 5, N'北重庆路369号方正凤凰国际东区14号楼2号', 118.000731, 36.836582, geography::Point(36.836582, 118.000731, 4326), N'高德地图', N'POI_BANK_0149', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行(世纪路支行)', 5, N'人民西路77号花好园1楼', 118.024404, 36.813927, geography::Point(36.813927, 118.024404, 4326), N'高德地图', N'POI_BANK_0150', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'兴业银行(世纪花园社区支行)', 5, N'世纪路115号世纪花园中心公园2号1楼', 118.018246, 36.833111, geography::Point(36.833111, 118.018246, 4326), N'高德地图', N'POI_BANK_0151', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(华侨城支行)', 5, N'中润大道与西五路交叉口西北角九宏大厦一层东首', 118.036189, 36.83785, geography::Point(36.83785, 118.036189, 4326), N'高德地图', N'POI_BANK_0152', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(柳泉路支行)', 5, N'柳泉路与新村西路交叉口西北角时代超市1FA4铺', 118.048134, 36.802208, geography::Point(36.802208, 118.048134, 4326), N'高德地图', N'POI_BANK_0153', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农村商业银行(城北支行)', 5, N'中润大道99号', 118.048689, 36.837336, geography::Point(36.837336, 118.048689, 4326), N'高德地图', N'POI_BANK_0154', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(义乌商城支行)', 5, N'华光路268号义乌小商品城广场街28-29号', 118.021214, 36.82305, geography::Point(36.82305, 118.021214, 4326), N'高德地图', N'POI_BANK_0155', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(高新紫荆苑支行)', 5, N'紫荆路2号甲7号', 118.054462, 36.832694, geography::Point(36.832694, 118.054462, 4326), N'高德地图', N'POI_BANK_0156', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东张店农村商业银行(莲池支行)', 5, N'联通路80号', 118.035635, 36.829086, geography::Point(36.829086, 118.035635, 4326), N'高德地图', N'POI_BANK_0157', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'交通银行(华侨城支行)', 5, N'高新区中润大道39甲1一层', 118.035572, 36.837721, geography::Point(36.837721, 118.035572, 4326), N'高德地图', N'POI_BANK_0158', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(共青团西路营业所)', 5, N'共青团西路1号', 118.06011, 36.804837, geography::Point(36.804837, 118.06011, 4326), N'高德地图', N'POI_BANK_0159', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农村商业银行(盛世康城分理处)', 5, N'盛世康城23号商住楼', 118.023064, 36.778546, geography::Point(36.778546, 118.023064, 4326), N'高德地图', N'POI_BANK_0160', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(张北支行)', 5, N'金晶大道199号甲1号', 118.063747, 36.815725, geography::Point(36.815725, 118.063747, 4326), N'高德地图', N'POI_BANK_0161', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(淄博新区支行)', 5, N'心环东路6号润德大厦26、27、28号沿街房', 117.991578, 36.822028, geography::Point(36.822028, 117.991578, 4326), N'高德地图', N'POI_BANK_0162', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东张店农村商业银行(湖田支行)', 5, N'湖光路21号', 118.12706, 36.789352, geography::Point(36.789352, 118.12706, 4326), N'高德地图', N'POI_BANK_0163', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东张店农村商业银行(阳光支行)', 5, N'西七路北首阳光花园28号楼', 118.024823, 36.841675, geography::Point(36.841675, 118.024823, 4326), N'高德地图', N'POI_BANK_0164', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(明清街营业所)', 5, N'张桓路36号甲20号', 118.044113, 36.833966, geography::Point(36.833966, 118.044113, 4326), N'高德地图', N'POI_BANK_0165', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(华光路支行)', 5, N'华光路82号', 118.042497, 36.821622, geography::Point(36.821622, 118.042497, 4326), N'高德地图', N'POI_BANK_0166', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'兴业银行(淄博凯瑞园社区支行)', 5, N'人民西路215号', 118.017313, 36.814445, geography::Point(36.814445, 118.017313, 4326), N'高德地图', N'POI_BANK_0167', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东张店农村商业银行(高铁新城支行)', 5, N'裕民路中国联通西60米', 118.031912, 36.865857, geography::Point(36.865857, 118.031912, 4326), N'高德地图', N'POI_BANK_0168', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农商银行(西城支行)', 5, N'华光路272号博大广场', 118.01733, 36.822934, geography::Point(36.822934, 118.01733, 4326), N'高德地图', N'POI_BANK_0169', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(湖田分理处)', 5, N'新村东路与富裕路交叉口东北40米', 118.096499, 36.79363, geography::Point(36.79363, 118.096499, 4326), N'高德地图', N'POI_BANK_0170', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(义乌商品城支行)', 5, N'华光路188号玉龙大厦B座F1层', 118.024309, 36.822558, geography::Point(36.822558, 118.024309, 4326), N'高德地图', N'POI_BANK_0171', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'浦发银行(世纪金源小微支行)', 5, N'柳泉路77号世纪新世界广场2号楼F1层', 118.054033, 36.825317, geography::Point(36.825317, 118.054033, 4326), N'高德地图', N'POI_BANK_0172', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农村商业银行(杏园支行)', 5, N'宝沣路1号', 118.077668, 36.773851, geography::Point(36.773851, 118.077668, 4326), N'高德地图', N'POI_BANK_0173', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(淄博城东支行)', 5, N'沣水镇城东路1号(沣水镇政府西邻)', 118.088594, 36.752221, geography::Point(36.752221, 118.088594, 4326), N'高德地图', N'POI_BANK_0174', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农村商业银行(经开区支行)', 5, N'王舍路与南京路交叉口东280米', 118.012722, 36.7915, geography::Point(36.7915, 118.012722, 4326), N'高德地图', N'POI_BANK_0175', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(淄博经济开发区支行)', 5, N'昌盛路36号甲3号', 118.049278, 36.736613, geography::Point(36.736613, 118.049278, 4326), N'高德地图', N'POI_BANK_0176', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农村商业银行(四宝山支行)', 5, N'宝山路97号', 118.099512, 36.838177, geography::Point(36.838177, 118.099512, 4326), N'高德地图', N'POI_BANK_0177', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东张店农村商业银行(乔庄支行)', 5, N'潘南东路17号', 118.075581, 36.812697, geography::Point(36.812697, 118.075581, 4326), N'高德地图', N'POI_BANK_0178', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国工商银行(工业路支行)', 5, N'南定镇工业路8号', 118.047475, 36.750975, geography::Point(36.750975, 118.047475, 4326), N'高德地图', N'POI_BANK_0179', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农村商业银行(迎宾路支行)', 5, N'昌国路鑫盛嘉园', 118.020692, 36.786624, geography::Point(36.786624, 118.020692, 4326), N'高德地图', N'POI_BANK_0180', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国建设银行', 5, N'南西六路与和平路交叉口北160米', 118.031485, 36.798748, geography::Point(36.798748, 118.031485, 4326), N'高德地图', N'POI_BANK_0181', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东张店农村商业银行(刘东分理处)', 5, N'铭波路3号', 118.04337, 36.849224, geography::Point(36.849224, 118.04337, 4326), N'高德地图', N'POI_BANK_0182', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农村商业银行祥瑞花园支行', 5, N'马尚镇华光路286号祥瑞园', 118.008072, 36.824887, geography::Point(36.824887, 118.008072, 4326), N'高德地图', N'POI_BANK_0183', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(天齐支行)', 5, N'和平街道美食街13号', 118.057668, 36.801615, geography::Point(36.801615, 118.057668, 4326), N'高德地图', N'POI_BANK_0184', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农商银行(王舍支行)', 5, N'王舍路与一区西路交叉口南240米', 118.038376, 36.786725, geography::Point(36.786725, 118.038376, 4326), N'高德地图', N'POI_BANK_0185', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(西六路营业所)', 5, N'南西六路55号', 118.031705, 36.800855, geography::Point(36.800855, 118.031705, 4326), N'高德地图', N'POI_BANK_0186', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(房镇支行)', 5, N'房镇镇齐盛路242号', 117.968576, 36.835506, geography::Point(36.835506, 117.968576, 4326), N'高德地图', N'POI_BANK_0187', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农商银行(林泽花园支行)', 5, N'浅海牧羊村烧烤东北门东140米', 117.995934, 36.819804, geography::Point(36.819804, 117.995934, 4326), N'高德地图', N'POI_BANK_0188', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东张店农村商业银行(杜科分理处)', 5, N'东三路2号甲1号', 118.072887, 36.803614, geography::Point(36.803614, 118.072887, 4326), N'高德地图', N'POI_BANK_0189', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农商银行房镇支行', 5, N'济南路与齐盛路交叉口西北40米', 117.969156, 36.835597, geography::Point(36.835597, 117.969156, 4326), N'高德地图', N'POI_BANK_0190', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东营银行(淄博经开支行)', 5, N'世纪路与考工路西北角', 118.022327, 36.775367, geography::Point(36.775367, 118.022327, 4326), N'高德地图', N'POI_BANK_0191', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东营银行(淄博高新支行)', 5, N'中润大道5号甲20号', 118.034256, 36.837798, geography::Point(36.837798, 118.034256, 4326), N'高德地图', N'POI_BANK_0192', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农商银行(卫固支行)', 5, N'卫固镇', 118.144935, 36.867536, geography::Point(36.867536, 118.144935, 4326), N'高德地图', N'POI_BANK_0193', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(西山营业所)', 5, N'西山四街西巷5号楼33-5号', 118.036103, 36.75278, geography::Point(36.75278, 118.036103, 4326), N'高德地图', N'POI_BANK_0194', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'兴业银行淄博绿城百合花园社区支行', 5, N'房镇镇北北京路77号百合花园桂花园9号楼1层102铺105铺', 117.993758, 36.846853, geography::Point(36.846853, 117.993758, 4326), N'高德地图', N'POI_BANK_0195', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农村商业银行(明清街支行)', 5, N'华光路72号甲16号', 118.045282, 36.821335, geography::Point(36.821335, 118.045282, 4326), N'高德地图', N'POI_BANK_0196', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(淄博市第三营业所)', 5, N'共青团西路86号', 118.043434, 36.808044, geography::Point(36.808044, 118.043434, 4326), N'高德地图', N'POI_BANK_0197', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(莲池支行)', 5, N'联通路82-4号', 118.034156, 36.829091, geography::Point(36.829091, 118.034156, 4326), N'高德地图', N'POI_BANK_0198', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农商银行(贾庄分理处)', 5, N'昌国路东首安康佳园2号楼', 118.053789, 36.781798, geography::Point(36.781798, 118.053789, 4326), N'高德地图', N'POI_BANK_0199', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农商银行(杏园东路支行)', 5, N'杏园东路85号甲14号', 118.07492, 36.787054, geography::Point(36.787054, 118.07492, 4326), N'高德地图', N'POI_BANK_0200', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东张店农村商业银行(营子分理处)', 5, N'考工路与北京路交叉口东南60米', 117.989815, 36.77867, geography::Point(36.77867, 117.989815, 4326), N'高德地图', N'POI_BANK_0201', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(商城街支行)', 5, N'义乌路商城街8-104-105', 118.018734, 36.823852, geography::Point(36.823852, 118.018734, 4326), N'高德地图', N'POI_BANK_0202', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(马尚营业厅)', 5, N'马尚大街14号甲9号', 117.998274, 36.79945, geography::Point(36.79945, 117.998274, 4326), N'高德地图', N'POI_BANK_0203', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(付家营业所)', 5, N'华福大道108号正东方向50米', 118.002575, 36.762198, geography::Point(36.762198, 118.002575, 4326), N'高德地图', N'POI_BANK_0204', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐商银行(淄博华侨城小微支行)', 5, N'中润·华侨城北区东北门旁', 118.03204, 36.846577, geography::Point(36.846577, 118.03204, 4326), N'高德地图', N'POI_BANK_0205', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(淄博市工业路营业所)', 5, N'工业路6号', 118.047061, 36.750883, geography::Point(36.750883, 118.047061, 4326), N'高德地图', N'POI_BANK_0206', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农商银行(凯瑞园支行)', 5, N'人民西路165号光彩大厦F1层', 118.0209, 36.814143, geography::Point(36.814143, 118.0209, 4326), N'高德地图', N'POI_BANK_0207', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行(淄博东方支行)', 5, N'柳泉路91甲7(东方之珠大厦1层)', 118.05479, 36.828499, geography::Point(36.828499, 118.05479, 4326), N'高德地图', N'POI_BANK_0208', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农商银行天津路分理处', 5, N'天津路与共青团西路交叉口南180米', 117.970475, 36.810775, geography::Point(36.810775, 117.970475, 4326), N'高德地图', N'POI_BANK_0209', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国人寿财险经开区支公司', 5, N'山泉路241号', 118.030829, 36.755105, geography::Point(36.755105, 118.030829, 4326), N'高德地图', N'POI_BANK_0210', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国农业银行淄博洪沟支行', 5, N'洪沟路21号院', 118.068693, 36.791737, geography::Point(36.791737, 118.068693, 4326), N'高德地图', N'POI_BANK_0211', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农商银行(天乙支行)', 5, N'开发区中路房镇镇政府1层', 117.99995, 36.844169, geography::Point(36.844169, 117.99995, 4326), N'高德地图', N'POI_BANK_0212', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农商银行(金都花园分理处)', 5, N'四宝山街道金都花园柳泉路247号', 118.068638, 36.882656, geography::Point(36.882656, 118.068638, 4326), N'高德地图', N'POI_BANK_0213', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国民生银行(淄博分行营业部)', 5, N'柳泉路238号潘成国际大厦', 118.055149, 36.825806, geography::Point(36.825806, 118.055149, 4326), N'高德地图', N'POI_BANK_0214', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东张店农村商业银行(宝山支行)', 5, N'张店开发区宝鑫路9号', 118.094938, 36.821917, geography::Point(36.821917, 118.094938, 4326), N'高德地图', N'POI_BANK_0215', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东张店农村商业银行(傅山支行)', 5, N'淄博高新区卫固镇傅山村', 118.135688, 36.879895, geography::Point(36.879895, 118.135688, 4326), N'高德地图', N'POI_BANK_0216', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东张店农村商业银行(城东支行)', 5, N'城东路36号甲2号', 118.091539, 36.762581, geography::Point(36.762581, 118.091539, 4326), N'高德地图', N'POI_BANK_0217', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农商银行(尚文苑分理处)', 5, N'世源大厦东南门西南50米', 118.004991, 36.804231, geography::Point(36.804231, 118.004991, 4326), N'高德地图', N'POI_BANK_0218', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(湖田营业所)', 5, N'湖田镇湖光路19号', 118.126473, 36.789781, geography::Point(36.789781, 118.126473, 4326), N'高德地图', N'POI_BANK_0219', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'农村商业银行(王庄分理处)', 5, N'怡海云锦东南门旁', 118.076725, 36.873125, geography::Point(36.873125, 118.076725, 4326), N'高德地图', N'POI_BANK_0220', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店农村商业银行(商家分理处)', 5, N'洪沟路与富裕路交叉口东320米', 118.099152, 36.789979, geography::Point(36.789979, 118.099152, 4326), N'高德地图', N'POI_BANK_0221', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行淄博经济开发区支行', 5, N'王舍路与南京路交叉口东280米', 118.012907, 36.79148, geography::Point(36.79148, 118.012907, 4326), N'高德地图', N'POI_BANK_0222', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博市农行', 5, N'西二路与味中味北街交叉口北60米', 118.055975, 36.811175, geography::Point(36.811175, 118.055975, 4326), N'高德地图', N'POI_BANK_0223', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国邮政储蓄银行(卫固营业所)', 5, N'卫固镇卫生院对过', 118.144223, 36.867604, geography::Point(36.867604, 118.144223, 4326), N'高德地图', N'POI_BANK_0224', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博中学', 1, N'中润大道东首295号', 118.120439, 36.831177, geography::Point(36.831177, 118.120439, 4326), N'高德地图', N'POI_SCH_0001', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东淄博实验中学', 1, N'张周路11号', 118.008153, 36.801282, geography::Point(36.801282, 118.008153, 4326), N'高德地图', N'POI_SCH_0002', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东省淄博第十一中学', 1, N'柳泉路北首119号', 118.058347, 36.850701, geography::Point(36.850701, 118.058347, 4326), N'高德地图', N'POI_SCH_0003', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东省淄博第五中学', 1, N'洪沟路6号', 118.063129, 36.791132, geography::Point(36.791132, 118.063129, 4326), N'高德地图', N'POI_SCH_0004', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博齐盛高级中学', 1, N'房镇镇南范路淄博新区', 117.976779, 36.852334, geography::Point(36.852334, 117.976779, 4326), N'高德地图', N'POI_SCH_0005', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店区第八中学', 1, N'华光路298号', 117.996954, 36.825344, geography::Point(36.825344, 117.996954, 4326), N'高德地图', N'POI_SCH_0006', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博高新区实验中学', 1, N'张店区高新区中润大道299号', 118.128522, 36.830556, geography::Point(36.830556, 118.128522, 4326), N'高德地图', N'POI_SCH_0007', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东省淄博第十七中学', 1, N'十七中北街1号', 118.035688, 36.810232, geography::Point(36.810232, 118.035688, 4326), N'高德地图', N'POI_SCH_0008', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博市张店区齐盛学校', 1, N'中润大道南', 117.97533, 36.836168, geography::Point(36.836168, 117.97533, 4326), N'高德地图', N'POI_SCH_0009', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博柳泉中学', 1, N'人民西路', 117.977727, 36.819203, geography::Point(36.819203, 117.977727, 4326), N'高德地图', N'POI_SCH_0010', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店区第一中学', 1, N'和平路7号', 118.043795, 36.795111, geography::Point(36.795111, 118.043795, 4326), N'高德地图', N'POI_SCH_0011', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店区第二中学', 1, N'人民东路14号', 118.070757, 36.808516, geography::Point(36.808516, 118.070757, 4326), N'高德地图', N'POI_SCH_0012', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东省淄博第十八中学', 1, N'潘南西路18号', 118.055517, 36.818262, geography::Point(36.818262, 118.055517, 4326), N'高德地图', N'POI_SCH_0013', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博市张店区实验中学', 1, N'世纪路36号', 118.025832, 36.799455, geography::Point(36.799455, 118.025832, 4326), N'高德地图', N'POI_SCH_0014', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店区第七中学', 1, N'北西六路57号', 118.03144, 36.818856, geography::Point(36.818856, 118.03144, 4326), N'高德地图', N'POI_SCH_0015', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店区第九中学', 1, N'人民西路126号', 118.022021, 36.815689, geography::Point(36.815689, 118.022021, 4326), N'高德地图', N'POI_SCH_0016', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店区第三中学', 1, N'金晶大道西4巷3号', 118.05725, 36.807199, geography::Point(36.807199, 118.05725, 4326), N'高德地图', N'POI_SCH_0017', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博市张店区铝城第一中学', 1, N'花园路30号', 118.040937, 36.748754, geography::Point(36.748754, 118.040937, 4326), N'高德地图', N'POI_SCH_0018', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'龙凤苑中学', 1, N'重庆路与齐盛路交叉口东北260米', 118.006056, 36.834279, geography::Point(36.834279, 118.006056, 4326), N'高德地图', N'POI_SCH_0019', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博市高新区第一中学', 1, N'兰雁大道', 118.036423, 36.855487, geography::Point(36.855487, 118.036423, 4326), N'高德地图', N'POI_SCH_0020', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博修文外国语学校', 1, N'中润大道与香港路交叉口南100米', 117.975357, 36.837448, geography::Point(36.837448, 117.975357, 4326), N'高德地图', N'POI_SCH_0021', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'潘庄高级中学', 1, N'迎春街与联通路交叉口南360米', 118.060365, 36.823397, geography::Point(36.823397, 118.060365, 4326), N'高德地图', N'POI_SCH_0022', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店区科技苑中学', 1, N'联通路与橙香路交叉口东北160米', 118.050969, 36.828994, geography::Point(36.828994, 118.050969, 4326), N'高德地图', N'POI_SCH_0023', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博世纪英才外语学校', 1, N'万杰路116号', 118.065, 36.842399, geography::Point(36.842399, 118.065, 4326), N'高德地图', N'POI_SCH_0024', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博市张店区第六中学', 1, N'南重庆路166号', 117.99802, 36.769038, geography::Point(36.769038, 117.99802, 4326), N'高德地图', N'POI_SCH_0025', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博高新区科学城实验中学', 1, N'陶韵路与齐祥路交叉口', 118.032822, 36.887442, geography::Point(36.887442, 118.032822, 4326), N'高德地图', N'POI_SCH_0026', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东淄博新元学校', 1, N'柳泉路224号', 118.053855, 36.819376, geography::Point(36.819376, 118.053855, 4326), N'高德地图', N'POI_SCH_0027', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店区世纪中学', 1, N'世纪路与和平路交叉口东南180米', 118.025401, 36.796467, geography::Point(36.796467, 118.025401, 4326), N'高德地图', N'POI_SCH_0028', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博黉门中学', 1, N'规划路11号', 118.052253, 36.856867, geography::Point(36.856867, 118.052253, 4326), N'高德地图', N'POI_SCH_0029', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博市张店区第四中学', 1, N'沣水镇城东路1号淄博市张店区沣水中学附近', 118.088207, 36.753633, geography::Point(36.753633, 118.088207, 4326), N'高德地图', N'POI_SCH_0030', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博市张店区建桥中学', 1, N'北西六路59号', 118.031465, 36.820234, geography::Point(36.820234, 118.031465, 4326), N'高德地图', N'POI_SCH_0031', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博市张店区南定中学', 1, N'崔军南定中学', 118.046504, 36.742334, geography::Point(36.742334, 118.046504, 4326), N'高德地图', N'POI_SCH_0032', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博市美达菲双语高级中学', 1, N'人民西路与济南路交叉口西南100米', 117.966026, 36.815861, geography::Point(36.815861, 117.966026, 4326), N'高德地图', N'POI_SCH_0033', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店区文苑学校', 1, N'南定镇朝阳路9号', 118.057396, 36.770116, geography::Point(36.770116, 118.057396, 4326), N'高德地图', N'POI_SCH_0034', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博黉门科技高中', 1, N'泰美路211号', 118.052404, 36.856963, geography::Point(36.856963, 118.052404, 4326), N'高德地图', N'POI_SCH_0035', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博市张店区第十二中学', 1, N'杏园街道办事处湖光路3号', 118.114856, 36.790903, geography::Point(36.790903, 118.114856, 4326), N'高德地图', N'POI_SCH_0036', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博宝鑫新经典中学', 1, N'尚庄路与春风路交叉口西北160米', 118.100135, 36.818183, geography::Point(36.818183, 118.100135, 4326), N'高德地图', N'POI_SCH_0037', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店区汇智中学', 1, N'王舍路83号', 118.034798, 36.78726, geography::Point(36.78726, 118.034798, 4326), N'高德地图', N'POI_SCH_0038', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东理工大学(西校区)', 1, N'新村西路266号', 118.000702, 36.81037, geography::Point(36.81037, 118.000702, 4326), N'高德地图', N'POI_SCH_0039', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东理工大学东校区', 1, N'共青团西路88号', 118.039909, 36.811461, geography::Point(36.811461, 118.039909, 4326), N'高德地图', N'POI_SCH_0040', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'鸿成八中校区', 1, N'华光路300号', 117.999495, 36.825989, geography::Point(36.825989, 117.999495, 4326), N'高德地图', N'POI_SCH_0041', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店区第七中学(东校区)', 1, N'橙香路与联通路交叉口北80米', 118.049725, 36.828725, geography::Point(36.828725, 118.049725, 4326), N'高德地图', N'POI_SCH_0042', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博张店美术中学', 1, N'科技苑庭兰村南1门东120米', 118.051318, 36.833698, geography::Point(36.833698, 118.051318, 4326), N'高德地图', N'POI_SCH_0043', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东理工大学东校区商学院', 1, N'共青团西路86号甲27号山东理工大学东校区', 118.03951, 36.813249, geography::Point(36.813249, 118.03951, 4326), N'高德地图', N'POI_SCH_0044', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东理工大学国际学术交流中心', 1, N'新世界商业街36号', 118.042084, 36.810257, geography::Point(36.810257, 118.042084, 4326), N'高德地图', N'POI_SCH_0045', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东理工大学机械交通实验中心', 1, N'新村西路266号山东理工大学', 117.994954, 36.806875, geography::Point(36.806875, 117.994954, 4326), N'高德地图', N'POI_SCH_0046', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东理工大学(西校区)-建筑工程学院大学生学习发展指导中心', 1, N'绿岛西路山东理工大学教学楼12号楼', 117.996859, 36.808628, geography::Point(36.808628, 117.996859, 4326), N'高德地图', N'POI_SCH_0047', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国人民大学少年新闻学院(淄博分院)', 1, N'世纪路阳光国际B座601室', 118.02444, 36.84188, geography::Point(36.84188, 118.02444, 4326), N'高德地图', N'POI_SCH_0048', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东理工大学商学院农业推广硕士教育中心', 1, N'共青团西路86号甲27号山东理工大学东校区', 118.037803, 36.812962, geography::Point(36.812962, 118.037803, 4326), N'高德地图', N'POI_SCH_0049', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东理工大学EDP教育中心', 1, N'共青团西路86号甲27号山东理工大学东校区', 118.037803, 36.812963, geography::Point(36.812963, 118.037803, 4326), N'高德地图', N'POI_SCH_0050', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东理工大学商学院学生学习与发展指导中心', 1, N'共青团西路86号甲27号山东理工大学东校区', 118.041525, 36.812975, geography::Point(36.812975, 118.041525, 4326), N'高德地图', N'POI_SCH_0051', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东理工大学农业工程与食品科学学院党团服务中心', 1, N'新村西路266号山东理工大学学生公寓15号楼', 117.996609, 36.814923, geography::Point(36.814923, 117.996609, 4326), N'高德地图', N'POI_SCH_0052', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东理工大学商学院工程硕士教育中心', 1, N'共青团西路86号甲27号山东理工大学东校区', 118.037803, 36.812962, geography::Point(36.812962, 118.037803, 4326), N'高德地图', N'POI_SCH_0053', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国音乐学院全国音乐家协会(南定)考级报名点', 1, N'张南路与朝阳路交叉口北80米', 118.050247, 36.770471, geography::Point(36.770471, 118.050247, 4326), N'高德地图', N'POI_SCH_0054', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东大学齐鲁医学院淄博临床学院', 1, N'中润大道世博高新医院', 118.106044, 36.829363, geography::Point(36.829363, 118.106044, 4326), N'高德地图', N'POI_SCH_0055', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东理工大学新型聚氨酯材料研究院科技成果展示厅', 1, N'山东理工大学物业管理中心西门旁', 117.993976, 36.810664, geography::Point(36.810664, 117.993976, 4326), N'高德地图', N'POI_SCH_0056', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博十七中新校区(建设中)', 1, N'考工路与重庆路交叉口西南角', 117.997909, 36.776304, geography::Point(36.776304, 117.997909, 4326), N'高德地图', N'POI_SCH_0057', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博第三十一中学(建设中)', 1, N'中埠镇铁山路 76 号', 118.190451, 36.854098, geography::Point(36.854098, 118.190451, 4326), N'高德地图', N'POI_SCH_0058', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'新城建工绿城北中学项目(建设中)', 1, N'绿城北中学项目(建设中)', 117.980425, 36.855275, geography::Point(36.855275, 117.980425, 4326), N'高德地图', N'POI_SCH_0059', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博万象汇', 3, N'金晶大道辅路', 118.061399, 36.802119, geography::Point(36.802119, 118.061399, 4326), N'高德地图', N'POI_MKT_0001', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'富力万达广场', 3, N'中润大道17号', 118.010986, 36.838791, geography::Point(36.838791, 118.010986, 4326), N'高德地图', N'POI_MKT_0002', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'吾悦广场(淄博店)', 3, N'世纪路昌国路交汇处东南角', 118.025098, 36.783679, geography::Point(36.783679, 118.025098, 4326), N'高德地图', N'POI_MKT_0003', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博鑫马吾悦广场', 3, N'华光路288号', 118.001652, 36.824664, geography::Point(36.824664, 118.001652, 4326), N'高德地图', N'POI_MKT_0004', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'银泰城', 3, N'鲁泰大道9号', 118.034853, 36.848682, geography::Point(36.848682, 118.034853, 4326), N'高德地图', N'POI_MKT_0005', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'印象汇', 3, N'柳泉路67号', 118.053114, 36.822911, geography::Point(36.822911, 118.053114, 4326), N'高德地图', N'POI_MKT_0006', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博恒太城', 3, N'华光路331号', 117.982976, 36.823338, geography::Point(36.823338, 117.982976, 4326), N'高德地图', N'POI_MKT_0007', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博王府井广场', 3, N'共青团路与柳泉路交叉口', 118.051895, 36.805278, geography::Point(36.805278, 118.051895, 4326), N'高德地图', N'POI_MKT_0008', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'新玛特购物广场(中润店)', 3, N'中润大道1号', 118.028589, 36.837956, geography::Point(36.837956, 118.028589, 4326), N'高德地图', N'POI_MKT_0009', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'新玛特购物广场店', 3, N'中润大道1号新玛特购物广场中润店B1层', 118.028601, 36.837944, geography::Point(36.837944, 118.028601, 4326), N'高德地图', N'POI_MKT_0010', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'银座商城(淄博店)', 3, N'银座商城负一层依兰坊', 118.050481, 36.805504, geography::Point(36.805504, 118.050481, 4326), N'高德地图', N'POI_MKT_0011', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博商厦', 3, N'金晶大道125号', 118.058471, 36.802055, geography::Point(36.802055, 118.058471, 4326), N'高德地图', N'POI_MKT_0012', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'银座·奥特莱斯(柳泉路店)', 3, N'柳泉路105号', 118.056075, 36.834419, geography::Point(36.834419, 118.056075, 4326), N'高德地图', N'POI_MKT_0013', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'利群集团淄博购物广场', 3, N'商场东路2号', 118.060455, 36.800429, geography::Point(36.800429, 118.060455, 4326), N'高德地图', N'POI_MKT_0014', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'银座购物广场(五里桥店)', 3, N'人民西路51号银座购物广场1层', 118.032224, 36.813519, geography::Point(36.813519, 118.032224, 4326), N'高德地图', N'POI_MKT_0015', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'奥朗特广场', 3, N'[]', 118.012429, 36.810507, geography::Point(36.810507, 118.012429, 4326), N'高德地图', N'POI_MKT_0016', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'德泰智汇广场', 3, N'华光路116号', 118.029104, 36.822275, geography::Point(36.822275, 118.029104, 4326), N'高德地图', N'POI_MKT_0017', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'铝城购物中心', 3, N'南定镇山铝花园路29号', 118.045266, 36.753116, geography::Point(36.753116, 118.045266, 4326), N'高德地图', N'POI_MKT_0018', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'富丽商城', 3, N'共青团西路23号', 118.056526, 36.805114, geography::Point(36.805114, 118.056526, 4326), N'高德地图', N'POI_MKT_0019', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'利群时代(柳泉路店)', 3, N'柳泉路29号', 118.047509, 36.801921, geography::Point(36.801921, 118.047509, 4326), N'高德地图', N'POI_MKT_0020', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'亿丰商场', 3, N'重庆路亿丰大厦1-3层', 118.002092, 36.816668, geography::Point(36.816668, 118.002092, 4326), N'高德地图', N'POI_MKT_0021', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'沣水生活广场', 3, N'昌国路良乡物流东1000米', 118.092496, 36.770362, geography::Point(36.770362, 118.092496, 4326), N'高德地图', N'POI_MKT_0022', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'振华商厦', 3, N'城中西内环路与西一路交叉口西北80米', 118.056051, 36.80162, geography::Point(36.80162, 118.056051, 4326), N'高德地图', N'POI_MKT_0023', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'秀水地下商城(振华商厦店)', 3, N'振华商厦', 118.055741, 36.80212, geography::Point(36.80212, 118.055741, 4326), N'高德地图', N'POI_MKT_0024', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'铭辰生活广场', 3, N'铭辰百货东南门旁', 118.092622, 36.770385, geography::Point(36.770385, 118.092622, 4326), N'高德地图', N'POI_MKT_0025', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'银泰百货(名尚银泰城店)', 3, N'鲁泰大道9号银泰城1F层', 118.035825, 36.848275, geography::Point(36.848275, 118.035825, 4326), N'高德地图', N'POI_MKT_0026', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'百信商场', 3, N'健康街与美食街交叉口西50米', 118.05071, 36.803084, geography::Point(36.803084, 118.05071, 4326), N'高德地图', N'POI_MKT_0027', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'KKV恒太城', 3, N'马尚街道办事处华光路331号淄博超级恒太城F1层1F-003-005-006KKV店', 117.983495, 36.822913, geography::Point(36.822913, 117.983495, 4326), N'高德地图', N'POI_MKT_0028', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'众成·美都汇服饰广场(健康街)', 3, N'健康街96号', 118.051487, 36.803548, geography::Point(36.803548, 118.051487, 4326), N'高德地图', N'POI_MKT_0029', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'银座中心店2期', 3, N'柳泉路110号', 118.050725, 36.805125, geography::Point(36.805125, 118.050725, 4326), N'高德地图', N'POI_MKT_0030', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'云顺购物广场', 3, N'南苑绿洲小区2区', 118.025122, 36.765016, geography::Point(36.765016, 118.025122, 4326), N'高德地图', N'POI_MKT_0031', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'万通', 3, N'张店区美食街82号', 118.050587, 36.803687, geography::Point(36.803687, 118.050587, 4326), N'高德地图', N'POI_MKT_0032', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'南定购物广场(淄博商厦铝城购物中心店)', 3, N'南定镇西山路3号', 118.046169, 36.752724, geography::Point(36.752724, 118.046169, 4326), N'高德地图', N'POI_MKT_0033', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博鑫阳二手商城(淄博仓)', 3, N'中润大道156号', 118.081153, 36.830496, geography::Point(36.830496, 118.081153, 4326), N'高德地图', N'POI_MKT_0034', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博大成商场', 3, N'西二路181号', 118.055089, 36.805645, geography::Point(36.805645, 118.055089, 4326), N'高德地图', N'POI_MKT_0035', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'钰朋购物中心(沣水店)', 3, N'城东路南首', 118.090277, 36.756057, geography::Point(36.756057, 118.090277, 4326), N'高德地图', N'POI_MKT_0036', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'核心商城', 3, N'昌国路105号鲁中装饰博览城', 118.02041, 36.785217, geography::Point(36.785217, 118.02041, 4326), N'高德地图', N'POI_MKT_0037', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'湖田供销社百货商场', 3, N'湖光路12号', 118.124208, 36.789429, geography::Point(36.789429, 118.124208, 4326), N'高德地图', N'POI_MKT_0038', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'修德百货', 3, N'健康街23号甲7号', 118.049951, 36.797448, geography::Point(36.797448, 118.049951, 4326), N'高德地图', N'POI_MKT_0039', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'金达购物广场', 3, N'金达大厦1号', 118.058281, 36.842413, geography::Point(36.842413, 118.058281, 4326), N'高德地图', N'POI_MKT_0040', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'明珠百货(洪沟路店)', 3, N'洪沟路与宝山路快速路辅路交叉口东80米', 118.096046, 36.788613, geography::Point(36.788613, 118.096046, 4326), N'高德地图', N'POI_MKT_0041', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'百姓商城驿站', 3, N'东二路与人民东路辅路交叉口南60米', 118.068149, 36.809626, geography::Point(36.809626, 118.068149, 4326), N'高德地图', N'POI_MKT_0042', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'静墨澜百货服装工作室(乔里店)', 3, N'体育场街道华光路16号乔里院落式办公D1', 118.075073, 36.81887, geography::Point(36.81887, 118.075073, 4326), N'高德地图', N'POI_MKT_0043', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'天鸿综合商城', 3, N'东一路区公安局对面', 118.062087, 36.799304, geography::Point(36.799304, 118.062087, 4326), N'高德地图', N'POI_MKT_0044', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'京艺琴行戏剧舞蹈商场', 3, N'共青团西路53之6-8', 118.05342, 36.805846, geography::Point(36.805846, 118.05342, 4326), N'高德地图', N'POI_MKT_0045', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'南定泰贸商场', 3, N'[]', 118.04791, 36.751906, geography::Point(36.751906, 118.04791, 4326), N'高德地图', N'POI_MKT_0046', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'嗨惠多商城', 3, N'铝城第一小学西北门东北50米', 118.043014, 36.751244, geography::Point(36.751244, 118.043014, 4326), N'高德地图', N'POI_MKT_0047', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'西山商场', 3, N'花园路20号', 118.04399, 36.752766, geography::Point(36.752766, 118.04399, 4326), N'高德地图', N'POI_MKT_0048', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'花仙女鲜花店商场西街店', 3, N'商场西街41号', 118.045878, 36.803872, geography::Point(36.803872, 118.045878, 4326), N'高德地图', N'POI_MKT_0049', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'金世界商城', 3, N'柳泉路西三巷38号', 118.050285, 36.819, geography::Point(36.819, 118.050285, 4326), N'高德地图', N'POI_MKT_0050', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'冰洁制冷电器家电商场', 3, N'沣水镇', 118.093975, 36.777328, geography::Point(36.777328, 118.093975, 4326), N'高德地图', N'POI_MKT_0051', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'鲁臣商城', 3, N'柳泉路与西二路西六巷交叉口东北140米', 118.051405, 36.809116, geography::Point(36.809116, 118.051405, 4326), N'高德地图', N'POI_MKT_0052', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'众赢商城', 3, N'共青团路53号', 118.053325, 36.805784, geography::Point(36.805784, 118.053325, 4326), N'高德地图', N'POI_MKT_0053', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'鹿隐女装(新东升·福园西区店)', 3, N'福园福悦南街47甲19号鹿隐女装', 118.027729, 36.807304, geography::Point(36.807304, 118.027729, 4326), N'高德地图', N'POI_MKT_0054', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'嗨惠多商城', 3, N'杜科中心街与共青团东路辅路交叉口北220米', 118.077323, 36.804818, geography::Point(36.804818, 118.077323, 4326), N'高德地图', N'POI_MKT_0055', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'惠购商城', 3, N'联通路与柳泉路交叉口东240米', 118.057835, 36.827413, geography::Point(36.827413, 118.057835, 4326), N'高德地图', N'POI_MKT_0056', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'永春日化义乌商城店', 3, N'华川西16街3326号', 118.020546, 36.824888, geography::Point(36.824888, 118.020546, 4326), N'高德地图', N'POI_MKT_0057', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'义乌商城(博大广场店)', 3, N'小商品街88号美达华庭', 118.017175, 36.823575, geography::Point(36.823575, 118.017175, 4326), N'高德地图', N'POI_MKT_0058', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'名筑商城', 3, N'马尚镇和平路148号', 117.996469, 36.799556, geography::Point(36.799556, 117.996469, 4326), N'高德地图', N'POI_MKT_0059', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'嗨惠多商城', 3, N'恒大帝景2期', 118.017095, 36.808445, geography::Point(36.808445, 118.017095, 4326), N'高德地图', N'POI_MKT_0060', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市青少年宫中心商城', 3, N'金晶大道118号中心商城', 118.061839, 36.806994, geography::Point(36.806994, 118.061839, 4326), N'高德地图', N'POI_MKT_0061', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'筑泰商贸城', 3, N'商场东路与宝沣路交叉口西140米', 118.083075, 36.798025, geography::Point(36.798025, 118.083075, 4326), N'高德地图', N'POI_MKT_0062', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'2元连锁超市(商城广场街店)', 3, N'淄博义乌小商品城一期南门东南60米', 118.022035, 36.822985, geography::Point(36.822985, 118.022035, 4326), N'高德地图', N'POI_MKT_0063', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'宏城国际广场商业街(宏程国际广场店)', 3, N'宏程·国际广场', 118.011066, 36.827125, geography::Point(36.827125, 118.011066, 4326), N'高德地图', N'POI_MKT_0064', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博商厦针织商场仓库', 3, N'金晶大道125号淄博商厦F3', 118.058175, 36.801875, geography::Point(36.801875, 118.058175, 4326), N'高德地图', N'POI_MKT_0065', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'洪沟五金机电城10号楼', 3, N'杏园东路68号洪沟五金机电城', 118.074202, 36.786367, geography::Point(36.786367, 118.074202, 4326), N'高德地图', N'POI_MKT_0066', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'麦德龙(淄博张店商场)', 3, N'经济技术开发区山泉路102号', 118.038197, 36.767146, geography::Point(36.767146, 118.038197, 4326), N'高德地图', N'POI_MKT_0067', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'红星美凯龙(淄博昌国商场)', 3, N'昌国路23号红星美凯龙', 118.033773, 36.783271, geography::Point(36.783271, 118.033773, 4326), N'高德地图', N'POI_MKT_0068', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'顾家家居(政通路居然店)', 3, N'柳泉路居然之家3楼', 118.057556, 36.84184, geography::Point(36.84184, 118.057556, 4326), N'高德地图', N'POI_MKT_0069', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'星盟烟酒超市(商场西街店)', 3, N'和平家具城社区北门旁', 118.046951, 36.80392, geography::Point(36.80392, 118.046951, 4326), N'高德地图', N'POI_MKT_0070', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'桐桐超市(商场东街店)', 3, N'商场东街22号13', 118.070653, 36.799632, geography::Point(36.799632, 118.070653, 4326), N'高德地图', N'POI_MKT_0071', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'红高粱老酒坊(商场路店)', 3, N'商场东街23号', 118.066225, 36.800475, geography::Point(36.800475, 118.066225, 4326), N'高德地图', N'POI_MKT_0072', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'舒达床垫(淄博红星美凯龙昌国商场店)', 3, N'车站街道昌国路23号红星美凯龙二楼', 118.033875, 36.783225, geography::Point(36.783225, 118.033875, 4326), N'高德地图', N'POI_MKT_0073', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'莱克健康家电体验馆(商场东街店)', 3, N'商场东路22-1', 118.069781, 36.79978, geography::Point(36.79978, 118.069781, 4326), N'高德地图', N'POI_MKT_0074', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'新日电动车(商场路店)', 3, N'商场西路10号世纪上城', 118.047278, 36.80421, geography::Point(36.80421, 118.047278, 4326), N'高德地图', N'POI_MKT_0075', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'银座超市(淄博银座商城店)', 3, N'柳泉路128号银座商城B1', 118.050484, 36.805618, geography::Point(36.805618, 118.050484, 4326), N'高德地图', N'POI_MKT_0076', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'添可Tineco银座商城(淄博店)', 3, N'银座商城(淄博店)', 118.050461, 36.805134, geography::Point(36.805134, 118.050461, 4326), N'高德地图', N'POI_MKT_0077', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博银座商城四楼nike kids', 3, N'公园街道柳泉路128号银座商城四楼', 118.049965, 36.8051, geography::Point(36.8051, 118.049965, 4326), N'高德地图', N'POI_MKT_0078', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'名鞋商场', 3, N'金晶大道125号淄博商厦F1层', 118.058133, 36.801923, geography::Point(36.801923, 118.058133, 4326), N'高德地图', N'POI_MKT_0079', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'红樱桃时尚购物广场(振华商厦店)', 3, N'和平街道美食街59号振华商厦负一楼', 118.055728, 36.802018, geography::Point(36.802018, 118.055728, 4326), N'高德地图', N'POI_MKT_0080', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博理想城商业休闲广场', 3, N'亿丰商场', 118.001994, 36.816309, geography::Point(36.816309, 118.001994, 4326), N'高德地图', N'POI_MKT_0081', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'王府井通讯商城(淄博王府井广场店)', 3, N'西二路231号怡莱酒店', 118.052126, 36.805493, geography::Point(36.805493, 118.052126, 4326), N'高德地图', N'POI_MKT_0082', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'巴达商贸(利群时代广场店)', 3, N'柳泉路29号利群时代广场F1层', 118.048045, 36.801854, geography::Point(36.801854, 118.048045, 4326), N'高德地图', N'POI_MKT_0083', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄诚电子商贸(利群时代广场店)', 3, N'柳泉路29号利群时代广场正门南侧', 118.048046, 36.801821, geography::Point(36.801821, 118.048046, 4326), N'高德地图', N'POI_MKT_0084', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'非同(昌国商场红星美凯龙店)', 3, N'南西五路与昌国路路口红星美凯龙(昌国商场店)一楼非同', 118.03451, 36.782601, geography::Point(36.782601, 118.03451, 4326), N'高德地图', N'POI_MKT_0085', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'日立中央空调智慧空气馆(红星美凯龙昌国商场店)', 3, N'昌国西路23号红星美凯龙四楼中厅', 118.033875, 36.783025, geography::Point(36.783025, 118.033875, 4326), N'高德地图', N'POI_MKT_0086', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'华鹤(红星美凯龙淄博昌国商场)', 3, N'车站街道昌国路23号3楼中厅', 118.033775, 36.783225, geography::Point(36.783225, 118.033775, 4326), N'高德地图', N'POI_MKT_0087', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'世友地板(红星美凯龙昌国商场)', 3, N'车站街道昌国西路23号红星美凯龙一楼', 118.033063, 36.783085, geography::Point(36.783085, 118.033063, 4326), N'高德地图', N'POI_MKT_0088', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'西门子(昌国商场红星美凯龙店)', 3, N'昌国路红星美凯龙1楼西北角', 118.033105, 36.783367, geography::Point(36.783367, 118.033105, 4326), N'高德地图', N'POI_MKT_0089', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'芝华仕头等舱沙发(昌国商场红星美凯龙店)', 3, N'昌国路29号1楼', 118.03428, 36.783035, geography::Point(36.783035, 118.03428, 4326), N'高德地图', N'POI_MKT_0090', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'优品购超市(商场西街店)', 3, N'梦圆广场', 118.043986, 36.805202, geography::Point(36.805202, 118.043986, 4326), N'高德地图', N'POI_MKT_0091', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'茂业天地(暂停营业)', 3, N'柳泉路152号', 118.050853, 36.807477, geography::Point(36.807477, 118.050853, 4326), N'高德地图', N'POI_MKT_0092', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'莲池利群购物广场(暂停营业)', 3, N'北西五路25号', 118.036154, 36.831436, geography::Point(36.831436, 118.036154, 4326), N'高德地图', N'POI_MKT_0093', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'自贸免税商城(建设中)', 3, N'鲁泰大道辅路与天鸿路交叉口东南140米', 118.055953, 36.845954, geography::Point(36.845954, 118.055953, 4326), N'高德地图', N'POI_MKT_0094', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'楚楚整家定制(红星美凯龙昌国商场店)', 3, N'昌国路23号红星美凯龙昌国商场二楼', 118.033775, 36.783225, geography::Point(36.783225, 118.033775, 4326), N'高德地图', N'POI_MKT_0095', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'得力文具(商场东街店)', 3, N'商场东路6号6号甲4号', 118.064748, 36.800478, geography::Point(36.800478, 118.064748, 4326), N'高德地图', N'POI_MKT_0096', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'英国集宝保险柜(红星美凯龙昌国商场店)', 3, N'昌国路23号', 118.033773, 36.783271, geography::Point(36.783271, 118.033773, 4326), N'高德地图', N'POI_MKT_0097', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'花星语鲜花店(商场西街店)', 3, N'和平街道商场西路中段3号楼一层东数第一间', 118.045846, 36.803841, geography::Point(36.803841, 118.045846, 4326), N'高德地图', N'POI_MKT_0098', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'潍坊六和窗帘(商场西街店)', 3, N'商场西街博物馆北门北十三巷', 118.038974, 36.805017, geography::Point(36.805017, 118.038974, 4326), N'高德地图', N'POI_MKT_0099', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'馨雅窗帘布艺(商场西街店)', 3, N'商场西街62号甲77号', 118.039563, 36.805039, geography::Point(36.805039, 118.039563, 4326), N'高德地图', N'POI_MKT_0100', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'华丽窗帘沙发套(商场西街店)', 3, N'商场西街62号甲44号', 118.039425, 36.805079, geography::Point(36.805079, 118.039425, 4326), N'高德地图', N'POI_MKT_0101', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'雅居窗帘(商场西街店)', 3, N'商场西街62号甲77号', 118.037682, 36.805073, geography::Point(36.805073, 118.037682, 4326), N'高德地图', N'POI_MKT_0102', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'贵雅窗帘(商场西街店)', 3, N'商场西街40号', 118.04412, 36.804702, geography::Point(36.804702, 118.04412, 4326), N'高德地图', N'POI_MKT_0103', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'小李水果(商场东街店)', 3, N'商场路东街4号甲11号', 118.064253, 36.800562, geography::Point(36.800562, 118.064253, 4326), N'高德地图', N'POI_MKT_0104', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'林海窗帘布艺(商场西街店)', 3, N'商场西街62号甲75号', 118.038125, 36.805025, geography::Point(36.805025, 118.038125, 4326), N'高德地图', N'POI_MKT_0105', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'暹罗阁泰国佛牌(富丽商城店)', 3, N'公园街道共青团西路23号富丽商城西区B151室', 118.056082, 36.805339, geography::Point(36.805339, 118.056082, 4326), N'高德地图', N'POI_MKT_0106', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'潍坊六丰窗饰(商场西街店)', 3, N'商场西街62号甲52号', 118.038918, 36.805017, geography::Point(36.805017, 118.038918, 4326), N'高德地图', N'POI_MKT_0107', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'台铃电动车(公园街道商场西街2店)', 3, N'公园街道新东升福园西区南门,78号甲17号', 118.027639, 36.805522, geography::Point(36.805522, 118.027639, 4326), N'高德地图', N'POI_MKT_0108', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'龙展烟酒商行(公园办事处商场西路店)', 3, N'商场西街8号', 118.046743, 36.804318, geography::Point(36.804318, 118.046743, 4326), N'高德地图', N'POI_MKT_0109', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'爱尚花坊(商场东街店)', 3, N'商场东路2甲8号万象汇3门正对面', 118.062131, 36.800792, geography::Point(36.800792, 118.062131, 4326), N'高德地图', N'POI_MKT_0110', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'正泰照明(装饰材料城核心商场店)', 3, N'傅家镇昌国路105号鲁中装饰材料城核心商场二楼左转博瑞特灯饰', 118.020625, 36.784084, geography::Point(36.784084, 118.020625, 4326), N'高德地图', N'POI_MKT_0111', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'乐芙服装店(商场西街店)', 3, N'共青团西路155号新东升·福园西区', 118.027922, 36.807305, geography::Point(36.807305, 118.027922, 4326), N'高德地图', N'POI_MKT_0112', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'雅帝乐入户门车库门(红星美凯龙昌国商场)', 3, N'昌国路红星美凯龙中厅3楼西北角', 118.033791, 36.783286, geography::Point(36.783286, 118.033791, 4326), N'高德地图', N'POI_MKT_0113', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'红旗仪表(商场东路店)', 3, N'商场东路(古玩市场D一112)', 118.082759, 36.79858, geography::Point(36.79858, 118.082759, 4326), N'高德地图', N'POI_MKT_0114', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'海尔冰箱专卖店(商场东街店)', 3, N'商场路与东四路往西200米路北海尔专卖店', 118.082017, 36.798602, geography::Point(36.798602, 118.082017, 4326), N'高德地图', N'POI_MKT_0115', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东盛水暖(商场东街店)', 3, N'商场东街18-8号', 118.068532, 36.799993, geography::Point(36.799993, 118.068532, 4326), N'高德地图', N'POI_MKT_0116', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'富源茶庄(商场西街店)', 3, N'商场西街62号甲57号', 118.038847, 36.805024, geography::Point(36.805024, 118.038847, 4326), N'高德地图', N'POI_MKT_0117', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'鹏源五金工具商行(天乐园商场店)', 3, N'兴学街21号甲4号天乐园商场F1层', 118.057161, 36.792686, geography::Point(36.792686, 118.057161, 4326), N'高德地图', N'POI_MKT_0118', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'新豪轩门窗(红星美凯龙昌国商场店)', 3, N'车站街道办事处昌国西路23号红星美凯龙二楼B8056', 118.033775, 36.783175, geography::Point(36.783175, 118.033775, 4326), N'高德地图', N'POI_MKT_0119', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东方弘叶家具(红星美凯龙昌国商场)', 3, N'红星美凯龙淄博昌国商场', 118.034375, 36.782975, geography::Point(36.782975, 118.034375, 4326), N'高德地图', N'POI_MKT_0120', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'陶渤建材(红星美凯龙昌国商场)', 3, N'昌国路23号红星美凯龙1层', 118.033392, 36.783624, geography::Point(36.783624, 118.033392, 4326), N'高德地图', N'POI_MKT_0121', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'诗荟花礼(商场东路南一巷店)', 3, N'商场东街与东一路交叉口西120米', 118.061902, 36.800463, geography::Point(36.800463, 118.061902, 4326), N'高德地图', N'POI_MKT_0122', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'美瞳公主(秀水服饰商场店)', 3, N'秀水西区4街415号', 118.055802, 36.802171, geography::Point(36.802171, 118.055802, 4326), N'高德地图', N'POI_MKT_0123', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'888服饰(商场西街店)', 3, N'柳泉路37号金宝岛大厦F1层', 118.047616, 36.803791, geography::Point(36.803791, 118.047616, 4326), N'高德地图', N'POI_MKT_0124', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国名酒货仓(商场东街店)', 3, N'商场东路与宝沣路交叉口西220米', 118.082157, 36.798607, geography::Point(36.798607, 118.082157, 4326), N'高德地图', N'POI_MKT_0125', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'海尔电器(商场东街店)', 3, N'东二路19号附近', 118.068321, 36.800018, geography::Point(36.800018, 118.068321, 4326), N'高德地图', N'POI_MKT_0126', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'鑫鑫窗帘(商场西街店)', 3, N'商场西街32甲1(大红门对面)', 118.044268, 36.804643, geography::Point(36.804643, 118.044268, 4326), N'高德地图', N'POI_MKT_0127', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'云峰茗茶(商场西街店)', 3, N'商场西街62号甲65号', 118.038528, 36.805017, geography::Point(36.805017, 118.038528, 4326), N'高德地图', N'POI_MKT_0128', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'小巴士电动车(东源商场店)', 3, N'共青团西路辅路与西二路交叉口东20米', 118.055747, 36.805996, geography::Point(36.805996, 118.055747, 4326), N'高德地图', N'POI_MKT_0129', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'鲁中五金机电汽配城(通力家园店)', 3, N'傅家镇昌国路鲁中五金机电汽配城中区', 118.014521, 36.783633, geography::Point(36.783633, 118.014521, 4326), N'高德地图', N'POI_MKT_0130', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'禧又(商场西街北十七巷店)', 3, N'共青团西路155号新东升·福园西区', 118.028725, 36.806375, geography::Point(36.806375, 118.028725, 4326), N'高德地图', N'POI_MKT_0131', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'金锣冷鲜肉专卖店(商场东街店)', 3, N'商场东街与东二路交叉口东200米', 118.071442, 36.799322, geography::Point(36.799322, 118.071442, 4326), N'高德地图', N'POI_MKT_0132', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'洪沟五金机电城', 3, N'杏园东路66号甲7号', 118.075571, 36.785841, geography::Point(36.785841, 118.075571, 4326), N'高德地图', N'POI_MKT_0133', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'飞利浦空调(商场东街店)', 3, N'商场东路与宝沣路交叉口西160米', 118.082874, 36.798579, geography::Point(36.798579, 118.082874, 4326), N'高德地图', N'POI_MKT_0134', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'爱恒优选(商场西街店)', 3, N'和平家具城社区北门西90米', 118.046258, 36.804043, geography::Point(36.804043, 118.046258, 4326), N'高德地图', N'POI_MKT_0135', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'德银五金淄博总公司', 3, N'洪沟西街与杏园东路交汇处东北角', 118.072206, 36.787541, geography::Point(36.787541, 118.072206, 4326), N'高德地图', N'POI_MKT_0136', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'晨光文具(商场东街店)', 3, N'淄建第三生活小区北门西50米', 118.064783, 36.800436, geography::Point(36.800436, 118.064783, 4326), N'高德地图', N'POI_MKT_0137', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'鲁中五金机电汽配城-中区', 3, N'复兴路与唐家山路交叉口西北300米', 118.014456, 36.783787, geography::Point(36.783787, 118.014456, 4326), N'高德地图', N'POI_MKT_0138', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'蓝精灵童装(商场东街店)', 3, N'商场东街与东二路交叉口东120米', 118.070589, 36.799653, geography::Point(36.799653, 118.070589, 4326), N'高德地图', N'POI_MKT_0139', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'木子尚·心动(商场西街北十七巷店)', 3, N'共青团西路155号新东升·福园西区', 118.027703, 36.80722, geography::Point(36.80722, 118.027703, 4326), N'高德地图', N'POI_MKT_0140', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'黑骑士部落(商场西街北九巷店)', 3, N'共青团西路南八巷与商场西街北八巷交叉口西北60米', 118.043564, 36.805963, geography::Point(36.805963, 118.043564, 4326), N'高德地图', N'POI_MKT_0141', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'红豆居家(大商新玛特商场店)', 3, N'中润大道1号新玛特购物广场中润店F3层', 118.028625, 36.837975, geography::Point(36.837975, 118.028625, 4326), N'高德地图', N'POI_MKT_0142', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'步阳安全门(红星美凯龙淄博昌国商场店)', 3, N'南西五路与昌国路辅路交叉口南160米', 118.033325, 36.783075, geography::Point(36.783075, 118.033325, 4326), N'高德地图', N'POI_MKT_0143', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'菜大全生鲜果蔬超市(商场西街店)', 3, N'商场西街与共青团西路南六巷交叉口南40米', 118.046007, 36.8038, geography::Point(36.8038, 118.046007, 4326), N'高德地图', N'POI_MKT_0144', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'vivo(天乐园商场店)', 3, N'兴学街与金晶大道辅路交叉口西北20米', 118.05771, 36.793618, geography::Point(36.793618, 118.05771, 4326), N'高德地图', N'POI_MKT_0145', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东成专业电动工具(天乐园商场店)', 3, N'安乐街与杏园西路交叉口西北80米', 118.057002, 36.792055, geography::Point(36.792055, 118.057002, 4326), N'高德地图', N'POI_MKT_0146', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'德尔地板(红星美凯龙淄博昌国商场店)', 3, N'昌国路23号', 118.033325, 36.782975, geography::Point(36.782975, 118.033325, 4326), N'高德地图', N'POI_MKT_0147', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'名烟名酒(商场西街店)', 3, N'商场西街与商场西街北七巷交叉口东南40米', 118.045371, 36.804095, geography::Point(36.804095, 118.045371, 4326), N'高德地图', N'POI_MKT_0148', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'顺发五金配钥匙大全', 3, N'高新区大张新村1号沿街房', 118.018837, 36.848666, geography::Point(36.848666, 118.018837, 4326), N'高德地图', N'POI_MKT_0149', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'金贵族(商场西街店)', 3, N'小商品街83号', 118.045921, 36.804109, geography::Point(36.804109, 118.045921, 4326), N'高德地图', N'POI_MKT_0150', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'海林五金建材(石村居民小区齐鲁德艺城店)', 3, N'西八路金石苑沿街房67号', 118.009446, 36.81942, geography::Point(36.81942, 118.009446, 4326), N'高德地图', N'POI_MKT_0151', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'旭升五金', 3, N'杏园街道办事处上湖村湖光路20号甲13号', 118.131626, 36.789142, geography::Point(36.789142, 118.131626, 4326), N'高德地图', N'POI_MKT_0152', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'广东靖达五金(盛世康城3期店)', 3, N'傅家镇鲁中材料城热力公司斜对面', 118.023225, 36.783036, geography::Point(36.783036, 118.023225, 4326), N'高德地图', N'POI_MKT_0153', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'泡泡玛特机器人商店(富力万达广场店)', 3, N'中润大道17号富力万达广场F1', 118.011122, 36.838607, geography::Point(36.838607, 118.011122, 4326), N'高德地图', N'POI_MKT_0154', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'世高五金工具建材商行(市建行宿舍店)', 3, N'西二路78号市建行宿舍', 118.053846, 36.800252, geography::Point(36.800252, 118.053846, 4326), N'高德地图', N'POI_MKT_0155', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'佳鑫盛五金', 3, N'张桓路与中润大道交叉口南160米', 118.043705, 36.83519, geography::Point(36.83519, 118.043705, 4326), N'高德地图', N'POI_MKT_0156', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博华川小商品城', 3, N'[]', 118.02133, 36.824093, geography::Point(36.824093, 118.02133, 4326), N'高德地图', N'POI_MKT_0157', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'盒马鲜生(富力万达广场店)', 3, N'万达广场B1层', 118.010974, 36.838866, geography::Point(36.838866, 118.010974, 4326), N'高德地图', N'POI_MKT_0158', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'鲁中装饰材料城', 3, N'昌国路与世纪路交叉口西300米', 118.020606, 36.785234, geography::Point(36.785234, 118.020606, 4326), N'高德地图', N'POI_MKT_0159', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博义乌小商品城一期', 3, N'华光路与瑞安路交叉口西北220米', 118.021555, 36.823656, geography::Point(36.823656, 118.021555, 4326), N'高德地图', N'POI_MKT_0160', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'银泰·金街', 3, N'鲁泰大道9号(鲁泰大道与西五路交汇处)', 118.03485, 36.848682, geography::Point(36.848682, 118.03485, 4326), N'高德地图', N'POI_MKT_0161', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'百脑汇', 3, N'柳泉路31号', 118.048091, 36.802835, geography::Point(36.802835, 118.048091, 4326), N'高德地图', N'POI_MKT_0162', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博国际商贸城', 3, N'昌国西路88号北京路与昌国路口东北角(原陶瓷科技城D馆)', 117.99447, 36.789472, geography::Point(36.789472, 117.99447, 4326), N'高德地图', N'POI_MKT_0163', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博新世界商业街', 3, N'商业步行街北段路东', 118.042176, 36.805194, geography::Point(36.805194, 118.042176, 4326), N'高德地图', N'POI_MKT_0164', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'八大局西门广场', 3, N'金晶大道140号', 118.06228, 36.809413, geography::Point(36.809413, 118.06228, 4326), N'高德地图', N'POI_MKT_0165', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'常青园便民市场', 3, N'西四路西街与南西五路交叉口东20米', 118.03729, 36.806015, geography::Point(36.806015, 118.03729, 4326), N'高德地图', N'POI_MKT_0166', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'联华·盛德美生活广场(淄博店)', 3, N'和平路与北京路交叉口向西100米路北', 117.989055, 36.801376, geography::Point(36.801376, 117.989055, 4326), N'高德地图', N'POI_MKT_0167', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'富尔玛国际家居', 3, N'人民西路120号', 118.026557, 36.814842, geography::Point(36.814842, 118.026557, 4326), N'高德地图', N'POI_MKT_0168', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'鲁中家具城', 3, N'商场西街121号', 118.042899, 36.803976, geography::Point(36.803976, 118.042899, 4326), N'高德地图', N'POI_MKT_0169', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'京东奥莱(淄博利群广场店)', 3, N'商场东路2号利群购物广场1-2层', 118.060524, 36.800448, geography::Point(36.800448, 118.060524, 4326), N'高德地图', N'POI_MKT_0170', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'盛德美超市(淄博鑫马吾悦广场店)', 3, N'马尚街道华光路288号淄博鑫马吾悦广场F1层', 118.000686, 36.82423, geography::Point(36.82423, 118.000686, 4326), N'高德地图', N'POI_MKT_0171', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'优衣库(淄博万象汇店)', 3, N'金晶大道66号淄博万象汇L1层L125(3号门附近)', 118.062527, 36.801504, geography::Point(36.801504, 118.062527, 4326), N'高德地图', N'POI_MKT_0172', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'大润发(福园店)', 3, N'世纪路与共青团路交叉口东南角的福园22-179-181号商业房', 118.027806, 36.808057, geography::Point(36.808057, 118.027806, 4326), N'高德地图', N'POI_MKT_0173', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'华为智能生活馆•淄博万象汇', 3, N'金晶大道66号淄博万象汇L1层L160(2号门附近)', 118.061048, 36.801426, geography::Point(36.801426, 118.061048, 4326), N'高德地图', N'POI_MKT_0174', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'王府井大街(淄博王府井广场店)', 3, N'公园街道共青团西路57号王府井广场G幢', 118.051974, 36.804646, geography::Point(36.804646, 118.051974, 4326), N'高德地图', N'POI_MKT_0175', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博吉星装饰材料城', 3, N'新村西路8号', 118.055809, 36.799534, geography::Point(36.799534, 118.055809, 4326), N'高德地图', N'POI_MKT_0176', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'嘉汇文具(新村路店)', 3, N'新村西路150-3号', 118.04424, 36.80153, geography::Point(36.80153, 118.04424, 4326), N'高德地图', N'POI_MKT_0177', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'新星家电淄博中心店', 3, N'金晶大道159号新星家电', 118.059613, 36.802739, geography::Point(36.802739, 118.059613, 4326), N'高德地图', N'POI_MKT_0178', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'三星授权体验店(淄博万象汇店)', 3, N'体育场街道66号华润社区淄博万象汇1楼L177', 118.061417, 36.802112, geography::Point(36.802112, 118.061417, 4326), N'高德地图', N'POI_MKT_0179', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'联想体验店(淄博鑫马吾悦店)', 3, N'马上街道办事处华光路288号鑫马吾悦广场一楼1016室', 118.000281, 36.824687, geography::Point(36.824687, 118.000281, 4326), N'高德地图', N'POI_MKT_0180', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'美的智慧家(淄博吾悦美行旗舰店)', 3, N'傅家镇昌国路77号吾悦广场(淄博店)三楼3006', 118.025605, 36.784289, geography::Point(36.784289, 118.025605, 4326), N'高德地图', N'POI_MKT_0181', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'小米之家(淄博市张店区淄博万象汇汽车体验店)', 3, N'体育场街道山东淄博市张店区体育场街道万象汇一楼2号门入口处小米之家', 118.06141, 36.801371, geography::Point(36.801371, 118.06141, 4326), N'高德地图', N'POI_MKT_0182', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'优衣库(富力万达广场店)', 3, N'中润大道17号富力万达广场5号楼F1层', 118.011445, 36.838549, geography::Point(36.838549, 118.011445, 4326), N'高德地图', N'POI_MKT_0183', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'Apple授权专营店(鑫马吾悦店)', 3, N'马尚街道办事处华光路288号鑫马吾悦广场1层1065号', 118.000991, 36.824575, geography::Point(36.824575, 118.000991, 4326), N'高德地图', N'POI_MKT_0184', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'Apple授权专营店(张店吾悦店)', 3, N'世纪路与昌国路交叉口吾悦广场一层1042号', 118.024909, 36.784583, geography::Point(36.784583, 118.024909, 4326), N'高德地图', N'POI_MKT_0185', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'源氏木语(张店万达店)', 3, N'中润大道17号万达广场三楼东南角源氏木语3FCB', 118.011006, 36.839077, geography::Point(36.839077, 118.011006, 4326), N'高德地图', N'POI_MKT_0186', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'KKV(淄博富力万达广场店)', 3, N'中润大道17号富力万达广场一楼次主2', 118.010366, 36.838863, geography::Point(36.838863, 118.010366, 4326), N'高德地图', N'POI_MKT_0187', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'KKV(淄博万象汇主力店)', 3, N'金晶大道66号淄博万象汇L2层L273(1号门进入直行30m,扶梯上到L2可见)', 118.060646, 36.8015, geography::Point(36.8015, 118.060646, 4326), N'高德地图', N'POI_MKT_0188', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'九号电动车(共青团西路店)', 3, N'共青团西路30号齐鲁医药商场东', 118.056714, 36.805879, geography::Point(36.805879, 118.056714, 4326), N'高德地图', N'POI_MKT_0189', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'DJI大疆(淄博万象汇授权体验店)', 3, N'金晶大道66号万象汇一楼L135', 118.061844, 36.801767, geography::Point(36.801767, 118.061844, 4326), N'高德地图', N'POI_MKT_0190', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'家家悦(淄博万象汇店)', 3, N'体育场街道金晶大道66号淄博万象汇负一', 118.061957, 36.801673, geography::Point(36.801673, 118.061957, 4326), N'高德地图', N'POI_MKT_0191', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'联想来酷智生活体验店(淄博商厦店)', 3, N'公园街道金晶大道125号淄博商厦5层', 118.05872, 36.802064, geography::Point(36.802064, 118.05872, 4326), N'高德地图', N'POI_MKT_0192', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'Apple授权专营店(张店万象汇店)', 3, N'金晶大道66号万象汇商场一层L132d', 118.062102, 36.801414, geography::Point(36.801414, 118.062102, 4326), N'高德地图', N'POI_MKT_0193', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'阿迪达斯(淄博万象汇店)', 3, N'金晶大道66号淄博万象汇L3层L359', 118.062384, 36.801508, geography::Point(36.801508, 118.062384, 4326), N'高德地图', N'POI_MKT_0194', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'大润发(淄博店)', 3, N'华光路86号', 118.041643, 36.822082, geography::Point(36.822082, 118.041643, 4326), N'高德地图', N'POI_MKT_0195', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'海圃生鲜超市', 3, N'和平路27甲号一层', 118.032036, 36.796781, geography::Point(36.796781, 118.032036, 4326), N'高德地图', N'POI_MKT_0196', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'天猫小店万春超市', 3, N'柳泉路民祥路路口往东200米路南', 118.065163, 36.855773, geography::Point(36.855773, 118.065163, 4326), N'高德地图', N'POI_MKT_0197', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'名集百福', 3, N'马尚镇人民西路185号凯瑞碧园北门往东约200米', 118.019565, 36.814246, geography::Point(36.814246, 118.019565, 4326), N'高德地图', N'POI_MKT_0198', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'家家悦超市(淄博华光路店)', 3, N'华光路北东三路213号', 118.072517, 36.816607, geography::Point(36.816607, 118.072517, 4326), N'高德地图', N'POI_MKT_0199', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'丰阳大超市(淄博店)', 3, N'西二路与新村西路辅路交叉口东南80米', 118.053854, 36.798598, geography::Point(36.798598, 118.053854, 4326), N'高德地图', N'POI_MKT_0200', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'家家悦(联通路店)', 3, N'红星美凯龙(联通路店)', 118.010705, 36.82892, geography::Point(36.82892, 118.010705, 4326), N'高德地图', N'POI_MKT_0201', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'来佳仓储折扣工厂店', 3, N'中润大道49号(与西五路交叉路口东北角)', 118.037616, 36.837445, geography::Point(36.837445, 118.037616, 4326), N'高德地图', N'POI_MKT_0202', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'名集百福仓储店', 3, N'华光路47号', 118.060489, 36.818916, geography::Point(36.818916, 118.060489, 4326), N'高德地图', N'POI_MKT_0203', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'同善德食材超市', 3, N'西七路与昌国路交叉口西', 118.01772, 36.786992, geography::Point(36.786992, 118.01772, 4326), N'高德地图', N'POI_MKT_0204', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'大众超市(南石社区南区店)', 3, N'南石社区南区东北门东100米', 118.034599, 36.865077, geography::Point(36.865077, 118.034599, 4326), N'高德地图', N'POI_MKT_0205', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'大福源超市(民泰龙凤苑店)', 3, N'马尚街道办事处中润大道西路66号民泰龙风苑农贸市场负一层', 118.009675, 36.836725, geography::Point(36.836725, 118.009675, 4326), N'高德地图', N'POI_MKT_0206', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'宏伟生活超市', 3, N'柳泉路北苑社区西门南侧16号沿街房', 118.068234, 36.874979, geography::Point(36.874979, 118.068234, 4326), N'高德地图', N'POI_MKT_0207', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'家家悦超市淄博恒太城店', 3, N'华光路331号淄博恒太城B1层', 117.982955, 36.823318, geography::Point(36.823318, 117.982955, 4326), N'高德地图', N'POI_MKT_0208', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'家家悦(淄博柳泉店)', 3, N'柳泉路67号印象汇F2层', 118.053458, 36.823382, geography::Point(36.823382, 118.053458, 4326), N'高德地图', N'POI_MKT_0209', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'赵一鸣省钱超市(山东淄博万象汇店)', 3, N'金晶大道157号', 118.059719, 36.802845, geography::Point(36.802845, 118.059719, 4326), N'高德地图', N'POI_MKT_0210', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'友谊超市(傅山店)', 3, N'卫固镇傅山村商贸中心102号商铺', 118.140827, 36.876836, geography::Point(36.876836, 118.140827, 4326), N'高德地图', N'POI_MKT_0211', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'家家悦(淄博吾悦广场店)', 3, N'世纪路昌国路交汇处东南角吾悦广场(淄博店)B1层', 118.025204, 36.784227, geography::Point(36.784227, 118.025204, 4326), N'高德地图', N'POI_MKT_0212', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山姆会员DG商店', 3, N'东二路19-5号', 118.069121, 36.799467, geography::Point(36.799467, 118.069121, 4326), N'高德地图', N'POI_MKT_0213', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'7-ELEVEn(淄博财富广场店)', 3, N'体育场街道金晶大道96号财富广场1层L108商铺', 118.061178, 36.804277, geography::Point(36.804277, 118.061178, 4326), N'高德地图', N'POI_MKT_0214', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'利群超市(淄博购物广场店)', 3, N'商场路2号淄博购物广场B1层', 118.060574, 36.800418, geography::Point(36.800418, 118.060574, 4326), N'高德地图', N'POI_MKT_0215', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'红柿子生鲜超市(齐悦一期店)', 3, N'马尚街道办事处北京路齐悦花园一期G01栋', 117.987939, 36.809138, geography::Point(36.809138, 117.987939, 4326), N'高德地图', N'POI_MKT_0216', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'7-ELEVEn(新世界商业街南段店)', 3, N'新世界商业街与共青团路路口路南', 118.042209, 36.807662, geography::Point(36.807662, 118.042209, 4326), N'高德地图', N'POI_MKT_0217', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'盈吉超市', 3, N'傅家镇营子村北门东100米路南院内营业房', 117.993525, 36.778393, geography::Point(36.778393, 117.993525, 4326), N'高德地图', N'POI_MKT_0218', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'辛坤超市', 3, N'北营金鑫园', 118.065891, 36.855443, geography::Point(36.855443, 118.065891, 4326), N'高德地图', N'POI_MKT_0219', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'嘉汇文具生活(美博二店)', 3, N'科苑街道办事处华光路108号黄金1号公馆3号楼1层102-104营业房', 118.031329, 36.822141, geography::Point(36.822141, 118.031329, 4326), N'高德地图', N'POI_MKT_0220', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'新星超市(杜科店)', 3, N'东三路1号', 118.072276, 36.803663, geography::Point(36.803663, 118.072276, 4326), N'高德地图', N'POI_MKT_0221', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'万佳超市(济南路店)', 3, N'房东村西大门口', 117.969801, 36.837014, geography::Point(36.837014, 117.969801, 4326), N'高德地图', N'POI_MKT_0222', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'晶晶超市(孙家店)', 3, N'傅家镇世纪路孙家社区孙家幼儿园对面', 118.02328, 36.763038, geography::Point(36.763038, 118.02328, 4326), N'高德地图', N'POI_MKT_0223', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'供销万家超市', 3, N'复兴路16号(盛世康城3期南门旁)', 118.022875, 36.781307, geography::Point(36.781307, 118.022875, 4326), N'高德地图', N'POI_MKT_0224', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'叶波大润发(矿机路店)', 3, N'矿机路与西山五街交叉口西20米', 118.034946, 36.752729, geography::Point(36.752729, 118.034946, 4326), N'高德地图', N'POI_MKT_0225', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'赵一鸣零食(淄博明清街店)', 3, N'明清街', 118.043933, 36.827972, geography::Point(36.827972, 118.043933, 4326), N'高德地图', N'POI_MKT_0226', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'丞丞妈冰品旗舰店', 3, N'玉龙商街停车楼北06号', 118.019762, 36.825796, geography::Point(36.825796, 118.019762, 4326), N'高德地图', N'POI_MKT_0227', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'得益鲜活牛奶(北二巷店)', 3, N'金晶大道东一街71号', 118.064207, 36.806941, geography::Point(36.806941, 118.064207, 4326), N'高德地图', N'POI_MKT_0228', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'十足便利店(淄博恒大帝景店)', 3, N'共青团西路203号恒大帝景', 118.017935, 36.808681, geography::Point(36.808681, 118.017935, 4326), N'高德地图', N'POI_MKT_0229', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'名创优品(淄博市万达广场店)', 3, N'中润大道17号富力万达广场二层2081铺位', 118.010537, 36.839001, geography::Point(36.839001, 118.010537, 4326), N'高德地图', N'POI_MKT_0230', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'7-ELEVEn(印象汇店)', 3, N'化纤街2号商铺', 118.053351, 36.823839, geography::Point(36.823839, 118.053351, 4326), N'高德地图', N'POI_MKT_0231', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'十足便利店(淄博洲际中心店)', 3, N'科苑街道柳泉路240号潘成大厦B座一单元一层', 118.055369, 36.82669, geography::Point(36.82669, 118.055369, 4326), N'高德地图', N'POI_MKT_0232', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'亿鲜源超市(鲁泰大道)', 3, N'正圆小区南门东70米', 118.042169, 36.847729, geography::Point(36.847729, 118.042169, 4326), N'高德地图', N'POI_MKT_0233', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'晶晶超市(嘉怡城店)', 3, N'嘉怡城北门东60米', 118.027542, 36.780223, geography::Point(36.780223, 118.027542, 4326), N'高德地图', N'POI_MKT_0234', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'友谊超市(卫固店)', 3, N'淄博高新技术产业开发区卫固镇卫固中心卫生院东北侧', 118.145112, 36.867408, geography::Point(36.867408, 118.145112, 4326), N'高德地图', N'POI_MKT_0235', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'十足便利店(淄博宏程国际店)', 3, N'马尚街道办事处联通路169号甲7号', 118.010201, 36.828922, geography::Point(36.828922, 118.010201, 4326), N'高德地图', N'POI_MKT_0236', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'7-ELEVEn(大学生创业园店)', 3, N'新村西路173号', 118.018025, 36.802625, geography::Point(36.802625, 118.018025, 4326), N'高德地图', N'POI_MKT_0237', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'7-ELEVEn(新世界商业街店)', 3, N'山东省张店区华光路93号7号营业房', 118.042541, 36.820665, geography::Point(36.820665, 118.042541, 4326), N'高德地图', N'POI_MKT_0238', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'叶波大润发生活超市(科苑市场店)', 3, N'联通路与明清街北科苑市场内', 118.044851, 36.829789, geography::Point(36.829789, 118.044851, 4326), N'高德地图', N'POI_MKT_0239', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'嘉汇文具生活(世纪店)', 3, N'房镇镇联通路169号锦商购物中心8号楼57号', 118.023875, 36.832875, geography::Point(36.832875, 118.023875, 4326), N'高德地图', N'POI_MKT_0240', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博商厦超市(小田店)', 3, N'傅家镇世纪路小田村13号楼3单元', 118.021832, 36.77207, geography::Point(36.77207, 118.021832, 4326), N'高德地图', N'POI_MKT_0241', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'7-ELEVEn(711宏程云锦店)', 3, N'宏程云锦北门', 117.976505, 36.847598, geography::Point(36.847598, 117.976505, 4326), N'高德地图', N'POI_MKT_0242', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'赵一鸣零食(淄博福园社区店)', 3, N'福园社区店', 118.029024, 36.807956, geography::Point(36.807956, 118.029024, 4326), N'高德地图', N'POI_MKT_0243', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'嘉汇文具生活(凤凰店)', 3, N'房镇镇重庆路方正·凤凰城15号楼7号', 118.000909, 36.83758, geography::Point(36.83758, 118.000909, 4326), N'高德地图', N'POI_MKT_0244', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'十足便利店(淄博中德金科学府店)', 3, N'柳泉路374号', 118.0684, 36.875879, geography::Point(36.875879, 118.0684, 4326), N'高德地图', N'POI_MKT_0245', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'名创优品(淄博吾悦广场店)', 3, N'世纪路昌国路交汇处东南角吾悦广场(淄博店)F1层', 118.024882, 36.783891, geography::Point(36.783891, 118.024882, 4326), N'高德地图', N'POI_MKT_0246', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'德熙超市(华福大道店)', 3, N'浮山驿西区南门东90米', 118.00622, 36.761943, geography::Point(36.761943, 118.00622, 4326), N'高德地图', N'POI_MKT_0247', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'橙子便利(金达大厦店)', 3, N'淄博市高新区柳泉路115号金达大厦A座一楼大厅东北角106室', 118.058134, 36.843012, geography::Point(36.843012, 118.058134, 4326), N'高德地图', N'POI_MKT_0248', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'赵一鸣零食(傅家镇吾悦金街店)', 3, N'傅家镇吾悅金街店', 118.024704, 36.782889, geography::Point(36.782889, 118.024704, 4326), N'高德地图', N'POI_MKT_0249', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'LAWSON罗森(淄博万象汇店)', 3, N'体育场街道办事处共青团东路南一巷17号华润凯旋门5号楼2号铺', 118.061668, 36.803546, geography::Point(36.803546, 118.061668, 4326), N'高德地图', N'POI_MKT_0250', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'名创优品(山东淄博张店银泰2店)', 3, N'鲁泰大道9号银泰城一楼', 118.034471, 36.848698, geography::Point(36.848698, 118.034471, 4326), N'高德地图', N'POI_MKT_0251', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'赵一鸣零食(淄博金鑫园店)', 3, N'和平路96号', 118.017727, 36.79902, geography::Point(36.79902, 118.017727, 4326), N'高德地图', N'POI_MKT_0252', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'橙子便利(玉龙大厦店)', 3, N'东一街27号玉龙大厦A座F1层', 118.023736, 36.822546, geography::Point(36.822546, 118.023736, 4326), N'高德地图', N'POI_MKT_0253', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'7-ELEVEn(淄博市图书馆店)', 3, N'市图书馆一楼西南角书香驿站', 117.986052, 36.828789, geography::Point(36.828789, 117.986052, 4326), N'高德地图', N'POI_MKT_0254', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'十足便利店(淄博王府井店)', 3, N'公园街道共青团西路57-3号AB栋B01一层', 118.051554, 36.806042, geography::Point(36.806042, 118.051554, 4326), N'高德地图', N'POI_MKT_0255', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'十足便利店(淄博陶瓷产业园店)', 3, N'先进陶瓷产业创新园C座C3北门', 118.061125, 36.856925, geography::Point(36.856925, 118.061125, 4326), N'高德地图', N'POI_MKT_0256', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'赵一鸣省钱超市(山东淄博龙泰店)', 3, N'华润·橡树湾东门东南100米', 118.000531, 36.834097, geography::Point(36.834097, 118.000531, 4326), N'高德地图', N'POI_MKT_0257', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'橙子便利(淄博吾悦广场店)', 3, N'傅家镇南世纪路与昌国路路口东南角嘉美大厦一层0122号', 118.024853, 36.782544, geography::Point(36.782544, 118.024853, 4326), N'高德地图', N'POI_MKT_0258', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'友客便利店(北京路百合花园紫薇店)', 3, N'绿城百合紫薇园南门旁', 117.994997, 36.846938, geography::Point(36.846938, 117.994997, 4326), N'高德地图', N'POI_MKT_0259', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'盈吉超市(傅家店)', 3, N'华福大道112号', 117.99877, 36.762434, geography::Point(36.762434, 117.99877, 4326), N'高德地图', N'POI_MKT_0260', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'宜品惠硬折扣超市', 3, N'新村西路185号甲7号', 118.014211, 36.80342, geography::Point(36.80342, 118.014211, 4326), N'高德地图', N'POI_MKT_0261', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'十足便利店(淄博风景华庭酒店店)', 3, N'华光路62-甲1号(中国农业银行南门旁)', 118.049973, 36.820995, geography::Point(36.820995, 118.049973, 4326), N'高德地图', N'POI_MKT_0262', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'锅圈食汇火锅烧烤食材超市(共青团路凯旋门店)', 3, N'共青团东路9号院65号', 118.063191, 36.804357, geography::Point(36.804357, 118.063191, 4326), N'高德地图', N'POI_MKT_0263', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'惠泽超市(魏家庄店)', 3, N'华瑞园北区东南门南90米', 118.060903, 36.834204, geography::Point(36.834204, 118.060903, 4326), N'高德地图', N'POI_MKT_0264', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博商厦超市(东城华府店)', 3, N'人民东路33甲19-22号', 118.07642, 36.808969, geography::Point(36.808969, 118.07642, 4326), N'高德地图', N'POI_MKT_0265', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'十足便利店(淄博中欧国际大厦店)', 3, N'中欧国际大厦30号一层', 117.992984, 36.820632, geography::Point(36.820632, 117.992984, 4326), N'高德地图', N'POI_MKT_0266', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'鑫强超市(兰雁大道店)', 3, N'兰雁大道华南园33号沿街房', 118.068349, 36.850703, geography::Point(36.850703, 118.068349, 4326), N'高德地图', N'POI_MKT_0267', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'快享便利(石村店)', 3, N'马尚镇新石街24号', 118.008528, 36.819802, geography::Point(36.819802, 118.008528, 4326), N'高德地图', N'POI_MKT_0268', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'橙子便利(中欧大厦店)', 3, N'马尚街道中欧国际大厦1号', 117.992936, 36.820622, geography::Point(36.820622, 117.992936, 4326), N'高德地图', N'POI_MKT_0269', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'聚贤苑快递超市', 3, N'淄博高新区人民法院法官便民工作站北侧100米', 118.072519, 36.8684, geography::Point(36.8684, 118.072519, 4326), N'高德地图', N'POI_MKT_0270', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'利群超市(利群时代店)', 3, N'柳泉路29号利群时代柳泉路店F1层', 118.048038, 36.801885, geography::Point(36.801885, 118.048038, 4326), N'高德地图', N'POI_MKT_0271', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博商厦超市(翡翠园店)', 3, N'翡翠园樱红路9号', 118.052748, 36.831627, geography::Point(36.831627, 118.052748, 4326), N'高德地图', N'POI_MKT_0272', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'十足便利店(淄博明博新城店)', 3, N'明博新城小区18幢', 117.982375, 36.820825, geography::Point(36.820825, 117.982375, 4326), N'高德地图', N'POI_MKT_0273', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'名创优品(印象汇店)', 3, N'柳泉路67号凯德广场一楼', 118.053139, 36.823185, geography::Point(36.823185, 118.053139, 4326), N'高德地图', N'POI_MKT_0274', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'7-ELEVEn(万科翡翠书院店)', 3, N'丰安路69号', 118.008075, 36.841025, geography::Point(36.841025, 118.008075, 4326), N'高德地图', N'POI_MKT_0275', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'华联超市(淄博站店)', 3, N'昌国快速路出口与昌国快速路入口交叉口东北220米', 118.057168, 36.787016, geography::Point(36.787016, 118.057168, 4326), N'高德地图', N'POI_MKT_0276', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'银泉超市(柳泉路店)', 3, N'傅家镇山泉路287号', 118.023346, 36.74502, geography::Point(36.74502, 118.023346, 4326), N'高德地图', N'POI_MKT_0277', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'橙子便利(星河城店)', 3, N'和平路177号', 117.988558, 36.799932, geography::Point(36.799932, 117.988558, 4326), N'高德地图', N'POI_MKT_0278', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'7-ELEVEn(重庆路店)', 3, N'亿丰商场', 118.002475, 36.816725, geography::Point(36.816725, 118.002475, 4326), N'高德地图', N'POI_MKT_0279', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'叶波大润发(叶波店)', 3, N'华光路与市府东一街交叉口东340米', 118.061002, 36.820902, geography::Point(36.820902, 118.061002, 4326), N'高德地图', N'POI_MKT_0280', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'银川清真牛羊肉(万科店)', 3, N'万科翡翠书院南区北门东北60米', 118.007819, 36.840918, geography::Point(36.840918, 118.007819, 4326), N'高德地图', N'POI_MKT_0281', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'橙子便利(淄博万达店)', 3, N'丰悦路与丰安路交叉口南180米', 118.00904, 36.839698, geography::Point(36.839698, 118.00904, 4326), N'高德地图', N'POI_MKT_0282', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'名创优品(淄博鑫马吾悦广场店)', 3, N'鑫马吾悦广场一层1066-1067', 118.001025, 36.824525, geography::Point(36.824525, 118.001025, 4326), N'高德地图', N'POI_MKT_0283', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'眼镜直通车超市(金晶大道店)', 3, N'和平街道金晶大道115号科技大楼二楼', 118.059346, 36.80102, geography::Point(36.80102, 118.059346, 4326), N'高德地图', N'POI_MKT_0284', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'橙子便利(尚美店)', 3, N'公园街道办事处北西五路6号院19号楼101号', 118.038962, 36.809118, geography::Point(36.809118, 118.038962, 4326), N'高德地图', N'POI_MKT_0285', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'7-ELEVEn(兴业家园店)', 3, N'北西六路78甲1号1层', 118.032525, 36.820125, geography::Point(36.820125, 118.032525, 4326), N'高德地图', N'POI_MKT_0286', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'十足便利店(淄博天乙花苑店)', 3, N'丰宁路23号曦园', 117.999694, 36.846354, geography::Point(36.846354, 117.999694, 4326), N'高德地图', N'POI_MKT_0287', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'7-ELEVEn(宏程·国际广场店)', 3, N'[]', 118.01094, 36.827576, geography::Point(36.827576, 118.01094, 4326), N'高德地图', N'POI_MKT_0288', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'赵一鸣省钱超市(山东淄博四宝山三玉店)', 3, N'四宝山街道王东村超市西第一间商铺', 118.072406, 36.873569, geography::Point(36.873569, 118.072406, 4326), N'高德地图', N'POI_MKT_0289', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'锅圈食汇火锅烧烤食材超市(世纪路店)', 3, N'傅家镇南世纪路78号(福林小区北2门北170米)', 118.022273, 36.772633, geography::Point(36.772633, 118.022273, 4326), N'高德地图', N'POI_MKT_0290', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'赵一鸣省钱超市(山东淄博九级金塔社区店)', 3, N'马尚街道瑞安路02号九级村金塔农贸市场内', 118.020935, 36.815565, geography::Point(36.815565, 118.020935, 4326), N'高德地图', N'POI_MKT_0291', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'锅圈食汇火锅烧烤食材超市(曦园店)', 3, N'北京路132号', 117.997572, 36.846319, geography::Point(36.846319, 117.997572, 4326), N'高德地图', N'POI_MKT_0292', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'锅圈食汇火锅烧烤食材超市(北营店)', 3, N'民祥路668号(北营金鑫园南区15号楼底商、南2门东侧)', 118.06793, 36.85588, geography::Point(36.85588, 118.06793, 4326), N'高德地图', N'POI_MKT_0293', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'惠东生鲜超市(新世界商业街店)', 3, N'新世界步行街北段92号(道庄小区东区西2门旁)', 118.042025, 36.818175, geography::Point(36.818175, 118.042025, 4326), N'高德地图', N'POI_MKT_0294', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'可好(创业火炬广场店)', 3, N'柳泉路109号创业火炬广场F1层', 118.057613, 36.841119, geography::Point(36.841119, 118.057613, 4326), N'高德地图', N'POI_MKT_0295', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'嘉汇生活(北营店)', 3, N'柳泉路342号一楼嘉汇北营店', 118.062075, 36.853125, geography::Point(36.853125, 118.062075, 4326), N'高德地图', N'POI_MKT_0296', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'锅圈食汇火锅烧烤食材超市(齐悦国际店)', 3, N'马尚街道齐悦国际花园一期沿街商铺G01-5', 117.989475, 36.810024, geography::Point(36.810024, 117.989475, 4326), N'高德地图', N'POI_MKT_0297', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'711便利店(淄博水晶街店)', 3, N'马尚街道人民西路186号亿丰大厦1层东北侧门头房', 118.002475, 36.816697, geography::Point(36.816697, 118.002475, 4326), N'高德地图', N'POI_MKT_0298', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'乾兴超市(王舍路店)', 3, N'王舍路237号植物园南门对过', 118.028741, 36.78975, geography::Point(36.78975, 118.028741, 4326), N'高德地图', N'POI_MKT_0299', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'卫固信诚超市', 3, N'卫北路与中心路交叉口东500米', 118.146474, 36.86886, geography::Point(36.86886, 118.146474, 4326), N'高德地图', N'POI_MKT_0300', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'锅圈食汇火锅烧烤食材超市(义乌路店)', 3, N'江南豪庭西北门北60米', 118.019114, 36.828678, geography::Point(36.828678, 118.019114, 4326), N'高德地图', N'POI_MKT_0301', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'可好(银泰时代广场店)', 3, N'玉龙大厦b座2号', 118.034384, 36.849914, geography::Point(36.849914, 118.034384, 4326), N'高德地图', N'POI_MKT_0302', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'赵一鸣省钱超市(山东淄博王舍店)', 3, N'王舍路68号王舍生活区一区', 118.040367, 36.789898, geography::Point(36.789898, 118.040367, 4326), N'高德地图', N'POI_MKT_0303', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'松鼠便利(山理工店)', 3, N'淄博市体育中心地下停车场四号口下来后跨过栏杆步行右拐后直走50米', 117.991491, 36.813667, geography::Point(36.813667, 117.991491, 4326), N'高德地图', N'POI_MKT_0304', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'雪银超市', 3, N'潘南东路22号小化纤工会礼堂一楼', 118.088871, 36.811739, geography::Point(36.811739, 118.088871, 4326), N'高德地图', N'POI_MKT_0305', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'菲高超市(张店区店)', 3, N'房镇镇北京路77号绿城百合花园桂花园', 117.992973, 36.847498, geography::Point(36.847498, 117.992973, 4326), N'高德地图', N'POI_MKT_0306', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'可好便利店(万象汇店)', 3, N'金晶大道66号万象汇F1层', 118.06171, 36.803537, geography::Point(36.803537, 118.06171, 4326), N'高德地图', N'POI_MKT_0307', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'可好(金晶大道061707店)', 3, N'金晶大道197号', 118.063439, 36.814585, geography::Point(36.814585, 118.063439, 4326), N'高德地图', N'POI_MKT_0308', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'名创优品(水晶街店)', 3, N'马尚街道人民西路与重庆路交汇处水晶街F座一层6A', 118.003875, 36.816325, geography::Point(36.816325, 118.003875, 4326), N'高德地图', N'POI_MKT_0309', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'绿农生鲜超市(三八线店)', 3, N'班家村便民市场12A', 117.967375, 36.808875, geography::Point(36.808875, 117.967375, 4326), N'高德地图', N'POI_MKT_0310', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'聚合购物(尚庄店)', 3, N'春风路与联通路交叉口南140米', 118.10215, 36.819746, geography::Point(36.819746, 118.10215, 4326), N'高德地图', N'POI_MKT_0311', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'锅圈食汇火锅烧烤食材超市(张店区房镇店)', 3, N'淄博创新谷东门南100米', 117.976066, 36.827721, geography::Point(36.827721, 117.976066, 4326), N'高德地图', N'POI_MKT_0312', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'橙子便利(西六路店)', 3, N'南西六路45号,山东省淄博市张店区南西六路45号', 118.031819, 36.80162, geography::Point(36.80162, 118.031819, 4326), N'高德地图', N'POI_MKT_0313', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'橙子便利(宏程国际店)', 3, N'房镇镇联通路169号宏程国际广场4号楼12号', 118.008706, 36.828506, geography::Point(36.828506, 118.008706, 4326), N'高德地图', N'POI_MKT_0314', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'十足便利店(淄博吾悦广场店)', 3, N'傅家镇南世纪路与昌国路路口东南角嘉亿国际财富中心5号楼1单元1层', 118.025553, 36.782655, geography::Point(36.782655, 118.025553, 4326), N'高德地图', N'POI_MKT_0315', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'嘉汇生活(天乙店)', 3, N'房镇镇北京路与天乙路路口东南角沿街房4-02百虹宾馆对面', 117.998045, 36.846393, geography::Point(36.846393, 117.998045, 4326), N'高德地图', N'POI_MKT_0316', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'锅圈食汇火锅烧烤食材超市(张店区橡树湾店)', 3, N'北京路64号', 118.000225, 36.835225, geography::Point(36.835225, 118.000225, 4326), N'高德地图', N'POI_MKT_0317', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'奥朗特超市', 3, N'奥朗特购物广场西南门旁', 118.012656, 36.81028, geography::Point(36.81028, 118.012656, 4326), N'高德地图', N'POI_MKT_0318', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'小玉杂货铺vintage', 3, N'和平路131号唐库文创园', 118.005551, 36.796908, geography::Point(36.796908, 118.005551, 4326), N'高德地图', N'POI_MKT_0319', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'7-ELEVEn(淄博恒太城店)', 3, N'华光路331号淄博恒太城F1层', 117.982175, 36.823775, geography::Point(36.823775, 117.982175, 4326), N'高德地图', N'POI_MKT_0320', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'锅圈食汇火锅烧烤食材超市(华光路金乔店)', 3, N'金乔社区北区西南2门南110米', 118.073205, 36.816741, geography::Point(36.816741, 118.073205, 4326), N'高德地图', N'POI_MKT_0321', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'呈大生鲜超市', 3, N'山东博泰集团西南门东60米', 118.05593, 36.853115, geography::Point(36.853115, 118.05593, 4326), N'高德地图', N'POI_MKT_0322', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'秋润鲜果蔬超市(和平路店)', 3, N'尚美苑西1门旁', 117.99457, 36.7992, geography::Point(36.7992, 117.99457, 4326), N'高德地图', N'POI_MKT_0323', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'锅圈食汇火锅烧烤食材超市(和平路店)', 3, N'马尚街道办事处和平路169甲', 117.992519, 36.799389, geography::Point(36.799389, 117.992519, 4326), N'高德地图', N'POI_MKT_0324', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'锅圈食汇火锅烧烤食材超市(华侨城店)', 3, N'张店区高新区万杰路79号天府名城1号楼甲4号沿街房一楼', 118.038088, 36.843699, geography::Point(36.843699, 118.038088, 4326), N'高德地图', N'POI_MKT_0325', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'如意超市(中德奥林新城店)', 3, N'柳泉路372号', 118.06982, 36.87342, geography::Point(36.87342, 118.06982, 4326), N'高德地图', N'POI_MKT_0326', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'爱家易购2元超市(小徐世纪嘉苑店)', 3, N'世纪路与海岱大道交叉口南460米', 118.023221, 36.765554, geography::Point(36.765554, 118.023221, 4326), N'高德地图', N'POI_MKT_0327', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'十足便利店(淄博华夏国际店)', 3, N'张店区美食街135号一楼', 118.050456, 36.803379, geography::Point(36.803379, 118.050456, 4326), N'高德地图', N'POI_MKT_0328', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博山姆甄选', 3, N'水晶街人民路与重庆路东北侧', 118.004809, 36.816033, geography::Point(36.816033, 118.004809, 4326), N'高德地图', N'POI_MKT_0329', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'团批司令', 3, N'昌国西路29号B12-6号', 118.03128, 36.781482, geography::Point(36.781482, 118.03128, 4326), N'高德地图', N'POI_MKT_0330', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'十足便利店(黄金总部大厦店)', 3, N'华光路108号', 118.031013, 36.822144, geography::Point(36.822144, 118.031013, 4326), N'高德地图', N'POI_MKT_0331', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'鲜啤福鹿家(淄博八大局店)', 3, N'体育场街道八大局便民市场南门东北侧', 118.064889, 36.80465, geography::Point(36.80465, 118.064889, 4326), N'高德地图', N'POI_MKT_0332', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'林华生鲜超市(林溪郡店)', 3, N'林溪郡', 118.024066, 36.86404, geography::Point(36.86404, 118.024066, 4326), N'高德地图', N'POI_MKT_0333', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'惠东生鲜超市(潘南东路店)', 3, N'潘南东路27号西北100米', 118.078846, 36.811945, geography::Point(36.811945, 118.078846, 4326), N'高德地图', N'POI_MKT_0334', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'德好便利店(银领店)', 3, N'华光路79号银领国际6号楼', 118.04957, 36.820286, geography::Point(36.820286, 118.04957, 4326), N'高德地图', N'POI_MKT_0335', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'可好(蓝钻国际店)', 3, N'共青团西路119号蓝钻国际F1层', 118.035244, 36.807599, geography::Point(36.807599, 118.035244, 4326), N'高德地图', N'POI_MKT_0336', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'广州眼镜直通车超市(理工大店)', 3, N'共青团路88号-甲1号甲2号', 118.039939, 36.80823, geography::Point(36.80823, 118.039939, 4326), N'高德地图', N'POI_MKT_0337', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'银泉烟酒超市', 3, N'淄博西张五金机电城A座115号', 118.083946, 36.79771, geography::Point(36.79771, 118.083946, 4326), N'高德地图', N'POI_MKT_0338', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'红梅超市(南营路店)', 3, N'南营小区西南门旁', 118.065603, 36.844766, geography::Point(36.844766, 118.065603, 4326), N'高德地图', N'POI_MKT_0339', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'佳居源百货商行(大卫拖把专家)', 3, N'华光路268号义乌小商品城二期三楼东区1618至1623佳居源百货商行大卫拖把专家', 118.021675, 36.825075, geography::Point(36.825075, 118.021675, 4326), N'高德地图', N'POI_MKT_0340', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博荟锦福超市(三玉店)', 3, N'淄博开发区石桥办事处王东村文化路与赵王路交叉口向西150米路北', 118.073431, 36.87345, geography::Point(36.87345, 118.073431, 4326), N'高德地图', N'POI_MKT_0341', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'华城惠家精品生鲜超市', 3, N'张店区高新区四宝山街道南石社区南区北门西侧24号楼沿街商铺东侧一楼', 118.033552, 36.865286, geography::Point(36.865286, 118.033552, 4326), N'高德地图', N'POI_MKT_0342', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'快享便利(九级村委会店)', 3, N'马尚镇九级村综合楼沿街房一层1-3号', 118.022084, 36.818642, geography::Point(36.818642, 118.022084, 4326), N'高德地图', N'POI_MKT_0343', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'7-ELEVEn(山东理工大学店)', 3, N'绿岛东路与绿岛西路交叉口东160米', 118.001642, 36.813754, geography::Point(36.813754, 118.001642, 4326), N'高德地图', N'POI_MKT_0344', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'友客便利(火炬广场店)', 3, N'万杰路102号火炬花园5号楼1-2层101网点', 118.055868, 36.840399, geography::Point(36.840399, 118.055868, 4326), N'高德地图', N'POI_MKT_0345', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'嘉汇生活(百合店)', 3, N'房镇镇北北京路77号百合花园桂花园8号楼1层105铺', 117.992319, 36.847562, geography::Point(36.847562, 117.992319, 4326), N'高德地图', N'POI_MKT_0346', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'惠泽超市(豪庭店)', 3, N'九级便民市场', 118.020449, 36.828608, geography::Point(36.828608, 118.020449, 4326), N'高德地图', N'POI_MKT_0347', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'一点利水果蔬菜超市(龙凤苑店)', 3, N'龙喜花苑南区东门西北70米', 118.007911, 36.831701, geography::Point(36.831701, 118.007911, 4326), N'高德地图', N'POI_MKT_0348', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'联民超市(东方公寓店)', 3, N'西二路68-15号', 118.054563, 36.797537, geography::Point(36.797537, 118.054563, 4326), N'高德地图', N'POI_MKT_0349', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'可好便利(水晶街店)', 3, N'马尚街道人民西路与重庆路交汇处水晶街项目F座1层05号铺', 118.003766, 36.816332, geography::Point(36.816332, 118.003766, 4326), N'高德地图', N'POI_MKT_0350', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'惠泽超市(义乌路店)', 3, N'义乌商城街红糖果北邻', 118.018568, 36.824045, geography::Point(36.824045, 118.018568, 4326), N'高德地图', N'POI_MKT_0351', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'合欢生活超市', 3, N'人民西路55-8号', 118.029782, 36.814032, geography::Point(36.814032, 118.029782, 4326), N'高德地图', N'POI_MKT_0352', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'锅圈食汇(明清街店)', 3, N'科苑街道办事处张桓路36号17甲营业房', 118.044075, 36.833875, geography::Point(36.833875, 118.044075, 4326), N'高德地图', N'POI_MKT_0353', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'大商超市(理工大学店)', 3, N'张周路12号(理工大学内)', 118.006325, 36.811225, geography::Point(36.811225, 118.006325, 4326), N'高德地图', N'POI_MKT_0354', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'顺风二手电动车超市(顺风车行)', 3, N'金晶大道189号华润中央公园3期北沿街商铺179号甲20号', 118.060509, 36.807296, geography::Point(36.807296, 118.060509, 4326), N'高德地图', N'POI_MKT_0355', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'心联心生活超市(南营双营园店)', 3, N'兰雁大道与华菁园西路交叉口东100米', 118.072249, 36.850075, geography::Point(36.850075, 118.072249, 4326), N'高德地图', N'POI_MKT_0356', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'橙子便利(云龙国际店)', 3, N'华光路28号甲3号云龙国际B座F1层', 118.063204, 36.81918, geography::Point(36.81918, 118.063204, 4326), N'高德地图', N'POI_MKT_0357', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'可好(翡丽公馆061738店)', 3, N'济南路碧桂园翡丽公馆1号商业楼102', 117.967263, 36.823979, geography::Point(36.823979, 117.967263, 4326), N'高德地图', N'POI_MKT_0358', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'宜家超市(魏北路店)', 3, N'魏家路与魏家路西一巷交叉口东南40米', 118.060935, 36.832623, geography::Point(36.832623, 118.060935, 4326), N'高德地图', N'POI_MKT_0359', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'可好便利店(恒大帝景1号公寓楼店)', 3, N'共青团西路237号', 118.017329, 36.808758, geography::Point(36.808758, 118.017329, 4326), N'高德地图', N'POI_MKT_0360', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'好又多超市(东方星城店)', 3, N'东方星城樱花园2号楼8室', 118.068649, 36.821823, geography::Point(36.821823, 118.068649, 4326), N'高德地图', N'POI_MKT_0361', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'得邻超市(儿童公园店)', 3, N'东二路24号百盛商城26-2号', 118.069694, 36.799871, geography::Point(36.799871, 118.069694, 4326), N'高德地图', N'POI_MKT_0362', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'锅圈食汇(王舍荣悦城店)', 3, N'车站街道南西四路王舍荣悦城88甲10号商铺', 118.040274, 36.787444, geography::Point(36.787444, 118.040274, 4326), N'高德地图', N'POI_MKT_0363', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'双汇鲜万家(唐家山路店)', 3, N'城南壹号北门西80米', 118.015275, 36.775575, geography::Point(36.775575, 118.015275, 4326), N'高德地图', N'POI_MKT_0364', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'乐爱购折扣生鲜超市(魏家庄店)', 3, N'四宝山街道办事处金晶大道北首253号-4号商铺西大厅', 118.068058, 36.831553, geography::Point(36.831553, 118.068058, 4326), N'高德地图', N'POI_MKT_0365', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'李铁食品(石村店)', 3, N'石村便民市场东南门旁', 118.003124, 36.821273, geography::Point(36.821273, 118.003124, 4326), N'高德地图', N'POI_MKT_0366', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博德熙超市(南苑绿洲店)', 3, N'南苑绿洲小区西门东侧路北16-17-18号房沿街房', 118.023315, 36.765554, geography::Point(36.765554, 118.023315, 4326), N'高德地图', N'POI_MKT_0367', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'宜品生鲜(丰泰路店)', 3, N'龙泰国际营业房13-9', 118.000687, 36.835179, geography::Point(36.835179, 118.000687, 4326), N'高德地图', N'POI_MKT_0368', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'积美便利店', 3, N'齐盛湖西积美路43号', 117.979723, 36.841863, geography::Point(36.841863, 117.979723, 4326), N'高德地图', N'POI_MKT_0369', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'眼镜直通车(王府井店)', 3, N'公园街道共青团西路57号淄博王府井广场AB幢57-1号二楼', 118.051524, 36.806029, geography::Point(36.806029, 118.051524, 4326), N'高德地图', N'POI_MKT_0370', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'客来CC便利店', 3, N'科苑街道办事处张桓路36甲1号1楼', 118.044109, 36.832959, geography::Point(36.832959, 118.044109, 4326), N'高德地图', N'POI_MKT_0371', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'欣荣超市(海岱大道店)', 3, N'南定镇夏庄小区一号楼和三号楼之间', 118.0543, 36.766162, geography::Point(36.766162, 118.0543, 4326), N'高德地图', N'POI_MKT_0372', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'宏程百货批发经营部', 3, N'中润大道136号', 118.0757, 36.83228, geography::Point(36.83228, 118.0757, 4326), N'高德地图', N'POI_MKT_0373', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐耀水果超市(金晶大道店)', 3, N'齐耀花园187号甲9号', 118.061075, 36.807875, geography::Point(36.807875, 118.061075, 4326), N'高德地图', N'POI_MKT_0374', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'聪小度生鲜团购批发仓', 3, N'马尚街道办事处和平路169甲1一层', 117.99376, 36.79932, geography::Point(36.79932, 117.99376, 4326), N'高德地图', N'POI_MKT_0375', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'信好又多生活超市(王舍路店)', 3, N'张店安冉诊所西北侧110米', 118.01971, 36.790866, geography::Point(36.790866, 118.01971, 4326), N'高德地图', N'POI_MKT_0376', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'红吉超市(万象汇店)', 3, N'东二路百盛商城22-27号', 118.07132, 36.799298, geography::Point(36.799298, 118.07132, 4326), N'高德地图', N'POI_MKT_0377', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'如果便利店(金桥商务中心店)', 3, N'华光路10号甲16号金桥商务中心F1层', 118.073859, 36.817439, geography::Point(36.817439, 118.073859, 4326), N'高德地图', N'POI_MKT_0378', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'惠宜选MAX超市(世纪路店)', 3, N'公园街道办事处北西六路1号中关村科技城地下一层52号', 118.031425, 36.809325, geography::Point(36.809325, 118.031425, 4326), N'高德地图', N'POI_MKT_0379', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'天宇茶叶平价超市(恒泰商城店)', 3, N'华光路恒泰商城68号甲8号', 118.048541, 36.821123, geography::Point(36.821123, 118.048541, 4326), N'高德地图', N'POI_MKT_0380', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'可好便利店(华侨大厦店)', 3, N'北京路华侨大厦8号商铺', 117.992876, 36.819887, geography::Point(36.819887, 117.992876, 4326), N'高德地图', N'POI_MKT_0381', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'鑫诺佳超市', 3, N'中埠镇鑫诺佳超市', 118.188617, 36.84749, geography::Point(36.84749, 118.188617, 4326), N'高德地图', N'POI_MKT_0382', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'三和超市(西二路店)', 3, N'西二路255-3号金穗家园', 118.056007, 36.810718, geography::Point(36.810718, 118.056007, 4326), N'高德地图', N'POI_MKT_0383', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'铠玮果蔬便利店', 3, N'西二路216号甲3号', 118.056294, 36.810286, geography::Point(36.810286, 118.056294, 4326), N'高德地图', N'POI_MKT_0384', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'转角遇到便利店(张辛小区店)', 3, N'张辛小区12号楼东门南60米', 118.058946, 36.810534, geography::Point(36.810534, 118.058946, 4326), N'高德地图', N'POI_MKT_0385', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'德好便利店(新元店)', 3, N'科苑街道柳泉路57号新元学校对面', 118.052574, 36.819206, geography::Point(36.819206, 118.052574, 4326), N'高德地图', N'POI_MKT_0386', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'麦便利(银领国际店)', 3, N'柳泉路西三巷4-6号', 118.051026, 36.818898, geography::Point(36.818898, 118.051026, 4326), N'高德地图', N'POI_MKT_0387', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'易捷便利店(张店第15加油站)', 3, N'华光路71号中国石化华光路广电大厦加油站(淄博高新15)', 118.054636, 36.819888, geography::Point(36.819888, 118.054636, 4326), N'高德地图', N'POI_MKT_0388', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'百兴便利店', 3, N'淄博市中心医院北1门旁', 118.051742, 36.808196, geography::Point(36.808196, 118.051742, 4326), N'高德地图', N'POI_MKT_0389', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'友客便利店(西二路中心医院店)', 3, N'滨州医学院淄博教学基地东门旁', 118.055702, 36.807388, geography::Point(36.807388, 118.055702, 4326), N'高德地图', N'POI_MKT_0390', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'铖霖超市', 3, N'华润中央公园东门旁', 118.062126, 36.810699, geography::Point(36.810699, 118.062126, 4326), N'高德地图', N'POI_MKT_0391', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'小麦便利店', 3, N'金晶大道与潘南东路交叉口西南160米', 118.063063, 36.813493, geography::Point(36.813493, 118.063063, 4326), N'高德地图', N'POI_MKT_0392', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'金通便利店', 3, N'金晶大道187号甲40号', 118.061688, 36.809688, geography::Point(36.809688, 118.061688, 4326), N'高德地图', N'POI_MKT_0393', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'乐点超市', 3, N'人民西路一甲八号', 118.061125, 36.811322, geography::Point(36.811322, 118.061125, 4326), N'高德地图', N'POI_MKT_0394', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'誉江山菊梓便利店', 3, N'公园街道办事处金晶大道187甲35号一层', 118.061575, 36.809275, geography::Point(36.809275, 118.061575, 4326), N'高德地图', N'POI_MKT_0395', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'便民超市(西二路西六巷店)', 3, N'共青团西路辅路与王府井时尚街交叉口北120米', 118.052581, 36.807254, geography::Point(36.807254, 118.052581, 4326), N'高德地图', N'POI_MKT_0396', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'可好便利(八大局不夜城060031店)', 3, N'人民东路6号八大局便民市场', 118.062212, 36.809139, geography::Point(36.809139, 118.062212, 4326), N'高德地图', N'POI_MKT_0397', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'辰喜便利店', 3, N'齐耀花园东1门西南170米', 118.06129, 36.808421, geography::Point(36.808421, 118.06129, 4326), N'高德地图', N'POI_MKT_0398', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'达达便利店(华润中央公园店)', 3, N'中心路177号西北方向120米华润·中央公园三期', 118.060273, 36.807361, geography::Point(36.807361, 118.060273, 4326), N'高德地图', N'POI_MKT_0399', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'可好便利店(中心医院1719店)', 3, N'共青团西路54号中心医院西侧', 118.051838, 36.806603, geography::Point(36.806603, 118.051838, 4326), N'高德地图', N'POI_MKT_0400', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'富余达优选', 3, N'柳泉路西三巷金世界商城1号楼飞象优选淄博001店', 118.050219, 36.818839, geography::Point(36.818839, 118.050219, 4326), N'高德地图', N'POI_MKT_0401', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'慧元惠选', 3, N'天府明珠东南门西南80米', 118.049553, 36.815785, geography::Point(36.815785, 118.049553, 4326), N'高德地图', N'POI_MKT_0402', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'辰星便利店(中央公园店)', 3, N'金晶大道179号甲14号', 118.060915, 36.807093, geography::Point(36.807093, 118.060915, 4326), N'高德地图', N'POI_MKT_0403', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'小满便利店', 3, N'金晶大道与潘南西路交叉口西南160米', 118.063076, 36.81354, geography::Point(36.81354, 118.063076, 4326), N'高德地图', N'POI_MKT_0404', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'友客便利店(共青团西路王府井店)', 3, N'共青团西路48-58号', 118.052475, 36.805875, geography::Point(36.805875, 118.052475, 4326), N'高德地图', N'POI_MKT_0405', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'快享便利(中央公园店)', 3, N'金晶大道179号甲8号', 118.060843, 36.806841, geography::Point(36.806841, 118.060843, 4326), N'高德地图', N'POI_MKT_0406', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'德好便利(齐耀店)', 3, N'齐耀花园南门旁', 118.060069, 36.807706, geography::Point(36.807706, 118.060069, 4326), N'高德地图', N'POI_MKT_0407', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'友客便利(金晶大道店)', 3, N'金晶大道和东一街路口', 118.061714, 36.807261, geography::Point(36.807261, 118.061714, 4326), N'高德地图', N'POI_MKT_0408', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'军民便利店(金晶大道店)', 3, N'金晶大道148号大红门酒店门口', 118.062694, 36.812551, geography::Point(36.812551, 118.062694, 4326), N'高德地图', N'POI_MKT_0409', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店笑笑团商贸(柳泉路店)', 3, N'柳泉路西三巷42号', 118.050028, 36.818828, geography::Point(36.818828, 118.050028, 4326), N'高德地图', N'POI_MKT_0410', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'伟航超市', 3, N'市委西一巷与人民西路交叉口北220米', 118.04481, 36.816259, geography::Point(36.816259, 118.04481, 4326), N'高德地图', N'POI_MKT_0411', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'天源超市', 3, N'潘庄东一巷11号', 118.060541, 36.820335, geography::Point(36.820335, 118.060541, 4326), N'高德地图', N'POI_MKT_0412', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'冠群超市', 3, N'人民西路16号院', 118.048732, 36.814261, geography::Point(36.814261, 118.048732, 4326), N'高德地图', N'POI_MKT_0413', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'月亮湾便利店(华光路店)', 3, N'潘庄东二巷36号', 118.062096, 36.820228, geography::Point(36.820228, 118.062096, 4326), N'高德地图', N'POI_MKT_0414', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'磐康团购超市', 3, N'华光路与柳泉路交叉口西160米', 118.051507, 36.820229, geography::Point(36.820229, 118.051507, 4326), N'高德地图', N'POI_MKT_0415', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'老路家便利店', 3, N'金晶大道西四巷与西二路交叉口东南20米', 118.056075, 36.808325, geography::Point(36.808325, 118.056075, 4326), N'高德地图', N'POI_MKT_0416', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'贝泽超市', 3, N'华光路与市府东一街交叉口西120米', 118.055968, 36.819714, geography::Point(36.819714, 118.055968, 4326), N'高德地图', N'POI_MKT_0417', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'德好便利店(八大局店)', 3, N'金晶大道118号中心商城', 118.061541, 36.806764, geography::Point(36.806764, 118.061541, 4326), N'高德地图', N'POI_MKT_0418', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'桂云便利店', 3, N'人民西路与市委西一巷交叉口东南140米', 118.045775, 36.813275, geography::Point(36.813275, 118.045775, 4326), N'高德地图', N'POI_MKT_0419', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'客来cc便利店(齐王府店)', 3, N'华光路68号恒泰商城F1层', 118.048649, 36.821415, geography::Point(36.821415, 118.048649, 4326), N'高德地图', N'POI_MKT_0420', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'军嫂便利店(王府井广场店)', 3, N'淄博市中心医院西南门西120米', 118.05146, 36.806639, geography::Point(36.806639, 118.05146, 4326), N'高德地图', N'POI_MKT_0421', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'蜂巢便利店(西二路店)', 3, N'西二路174号', 118.055251, 36.804744, geography::Point(36.804744, 118.055251, 4326), N'高德地图', N'POI_MKT_0422', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'凯福超市', 3, N'华光路33-9号', 118.062882, 36.818542, geography::Point(36.818542, 118.062882, 4326), N'高德地图', N'POI_MKT_0423', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'沃润便利店', 3, N'柳泉路71号尚城大厦36号', 118.053486, 36.824175, geography::Point(36.824175, 118.053486, 4326), N'高德地图', N'POI_MKT_0424', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'惠丰超市', 3, N'金晶大道171号西三巷东数第五间', 118.059775, 36.803972, geography::Point(36.803972, 118.059775, 4326), N'高德地图', N'POI_MKT_0425', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'拾壹便利店(华美达店)', 3, N'银座华美达大酒店北门东50米', 118.058673, 36.804943, geography::Point(36.804943, 118.058673, 4326), N'高德地图', N'POI_MKT_0426', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'优同24小时便利店(财富广场店)', 3, N'共青团东路4号甲4号', 118.061447, 36.80458, geography::Point(36.80458, 118.061447, 4326), N'高德地图', N'POI_MKT_0427', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'喜好超市(丽水景苑店)', 3, N'金晶大道209号金晟丽水景苑1号楼', 118.064347, 36.819853, geography::Point(36.819853, 118.064347, 4326), N'高德地图', N'POI_MKT_0428', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'超会买精品超市(淄博店)', 3, N'美食街与西二路交叉口西北60米', 118.053925, 36.802997, geography::Point(36.802997, 118.053925, 4326), N'高德地图', N'POI_MKT_0429', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'诚悦便利店(恒泰商城店)', 3, N'华光路68号商住楼7号1层甲3号', 118.048611, 36.821321, geography::Point(36.821321, 118.048611, 4326), N'高德地图', N'POI_MKT_0430', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'旭昇便利店(华光路店)', 3, N'金晶大道170甲4-5', 118.065298, 36.817845, geography::Point(36.817845, 118.065298, 4326), N'高德地图', N'POI_MKT_0431', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'德好便利(淄博人民公园店)', 3, N'金鼎商城北门东60米', 118.046868, 36.806873, geography::Point(36.806873, 118.046868, 4326), N'高德地图', N'POI_MKT_0432', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'金善商店', 3, N'金晶大道东一街南8甲号', 118.064094, 36.806759, geography::Point(36.806759, 118.064094, 4326), N'高德地图', N'POI_MKT_0433', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'可好(世纪新世界广场店)', 3, N'柳泉路77号新世界广场2号楼', 118.053788, 36.825493, geography::Point(36.825493, 118.053788, 4326), N'高德地图', N'POI_MKT_0434', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'燕东超市(商业步行街店)', 3, N'新世界商业步行街北段91号甲1号', 118.042414, 36.818066, geography::Point(36.818066, 118.042414, 4326), N'高德地图', N'POI_MKT_0435', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'金伴便利店(柳泉璞苑店)', 3, N'化纤南街6号甲1号', 118.048839, 36.822657, geography::Point(36.822657, 118.048839, 4326), N'高德地图', N'POI_MKT_0436', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'德好24h便利店(大润发店)', 3, N'商业街107号北亭1楼北间', 118.042014, 36.820184, geography::Point(36.820184, 118.042014, 4326), N'高德地图', N'POI_MKT_0437', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'糖果24h便利店(步行街店)', 3, N'西四路步行街73号', 118.042318, 36.811774, geography::Point(36.811774, 118.042318, 4326), N'高德地图', N'POI_MKT_0438', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'冠群超市(步行街店)', 3, N'步行街北段32号', 118.042135, 36.815909, geography::Point(36.815909, 118.042135, 4326), N'高德地图', N'POI_MKT_0439', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'尚城超市', 3, N'尚城大厦西北门旁', 118.053116, 36.824213, geography::Point(36.824213, 118.053116, 4326), N'高德地图', N'POI_MKT_0440', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'易购乐便利店商业街店', 3, N'科苑街道新世界商业街北段49号', 118.042334, 36.816561, geography::Point(36.816561, 118.042334, 4326), N'高德地图', N'POI_MKT_0441', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'德好便利店(万象汇店)', 3, N'金晶大道159号新星电器一楼', 118.059675, 36.802646, geography::Point(36.802646, 118.059675, 4326), N'高德地图', N'POI_MKT_0442', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'果梅超市(步行街店)', 3, N'新世界商业街北段62-2号', 118.042104, 36.816897, geography::Point(36.816897, 118.042104, 4326), N'高德地图', N'POI_MKT_0443', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店木雨便利店', 3, N'金晶大道171号西三巷', 118.059997, 36.803848, geography::Point(36.803848, 118.059997, 4326), N'高德地图', N'POI_MKT_0444', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'蓝钻便利店(步行街店)', 3, N'共青团西路与新世界商业街交叉口东北100米', 118.042427, 36.808398, geography::Point(36.808398, 118.042427, 4326), N'高德地图', N'POI_MKT_0445', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'友客便利(钻石商务大厦店)', 3, N'共青团西路95号钻石大厦一层西头', 118.047516, 36.806657, geography::Point(36.806657, 118.047516, 4326), N'高德地图', N'POI_MKT_0446', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'鑫源便利店', 3, N'共青团东路与共青团路交叉口东60米', 118.062624, 36.804988, geography::Point(36.804988, 118.062624, 4326), N'高德地图', N'POI_MKT_0447', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'友客便利店(共青团东路八大局店)', 3, N'体育场街道东一路65号凯旋门小区', 118.063383, 36.804329, geography::Point(36.804329, 118.063383, 4326), N'高德地图', N'POI_MKT_0448', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张未便利店', 3, N'西四路与共青团西路辅路交叉口北100米', 118.04243, 36.8088, geography::Point(36.8088, 118.04243, 4326), N'高德地图', N'POI_MKT_0449', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'甜心便利店(西二路店)', 3, N'和平街道办事处西二路93号', 118.053757, 36.80114, geography::Point(36.80114, 118.053757, 4326), N'高德地图', N'POI_MKT_0450', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'美尚便利店(风景世家店)', 3, N'华光路72号风景世家', 118.045839, 36.822336, geography::Point(36.822336, 118.045839, 4326), N'高德地图', N'POI_MKT_0451', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'欧客24小时便利店(商业步行街店)', 3, N'科苑街道步行街北段C-118', 118.042146, 36.819015, geography::Point(36.819015, 118.042146, 4326), N'高德地图', N'POI_MKT_0452', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'兔喜生活铭格便利店(柳泉路店)', 3, N'百脑汇北门往西20米', 118.048076, 36.803229, geography::Point(36.803229, 118.048076, 4326), N'高德地图', N'POI_MKT_0453', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'好客便利店(自来水公司店)', 3, N'共青团东路21号院20号楼', 118.065233, 36.804614, geography::Point(36.804614, 118.065233, 4326), N'高德地图', N'POI_MKT_0454', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'米客便利店(淄博新世界商业街店)', 3, N'新世界商业界南段125号', 118.042335, 36.807343, geography::Point(36.807343, 118.042335, 4326), N'高德地图', N'POI_MKT_0455', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'麦便利(凯旋门店)', 3, N'体育场街道办事处东一路67号凯旋门小区2栋1商铺', 118.063283, 36.802967, geography::Point(36.802967, 118.063283, 4326), N'高德地图', N'POI_MKT_0456', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'八大局便利店', 3, N'共青团西路辅路与金晶大道交叉口西220米', 118.058194, 36.805637, geography::Point(36.805637, 118.058194, 4326), N'高德地图', N'POI_MKT_0457', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'梦圆超市', 3, N'张店区步行街37号', 118.042339, 36.815882, geography::Point(36.815882, 118.042339, 4326), N'高德地图', N'POI_MKT_0458', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'好莱·名烟名酒便利店', 3, N'科苑街道办事处张桓路4号百盛沿街房B段4-18号', 118.04478, 36.823576, geography::Point(36.823576, 118.04478, 4326), N'高德地图', N'POI_MKT_0459', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'暖众家便利店', 3, N'科苑街道办事处柳泉路以西洲际中心1栋1单元1层', 118.053731, 36.82675, geography::Point(36.82675, 118.053731, 4326), N'高德地图', N'POI_MKT_0460', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'佳家超市(凯旋门小区店)', 3, N'东一路71号凯旋门小区', 118.063358, 36.803189, geography::Point(36.803189, 118.063358, 4326), N'高德地图', N'POI_MKT_0461', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'根源生鲜便利店(明清街店)', 3, N'联通路51号甲15号丽景翠苑', 118.04416, 36.824791, geography::Point(36.824791, 118.04416, 4326), N'高德地图', N'POI_MKT_0462', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'丁香超市(共青团西路店)', 3, N'共青团西路南六巷与柳泉路西一巷交叉口西北20米', 118.046082, 36.805813, geography::Point(36.805813, 118.046082, 4326), N'高德地图', N'POI_MKT_0463', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'云品便利店', 3, N'北西五路尚美第三城15号楼1号商铺', 118.038673, 36.809435, geography::Point(36.809435, 118.038673, 4326), N'高德地图', N'POI_MKT_0464', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'八大局超市(共青团东路14号院店)', 3, N'共青团东路16号甲1号', 118.066075, 36.803875, geography::Point(36.803875, 118.066075, 4326), N'高德地图', N'POI_MKT_0465', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'壹号便利店(中央国际广场店)', 3, N'金晶大道107号中央国际领寓B座F1层', 118.059179, 36.800443, geography::Point(36.800443, 118.059179, 4326), N'高德地图', N'POI_MKT_0466', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'如果便利店(金乔小区北区店)', 3, N'金乔社区北区西南2门西320米', 118.070372, 36.817936, geography::Point(36.817936, 118.070372, 4326), N'高德地图', N'POI_MKT_0467', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'洲际便利店', 3, N'柳泉路与联通路路口洲际中心', 118.055717, 36.827114, geography::Point(36.827114, 118.055717, 4326), N'高德地图', N'POI_MKT_0468', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'易捷便利店(张店1加油站)', 3, N'共青团东路20号中国石化自来水公司加油站(淄博张店1)', 118.066728, 36.803967, geography::Point(36.803967, 118.066728, 4326), N'高德地图', N'POI_MKT_0469', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'可好(万象汇061717店)', 3, N'万象汇南门东70米', 118.062851, 36.801054, geography::Point(36.801054, 118.062851, 4326), N'高德地图', N'POI_MKT_0470', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'云涛便利店(道庄小区店)', 3, N'华光路117号道庄小区西区', 118.039746, 36.819652, geography::Point(36.819652, 118.039746, 4326), N'高德地图', N'POI_MKT_0471', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店一叶超市(体彩3707003206店)', 3, N'健康街中医院东', 118.050682, 36.800426, geography::Point(36.800426, 118.050682, 4326), N'高德地图', N'POI_MKT_0472', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'然然超市', 3, N'新世界商业街中段99号', 118.042339, 36.81281, geography::Point(36.81281, 118.042339, 4326), N'高德地图', N'POI_MKT_0473', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'根源生鲜便利店(新村路店)', 3, N'新村西路24号甲4号', 118.050625, 36.800275, geography::Point(36.800275, 118.050625, 4326), N'高德地图', N'POI_MKT_0474', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'嘉福便利店(共青团西路店)', 3, N'张共青团西路与西五路路口东180米路北尚美第三城南门进入50米路东', 118.03891, 36.808484, geography::Point(36.808484, 118.03891, 4326), N'高德地图', N'POI_MKT_0475', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'秀龙超市', 3, N'共青团西路111号甲10号', 118.038951, 36.807799, geography::Point(36.807799, 118.038951, 4326), N'高德地图', N'POI_MKT_0476', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'欣宇超市', 3, N'华光路与市府东一街交叉口东北260米', 118.059775, 36.821175, geography::Point(36.821175, 118.059775, 4326), N'高德地图', N'POI_MKT_0477', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'供销便民超市新恒昌店', 3, N'迎春园东北门旁', 118.059802, 36.826735, geography::Point(36.826735, 118.059802, 4326), N'高德地图', N'POI_MKT_0478', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'德好便利店(悦达店)', 3, N'金晶大道107号中央国际领寓B座F1层', 118.059125, 36.800372, geography::Point(36.800372, 118.059125, 4326), N'高德地图', N'POI_MKT_0479', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'紫玉花便利店(张店区中心店)', 3, N'北西五路7-104号门头', 118.036879, 36.816752, geography::Point(36.816752, 118.036879, 4326), N'高德地图', N'POI_MKT_0480', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'信发便利店(火车站·万象汇·市政府店)', 3, N'东二路36-2号', 118.068773, 36.803595, geography::Point(36.803595, 118.068773, 4326), N'高德地图', N'POI_MKT_0481', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'惠东生活便利店(王府井广场店)', 3, N'王府井广场西南1门旁', 118.05223, 36.804206, geography::Point(36.804206, 118.05223, 4326), N'高德地图', N'POI_MKT_0482', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淑绵便利店', 3, N'东一路39号东一路39号院1号楼', 118.062275, 36.800775, geography::Point(36.800775, 118.062275, 4326), N'高德地图', N'POI_MKT_0483', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'2号楼三餐便利店', 3, N'体育场街道人民路河东小区二号楼三餐便利店', 118.069616, 36.810803, geography::Point(36.810803, 118.069616, 4326), N'高德地图', N'POI_MKT_0484', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'U+便利店(淄博西二路店)', 3, N'西二路113号城中东方社区', 118.054067, 36.801293, geography::Point(36.801293, 118.054067, 4326), N'高德地图', N'POI_MKT_0485', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'沐橙便利店', 3, N'商场东街4号甲3号', 118.063841, 36.800601, geography::Point(36.800601, 118.063841, 4326), N'高德地图', N'POI_MKT_0486', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'绿柳便利店', 3, N'金晶大道西三巷金晶大道联通公司家属院', 118.059911, 36.803787, geography::Point(36.803787, 118.059911, 4326), N'高德地图', N'POI_MKT_0487', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'来客朋超市(梦圆广场店)', 3, N'商场西街48-21号', 118.043427, 36.805404, geography::Point(36.805404, 118.043427, 4326), N'高德地图', N'POI_MKT_0488', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'秀水便利店', 3, N'西二路城中小区东南村内环路63甲19号秀水西门', 118.055278, 36.801386, geography::Point(36.801386, 118.055278, 4326), N'高德地图', N'POI_MKT_0489', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'奈猫便利超市(华茂观邸店)', 3, N'新村西路83号华茂观邸', 118.047506, 36.799536, geography::Point(36.799536, 118.047506, 4326), N'高德地图', N'POI_MKT_0490', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'林高便利店', 3, N'金乔南区北门口外边东20米(华光路13甲21号)', 118.073903, 36.816729, geography::Point(36.816729, 118.073903, 4326), N'高德地图', N'POI_MKT_0491', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'沃润便利店(尚品大厦店)', 3, N'尚品大厦', 118.066505, 36.826208, geography::Point(36.826208, 118.066505, 4326), N'高德地图', N'POI_MKT_0492', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'丽宝便利店', 3, N'新村西路2号甲1号', 118.05856, 36.798427, geography::Point(36.798427, 118.05856, 4326), N'高德地图', N'POI_MKT_0493', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'可好便利(王府井061770店)', 3, N'共青团西路57号王府井广场名店街96号', 118.051269, 36.804545, geography::Point(36.804545, 118.051269, 4326), N'高德地图', N'POI_MKT_0494', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'红霞便利店', 3, N'柳泉路246号世纪商务中心F1层', 118.056027, 36.829319, geography::Point(36.829319, 118.056027, 4326), N'高德地图', N'POI_MKT_0495', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'全好佳超市(王府井店)', 3, N'共青团西路辅路与新世界商业街交叉口东南80米', 118.042775, 36.807125, geography::Point(36.807125, 118.042775, 4326), N'高德地图', N'POI_MKT_0496', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'智能便利店(金宝岛大厦店)', 3, N'柳泉路37号金宝岛大厦F1层', 118.047965, 36.803804, geography::Point(36.803804, 118.047965, 4326), N'高德地图', N'POI_MKT_0497', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'新华便利店(华光路店)', 3, N'华光路19号', 118.071545, 36.816547, geography::Point(36.816547, 118.071545, 4326), N'高德地图', N'POI_MKT_0498', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'桔子便利', 3, N'道庄小区东区西1门南160米', 118.042316, 36.815489, geography::Point(36.815489, 118.042316, 4326), N'高德地图', N'POI_MKT_0499', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'爱恒优选(华光路柳泉新村北区店)', 3, N'梅苑社区居委会东侧', 118.051057, 36.822802, geography::Point(36.822802, 118.051057, 4326), N'高德地图', N'POI_MKT_0500', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'惠万家便民超市(河东小区店)', 3, N'河东小区东北门旁', 118.070265, 36.813239, geography::Point(36.813239, 118.070265, 4326), N'高德地图', N'POI_MKT_0501', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'迎春园便利店', 3, N'联通路迎春苑南门得益奶站', 118.057595, 36.825824, geography::Point(36.825824, 118.057595, 4326), N'高德地图', N'POI_MKT_0502', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'喜好超市(朝阳街店)', 3, N'朝阳街6号甲1号', 118.064819, 36.820796, geography::Point(36.820796, 118.064819, 4326), N'高德地图', N'POI_MKT_0503', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'万象便利店', 3, N'金晶大道辅路与金晶大道西三巷交叉口北40米', 118.060125, 36.804125, geography::Point(36.804125, 118.060125, 4326), N'高德地图', N'POI_MKT_0504', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'爱购便利店', 3, N'金晶大道79号甲4号', 118.058577, 36.797181, geography::Point(36.797181, 118.058577, 4326), N'高德地图', N'POI_MKT_0505', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'宜家超市', 3, N'八大局便民市场东1入口西420米', 118.064675, 36.806925, geography::Point(36.806925, 118.064675, 4326), N'高德地图', N'POI_MKT_0506', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'嘉和超市(人民东路店)', 3, N'人民东路36号甲5号', 118.074299, 36.80871, geography::Point(36.80871, 118.074299, 4326), N'高德地图', N'POI_MKT_0507', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'圣朗酒水便利店', 3, N'联通路40-2号', 118.051125, 36.828125, geography::Point(36.828125, 118.051125, 4326), N'高德地图', N'POI_MKT_0508', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'麦优便利(华茂观邸店)', 3, N'新村西路83号华茂观邸', 118.047114, 36.800313, geography::Point(36.800313, 118.047114, 4326), N'高德地图', N'POI_MKT_0509', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'小仓生活', 3, N'金旮旯蔬菜超市院内负一层', 118.051976, 36.803602, geography::Point(36.803602, 118.051976, 4326), N'高德地图', N'POI_MKT_0510', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'彩迎超市', 3, N'金晶大道新村路西北新村西路2号甲1号', 118.057425, 36.798875, geography::Point(36.798875, 118.057425, 4326), N'高德地图', N'POI_MKT_0511', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'京东便利店', 3, N'西四路与王辛西街交叉口西200米', 118.039898, 36.810875, geography::Point(36.810875, 118.039898, 4326), N'高德地图', N'POI_MKT_0512', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'汇客便利店(华光路店)', 3, N'金乔北区东门北侧', 118.074611, 36.819032, geography::Point(36.819032, 118.074611, 4326), N'高德地图', N'POI_MKT_0513', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'多乐福超市(迎春街店)', 3, N'迎春街与联通路交叉口东南140米', 118.061313, 36.825329, geography::Point(36.825329, 118.061313, 4326), N'高德地图', N'POI_MKT_0514', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'胖丁超市', 3, N'商场西街与商场西街北十五巷交叉口西40米', 118.037405, 36.805022, geography::Point(36.805022, 118.037405, 4326), N'高德地图', N'POI_MKT_0515', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'鑫欣便利店(柳泉路店)', 3, N'柳泉路77甲20鑫鑫便利店', 118.054025, 36.826125, geography::Point(36.826125, 118.054025, 4326), N'高德地图', N'POI_MKT_0516', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'德好便利店(蓝钻国际店)', 3, N'共青团西路119号蓝钻国际F1层', 118.034975, 36.807625, geography::Point(36.807625, 118.034975, 4326), N'高德地图', N'POI_MKT_0517', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'天牛便利店', 3, N'张桓路与化纤南街交叉口北80米', 118.044795, 36.823261, geography::Point(36.823261, 118.044795, 4326), N'高德地图', N'POI_MKT_0518', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'小熊便利店', 3, N'西二路113号城中东方社区', 118.054054, 36.801265, geography::Point(36.801265, 118.054054, 4326), N'高德地图', N'POI_MKT_0519', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'景航便利店', 3, N'共青团西路与西四路交叉口西80米', 118.04131, 36.807676, geography::Point(36.807676, 118.04131, 4326), N'高德地图', N'POI_MKT_0520', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东一路超市', 3, N'东一路与新村东路辅路交叉口北60米', 118.062529, 36.798173, geography::Point(36.798173, 118.062529, 4326), N'高德地图', N'POI_MKT_0521', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'国夏优选团购超市', 3, N'梦圆广场南门旁', 118.043325, 36.805275, geography::Point(36.805275, 118.043325, 4326), N'高德地图', N'POI_MKT_0522', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'优选利民超市(梦圆广场店)', 3, N'商场西街北九巷48-16', 118.04331, 36.80526, geography::Point(36.80526, 118.04331, 4326), N'高德地图', N'POI_MKT_0523', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'铂金便利店', 3, N'新村西路42号铂金大厦F1层', 118.047595, 36.800975, geography::Point(36.800975, 118.047595, 4326), N'高德地图', N'POI_MKT_0524', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'德瑞万家便利店', 3, N'张桓路33-9号', 118.043574, 36.826182, geography::Point(36.826182, 118.043574, 4326), N'高德地图', N'POI_MKT_0525', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'京东便利店(尚美店)', 3, N'北西五路尚美第三城6号院号楼号铺', 118.037621, 36.810014, geography::Point(36.810014, 118.037621, 4326), N'高德地图', N'POI_MKT_0526', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'德康便利店', 3, N'和棠悦府营销中心(洲际中心店)', 118.054073, 36.826677, geography::Point(36.826677, 118.054073, 4326), N'高德地图', N'POI_MKT_0527', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店承玉综合便利店', 3, N'联通路金花村', 118.04563, 36.828639, geography::Point(36.828639, 118.04563, 4326), N'高德地图', N'POI_MKT_0528', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'福华超市', 3, N'华光路29号张钢生活区', 118.066776, 36.815935, geography::Point(36.815935, 118.066776, 4326), N'高德地图', N'POI_MKT_0529', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'尚客便利', 3, N'共青团西路辅路与北西五路交叉口东180米', 118.038898, 36.808661, geography::Point(36.808661, 118.038898, 4326), N'高德地图', N'POI_MKT_0530', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'烟酒茶便利店', 3, N'山东理工大学东校区西门南360米', 118.037148, 36.811024, geography::Point(36.811024, 118.037148, 4326), N'高德地图', N'POI_MKT_0531', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'鲸鱼优选超市', 3, N'西一路与新村西路辅路交叉口东北180米', 118.058325, 36.800075, geography::Point(36.800075, 118.058325, 4326), N'高德地图', N'POI_MKT_0532', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'雅堂小超(盛安集团店)', 3, N'新村西路95号', 118.042975, 36.800918, geography::Point(36.800918, 118.042975, 4326), N'高德地图', N'POI_MKT_0533', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'徐惠副食批发', 3, N'健康街26号甲9号', 118.050267, 36.798479, geography::Point(36.798479, 118.050267, 4326), N'高德地图', N'POI_MKT_0534', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'纪巧便利店', 3, N'人民东路31号甲1号', 118.074177, 36.809265, geography::Point(36.809265, 118.074177, 4326), N'高德地图', N'POI_MKT_0535', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'龙马超市', 3, N'东一路18号甲2号', 118.063023, 36.798814, geography::Point(36.798814, 118.063023, 4326), N'高德地图', N'POI_MKT_0536', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'津扬超市', 3, N'联通路8号温馨家园15号丙121号', 118.061152, 36.828146, geography::Point(36.828146, 118.061152, 4326), N'高德地图', N'POI_MKT_0537', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'爱家便利店(淄博张店区)', 3, N'联通路与明清街北行50米', 118.044002, 36.828907, geography::Point(36.828907, 118.044002, 4326), N'高德地图', N'POI_MKT_0538', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'友家便利店(将军花园店)', 3, N'人民西路41号将军花园', 118.035799, 36.813879, geography::Point(36.813879, 118.035799, 4326), N'高德地图', N'POI_MKT_0539', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'快享便利(颐景园店)', 3, N'柳泉路21号甲5号', 118.046962, 36.797536, geography::Point(36.797536, 118.046962, 4326), N'高德地图', N'POI_MKT_0540', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'同红便利店', 3, N'潘南路与人民东路北六巷交叉口东220米', 118.072742, 36.81416, geography::Point(36.81416, 118.072742, 4326), N'高德地图', N'POI_MKT_0541', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'友客便利(乾盛大厦店)', 3, N'西六路乾盛大厦6A-10号', 118.03325, 36.81134, geography::Point(36.81134, 118.03325, 4326), N'高德地图', N'POI_MKT_0542', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'好世客超市', 3, N'湖田街道金晶大道32号', 118.05894, 36.796601, geography::Point(36.796601, 118.05894, 4326), N'高德地图', N'POI_MKT_0543', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'益佰便利店(南西四路店)', 3, N'南西四路与新村西路南五巷交叉口西20米', 118.041802, 36.799961, geography::Point(36.799961, 118.041802, 4326), N'高德地图', N'POI_MKT_0544', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'钦羽超市(金乔社区北区店)', 3, N'华光路金乔北区23号楼', 118.073744, 36.819135, geography::Point(36.819135, 118.073744, 4326), N'高德地图', N'POI_MKT_0545', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'欣欣向荣百货便利店(银都花园店)', 3, N'东三路11-3号银都花园', 118.071846, 36.806544, geography::Point(36.806544, 118.071846, 4326), N'高德地图', N'POI_MKT_0546', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'昆仑好客便利店(东二路店)', 3, N'中国石油淄博57站(张店东二路站)', 118.06898, 36.802091, geography::Point(36.802091, 118.06898, 4326), N'高德地图', N'POI_MKT_0547', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'金福便民超市(西四路店)', 3, N'西四路南段18号', 118.042166, 36.799033, geography::Point(36.799033, 118.042166, 4326), N'高德地图', N'POI_MKT_0548', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'鸿昌隆超市', 3, N'明清街135号', 118.043923, 36.830155, geography::Point(36.830155, 118.043923, 4326), N'高德地图', N'POI_MKT_0549', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'惠捷超市', 3, N'华光路86号大润发(淄博店)', 118.041475, 36.821725, geography::Point(36.821725, 118.041475, 4326), N'高德地图', N'POI_MKT_0550', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'富源超市(人民西路店)', 3, N'科苑街道人民西路57号甲3中国烟草', 118.029337, 36.813921, geography::Point(36.813921, 118.029337, 4326), N'高德地图', N'POI_MKT_0551', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'众惠便利店(东三路店)', 3, N'东三路12号', 118.072988, 36.804419, geography::Point(36.804419, 118.072988, 4326), N'高德地图', N'POI_MKT_0552', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'NOWS便利店', 3, N'联通路温馨家园15号丙111号', 118.06096, 36.8275, geography::Point(36.8275, 118.06096, 4326), N'高德地图', N'POI_MKT_0553', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博人民公园', 4, N'公园街道柳泉路', 118.048798, 36.810627, geography::Point(36.810627, 118.048798, 4326), N'高德地图', N'POI_PARK_0001', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店儿童公园', 4, N'共青团东路30号', 118.071556, 36.801765, geography::Point(36.801765, 118.071556, 4326), N'高德地图', N'POI_PARK_0002', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'火炬公园', 4, N'柳泉路与中润大道交汇处西北角', 118.053802, 36.837551, geography::Point(36.837551, 118.053802, 4326), N'高德地图', N'POI_PARK_0003', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博高新区文体公园', 4, N'四宝山街道政通路165号', 118.07024, 36.840741, geography::Point(36.840741, 118.07024, 4326), N'高德地图', N'POI_PARK_0004', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店市民公园', 4, N'马尚街道张店区政府旁', 118.021792, 36.804554, geography::Point(36.804554, 118.021792, 4326), N'高德地图', N'POI_PARK_0005', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'新华公园', 4, N'东二路与新村东路交叉口西南', 118.067006, 36.7957, geography::Point(36.7957, 118.067006, 4326), N'高德地图', N'POI_PARK_0006', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'小西湖公园', 4, N'北西五路与共青团西路辅路交叉口北80米', 118.036583, 36.809735, geography::Point(36.809735, 118.036583, 4326), N'高德地图', N'POI_PARK_0007', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'青龙山公园', 4, N'纬一路', 118.088849, 36.826097, geography::Point(36.826097, 118.088849, 4326), N'高德地图', N'POI_PARK_0008', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'莲池法治文化公园', 4, N'华光路123号', 118.03423, 36.823497, geography::Point(36.823497, 118.03423, 4326), N'高德地图', N'POI_PARK_0009', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'瑷肯体育公园', 4, N'政通路151号院内球馆(原大球馆)', 118.06226, 36.83922, geography::Point(36.83922, 118.06226, 4326), N'高德地图', N'POI_PARK_0010', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'猪龙河生态公园', 4, N'柳泉路与美食街交叉路口往东北约100米', 118.04949, 36.804743, geography::Point(36.804743, 118.04949, 4326), N'高德地图', N'POI_PARK_0011', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'西张游园', 4, N'东四路与新村路交叉口东北', 118.085153, 36.796736, geography::Point(36.796736, 118.085153, 4326), N'高德地图', N'POI_PARK_0012', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐盛湖公园', 4, N'中润大道', 117.989284, 36.841662, geography::Point(36.841662, 117.989284, 4326), N'高德地图', N'POI_PARK_0013', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'金乔游园', 4, N'东三路与潘南路交叉口东北240米', 118.076624, 36.814346, geography::Point(36.814346, 118.076624, 4326), N'高德地图', N'POI_PARK_0014', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'金带公园', 4, N'人民西路218号', 117.987166, 36.820675, geography::Point(36.820675, 117.987166, 4326), N'高德地图', N'POI_PARK_0015', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'人民公园牡丹花', 4, N'人民西路19号', 118.04935, 36.812103, geography::Point(36.812103, 118.04935, 4326), N'高德地图', N'POI_PARK_0016', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'良乡体育运动公园', 4, N'良乡小区内', 118.073226, 36.777487, geography::Point(36.777487, 118.073226, 4326), N'高德地图', N'POI_PARK_0017', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'孝妇河湿地公园', 4, N'和平路', 117.966585, 36.799996, geography::Point(36.799996, 117.966585, 4326), N'高德地图', N'POI_PARK_0018', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'玉龙湖湿地公园', 4, N'齐新大道与北西五路交叉口西260米', 118.036436, 36.876983, geography::Point(36.876983, 118.036436, 4326), N'高德地图', N'POI_PARK_0019', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'西五路游园', 4, N'西五路与政通路西', 118.03678, 36.84263, geography::Point(36.84263, 118.03678, 4326), N'高德地图', N'POI_PARK_0020', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'柳泉路沿河公园', 4, N'兴学街与柳泉路交叉口东20米', 118.046793, 36.794352, geography::Point(36.794352, 118.046793, 4326), N'高德地图', N'POI_PARK_0021', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'商家公园', 4, N'烟厂东路4号', 118.097382, 36.784934, geography::Point(36.784934, 118.097382, 4326), N'高德地图', N'POI_PARK_0022', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'北营公园', 4, N'金晶大道与淄博立交交叉口西约100米', 118.076584, 36.860381, geography::Point(36.860381, 118.076584, 4326), N'高德地图', N'POI_PARK_0023', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'颐景园中心公园', 4, N'柳泉路21号颐景园内', 118.045123, 36.797955, geography::Point(36.797955, 118.045123, 4326), N'高德地图', N'POI_PARK_0024', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博2025机器人公园', 4, N'四宝山街道二零二二路1001号', 118.108726, 36.810638, geography::Point(36.810638, 118.108726, 4326), N'高德地图', N'POI_PARK_0025', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'九顶山公园', 4, N'四宝山街道四宝山街道荣兰线', 118.149906, 36.825267, geography::Point(36.825267, 118.149906, 4326), N'高德地图', N'POI_PARK_0026', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'良乡公园', 4, N'良乡体育运动公园(东北角)', 118.073459, 36.777821, geography::Point(36.777821, 118.073459, 4326), N'高德地图', N'POI_PARK_0027', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐林公园', 4, N'裕民路金晶大道126号', 118.062031, 36.860615, geography::Point(36.860615, 118.062031, 4326), N'高德地图', N'POI_PARK_0028', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店儿童公园活氧森林', 4, N'共青团东路30号张店儿童公园内(东侧)', 118.073114, 36.801707, geography::Point(36.801707, 118.073114, 4326), N'高德地图', N'POI_PARK_0029', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'孝妇河骑行公园', 4, N'南京路138号', 118.003852, 36.747937, geography::Point(36.747937, 118.003852, 4326), N'高德地图', N'POI_PARK_0030', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'和平游园', 4, N'和平路以北和平路北二巷以西', 118.032201, 36.797716, geography::Point(36.797716, 118.032201, 4326), N'高德地图', N'POI_PARK_0031', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'桥下公园', 4, N'原山大道与鲁泰大道交叉处', 117.968623, 36.851769, geography::Point(36.851769, 117.968623, 4326), N'高德地图', N'POI_PARK_0032', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'猪龙河银泰城游园', 4, N'银泰城口南北两侧', 118.037736, 36.852834, geography::Point(36.852834, 118.037736, 4326), N'高德地图', N'POI_PARK_0033', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'泰苑社区科普主题公园', 4, N'北西五路兴业家园(北西六路)', 118.036588, 36.818969, geography::Point(36.818969, 118.036588, 4326), N'高德地图', N'POI_PARK_0034', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'法治文化公园', 4, N'四宝山街道柳泉路甜源生活区西', 118.07064, 36.884022, geography::Point(36.884022, 118.07064, 4326), N'高德地图', N'POI_PARK_0035', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'和平街道见义勇为主题公园', 4, N'和平社区', 118.039853, 36.798472, geography::Point(36.798472, 118.039853, 4326), N'高德地图', N'POI_PARK_0036', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'劳动公园-福欣园', 4, N'南西六路共青团西路交叉口东南角', 118.032785, 36.807663, geography::Point(36.807663, 118.032785, 4326), N'高德地图', N'POI_PARK_0037', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'凯盛南湖湿地公园', 4, N'财富大道3号', 118.007744, 36.742352, geography::Point(36.742352, 118.007744, 4326), N'高德地图', N'POI_PARK_0038', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'远景花园法治科普游园', 4, N'盛湖路与北苑东街交叉口东南120米', 118.019766, 36.842117, geography::Point(36.842117, 118.019766, 4326), N'高德地图', N'POI_PARK_0039', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'孙庄党建主题公园', 4, N'孙庄社区', 118.123778, 36.846458, geography::Point(36.846458, 118.123778, 4326), N'高德地图', N'POI_PARK_0040', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'猪龙河万杰路游园', 4, N'猪龙河万杰路口南北两侧', 118.040305, 36.842185, geography::Point(36.842185, 118.040305, 4326), N'高德地图', N'POI_PARK_0041', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'劳动公园', 4, N'北京路31号', 117.995085, 36.823149, geography::Point(36.823149, 117.995085, 4326), N'高德地图', N'POI_PARK_0042', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博市张店区和平喷泉公园', 4, N'天津路南头与和平路西端交汇处丁字路口南侧', 117.970292, 36.802271, geography::Point(36.802271, 117.970292, 4326), N'高德地图', N'POI_PARK_0043', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'新时代美德健康生活主题公园', 4, N'西五路与政通路西西五路游园内(南侧)', 118.036701, 36.840526, geography::Point(36.840526, 118.036701, 4326), N'高德地图', N'POI_PARK_0044', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'美达世纪华庭中心公园', 4, N'小商品街88号美达世纪华庭内', 118.016764, 36.824686, geography::Point(36.824686, 118.016764, 4326), N'高德地图', N'POI_PARK_0045', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐盛湖公园北门办公区', 4, N'龙泰贵府盛湖路南门对面公园停车场公园内东50米', 117.988034, 36.844019, geography::Point(36.844019, 117.988034, 4326), N'高德地图', N'POI_PARK_0046', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'高新区122交通安全主题公园', 4, N'裕民路与顺河路交叉口', 118.071863, 36.865687, geography::Point(36.865687, 118.071863, 4326), N'高德地图', N'POI_PARK_0047', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'房镇体育公园', 4, N'美田路', 117.965537, 36.86354, geography::Point(36.86354, 117.965537, 4326), N'高德地图', N'POI_PARK_0048', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'傅山公园', 4, N'中心路与蟠龙山东路交叉口东南240米', 118.143232, 36.875205, geography::Point(36.875205, 118.143232, 4326), N'高德地图', N'POI_PARK_0049', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'孙庄游园', 4, N'民祥路与玉皇山路交叉口东南角', 118.122867, 36.846228, geography::Point(36.846228, 118.122867, 4326), N'高德地图', N'POI_PARK_0050', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'体坛小区中心公园', 4, N'新村路劳动大厦西新村西路体坛小区内', 118.028164, 36.800127, geography::Point(36.800127, 118.028164, 4326), N'高德地图', N'POI_PARK_0051', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'百家姓主题纪念公园', 4, N'北京路和齐祥交叉口', 117.995852, 36.885687, geography::Point(36.885687, 117.995852, 4326), N'高德地图', N'POI_PARK_0052', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'白鹭乐园', 4, N'财富大道3号凯盛南湖湿地公园', 118.008001, 36.742924, geography::Point(36.742924, 118.008001, 4326), N'高德地图', N'POI_PARK_0053', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'涝淄河交通安全主题园', 4, N'警民路与文化路交叉口西120米', 118.072132, 36.867468, geography::Point(36.867468, 118.072132, 4326), N'高德地图', N'POI_PARK_0054', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'德治文化公园', 4, N'法治文化公园', 118.074285, 36.883545, geography::Point(36.883545, 118.074285, 4326), N'高德地图', N'POI_PARK_0055', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'青年公园', 4, N'南定镇西山路21号', 118.040537, 36.760851, geography::Point(36.760851, 118.040537, 4326), N'高德地图', N'POI_PARK_0056', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'南营公园', 4, N'鲁泰大道', 118.068447, 36.845105, geography::Point(36.845105, 118.068447, 4326), N'高德地图', N'POI_PARK_0057', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'涝淄河公园', 4, N'四宝山街道赵王路三玉花园附近', 118.071893, 36.87101, geography::Point(36.87101, 118.071893, 4326), N'高德地图', N'POI_PARK_0058', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市政府(公交站)', 7, N'102路/K102路;105路/K105路;108路/K108路;116路/K116路(北线);116路/K116路(南线);127路/K127路;135路/K135路;136路/K136路', 118.054332, 36.812938, geography::Point(36.812938, 118.054332, 4326), N'高德地图', N'POI_BUS_0001', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中国银行(公交站)', 7, N'123路/K123路;136路/K136路;151路(王府井-淄川)直达/K151路;157路/K157路;158路/K158路;181路/K181路;251路/K251路;35路/K35路;51路西线;58路/K58路;89路/K89路;90路/K90路北线;90路/K90路南线;接站专线车', 118.052072, 36.815448, geography::Point(36.815448, 118.052072, 4326), N'高德地图', N'POI_BUS_0002', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市青少年宫(公交站)', 7, N'123路/K123路;127路/K127路;157路/K157路;158路/K158路;251路/K251路;35路/K35路;51路西线;58路/K58路;89路/K89路;90路/K90路北线;90路/K90路南线;92路/K92路;接站专线车', 118.051109, 36.812191, geography::Point(36.812191, 118.051109, 4326), N'高德地图', N'POI_BUS_0003', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市府东一街(公交站)', 7, N'102路/K102路;122路/K122路;125路/K125路', 118.055937, 36.813894, geography::Point(36.813894, 118.055937, 4326), N'高德地图', N'POI_BUS_0004', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'人民公园(公交站)', 7, N'123路/K123路;127路/K127路;151路(王府井-淄川)直达/K151路;157路/K157路;158路/K158路;251路/K251路;35路/K35路;51路西线;58路/K58路;89路/K89路;90路/K90路北线;90路/K90路南线;92路/K92路;定制公交赏花灯专线一', 118.050289, 36.809018, geography::Point(36.809018, 118.050289, 4326), N'高德地图', N'POI_BUS_0005', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'新元学校(公交站)', 7, N'123路/K123路;136路/K136路;157路/K157路;158路/K158路;251路/K251路;35路/K35路;51路西线;58路/K58路;89路/K89路;90路/K90路北线;90路/K90路南线;接站专线车', 118.05299, 36.819049, geography::Point(36.819049, 118.05299, 4326), N'高德地图', N'POI_BUS_0006', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'天泰金店珠宝城(公交站)', 7, N'132路/K132路;137路/K137路;151路(王府井-淄川)直达/K151路;160路/K160路;181路/K181路;251路/K251路;35路/K35路;51路西线;87路大站快线;89路/K89路;90路/K90路北线;90路/K90路南线;92路/K92路;夜160路', 118.04934, 36.8048, geography::Point(36.8048, 118.04934, 4326), N'高德地图', N'POI_BUS_0007', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'八大局市场南门(公交站)', 7, N'(停运)公交专线;(停运)蒲松龄纪念馆公交旅游专线;136路/K136路;71路;71路(6点30分);定制公交赏花灯专线一', 118.066253, 36.804204, geography::Point(36.804204, 118.066253, 4326), N'高德地图', N'POI_BUS_0008', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'人民路金晶大道路口(公交站)', 7, N'105路/K105路;108路/K108路;116路/K116路(北线);116路/K116路(南线);127路/K127路;135路/K135路;136路/K136路', 118.061024, 36.81169, geography::Point(36.81169, 118.061024, 4326), N'高德地图', N'POI_BUS_0009', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博市级机关医院(公交站)', 7, N'122路/K122路;125路/K125路', 118.056262, 36.811678, geography::Point(36.811678, 118.056262, 4326), N'高德地图', N'POI_BUS_0010', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市工商银行(公交站)', 7, N'116路/K116路(北线);116路/K116路(南线);138路东线;138路西线;159路/K159路;162路;266路/K266路;2路/K2路;51路(东线)', 118.063146, 36.812928, geography::Point(36.812928, 118.063146, 4326), N'高德地图', N'POI_BUS_0011', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博商厦(公交站)', 7, N'108路/K108路;123路/K123路;127路/K127路;138路东线;138路西线;139路/K139路;150路/K150路;159路/K159路;162路;172路大站快线;1路直达(利群);222路/K222路;266路/K266路;2路/K2路;51路(东线);58路/K58路;76路/K76路', 118.05936, 36.799971, geography::Point(36.799971, 118.05936, 4326), N'高德地图', N'POI_BUS_0012', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'浦发银行(公交站)', 7, N'102路/K102路;105路/K105路;108路/K108路;116路/K116路(北线);116路/K116路(南线);135路/K135路;92路/K92路', 118.049528, 36.813745, geography::Point(36.813745, 118.049528, 4326), N'高德地图', N'POI_BUS_0013', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'广电大厦(公交站)', 7, N'102路/K102路;125路/K125路;138路东线;138路西线;2路/K2路;89路/K89路', 118.05526, 36.820202, geography::Point(36.820202, 118.05526, 4326), N'高德地图', N'POI_BUS_0014', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店区第三中学(公交站)', 7, N'122路/K122路;125路/K125路', 118.055927, 36.807596, geography::Point(36.807596, 118.055927, 4326), N'高德地图', N'POI_BUS_0015', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博饭店(公交站)', 7, N'108路/K108路;138路东线;138路西线;159路/K159路;162路;266路/K266路;2路/K2路;51路(东线);接站专线车', 118.060968, 36.805968, geography::Point(36.805968, 118.060968, 4326), N'高德地图', N'POI_BUS_0016', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'潘庄(公交站)', 7, N'102路/K102路;123路/K123路;125路/K125路;157路/K157路;251路/K251路;35路/K35路;51路西线;58路/K58路;定制公交赏花灯专线一;接站专线车', 118.053795, 36.822574, geography::Point(36.822574, 118.053795, 4326), N'高德地图', N'POI_BUS_0017', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'北京同仁堂淄博药店(公交站)', 7, N'108路/K108路;138路东线;138路西线;159路/K159路;162路;266路/K266路;2路/K2路;51路(东线)', 118.061864, 36.809021, geography::Point(36.809021, 118.061864, 4326), N'高德地图', N'POI_BUS_0018', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'利群(公交站)', 7, N'(停运)公交专线;138路东线;138路西线;150路/K150路;222路/K222路', 118.060653, 36.801164, geography::Point(36.801164, 118.060653, 4326), N'高德地图', N'POI_BUS_0019', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博剧院(公交站)', 7, N'123路/K123路;127路/K127路;139路/K139路;158路/K158路;58路/K58路;7路/K7路;88路/K88路内环;88路/K88路外环;接站专线车', 118.058919, 36.805375, geography::Point(36.805375, 118.058919, 4326), N'高德地图', N'POI_BUS_0020', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中房(公交站)', 7, N'136路/K136路;138路东线;138路西线;158路/K158路;2路/K2路;90路/K90路北线;90路/K90路南线', 118.0504, 36.820686, geography::Point(36.820686, 118.0504, 4326), N'高德地图', N'POI_BUS_0021', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市中心医院(公交站)', 7, N'(停运)公交专线;123路/K123路;127路/K127路;132路/K132路;139路/K139路;158路/K158路;58路/K58路;7路/K7路;88路/K88路内环;88路/K88路外环;接站专线车', 118.053629, 36.806047, geography::Point(36.806047, 118.053629, 4326), N'高德地图', N'POI_BUS_0022', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博文化艺术城(公交站)', 7, N'116路/K116路(北线);116路/K116路(南线);138路东线;138路西线;159路/K159路;162路;266路/K266路;2路/K2路;51路(东线);71路;71路(6点30分);88路/K88路内环;88路/K88路外环;89路/K89路', 118.064635, 36.817114, geography::Point(36.817114, 118.064635, 4326), N'高德地图', N'POI_BUS_0023', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'第七医院(公交站)', 7, N'102路/K102路;123路/K123路;125路/K125路;157路/K157路;35路/K35路;51路西线;58路/K58路;定制公交赏花灯专线一;接站专线车', 118.054646, 36.82602, geography::Point(36.82602, 118.054646, 4326), N'高德地图', N'POI_BUS_0024', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市政府三宿舍(公交站)', 7, N'108路/K108路;137路/K137路;169路/K169路;223路/K223路;90路/K90路北线;90路/K90路南线', 118.036987, 36.825352, geography::Point(36.825352, 118.036987, 4326), N'高德地图', N'POI_BUS_0025', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市职教研究院(公交站)', 7, N'102路/K102路;125路/K125路', 118.05699, 36.817908, geography::Point(36.817908, 118.05699, 4326), N'高德地图', N'POI_BUS_0026', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市第十八中学(公交站)', 7, N'122路/K122路', 118.057528, 36.816185, geography::Point(36.816185, 118.057528, 4326), N'高德地图', N'POI_BUS_0027', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'西二路农贸市场(公交站)', 7, N'122路/K122路;125路/K125路;132路/K132路', 118.054905, 36.80421, geography::Point(36.80421, 118.054905, 4326), N'高德地图', N'POI_BUS_0028', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博商厦(齐商银行)(公交站)', 7, N'150路/K150路', 118.059501, 36.800363, geography::Point(36.800363, 118.059501, 4326), N'高德地图', N'POI_BUS_0029', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市委(公交站)', 7, N'102路/K102路;105路/K105路;108路/K108路;116路/K116路(北线);116路/K116路(南线);135路/K135路;92路/K92路', 118.045743, 36.814124, geography::Point(36.814124, 118.045743, 4326), N'高德地图', N'POI_BUS_0030', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'钻石商务大厦(公交站)', 7, N'(停运)公交专线;137路/K137路;139路/K139路;157路/K157路;160路/K160路;7路/K7路;88路/K88路内环;88路/K88路外环;夜160路', 118.046496, 36.807251, geography::Point(36.807251, 118.046496, 4326), N'高德地图', N'POI_BUS_0031', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'新村路金晶大道路口(公交站)', 7, N'122路/K122路;125路/K125路;126路/K126路;12路/K12路;89路/K89路;92路/K92路;96路/K96路', 118.056954, 36.798474, geography::Point(36.798474, 118.056954, 4326), N'高德地图', N'POI_BUS_0032', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'大润发超市(公交站)', 7, N'121路/K121路;126路/K126路;136路/K136路;138路东线;138路西线;151路(王府井-淄川)直达/K151路;158路/K158路;181路/K181路;185路;2路/K2路;88路/K88路内环;88路/K88路外环;90路/K90路北线;90路/K90路南线;玉黛赏花灯定制公交', 118.041422, 36.821142, geography::Point(36.821142, 118.041422, 4326), N'高德地图', N'POI_BUS_0033', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'理工大学东校区(南门)(公交站)', 7, N'88路/K88路内环;夜160路', 118.041022, 36.807925, geography::Point(36.807925, 118.041022, 4326), N'高德地图', N'POI_BUS_0034', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'人民东路小学(公交站)', 7, N'105路/K105路;127路/K127路;135路/K135路;136路/K136路', 118.064995, 36.810867, geography::Point(36.810867, 118.064995, 4326), N'高德地图', N'POI_BUS_0035', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东二路(公交站)', 7, N'122路/K122路;123路/K123路;150路/K150路;206路;20路;37路/K37路;5路;6路/K6路;82路', 118.070259, 36.796677, geography::Point(36.796677, 118.070259, 4326), N'高德地图', N'POI_BUS_0036', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'华瑞园(公交站)', 7, N'102路/K102路;125路/K125路;126路/K126路;159路/K159路;251路/K251路;35路/K35路;51路西线;58路/K58路;定制公交赏花灯专线一;接站专线车', 118.056026, 36.830856, geography::Point(36.830856, 118.056026, 4326), N'高德地图', N'POI_BUS_0037', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'华夏商厦(公交站)', 7, N'138路东线;138路西线;222路/K222路', 118.051168, 36.80331, geography::Point(36.80331, 118.051168, 4326), N'高德地图', N'POI_BUS_0038', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市保安公司(公交站)', 7, N'136路/K136路;150路/K150路;222路/K222路;71路;71路(6点30分);7路/K7路;8路/K8路', 118.063001, 36.799795, geography::Point(36.799795, 118.063001, 4326), N'高德地图', N'POI_BUS_0039', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'开元文化大世界(公交站)', 7, N'122路/K122路;125路/K125路;132路/K132路;138路东线;138路西线;222路/K222路', 118.053972, 36.802551, geography::Point(36.802551, 118.053972, 4326), N'高德地图', N'POI_BUS_0040', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东一路新村路口(公交站)', 7, N'136路/K136路;206路;222路/K222路;5路;6路/K6路;71路;71路(6点30分);7路/K7路;82路;8路/K8路', 118.062464, 36.796641, geography::Point(36.796641, 118.062464, 4326), N'高德地图', N'POI_BUS_0041', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店区中医院(公交站)', 7, N'126路/K126路;12路/K12路;132路/K132路;89路/K89路;92路/K92路;96路/K96路', 118.051779, 36.799863, geography::Point(36.799863, 118.051779, 4326), N'高德地图', N'POI_BUS_0042', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'第七医院北门(公交站)', 7, N'123路/K123路;126路/K126路;79路/K79路', 118.052491, 36.827855, geography::Point(36.827855, 118.052491, 4326), N'高德地图', N'POI_BUS_0043', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'新村路柳泉路口(公交站)', 7, N'126路/K126路;12路/K12路;132路/K132路;35路/K35路;90路/K90路北线;90路/K90路南线;96路/K96路', 118.045433, 36.800866, geography::Point(36.800866, 118.045433, 4326), N'高德地图', N'POI_BUS_0044', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市自然资源局(公交站)', 7, N'102路/K102路;105路/K105路;108路/K108路;116路/K116路(北线);116路/K116路(南线);135路/K135路;92路/K92路', 118.041191, 36.814252, geography::Point(36.814252, 118.041191, 4326), N'高德地图', N'POI_BUS_0045', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东方星城(公交站)', 7, N'116路/K116路(北线);116路/K116路(南线);122路/K122路;159路/K159路;162路;51路(东线);71路;71路(6点30分);88路/K88路内环;88路/K88路外环', 118.066405, 36.822387, geography::Point(36.822387, 118.066405, 4326), N'高德地图', N'POI_BUS_0046', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东营银行淄博分行(公交站)', 7, N'138路东线;138路西线;2路/K2路;89路/K89路', 118.060794, 36.81922, geography::Point(36.81922, 118.060794, 4326), N'高德地图', N'POI_BUS_0047', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'迎春园(公交站)', 7, N'157路/K157路;159路/K159路;79路/K79路;88路/K88路内环;88路/K88路外环', 118.057882, 36.827157, geography::Point(36.827157, 118.057882, 4326), N'高德地图', N'POI_BUS_0048', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市政务服务中心(公交站)', 7, N'126路/K126路;12路/K12路;138路东线;138路西线;222路/K222路;96路/K96路', 118.039482, 36.801659, geography::Point(36.801659, 118.039482, 4326), N'高德地图', N'POI_BUS_0049', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'潘南路金晶大道路口(公交站)', 7, N'122路/K122路', 118.062485, 36.81519, geography::Point(36.81519, 118.062485, 4326), N'高德地图', N'POI_BUS_0050', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'杏园路金晶大道路口(公交站)', 7, N'108路/K108路;125路/K125路;126路/K126路;127路/K127路;12路/K12路;136路/K136路;139路/K139路;158路/K158路;159路/K159路;160路/K160路;162路;1路直达(利群);206路;20路;266路/K266路;2路/K2路;37路/K37路;51路(东线);58路/K58路;5路;71路;71路(6点30分);76路/K76路;82路;87路大站快线;89路/K89路;95路/K95路;96路/K96路;夜160路', 118.056288, 36.79049, geography::Point(36.79049, 118.056288, 4326), N'高德地图', N'POI_BUS_0051', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东一路·八大局市场南门(公交站)', 7, N'7路/K7路', 118.06366, 36.803676, geography::Point(36.803676, 118.06366, 4326), N'高德地图', N'POI_BUS_0052', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'西五路华光路口(公交站)', 7, N'108路/K108路;135路/K135路;137路/K137路;223路/K223路;92路/K92路', 118.036942, 36.818325, geography::Point(36.818325, 118.036942, 4326), N'高德地图', N'POI_BUS_0053', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'交警支队(公交站)', 7, N'121路/K121路;137路/K137路;151路(王府井-淄川)直达/K151路;160路/K160路;181路/K181路;251路/K251路;51路西线;95路/K95路;夜160路', 118.04681, 36.795139, geography::Point(36.795139, 118.04681, 4326), N'高德地图', N'POI_BUS_0054', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店王府井(公交站)', 7, N'接站专线车', 118.052818, 36.806171, geography::Point(36.806171, 118.052818, 4326), N'高德地图', N'POI_BUS_0055', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'潘成装饰材料城(公交站)', 7, N'157路/K157路;159路/K159路;79路/K79路;88路/K88路内环;88路/K88路外环', 118.064164, 36.825854, geography::Point(36.825854, 118.064164, 4326), N'高德地图', N'POI_BUS_0056', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'红卫电机厂生活区(公交站)', 7, N'137路/K137路;160路/K160路;251路/K251路;51路西线;夜160路', 118.047739, 36.798724, geography::Point(36.798724, 118.047739, 4326), N'高德地图', N'POI_BUS_0057', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'金丰大厦(公交站)', 7, N'126路/K126路;12路/K12路;7路/K7路;96路/K96路', 118.033961, 36.802298, geography::Point(36.802298, 118.033961, 4326), N'高德地图', N'POI_BUS_0058', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东二路人民路口(公交站)', 7, N'136路/K136路;71路;71路(6点30分)', 118.068352, 36.809074, geography::Point(36.809074, 118.068352, 4326), N'高德地图', N'POI_BUS_0059', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄建第五生活区(公交站)', 7, N'136路/K136路;71路;71路(6点30分);8路/K8路', 118.068451, 36.807171, geography::Point(36.807171, 118.068451, 4326), N'高德地图', N'POI_BUS_0060', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市政务服务中心(市博物馆)西门(公交站)', 7, N'223路/K223路;7路/K7路', 118.036945, 36.80352, geography::Point(36.80352, 118.036945, 4326), N'高德地图', N'POI_BUS_0061', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'盘古映画(公交站)', 7, N'136路/K136路;138路东线;138路西线;71路;71路(6点30分);76路/K76路;8路/K8路', 118.065291, 36.804291, geography::Point(36.804291, 118.065291, 4326), N'高德地图', N'POI_BUS_0062', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'莲池公园(公交站)', 7, N'121路/K121路;126路/K126路;135路/K135路;136路/K136路;138路东线;138路西线;158路/K158路;169路/K169路;185路;2路/K2路;88路/K88路内环;88路/K88路外环;92路/K92路', 118.034616, 36.821483, geography::Point(36.821483, 118.034616, 4326), N'高德地图', N'POI_BUS_0063', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博火车站(南广场)(公交站)', 7, N'103路/K103路;108路/K108路;119路;125路/K125路;126路/K126路;12路/K12路;139路/K139路;159路/K159路;162路;171路;1路北线;206路;20路;251路/K251路;266路/K266路;2路/K2路;36路;36路(半点发车);37路/K37路;3路;45路/K45路;46路/K46路;4路;51路西线;53路/K53路;5路;76路/K76路;80路/K80路;82路;87路大站快线;96路/K96路;沂源长途汽车站-公交东站定制公交通勤专线', 118.056019, 36.786483, geography::Point(36.786483, 118.056019, 4326), N'高德地图', N'POI_BUS_0064', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'煤气大厦(公交站)', 7, N'71路;71路(6点30分);8路/K8路', 118.068207, 36.811642, geography::Point(36.811642, 118.068207, 4326), N'高德地图', N'POI_BUS_0065', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'华光路张桓路口(公交站)', 7, N'136路/K136路;138路西线;158路/K158路;2路/K2路;90路/K90路北线;90路/K90路南线', 118.046665, 36.820884, geography::Point(36.820884, 118.046665, 4326), N'高德地图', N'POI_BUS_0066', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张南路王舍路口(公交站)', 7, N'103路/K103路;108路/K108路;119路;125路/K125路;126路/K126路;127路/K127路;12路/K12路;139路/K139路;159路/K159路;162路;172路大站快线;1路北线;1路直达(利群);206路;20路;251路/K251路;266路/K266路;2路/K2路;36路;36路(半点发车);37路/K37路;3路;45路/K45路;46路/K46路;4路;51路(东线);51路西线;53路/K53路;58路/K58路;5路;71路;71路(6点30分);76路/K76路;80路/K80路;82路;89路/K89路;95路/K95路;96路/K96路', 118.050506, 36.788183, geography::Point(36.788183, 118.050506, 4326), N'高德地图', N'POI_BUS_0067', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'宠物市场(公交站)', 7, N'206路;266路/K266路;89路/K89路', 118.07019, 36.817604, geography::Point(36.817604, 118.07019, 4326), N'高德地图', N'POI_BUS_0068', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'鲁中家具城(公交站)', 7, N'138路东线;138路西线;222路/K222路', 118.043338, 36.804668, geography::Point(36.804668, 118.043338, 4326), N'高德地图', N'POI_BUS_0069', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博火车站北广场(公交站)', 7, N'150路/K150路;7路/K7路;92路/K92路', 118.05913, 36.78893, geography::Point(36.78893, 118.05913, 4326), N'高德地图', N'POI_BUS_0070', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'共青团路西五路口(公交站)', 7, N'(停运)公交专线;137路/K137路;139路/K139路;157路/K157路;160路/K160路;7路/K7路;88路/K88路内环;88路/K88路外环;夜160路', 118.037974, 36.807921, geography::Point(36.807921, 118.037974, 4326), N'高德地图', N'POI_BUS_0071', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'理工大学东校区南门(公交站)', 7, N'(停运)公交专线;137路/K137路;139路/K139路;157路/K157路;160路/K160路;7路/K7路;88路/K88路外环', 118.042953, 36.807728, geography::Point(36.807728, 118.042953, 4326), N'高德地图', N'POI_BUS_0072', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'第七医院(北门)(公交站)', 7, N'123路/K123路;126路/K126路;88路/K88路内环;88路/K88路外环', 118.052491, 36.827855, geography::Point(36.827855, 118.052491, 4326), N'高德地图', N'POI_BUS_0073', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'小商品街(公交站)', 7, N'138路东线;138路西线;222路/K222路', 118.04744, 36.803971, geography::Point(36.803971, 118.04744, 4326), N'高德地图', N'POI_BUS_0074', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'新村(公交站)', 7, N'150路/K150路;206路;5路;6路/K6路;82路', 118.06612, 36.797143, geography::Point(36.797143, 118.06612, 4326), N'高德地图', N'POI_BUS_0075', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'城西新村(公交站)', 7, N'223路/K223路;7路/K7路', 118.036998, 36.806515, geography::Point(36.806515, 118.036998, 4326), N'高德地图', N'POI_BUS_0076', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市中医医院骨科医院(公交站)', 7, N'251路/K251路', 118.054646, 36.82602, geography::Point(36.82602, 118.054646, 4326), N'高德地图', N'POI_BUS_0077', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'齐赛科技(公交站)', 7, N'121路/K121路;126路/K126路', 118.032953, 36.811811, geography::Point(36.811811, 118.032953, 4326), N'高德地图', N'POI_BUS_0078', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市中西医结合医院(公交站)', 7, N'108路/K108路;123路/K123路;126路/K126路;150路/K150路;159路/K159路;162路;2路/K2路;51路(东线);58路/K58路;6路/K6路;76路/K76路;89路/K89路;92路/K92路', 118.05847, 36.795307, geography::Point(36.795307, 118.05847, 4326), N'高德地图', N'POI_BUS_0079', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'百盛集团(公交站)', 7, N'121路/K121路;126路/K126路;185路;88路/K88路内环;88路/K88路外环', 118.044635, 36.823238, geography::Point(36.823238, 118.044635, 4326), N'高德地图', N'POI_BUS_0080', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店二中(公交站)', 7, N'105路/K105路;127路/K127路', 118.071765, 36.809546, geography::Point(36.809546, 118.071765, 4326), N'高德地图', N'POI_BUS_0081', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'远景大厦(公交站)', 7, N'123路/K123路;126路/K126路;79路/K79路;88路/K88路内环;88路/K88路外环', 118.045742, 36.828188, geography::Point(36.828188, 118.045742, 4326), N'高德地图', N'POI_BUS_0082', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'大润发超市(下客站)(公交站)', 7, N'181路/K181路', 118.041422, 36.821142, geography::Point(36.821142, 118.041422, 4326), N'高德地图', N'POI_BUS_0083', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'义乌小商品城(公交站)', 7, N'(停运)191路;(停运)文昌湖景区旅游专线;136路/K136路;138路东线;138路西线;139路/K139路;151路(王府井-淄川)直达/K151路;158路/K158路;159路/K159路;168路/K168路;169路/K169路;177路;181路/K181路;185路;200路;257路/K257路;34路/K34路;42路;87路大站快线;88路/K88路内环;88路/K88路外环;90路/K90路北线;90路/K90路南线;92路/K92路;95路/K95路;97路/K97路;9路/K9路;三水源景区旅游专线;双溪山、潭溪山景区旅游专线;周村-义乌小商品城;定制公交赏花灯专线三;岜山中医药健康旅游示范基地、白石洞、原山景区旅游专线;开元溶洞旅游专线;开元溶洞景区旅游专线;玉黛赏花灯定制公交;王渔洋、在河之洲、高青天鹅湖景区旅游专线;红叶柿岩、如月湖景区旅游专线;齐文化博物馆、中国古车博物馆旅游专线', 118.020534, 36.822689, geography::Point(36.822689, 118.020534, 4326), N'高德地图', N'POI_BUS_0084', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博火车站(公交站)', 7, N'126路/K126路', 118.054895, 36.784912, geography::Point(36.784912, 118.054895, 4326), N'高德地图', N'POI_BUS_0085', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'金乔生活区(南门)(公交站)', 7, N'88路/K88路内环;88路/K88路外环;8路/K8路', 118.072318, 36.81309, geography::Point(36.81309, 118.072318, 4326), N'高德地图', N'POI_BUS_0086', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店一中(公交站)', 7, N'121路/K121路;95路/K95路', 118.043263, 36.796439, geography::Point(36.796439, 118.043263, 4326), N'高德地图', N'POI_BUS_0087', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'火炬公园(公交站)', 7, N'102路/K102路;126路/K126路;156路/K156路;159路/K159路;162路;185路;200路;71路;71路(6点30分);接站专线车', 118.055614, 36.836523, geography::Point(36.836523, 118.055614, 4326), N'高德地图', N'POI_BUS_0088', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'潘南路东二路口(公交站)', 7, N'88路/K88路内环;88路/K88路外环;8路/K8路', 118.069346, 36.813731, geography::Point(36.813731, 118.069346, 4326), N'高德地图', N'POI_BUS_0089', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'富尔玛家居广场(公交站)', 7, N'102路/K102路;105路/K105路;116路/K116路(北线);116路/K116路(南线);139路/K139路;160路/K160路;229路/K229路;257路/K257路;2路/K2路;90路/K90路北线;90路/K90路南线;夜160路', 118.027741, 36.814198, geography::Point(36.814198, 118.027741, 4326), N'高德地图', N'POI_BUS_0090', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'新华医疗小区(公交站)', 7, N'121路/K121路;126路/K126路;185路;88路/K88路内环;88路/K88路外环', 118.04427, 36.826457, geography::Point(36.826457, 118.04427, 4326), N'高德地图', N'POI_BUS_0091', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博牵引电机医院(公交站)', 7, N'135路/K135路', 118.078424, 36.802669, geography::Point(36.802669, 118.078424, 4326), N'高德地图', N'POI_BUS_0092', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博(国贸大厦鲁中城市候机楼)(公交站)', 7, N'接站专线车;机场大巴淄博线', 118.057092, 36.835456, geography::Point(36.835456, 118.057092, 4326), N'高德地图', N'POI_BUS_0093', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博五中(公交站)', 7, N'122路/K122路;123路/K123路;136路/K136路;206路;20路;222路/K222路;37路/K37路;5路;71路;71路(6点30分);7路/K7路;82路;8路/K8路', 118.062813, 36.792097, geography::Point(36.792097, 118.062813, 4326), N'高德地图', N'POI_BUS_0094', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市中心医院(王府井)(公交站)', 7, N'(停运)公交专线', 118.052948, 36.806225, geography::Point(36.806225, 118.052948, 4326), N'高德地图', N'POI_BUS_0095', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'莲池小区(公交站)', 7, N'123路/K123路;137路/K137路;168路/K168路;169路/K169路;79路/K79路;90路/K90路北线;90路/K90路南线;定制公交赏花灯专线四;市中医医院健康专线', 118.035413, 36.828757, geography::Point(36.828757, 118.035413, 4326), N'高德地图', N'POI_BUS_0096', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市府三宿舍(西门)(公交站)', 7, N'168路/K168路', 118.032323, 36.825241, geography::Point(36.825241, 118.032323, 4326), N'高德地图', N'POI_BUS_0097', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'共青团路西六路口(公交站)', 7, N'157路/K157路;160路/K160路;88路/K88路内环;88路/K88路外环;夜160路', 118.029992, 36.808287, geography::Point(36.808287, 118.029992, 4326), N'高德地图', N'POI_BUS_0098', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'共青团路(公交站)', 7, N'接站专线车', 118.050461, 36.806545, geography::Point(36.806545, 118.050461, 4326), N'高德地图', N'POI_BUS_0099', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'五里桥生活区(公交站)', 7, N'102路/K102路;105路/K105路;116路/K116路(北线);116路/K116路(南线);2路/K2路;定制公交赏花灯专线四', 118.030418, 36.814198, geography::Point(36.814198, 118.030418, 4326), N'高德地图', N'POI_BUS_0100', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'杜科新村(公交站)', 7, N'定制公交赏花灯专线一', 118.071648, 36.803452, geography::Point(36.803452, 118.071648, 4326), N'高德地图', N'POI_BUS_0101', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'天星小区(公交站)', 7, N'138路东线;138路西线;223路/K223路', 118.036629, 36.79908, geography::Point(36.79908, 118.036629, 4326), N'高德地图', N'POI_BUS_0102', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'庄园集团(公交站)', 7, N'121路/K121路;185路', 118.044132, 36.830065, geography::Point(36.830065, 118.044132, 4326), N'高德地图', N'POI_BUS_0103', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店宾馆(公交站)', 7, N'121路/K121路;160路/K160路;251路/K251路;51路西线;95路/K95路;夜160路', 118.055046, 36.793731, geography::Point(36.793731, 118.055046, 4326), N'高德地图', N'POI_BUS_0104', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博火车站南广场(公交站)', 7, N'(停运)淄博烧烤专线10路;110路;1路直达;周村-淄博火车站(南广场);淄博烧烤专线5路', 118.056511, 36.786201, geography::Point(36.786201, 118.056511, 4326), N'高德地图', N'POI_BUS_0105', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'魏家庄(公交站)', 7, N'116路/K116路(北线);116路/K116路(南线);122路/K122路;157路/K157路;162路;206路;51路(东线);71路;71路(6点30分)', 118.069466, 36.832218, geography::Point(36.832218, 118.069466, 4326), N'高德地图', N'POI_BUS_0106', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'八大局市场南门(临时站)(公交站)', 7, N'136路/K136路', 118.066253, 36.804204, geography::Point(36.804204, 118.066253, 4326), N'高德地图', N'POI_BUS_0107', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'八一路八大局南门(临时站)(公交站)', 7, N'136路/K136路', 118.063658, 36.803667, geography::Point(36.803667, 118.063658, 4326), N'高德地图', N'POI_BUS_0108', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市政务服务中心(市博物馆)(公交站)', 7, N'138路东线;138路西线', 118.039177, 36.801781, geography::Point(36.801781, 118.039177, 4326), N'高德地图', N'POI_BUS_0109', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'硅苑科技(公交站)', 7, N'125路/K125路;185路;251路/K251路;35路/K35路;51路西线;58路/K58路', 118.058479, 36.840339, geography::Point(36.840339, 118.058479, 4326), N'高德地图', N'POI_BUS_0110', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博口腔医院(公交站)', 7, N'102路/K102路;12路/K12路;157路/K157路;229路/K229路;257路/K257路;7路/K7路;90路/K90路北线;90路/K90路南线;96路/K96路', 118.027008, 36.802939, geography::Point(36.802939, 118.027008, 4326), N'高德地图', N'POI_BUS_0111', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市政务服务中心(市博物馆)北门(公交站)', 7, N'222路/K222路', 118.039356, 36.80488, geography::Point(36.80488, 118.039356, 4326), N'高德地图', N'POI_BUS_0112', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市第二康复医院(公交站)', 7, N'206路;266路/K266路', 118.07298, 36.817185, geography::Point(36.817185, 118.07298, 4326), N'高德地图', N'POI_BUS_0113', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市中西医院(公交站)', 7, N'108路/K108路;122路/K122路;125路/K125路;126路/K126路;127路/K127路;12路/K12路;139路/K139路;159路/K159路;266路/K266路;51路(东线);76路/K76路', 118.05847, 36.795307, geography::Point(36.795307, 118.05847, 4326), N'高德地图', N'POI_BUS_0114', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'潘南路东四路口(公交站)', 7, N'127路/K127路;8路/K8路', 118.079806, 36.811746, geography::Point(36.811746, 118.079806, 4326), N'高德地图', N'POI_BUS_0115', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'盘古映画(八大局市场南门)(公交站)', 7, N'8路/K8路', 118.065352, 36.804283, geography::Point(36.804283, 118.065352, 4326), N'高德地图', N'POI_BUS_0116', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博市技师学院北门(公交站)', 7, N'136路/K136路;138路东线;138路西线;158路/K158路;168路/K168路;169路/K169路;185路;88路/K88路内环;88路/K88路外环', 118.029953, 36.821701, geography::Point(36.821701, 118.029953, 4326), N'高德地图', N'POI_BUS_0117', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中关村科技城(公交站)', 7, N'121路/K121路;126路/K126路', 118.032611, 36.809143, geography::Point(36.809143, 118.032611, 4326), N'高德地图', N'POI_BUS_0118', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'盘古映画(东一路·八大局市场南门)(公交站)', 7, N'8路/K8路', 118.063658, 36.803667, geography::Point(36.803667, 118.063658, 4326), N'高德地图', N'POI_BUS_0119', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市妇幼保健院杏园院区(公交站)', 7, N'121路/K121路;136路/K136路;206路;20路;222路/K222路;37路/K37路;5路;71路;71路(6点30分);7路/K7路;82路;8路/K8路', 118.061474, 36.790623, geography::Point(36.790623, 118.061474, 4326), N'高德地图', N'POI_BUS_0120', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中源集团(公交站)', 7, N'132路/K132路;35路/K35路;90路/K90路北线;90路/K90路南线', 118.041721, 36.798369, geography::Point(36.798369, 118.041721, 4326), N'高德地图', N'POI_BUS_0121', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博文化艺术城-市鲁中公证处(公交站)', 7, N'122路/K122路', 118.06459, 36.817364, geography::Point(36.817364, 118.06459, 4326), N'高德地图', N'POI_BUS_0122', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'鲁中城市候机楼(公交站)', 7, N'机场巴士临淄线', 118.057092, 36.835456, geography::Point(36.835456, 118.057092, 4326), N'高德地图', N'POI_BUS_0123', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'潘成粮油批发市场(公交站)', 7, N'116路/K116路(北线);116路/K116路(南线);122路/K122路;157路/K157路;162路;206路;51路(东线);71路;71路(6点30分)', 118.068555, 36.829167, geography::Point(36.829167, 118.068555, 4326), N'高德地图', N'POI_BUS_0124', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博义乌小商品城(公交站)', 7, N'淄博市区直达双马山景区免费公交旅游专线', 118.020647, 36.822227, geography::Point(36.822227, 118.020647, 4326), N'高德地图', N'POI_BUS_0125', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市第十七中学(公交站)', 7, N'137路/K137路;223路/K223路', 118.037001, 36.810364, geography::Point(36.810364, 118.037001, 4326), N'高德地图', N'POI_BUS_0126', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东四路联通路口(公交站)', 7, N'105路/K105路;266路/K266路;76路/K76路;8路/K8路', 118.079155, 36.821503, geography::Point(36.821503, 118.079155, 4326), N'高德地图', N'POI_BUS_0127', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'莲池小学(公交站)', 7, N'123路/K123路;137路/K137路;169路/K169路;79路/K79路', 118.031011, 36.829047, geography::Point(36.829047, 118.031011, 4326), N'高德地图', N'POI_BUS_0128', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'华光路张恒路路口(公交站)', 7, N'138路东线', 118.046665, 36.820884, geography::Point(36.820884, 118.046665, 4326), N'高德地图', N'POI_BUS_0129', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'共青团路世纪路(西七路)口(公交站)', 7, N'夜160路', 118.026314, 36.808578, geography::Point(36.808578, 118.026314, 4326), N'高德地图', N'POI_BUS_0130', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'创业·东城华府(公交站)', 7, N'105路/K105路;88路/K88路内环;88路/K88路外环', 118.075582, 36.808765, geography::Point(36.808765, 118.075582, 4326), N'高德地图', N'POI_BUS_0131', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市第二康复医院·区医院北院区(公交站)', 7, N'89路/K89路', 118.072884, 36.817268, geography::Point(36.817268, 118.072884, 4326), N'高德地图', N'POI_BUS_0132', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博火车站(王舍路)(公交站)', 7, N'(停运)公交专线', 118.0532, 36.785794, geography::Point(36.785794, 118.0532, 4326), N'高德地图', N'POI_BUS_0133', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店交警大队(公交站)', 7, N'121路/K121路;132路/K132路;138路东线;138路西线;95路/K95路', 118.032154, 36.797336, geography::Point(36.797336, 118.032154, 4326), N'高德地图', N'POI_BUS_0134', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'恩诚口腔诊所(公交站)', 7, N'139路/K139路;157路/K157路;160路/K160路;88路/K88路内环;88路/K88路外环', 118.0335, 36.808001, geography::Point(36.808001, 118.0335, 4326), N'高德地图', N'POI_BUS_0135', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'王舍汽配城·茶城(公交站)', 7, N'119路;151路(王府井-淄川)直达/K151路;171路;172路大站快线;1路直达(利群);80路/K80路;沂源长途汽车站-公交东站定制公交通勤专线', 118.042554, 36.779095, geography::Point(36.779095, 118.042554, 4326), N'高德地图', N'POI_BUS_0136', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'共青团路世纪路口(公交站)', 7, N'157路/K157路;160路/K160路;88路/K88路内环;88路/K88路外环', 118.027068, 36.808562, geography::Point(36.808562, 118.027068, 4326), N'高德地图', N'POI_BUS_0137', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市技师学院北门(公交站)', 7, N'135路/K135路;185路;92路/K92路', 118.029404, 36.82164, geography::Point(36.82164, 118.029404, 4326), N'高德地图', N'POI_BUS_0138', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博广大农贸便民市场(公交站)', 7, N'88路/K88路内环;88路/K88路外环', 118.066201, 36.814388, geography::Point(36.814388, 118.066201, 4326), N'高德地图', N'POI_BUS_0139', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'联通路金晶大道路口(公交站)', 7, N'206路;79路/K79路', 118.070278, 36.824575, geography::Point(36.824575, 118.070278, 4326), N'高德地图', N'POI_BUS_0140', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博市中医医院柳泉路院区(公交站)', 7, N'市中医医院健康专线', 118.053398, 36.826671, geography::Point(36.826671, 118.053398, 4326), N'高德地图', N'POI_BUS_0141', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'世纪路共青团路口(公交站)', 7, N'102路/K102路;139路/K139路;157路/K157路;229路/K229路;257路/K257路;90路/K90路北线;90路/K90路南线;定制公交赏花灯专线三', 118.02507, 36.80806, geography::Point(36.80806, 118.02507, 4326), N'高德地图', N'POI_BUS_0142', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'二毛宿舍(公交站)', 7, N'127路/K127路', 118.074059, 36.809555, geography::Point(36.809555, 118.074059, 4326), N'高德地图', N'POI_BUS_0143', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市农科院(公交站)', 7, N'139路/K139路;222路/K222路', 118.031029, 36.804966, geography::Point(36.804966, 118.031029, 4326), N'高德地图', N'POI_BUS_0144', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中润大道西四路口(公交站)', 7, N'121路/K121路;156路/K156路;159路/K159路;162路;200路;71路;71路(6点30分);接站专线车', 118.042248, 36.83674, geography::Point(36.83674, 118.042248, 4326), N'高德地图', N'POI_BUS_0145', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'银座广场(公交站)', 7, N'121路/K121路;126路/K126路;2路/K2路', 118.032238, 36.815676, geography::Point(36.815676, 118.032238, 4326), N'高德地图', N'POI_BUS_0146', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'西六路华光路口(公交站)', 7, N'121路/K121路;126路/K126路;2路/K2路', 118.032266, 36.819951, geography::Point(36.819951, 118.032266, 4326), N'高德地图', N'POI_BUS_0147', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'洪沟铁路小区(公交站)', 7, N'122路/K122路;123路/K123路;20路;37路/K37路', 118.06786, 36.792205, geography::Point(36.792205, 118.06786, 4326), N'高德地图', N'POI_BUS_0148', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'新村路东三路口(公交站)', 7, N'122路/K122路;123路/K123路;150路/K150路;206路;20路;37路/K37路;5路;6路/K6路;82路', 118.074845, 36.796251, geography::Point(36.796251, 118.074845, 4326), N'高德地图', N'POI_BUS_0149', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'英豪·东方明珠(公交站)', 7, N'206路;266路/K266路', 118.076741, 36.816618, geography::Point(36.816618, 118.076741, 4326), N'高德地图', N'POI_BUS_0150', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'孙孟口腔(公交站)', 7, N'156路/K156路;185路', 118.050664, 36.836526, geography::Point(36.836526, 118.050664, 4326), N'高德地图', N'POI_BUS_0151', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'将军花园(公交站)', 7, N'102路/K102路;105路/K105路;116路/K116路(北线);116路/K116路(南线)', 118.035455, 36.814268, geography::Point(36.814268, 118.035455, 4326), N'高德地图', N'POI_BUS_0152', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'西六路新村路口(公交站)', 7, N'121路/K121路;126路/K126路', 118.031836, 36.80333, geography::Point(36.80333, 118.031836, 4326), N'高德地图', N'POI_BUS_0153', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中润华侨城南门(公交站)', 7, N'162路;200路;71路;71路(6点30分)', 118.030739, 36.837181, geography::Point(36.837181, 118.030739, 4326), N'高德地图', N'POI_BUS_0154', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'西六路商场路口(公交站)', 7, N'121路/K121路;126路/K126路;139路/K139路', 118.032211, 36.806372, geography::Point(36.806372, 118.032211, 4326), N'高德地图', N'POI_BUS_0155', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市中西医结合医院-张店区人民医院(公交站)', 7, N'122路/K122路;96路/K96路', 118.058163, 36.794399, geography::Point(36.794399, 118.058163, 4326), N'高德地图', N'POI_BUS_0156', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'和平小区(公交站)', 7, N'121路/K121路;132路/K132路;35路/K35路;95路/K95路', 118.039214, 36.796738, geography::Point(36.796738, 118.039214, 4326), N'高德地图', N'POI_BUS_0157', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市中西医院南门(公交站)', 7, N'121路/K121路;122路/K122路;123路/K123路;6路/K6路', 118.05938, 36.792472, geography::Point(36.792472, 118.05938, 4326), N'高德地图', N'POI_BUS_0158', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市十七中学(公交站)', 7, N'223路/K223路', 118.036932, 36.810635, geography::Point(36.810635, 118.036932, 4326), N'高德地图', N'POI_BUS_0159', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'潘南路东四路路口(乔庄)(公交站)', 7, N'88路/K88路内环;88路/K88路外环', 118.07898, 36.811604, geography::Point(36.811604, 118.07898, 4326), N'高德地图', N'POI_BUS_0160', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'城西小区(公交站)', 7, N'222路/K222路', 118.033891, 36.804861, geography::Point(36.804861, 118.033891, 4326), N'高德地图', N'POI_BUS_0161', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博莲池骨科医院(公交站)', 7, N'223路/K223路', 118.037088, 36.83112, geography::Point(36.83112, 118.037088, 4326), N'高德地图', N'POI_BUS_0162', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'西五路莲池村中心路口(公交站)', 7, N'108路/K108路;168路/K168路', 118.037088, 36.83112, geography::Point(36.83112, 118.037088, 4326), N'高德地图', N'POI_BUS_0163', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'启家口腔医院(公交站)', 7, N'121路/K121路;185路', 118.043863, 36.834502, geography::Point(36.834502, 118.043863, 4326), N'高德地图', N'POI_BUS_0164', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'柳泉艺术学校(公交站)', 7, N'127路/K127路;88路/K88路内环;88路/K88路外环;8路/K8路', 118.074904, 36.811772, geography::Point(36.811772, 118.074904, 4326), N'高德地图', N'POI_BUS_0165', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东方星城·塾香园(公交站)', 7, N'79路/K79路', 118.076219, 36.823456, geography::Point(36.823456, 118.076219, 4326), N'高德地图', N'POI_BUS_0166', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'新村路东四路口(公交站)', 7, N'122路/K122路;123路/K123路;37路/K37路', 118.08045, 36.795654, geography::Point(36.795654, 118.08045, 4326), N'高德地图', N'POI_BUS_0167', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博火车站北广场(临时站)(公交站)', 7, N'121路/K121路;136路/K136路;8路/K8路', 118.05921, 36.78893, geography::Point(36.78893, 118.05921, 4326), N'高德地图', N'POI_BUS_0168', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市政务服务中心西门(公交站)', 7, N'223路/K223路', 118.036945, 36.80352, geography::Point(36.80352, 118.036945, 4326), N'高德地图', N'POI_BUS_0169', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'兴学街(公交站)', 7, N'121路/K121路;160路/K160路;251路/K251路;51路西线;95路/K95路;夜160路', 118.051398, 36.793984, geography::Point(36.793984, 118.051398, 4326), N'高德地图', N'POI_BUS_0170', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'美年大健康(金晶大道路口)(公交站)', 7, N'156路/K156路;162路', 118.068551, 36.836066, geography::Point(36.836066, 118.068551, 4326), N'高德地图', N'POI_BUS_0171', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博莲池妇婴医院(公交站)', 7, N'108路/K108路;168路/K168路;223路/K223路', 118.037102, 36.834648, geography::Point(36.834648, 118.037102, 4326), N'高德地图', N'POI_BUS_0172', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'商场路世纪路口(公交站)', 7, N'139路/K139路;222路/K222路', 118.027151, 36.805323, geography::Point(36.805323, 118.027151, 4326), N'高德地图', N'POI_BUS_0173', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博市技师学院东门(公交站)', 7, N'121路/K121路;126路/K126路;2路/K2路', 118.032291, 36.817354, geography::Point(36.817354, 118.032291, 4326), N'高德地图', N'POI_BUS_0174', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'移动大厦(公交站)', 7, N'135路/K135路;139路/K139路;159路/K159路;160路/K160路;229路/K229路;257路/K257路;90路/K90路南线;95路/K95路;97路/K97路;9路/K9路;夜160路', 118.025659, 36.820742, geography::Point(36.820742, 118.025659, 4326), N'高德地图', N'POI_BUS_0175', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'魏家庄(中润大道)(公交站)', 7, N'156路/K156路;162路;71路;71路(6点30分)', 118.061962, 36.836237, geography::Point(36.836237, 118.061962, 4326), N'高德地图', N'POI_BUS_0176', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'王舍(公交站)', 7, N'137路/K137路', 118.045273, 36.789207, geography::Point(36.789207, 118.045273, 4326), N'高德地图', N'POI_BUS_0177', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'盛世新东城(公交站)', 7, N'105路/K105路;88路/K88路内环;88路/K88路外环', 118.079819, 36.807896, geography::Point(36.807896, 118.079819, 4326), N'高德地图', N'POI_BUS_0178', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博市技师学院(公交站)', 7, N'139路/K139路;160路/K160路;229路/K229路;257路/K257路;90路/K90路北线;90路/K90路南线;夜160路', 118.025554, 36.818461, geography::Point(36.818461, 118.025554, 4326), N'高德地图', N'POI_BUS_0179', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市府三宿舍西门(公交站)', 7, N'168路/K168路', 118.032264, 36.825916, geography::Point(36.825916, 118.032264, 4326), N'高德地图', N'POI_BUS_0180', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'义乌小商品城(南)(公交站)', 7, N'257路/K257路', 118.021949, 36.821936, geography::Point(36.821936, 118.021949, 4326), N'高德地图', N'POI_BUS_0181', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博火车站南广场6号门(公交站)', 7, N'110路;37路/K37路', 118.056307, 36.786505, geography::Point(36.786505, 118.056307, 4326), N'高德地图', N'POI_BUS_0182', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东二路联通路口(公交站)', 7, N'206路', 118.070487, 36.822456, geography::Point(36.822456, 118.070487, 4326), N'高德地图', N'POI_BUS_0183', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'区疾病防控中心(公交站)', 7, N'7路/K7路;96路/K96路', 118.029318, 36.80272, geography::Point(36.80272, 118.029318, 4326), N'高德地图', N'POI_BUS_0184', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市保安公司(临时站)(公交站)', 7, N'136路/K136路', 118.063001, 36.799795, geography::Point(36.799795, 118.063001, 4326), N'高德地图', N'POI_BUS_0185', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博火车站-南广场(公交站)', 7, N'1路直达;46路/K46路', 118.05626, 36.7861, geography::Point(36.7861, 118.05626, 4326), N'高德地图', N'POI_BUS_0186', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'杏园路金晶大道路口(淄博站广场)(公交站)', 7, N'37路/K37路;5路;82路', 118.057116, 36.790112, geography::Point(36.790112, 118.057116, 4326), N'高德地图', N'POI_BUS_0187', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'十里河(公交站)', 7, N'116路/K116路(北线);116路/K116路(南线);122路/K122路;206路;51路(东线)', 118.071413, 36.838711, geography::Point(36.838711, 118.071413, 4326), N'高德地图', N'POI_BUS_0188', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中润大道西五路口(公交站)', 7, N'121路/K121路;156路/K156路;159路/K159路;162路;200路;71路;71路(6点30分)', 118.036137, 36.837034, geography::Point(36.837034, 118.036137, 4326), N'高德地图', N'POI_BUS_0189', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中润华侨城西门(公交站)', 7, N'123路/K123路;162路;229路/K229路;297路;71路;71路(6点30分);90路/K90路北线;90路/K90路南线;95路/K95路;97路/K97路', 118.026656, 36.841047, geography::Point(36.841047, 118.026656, 4326), N'高德地图', N'POI_BUS_0190', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博四季青医院(公交站)', 7, N'123路/K123路;79路/K79路', 118.040972, 36.82842, geography::Point(36.82842, 118.040972, 4326), N'高德地图', N'POI_BUS_0191', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'公交东站(公交站)', 7, N'126路/K126路;139路/K139路;152路/K152路;159路/K159路;171路;1路北线;206路;269路;33路;36路;36路(半点发车);37路/K37路;3路;53路/K53路;58路/K58路;5路;71路;71路(6点30分);80路/K80路;82路;86路;沂源长途汽车站-公交东站定制公交通勤专线', 118.080404, 36.773819, geography::Point(36.773819, 118.080404, 4326), N'高德地图', N'POI_BUS_0192', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'市实验中学(公交站)', 7, N'102路/K102路;12路/K12路;138路东线;138路西线;168路/K168路;222路/K222路;7路/K7路;95路/K95路;96路/K96路;第一医院健康专线', 118.010344, 36.803347, geography::Point(36.803347, 118.010344, 4326), N'高德地图', N'POI_BUS_0193', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东四路共青团路口(公交站)', 7, N'206路', 118.083364, 36.803954, geography::Point(36.803954, 118.083364, 4326), N'高德地图', N'POI_BUS_0194', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'西班牙风情街(公交站)', 7, N'135路/K135路;159路/K159路;160路/K160路;229路/K229路;34路/K34路;95路/K95路;97路/K97路;9路/K9路;夜160路', 118.025887, 36.826363, geography::Point(36.826363, 118.025887, 4326), N'高德地图', N'POI_BUS_0195', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'火车站南广场(公交站)', 7, N'1路北线;37路/K37路', 118.054895, 36.784912, geography::Point(36.784912, 118.054895, 4326), N'高德地图', N'POI_BUS_0196', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博五中(临时站)(公交站)', 7, N'136路/K136路;206路', 118.062049, 36.794106, geography::Point(36.794106, 118.062049, 4326), N'高德地图', N'POI_BUS_0197', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'石桥办事处(公交站)', 7, N'116路/K116路(北线);116路/K116路(南线);122路/K122路;206路;51路(东线);51路西线', 118.072962, 36.843641, geography::Point(36.843641, 118.072962, 4326), N'高德地图', N'POI_BUS_0198', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'商场路(5号院烧烤)(公交站)', 7, N'淄博烧烤专线5路', 118.044655, 36.804448, geography::Point(36.804448, 118.044655, 4326), N'高德地图', N'POI_BUS_0199', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'济南铁路局工务工厂(公交站)', 7, N'105路/K105路;206路;76路/K76路;88路/K88路内环;88路/K88路外环', 118.081923, 36.808347, geography::Point(36.808347, 118.081923, 4326), N'高德地图', N'POI_BUS_0200', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'山东电泵(公交站)', 7, N'125路/K125路;126路/K126路;185路;203路/K203路;251路/K251路;35路/K35路;58路/K58路', 118.059547, 36.844933, geography::Point(36.844933, 118.059547, 4326), N'高德地图', N'POI_BUS_0201', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'火车站北广场首末站(公交站)', 7, N'136路/K136路;222路/K222路', 118.05921, 36.78893, geography::Point(36.78893, 118.05921, 4326), N'高德地图', N'POI_BUS_0202', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东二路(南行)(公交站)', 7, N'123路/K123路', 118.068512, 36.795895, geography::Point(36.795895, 118.068512, 4326), N'高德地图', N'POI_BUS_0203', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'柳泉路(大嘴烧烤)(公交站)', 7, N'淄博烧烤专线5路', 118.046549, 36.794439, geography::Point(36.794439, 118.046549, 4326), N'高德地图', N'POI_BUS_0204', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东四路(公交站)', 7, N'123路/K123路;150路/K150路;206路;20路;5路;82路', 118.080646, 36.795643, geography::Point(36.795643, 118.080646, 4326), N'高德地图', N'POI_BUS_0205', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'淄博面粉厂(东张村)(公交站)', 7, N'123路/K123路;135路/K135路;150路/K150路;20路;37路/K37路;5路;82路', 118.091096, 36.793617, geography::Point(36.793617, 118.091096, 4326), N'高德地图', N'POI_BUS_0206', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'高新区行政服务中心(公交站)', 7, N'接站专线车', 118.052612, 36.836479, geography::Point(36.836479, 118.052612, 4326), N'高德地图', N'POI_BUS_0207', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'银泰城西门(公交站)', 7, N'123路/K123路;131路/K131路;168路/K168路;297路;35路/K35路;95路/K95路', 118.032806, 36.850178, geography::Point(36.850178, 118.032806, 4326), N'高德地图', N'POI_BUS_0208', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张南路王舍路口(王舍路)(公交站)', 7, N'37路/K37路;5路;82路', 118.050333, 36.786537, geography::Point(36.786537, 118.050333, 4326), N'高德地图', N'POI_BUS_0209', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'器械厂宿舍(公交站)', 7, N'122路/K122路;123路/K123路;20路;37路/K37路', 118.066663, 36.791669, geography::Point(36.791669, 118.066663, 4326), N'高德地图', N'POI_BUS_0210', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'英豪东方明珠(公交站)', 7, N'206路', 118.077259, 36.816606, geography::Point(36.816606, 118.077259, 4326), N'高德地图', N'POI_BUS_0211', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'世纪花园(公交站)', 7, N'123路/K123路;137路/K137路;169路/K169路;200路;229路/K229路;95路/K95路;97路/K97路;9路/K9路;定制公交赏花灯专线三', 118.026366, 36.833529, geography::Point(36.833529, 118.026366, 4326), N'高德地图', N'POI_BUS_0212', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店政务中心(公交站)', 7, N'96路/K96路', 118.017065, 36.803823, geography::Point(36.803823, 118.017065, 4326), N'高德地图', N'POI_BUS_0213', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'胜利桥小区(公交站)', 7, N'90路/K90路北线;90路/K90路南线', 118.040892, 36.792058, geography::Point(36.792058, 118.040892, 4326), N'高德地图', N'POI_BUS_0214', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'牵引电机生活区(公交站)', 7, N'135路/K135路', 118.082057, 36.802244, geography::Point(36.802244, 118.082057, 4326), N'高德地图', N'POI_BUS_0215', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'美年大健康(公交站)', 7, N'71路;71路(6点30分)', 118.068551, 36.836066, geography::Point(36.836066, 118.068551, 4326), N'高德地图', N'POI_BUS_0216', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张店九中(公交站)', 7, N'105路/K105路;116路/K116路(北线);116路/K116路(南线);2路/K2路', 118.020218, 36.814671, geography::Point(36.814671, 118.020218, 4326), N'高德地图', N'POI_BUS_0217', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'植物园东门(公交站)', 7, N'223路/K223路;35路/K35路', 118.034097, 36.791428, geography::Point(36.791428, 118.034097, 4326), N'高德地图', N'POI_BUS_0218', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'张庄(公交站)', 7, N'135路/K135路;206路', 118.084304, 36.797122, geography::Point(36.797122, 118.084304, 4326), N'高德地图', N'POI_BUS_0219', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'东一路新村路口(临时站)(公交站)', 7, N'136路/K136路;206路', 118.062439, 36.796506, geography::Point(36.796506, 118.062439, 4326), N'高德地图', N'POI_BUS_0220', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'西六路华光路口(尖峰教育)(公交站)', 7, N'2路/K2路', 118.032266, 36.819951, geography::Point(36.819951, 118.032266, 4326), N'高德地图', N'POI_BUS_0221', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'区政务中心(公交站)', 7, N'102路/K102路;12路/K12路;138路东线;138路西线;222路/K222路;7路/K7路', 118.017065, 36.803823, geography::Point(36.803823, 118.017065, 4326), N'高德地图', N'POI_BUS_0222', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'中润华侨城(公交站)', 7, N'121路/K121路;156路/K156路;159路/K159路;162路;71路;90路/K90路北线;90路/K90路南线;9路/K9路', 118.030918, 36.837184, geography::Point(36.837184, 118.030918, 4326), N'高德地图', N'POI_BUS_0223', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'巨能电器(公交站)', 7, N'121路/K121路', 118.031372, 36.799591, geography::Point(36.799591, 118.031372, 4326), N'高德地图', N'POI_BUS_0224', 1);
INSERT INTO dbo.facility (facility_name, category_id, address, longitude, latitude, location, source, poi_id, status) VALUES
  (N'安康佳园(公交站)', 7, N'51路(东线);58路/K58路;71路;71路(6点30分)', 118.053711, 36.782569, geography::Point(36.782569, 118.053711, 4326), N'高德地图', N'POI_BUS_0225', 1);
GO

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
