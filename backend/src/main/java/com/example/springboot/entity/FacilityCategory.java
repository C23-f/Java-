package com.example.springboot.entity;

import lombok.Data;
import java.math.BigDecimal;


@Data
public class FacilityCategory {

    private Integer categoryId;      // 分类ID
    private String categoryCode;     // 分类编码（EDU/MED/MKT...）
    private String categoryName;     // 分类名称（教育设施/医疗卫生...）
    private BigDecimal weight;       // 评分权重
    private Integer sortOrder;       // 排序号
    private String description;      // 说明
}
