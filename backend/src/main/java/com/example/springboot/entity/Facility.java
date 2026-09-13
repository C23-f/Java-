package com.example.springboot.entity;

import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
public class Facility {
    private Integer facilityId;
    private String facilityName;
    private Integer categoryId;
    private String address;
    private Double longitude;
    private Double latitude;
    private String source;
    private String poiId;
    private Short status;
    private LocalDateTime createTime;

    // ---------- 以下字段由 T28 数据库迭代新增，实体同步补齐 ----------
    /** 设施平均分 0-5（审核通过评价自动重算） */
    private BigDecimal avgScore;
    /** 开放时间 */
    private String openTime;
    /** 联系电话 */
    private String phone;
    /** 关联街道id（district 表） */
    private Integer districtId;
    /** 设施分类名称（联表展示用，非表字段） */
    private String categoryName;
    /** 设施分类编码（联表展示用，非表字段） */
    private String categoryCode;
    /** 距起点距离（米，空间查询时返回，非表字段） */
    private Double distance;
}
