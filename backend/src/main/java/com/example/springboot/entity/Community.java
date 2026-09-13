package com.example.springboot.entity;

import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
public class Community {
    private Integer communityId;
    private String communityName;
    private String address;
    private Integer regionId;
    private Double longitude;
    private Double latitude;
    private Integer houseCount;
    private Integer buildYear;
    private Double walkSpeed;
    private String description;
    private LocalDateTime createTime;
    private LocalDateTime updateTime;

    // ---------- 以下字段由 T28 数据库迭代新增，实体同步补齐 ----------
    /** 房价 元/㎡ */
    private BigDecimal price;
    /** 用户平均分 0-5（审核通过评价自动重算） */
    private BigDecimal avgScore;
    /** 户数 */
    private Integer household;
    /** 人口 */
    private Integer population;
    /** 关联街道id（district 表） */
    private Integer districtId;
    /** 街道名称（联表展示用，非表字段） */
    private String districtName;
}
